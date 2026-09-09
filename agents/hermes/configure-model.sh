#!/usr/bin/env bash
# Copyright 2026 AgentDorm contributors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Choose a provider and a model and persist them to $HERMES_HOME/config.yaml
# (the .harness mount), so the choice survives container removal:
#
#   model:
#     default: <model id>
#     provider: <provider id>
#     base_url: <API base URL>
#     context_length: <tokens>
#   custom_providers:            # only for an endpoint of your own
#     - name: Local (localhost:1234)
#       base_url: http://localhost:1234/v1
#       model: <model id>
#   fallback_providers:          # only when HERMES_FALLBACKS is set
#     - provider: openrouter
#       model: openrouter/owl-alpha
#       base_url: https://openrouter.ai/api/v1
#       api_mode: chat_completions
#
# Two modes:
#
#   --interactive   Two steps -- pick a provider, then pick one of the models
#                   its /models endpoint reports. `hermes.sh` runs this once,
#                   on the first start of a fresh .harness. Needs a terminal.
#                   After that the dashboard, `hermes model`, or the agent
#                   itself owns the config.
#
#   (default)       Non-interactive: resolve everything from the environment.
#                   Runs on every start from the entrypoint.
#                     provider  HERMES_PROVIDER, else the first provider whose
#                               API key is set
#                     model     HERMES_MODEL, else the first id in
#                               HERMES_MODELS, else the first id from the
#                               provider's /models endpoint (preferring a match
#                               for HERMES_MODEL_PREFER), else a built-in default
#                     base_url  HERMES_BASE_URL, else <PROVIDER>_BASE_URL, else
#                               the built-in one
#                     context   HERMES_CONTEXT_LENGTH, else 64000
#                     fallbacks HERMES_FALLBACKS, entries separated by ';', each
#                               "provider|model|base_url|api_mode" (the last two
#                               optional), e.g.
#                               "minimax|MiniMax-M2.7|https://api.minimax.io/anthropic;openrouter|owl-alpha||chat_completions"
#
#                   It rewrites the config on every start when any of
#                   HERMES_PROVIDER, HERMES_MODEL, HERMES_MODELS or
#                   HERMES_BASE_URL is set -- the environment is the source of
#                   truth then. With none of them set it only seeds an unset
#                   config, so a model picked in the dashboard or with
#                   `hermes model` is never overwritten.
#                   HERMES_MODEL_REWRITE=always|never forces either behaviour.
#
# API keys are read from the environment and never written to disk.

set -euo pipefail

HERMES_CONTEXT_LENGTH="${HERMES_CONTEXT_LENGTH:-64000}"
# Provider used when nothing in the environment says otherwise, and the model
# filter applied to its catalogue (OpenRouter marks free models with `:free`).
DEFAULT_PROVIDER="${HERMES_DEFAULT_PROVIDER:-openrouter}"
DEFAULT_OPENROUTER_PREFER=':free$'
CONFIG="${HERMES_HOME:-$HOME/.hermes}/config.yaml"
INTERACTIVE=no
[ "${1:-}" = "--interactive" ] && INTERACTIVE=yes

# provider | key env var | base URL env var | default base URL | default model
PROVIDERS=(
  "nous|NOUS_API_KEY|NOUS_BASE_URL|https://inference-api.nousresearch.com/v1|Hermes-4-405B"
  "openrouter|OPENROUTER_API_KEY|OPENROUTER_BASE_URL|https://openrouter.ai/api/v1|minimax/minimax-m3:free"
  "anthropic|ANTHROPIC_API_KEY|ANTHROPIC_BASE_URL|https://api.anthropic.com/v1|claude-sonnet-4-5"
  "openai|OPENAI_API_KEY|OPENAI_BASE_URL|https://api.openai.com/v1|gpt-4.1"
  "gemini|GEMINI_API_KEY|GEMINI_BASE_URL|https://generativelanguage.googleapis.com/v1beta|gemini-flash-latest"
  "deepseek|DEEPSEEK_API_KEY|DEEPSEEK_BASE_URL|https://api.deepseek.com/v1|deepseek-chat"
  "minimax|MINIMAX_API_KEY|MINIMAX_BASE_URL|https://api.minimax.io/anthropic|MiniMax-M2.7"
)

