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

set -euo pipefail

# Port published out of the container. dsh itself always binds loopback.
DSH_PORT="${DSH_PORT:-3080}"
# Internal loopback port the harness serves on.
DSH_INTERNAL_PORT="${DSH_INTERNAL_PORT:-3080}"
# Port socat listens on for the published-port NAT.
DSH_BRIDGE_PORT="${DSH_BRIDGE_PORT:-13080}"

# /opt/dsh may be a host bind mount (.deps). Fill it from the image's seed on
# first start, and REPLACE it whenever the image was rebuilt (the seed stamp
# differs): otherwise an upgrade would keep running the old copy persisted in
# .deps. Replaced wholesale, not merged, so no stale package shadows a new one.
refresh_seed() {
  seed=/opt/dsh-seed target=/opt/dsh
  if [ -f "$target/.agentdorm-seed" ] && cmp -s "$seed/.agentdorm-seed" "$target/.agentdorm-seed"; then
    return 0
  fi
  if [ -n "$(ls -A "$target" 2>/dev/null)" ]; then
    echo "dsh: image changed; refreshing $target from it ..." >&2
  else
    echo "dsh: seeding $target from the image (first start) ..." >&2
  fi
  find "$target" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  cp -a "$seed/." "$target/"
}
refresh_seed

# Register OpenRouter as a custom pi-ai provider when its key is present.
# settings.yaml holds only the apiKeyEnv reference; the key itself stays in
# the environment and is resolved per request by dsh.
#
# The generated block is marked "managed by dsh entrypoint" and is REWRITTEN
# on every start from the current OPENROUTER_* env, so changing
# OPENROUTER_MODELS or OPENROUTER_BASE_URL takes effect on next launch.
# A hand-written openrouter provider (no marker) is left untouched.
MARKER="# managed by dsh entrypoint; configure via OPENROUTER_* env"

write_provider_block() {
  # Provider body at llm-pi-ai.providers level (4-space indent), marker included.
  echo "    $MARKER"
  echo "    openrouter:"
  echo "      apiKeyEnv: OPENROUTER_API_KEY"
  echo "      api: openai-completions"
  echo "      baseURL: ${OPENROUTER_BASE_URL:-https://openrouter.ai/api/v1}"
  echo "      models:"
  local model id
  for model in ${OPENROUTER_MODELS:-deepseek/deepseek-chat-v3.1}; do
    for id in $(echo "$model" | tr ',' ' '); do
      echo "        - id: $id"
    done
  done
}

# Remove a generated openrouter block. Mode "marker" starts at the marker
# comment; mode "legacy" matches pre-marker blocks (identified by their
# apiKeyEnv reference). The `openrouter:` key line is consumed first; the
# block then ends at the next sibling provider (4-space key) or anything
# dedenting past 4 spaces. Blank lines inside are dropped.
strip_openrouter() { # $1=file  $2=mode
  awk -v mode="$2" -v marker="$MARKER" '
    (mode == "marker" && index($0, marker)) { skip = 1; next }
    (mode == "legacy" && /^    openrouter:/) { skip = 1; seen = 1; next }
    skip && !seen && /^    openrouter:/ { seen = 1; next }
    skip && seen && /^[ ]{0,3}[^ ]/ { skip = 0 }
    skip && seen && /^    [A-Za-z0-9_-]+:/ { skip = 0 }
    skip && /^[ \t]*$/ { next }
    !skip { print }
  ' "$1"
}

configure_openrouter() {
  [ -n "${OPENROUTER_API_KEY:-}" ] || return 0
  mkdir -p "$DSH_HOME"
  local settings="$DSH_HOME/settings.yaml"

  if [ ! -f "$settings" ]; then
    { echo "llm-pi-ai:"
      echo "  providers:"
      write_provider_block
    } > "$settings"
    echo "dsh: openrouter provider written to $settings" >&2
    return 0
  fi

  # Managed block from a previous start, or a legacy generated one (same
  # apiKeyEnv reference, no marker) — regenerate both from current env.
  local mode=""
  if grep -qF "$MARKER" "$settings"; then
    mode="marker"
  elif grep -q '^    openrouter:' "$settings" \
    && grep -qF 'apiKeyEnv: OPENROUTER_API_KEY' "$settings"; then
    mode="legacy"
  fi

  if [ -n "$mode" ]; then
    strip_openrouter "$settings" "$mode" > "$settings.tmp"
    if ! grep -q '^llm-pi-ai:' "$settings.tmp" \
       || ! grep -q '^  providers:' "$settings.tmp"; then
      echo "dsh: $settings lost its llm-pi-ai.providers mapping; rewriting it" >&2
      { echo "llm-pi-ai:"
        echo "  providers:"
        write_provider_block
      } > "$settings"
    else
      write_provider_block >> "$settings.tmp"
      mv "$settings.tmp" "$settings"
    fi
    rm -f "$settings.tmp"
    echo "dsh: openrouter provider updated in $settings$([ "$mode" = legacy ] && echo ' (migrated old format)')" >&2
    return 0
  fi

  if grep -q 'openrouter:' "$settings"; then
    echo "dsh: $settings defines a manual openrouter provider; leaving it untouched" >&2
    return 0
  fi
  if grep -q '^llm-pi-ai:' "$settings"; then
    echo "dsh: $settings already defines llm-pi-ai; add the openrouter provider manually" >&2
    return 0
  fi
}
configure_openrouter

if [ "${1:-}" = "web" ]; then
  shift
  extra=()
  # The /api browser-trust fence accepts loopback Host headers (localhost,
  # 127.0.0.0/8). Add any other authority you reach the UI by.
  if [ -n "${DSH_TRUSTED_HOSTS:-}" ]; then
    for h in ${DSH_TRUSTED_HOSTS}; do extra+=(--trusted-host "$h"); done
  fi

  # The webserver only accepts 127.0.0.1 or 0.0.0.0, and the CLI rejects
  # 0.0.0.0 on purpose (the harness runs shell commands). So dsh stays on
  # loopback and socat bridges the published port to it.
  socat "TCP-LISTEN:${DSH_BRIDGE_PORT},fork,reuseaddr" \
        "TCP:127.0.0.1:${DSH_INTERNAL_PORT}" &
  echo "dsh: serving http://localhost:${DSH_PORT} (container loopback ${DSH_INTERNAL_PORT} via bridge ${DSH_BRIDGE_PORT})" >&2

  # No browser inside the container.
  set -- web --no-open --host 127.0.0.1 --port "$DSH_INTERNAL_PORT" ${extra[@]+"${extra[@]}"} "$@"
fi

exec dsh "$@"