field() { echo "$1" | cut -d'|' -f"$2"; }

row_for() {
  local row
  for row in "${PROVIDERS[@]}"; do
    [ "${row%%|*}" = "$1" ] && { echo "$row"; return 0; }
  done
  return 1
}

# List model ids from an OpenAI-compatible (or Anthropic/Gemini) endpoint.
list_models() {  # $1 base_url  $2 api_key  $3 provider
  local url="${1%/}/models" key="$2" prov="$3" body
  local -a hdr=()
  case "$prov" in
    anthropic|minimax) [ -n "$key" ] && hdr=(-H "x-api-key: $key" -H "anthropic-version: 2023-06-01") ;;
    gemini)            [ -n "$key" ] && hdr=(-H "x-goog-api-key: $key") ;;
    *)                 [ -n "$key" ] && hdr=(-H "Authorization: Bearer $key") ;;
  esac
  body="$(curl -fsS --max-time 20 ${hdr[@]+"${hdr[@]}"} "$url" 2>/dev/null)" || return 0
  # OpenAI/Anthropic shape: .data[].id — Gemini shape: .models[].name
  echo "$body" | jq -r '
    [ (.data[]?.id // empty), ((.models[]?.name // empty) | sub("^models/"; "")) ] | .[]
  ' 2>/dev/null || true
}

# Merge one entry into the config's `custom_providers:` list, keyed by base_url.
add_custom_provider() {  # $1 name  $2 base_url  $3 model
  CP_NAME="$1" CP_URL="$2" CP_MODEL="$3" CONFIG="$CONFIG" python - <<'PY'
import os, pathlib, yaml
path = pathlib.Path(os.environ["CONFIG"])
cfg = yaml.safe_load(path.read_text()) if path.exists() else {}
cfg = cfg or {}
entries = cfg.get("custom_providers")
entries = entries if isinstance(entries, list) else []
entry = {
    "name": os.environ["CP_NAME"],
    "base_url": os.environ["CP_URL"],
    "model": os.environ["CP_MODEL"],
}
url = entry["base_url"].rstrip("/").lower()
for i, existing in enumerate(entries):
    if isinstance(existing, dict) and str(existing.get("base_url", "")).rstrip("/").lower() == url:
        entries[i] = {**existing, **entry}
        break
else:
    entries.append(entry)
cfg["custom_providers"] = entries
path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(yaml.safe_dump(cfg, sort_keys=False, default_flow_style=False))
PY
}

# Replace `fallback_providers:` with the HERMES_FALLBACKS chain, in order.
write_fallbacks() {  # $1 = "provider|model|base_url|api_mode; ..."
  FB_SPEC="$1" CONFIG="$CONFIG" python - <<'PY'
import os, pathlib, yaml
spec = os.environ["FB_SPEC"]
path = pathlib.Path(os.environ["CONFIG"])
cfg = yaml.safe_load(path.read_text()) if path.exists() else {}
cfg = cfg or {}
chain = []
for raw in spec.split(";"):
    raw = raw.strip()
    if not raw:
        continue
    parts = [p.strip() for p in raw.split("|")]
    provider, model = (parts + ["", ""])[:2]
    if not provider or not model:
        continue
    entry = {"provider": provider, "model": model}
    if len(parts) > 2 and parts[2]:
        entry["base_url"] = parts[2]
    if len(parts) > 3 and parts[3]:
        entry["api_mode"] = parts[3]
    chain.append(entry)
if chain:
    cfg["fallback_providers"] = chain
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.safe_dump(cfg, sort_keys=False, default_flow_style=False))
PY
}

write_config() {  # $1 provider  $2 model  $3 base_url
  hermes config set model.provider "$1" >/dev/null
  hermes config set model.default "$2" >/dev/null
  [ -n "$3" ] && hermes config set model.base_url "$3" >/dev/null
  hermes config set model.context_length "$HERMES_CONTEXT_LENGTH" >/dev/null
  [ -n "${HERMES_FALLBACKS:-}" ] && write_fallbacks "$HERMES_FALLBACKS"
  return 0
}

# ---------------------------------------------------------------- interactive

if [ "$INTERACTIVE" = "yes" ]; then
  if [ ! -t 0 ]; then
    echo "hermes: --interactive needs a terminal" >&2
    exit 1
  fi

  echo
  echo "Step 1/2 - provider"
  i=0
  options=()
  for row in "${PROVIDERS[@]}"; do
    i=$((i + 1))
    key_var="$(field "$row" 2)"
    if [ -n "${!key_var:-}" ]; then mark="key set"; else mark="no $key_var"; fi
    printf '  %d) %-11s %s\n' "$i" "${row%%|*}" "($mark)"
    options+=("${row%%|*}")
  done
  i=$((i + 1))
  custom_index=$i
  printf '  %d) %-11s %s\n' "$i" "custom" "(your own endpoint, e.g. http://localhost:1234/v1)"
  echo
  read -r -p "provider [1-$i]: " choice
  echo

  if [ "$choice" = "$custom_index" ]; then
    provider="custom"
    read -r -p "name (e.g. Local (localhost:1234)): " custom_name
    read -r -p "base_url (e.g. http://localhost:1234/v1): " base_url
    read -r -p "API key env var (blank for none): " custom_key_var
    api_key="${custom_key_var:+${!custom_key_var:-}}"
    [ -n "$custom_name" ] || custom_name="$base_url"
  else
    case "$choice" in
      ''|*[!0-9]*) echo "hermes: not a number: $choice" >&2; exit 1 ;;
    esac
    { [ "$choice" -ge 1 ] && [ "$choice" -lt "$custom_index" ]; } \
      || { echo "hermes: out of range: $choice" >&2; exit 1; }
    provider="${options[$((choice - 1))]}"
    row="$(row_for "$provider")"
    key_var="$(field "$row" 2)"
    base_var="$(field "$row" 3)"
    api_key="${!key_var:-}"
    base_url="${HERMES_BASE_URL:-${!base_var:-$(field "$row" 4)}}"
  fi

  [ -n "${base_url:-}" ] || { echo "hermes: a base_url is required" >&2; exit 1; }

  echo "Step 2/2 - model"
  echo "  querying ${base_url%/}/models ..."
  mapfile -t models < <(list_models "$base_url" "${api_key:-}" "$provider" | head -60)

  model=""
  if [ "${#models[@]}" -gt 0 ]; then
    i=0
    for m in "${models[@]}"; do
      i=$((i + 1))
      printf '  %d) %s\n' "$i" "$m"
    done
    echo
    read -r -p "model [1-$i, or type an id]: " pick
    case "$pick" in
      ''|*[!0-9]*) model="$pick" ;;
      *) { [ "$pick" -ge 1 ] && [ "$pick" -le "$i" ]; } && model="${models[$((pick - 1))]}" ;;
    esac
  else
    echo "  (no model list from that endpoint - type the id yourself)"
    read -r -p "model id: " model
  fi

  [ -n "$model" ] || { echo "hermes: no model chosen" >&2; exit 1; }

  write_config "$provider" "$model" "$base_url"
  [ "$provider" = "custom" ] && add_custom_provider "$custom_name" "$base_url" "$model"

  echo
  echo "hermes: provider=$provider model=$model base_url=$base_url -> $CONFIG"
  exit 0
fi

# ------------------------------------------------------------ non-interactive

provider="${HERMES_PROVIDER:-}"
if [ -z "$provider" ]; then
  for row in "${PROVIDERS[@]}"; do
    key_var="$(field "$row" 2)"
    if [ -n "${!key_var:-}" ]; then provider="${row%%|*}"; break; fi
  done
fi

# Default provider, key or not: OpenRouter on a free model. The agent will
# ask for a key on first use; until then the config is at least coherent.
if [ -z "$provider" ]; then
  provider="$DEFAULT_PROVIDER"
  echo "hermes: no provider key in the environment; defaulting to $DEFAULT_PROVIDER (set OPENROUTER_API_KEY, or pick another with HERMES_PROVIDER/HERMES_MODEL)" >&2
fi

if row="$(row_for "$provider")"; then
  key_var="$(field "$row" 2)"
  base_var="$(field "$row" 3)"
  api_key="${!key_var:-}"
  base_url="${HERMES_BASE_URL:-${!base_var:-$(field "$row" 4)}}"
  default_model="$(field "$row" 5)"
else
  # A provider this script does not know still works, but it has no defaults
  # to fall back to: the environment has to name the model and the endpoint.
  if [ -z "${HERMES_MODEL:-}${HERMES_MODELS:-}" ] || [ -z "${HERMES_BASE_URL:-}" ]; then
    echo "hermes: unknown provider '$provider'; set HERMES_MODEL and HERMES_BASE_URL too" >&2
    exit 0
  fi
  api_key="${HERMES_API_KEY:-}"
  base_url="$HERMES_BASE_URL"
  default_model=""
fi

configured=""
[ -f "$CONFIG" ] && configured="$(grep -E '^[[:space:]]+default:' "$CONFIG" | head -1 || true)"

case "${HERMES_MODEL_REWRITE:-auto}" in
  always) write=yes ;;
  never)  write=no ;;
  *)
    if [ -n "${HERMES_PROVIDER:-}${HERMES_MODEL:-}${HERMES_MODELS:-}${HERMES_BASE_URL:-}" ]; then
      write=yes
    elif [ -z "$configured" ]; then
      write=yes
    else
      write=no
    fi
    ;;
esac

warn_missing_key() {
  # A configured provider with no key reaches the agent as the unhelpful
  # "No LLM provider configured" / "provider is not authenticated". Say which
  # variable is missing while the reason is still visible.
  [ -n "${api_key:-}" ] && return 0
  [ "$provider" = "custom" ] && return 0
  echo "hermes: WARNING - ${key_var:-the provider API key} is not set, so $provider cannot authenticate." >&2
  echo "hermes:           Restart with it exported, e.g. ${key_var:-API_KEY}=... ./hermes.sh" >&2
}

if [ "$write" = "no" ]; then
  echo "hermes: keeping the model already configured in $CONFIG" >&2
  warn_missing_key
  exit 0
fi

first_id() { echo "$1" | tr ',' ' ' | awk '{print $1}'; }

model="${HERMES_MODEL:-}"
source_note="HERMES_MODEL"
if [ -z "$model" ] && [ -n "${HERMES_MODELS:-}" ]; then
  model="$(first_id "$HERMES_MODELS")"
  source_note="HERMES_MODELS"
fi
if [ -z "$model" ]; then
  ids="$(list_models "$base_url" "${api_key:-}" "$provider")"
  prefer="${HERMES_MODEL_PREFER:-}"
  # Unasked-for spend is the worse surprise: on OpenRouter, prefer a free model.
  if [ -z "$prefer" ] && [ "$provider" = "openrouter" ]; then
    prefer="$DEFAULT_OPENROUTER_PREFER"
  fi
  if [ -n "$ids" ] && [ -n "$prefer" ]; then
    model="$(echo "$ids" | grep -E "$prefer" | head -1 || true)"
  fi
  [ -z "$model" ] && model="$(echo "$ids" | head -1)"
  source_note="${base_url%/}/models"
fi
if [ -z "$model" ]; then
  model="$default_model"
  source_note="built-in default"
fi

if [ -z "$model" ]; then
  echo "hermes: could not resolve a model for provider '$provider'; set HERMES_MODEL" >&2
  exit 0
fi

write_config "$provider" "$model" "$base_url"
[ "$provider" = "custom" ] && add_custom_provider "${HERMES_PROVIDER_NAME:-$base_url}" "$base_url" "$model"

echo "hermes: provider=$provider model=$model (from $source_note) base_url=$base_url context_length=$HERMES_CONTEXT_LENGTH" >&2

warn_missing_key
