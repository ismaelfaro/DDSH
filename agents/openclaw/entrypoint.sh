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

# Port published out of the container. The Gateway itself always binds loopback.
OPENCLAW_PORT="${OPENCLAW_PORT:-18789}"
# Internal loopback port the Gateway serves the Control UI on.
OPENCLAW_INTERNAL_PORT="${OPENCLAW_INTERNAL_PORT:-18789}"
# Port socat listens on for the published-port NAT.
OPENCLAW_BRIDGE_PORT="${OPENCLAW_BRIDGE_PORT:-18790}"

# /opt/openclaw may be a host bind mount (.deps). Fill it from the image's seed on
# first start, and REPLACE it whenever the image was rebuilt (the seed stamp
# differs): otherwise an upgrade would keep running the old copy persisted in
# .deps. Replaced wholesale, not merged, so no stale package shadows a new one.
refresh_seed() {
  seed=/opt/openclaw-seed target=/opt/openclaw
  if [ -f "$target/.agentdorm-seed" ] && cmp -s "$seed/.agentdorm-seed" "$target/.agentdorm-seed"; then
    return 0
  fi
  if [ -n "$(ls -A "$target" 2>/dev/null)" ]; then
    echo "openclaw: image changed; refreshing $target from it ..." >&2
  else
    echo "openclaw: seeding $target from the image (first start) ..." >&2
  fi
  find "$target" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  cp -a "$seed/." "$target/"
}
refresh_seed

echo "openclaw: workspace ${HOST_WORKSPACE:-(host folder)} -> /workspace" >&2

# First start on an empty state directory: onboard without prompts, using
# whichever provider key is in the environment. Keys are passed through, never
# written into the image.
if [ ! -f "$OPENCLAW_STATE_DIR/openclaw.json" ]; then
  auth_choice=""
  key_flag=()
  if   [ -n "${OPENROUTER_API_KEY:-}" ]; then auth_choice="openrouter-api-key"; key_flag=(--openrouter-api-key "$OPENROUTER_API_KEY")
  elif [ -n "${ANTHROPIC_API_KEY:-}" ]; then auth_choice="apiKey";             key_flag=(--api-key "$ANTHROPIC_API_KEY")
  elif [ -n "${OPENAI_API_KEY:-}" ];    then auth_choice="openai-api-key";     key_flag=(--openai-api-key "$OPENAI_API_KEY")
  elif [ -n "${DEEPSEEK_API_KEY:-}" ];  then auth_choice="deepseek-api-key";   key_flag=(--deepseek-api-key "$DEEPSEEK_API_KEY")
  elif [ -n "${GEMINI_API_KEY:-}" ];    then auth_choice="gemini-api-key";     key_flag=(--gemini-api-key "$GEMINI_API_KEY")
  fi

  if [ -n "$auth_choice" ]; then
    echo "openclaw: first start — onboarding with $auth_choice ..." >&2
    # --accept-risk is what --non-interactive requires: this agent runs shell
    # commands, and here it can only reach /workspace.
    # --skip-health: onboarding would probe a gateway that only starts below.
    # --skip-daemon/--skip-ui/--skip-channels: no service manager, browser, or
    # inbound network in a container; channels are paired later by hand.
    openclaw onboard --non-interactive --accept-risk \
      --auth-choice "$auth_choice" "${key_flag[@]}" \
      --workspace /workspace \
      --skip-health --skip-daemon --skip-ui --skip-channels >&2 || \
      echo "openclaw: onboarding failed; run 'agentdorm shell <name> openclaw onboard' yourself" >&2
  else
    echo "openclaw: no provider key in the environment (OPENROUTER_API_KEY, ANTHROPIC_API_KEY, OPENAI_API_KEY, DEEPSEEK_API_KEY, GEMINI_API_KEY); skipping onboarding" >&2
  fi
fi

# The Gateway refuses to come up while any plugin still needs capability
# consent -- onboarding installs provider plugins that ask for it, and there is
# no prompt to answer in here. Run it once, read which plugins it named, accept
# those, and move on. Only the first start pays for this.
consent_to_plugins() {
  local log=/tmp/gateway-preflight.log ids id pid
  : > "$log"
  # Started directly, not under `timeout`: killing a `timeout` wrapper can
  # orphan the gateway, which then keeps its state-directory lease and blocks
  # the real gateway below. The loop bounds the wait instead.
  openclaw gateway run --bind loopback --port "$OPENCLAW_INTERNAL_PORT" > "$log" 2>&1 &
  pid=$!
  for _ in $(seq 1 60); do
    grep -q "requires capability consent" "$log" && break
    grep -qiE "gateway (is )?ready|listening on" "$log" && break
    kill -0 "$pid" 2>/dev/null || break
    sleep 2
  done
  # SIGTERM and wait: a gateway that shuts down cleanly releases its lease.
  kill -TERM "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true

  # `|| true`: no plugin needing consent is the normal case on recent
  # releases, and a no-match grep must not trip set -e/pipefail.
  ids="$(grep -oE 'Plugin "[^"]+" requires capability consent' "$log" | cut -d'"' -f2 | sort -u || true)"
  [ -n "$ids" ] || return 0
  for id in $ids; do
    echo "openclaw: accepting capabilities for plugin '$id' ..." >&2
    openclaw plugins install "$id" --accept-capabilities >/dev/null 2>&1 \
      || openclaw plugins enable "$id" --accept-capabilities >/dev/null 2>&1 \
      || echo "openclaw: could not enable plugin '$id'" >&2
  done
}

# Inside an AgentDorm, register the commons as an MCP tool server. The entry
# carries DORM_NAME because MCP servers start with a minimal environment.
register_dorm_mcp() {
  [ -n "${DORM_NAME:-}" ] && [ -x /usr/local/bin/dorm-mcp ] || return 0
  openclaw mcp set dorm "{\"command\":\"/usr/local/bin/dorm-mcp\",\"args\":[],\"env\":{\"DORM_NAME\":\"${DORM_NAME}\",\"DORM_DIR\":\"/dorm\",\"PATH\":\"/usr/local/bin:/usr/bin:/bin\"}}" \
    >/dev/null 2>&1 || echo "openclaw: could not register the dorm MCP server" >&2
}

if [ "${1:-}" = "gateway" ]; then
  shift

  register_dorm_mcp

  if [ ! -f "$OPENCLAW_STATE_DIR/.agentdorm-plugins-accepted" ]; then
    consent_to_plugins
    touch "$OPENCLAW_STATE_DIR/.agentdorm-plugins-accepted"
  fi
  # The Gateway is the control plane for an agent with shell access, so it
  # stays on container loopback; socat bridges the published port, which the
  # host maps to 127.0.0.1 only.
  socat "TCP-LISTEN:${OPENCLAW_BRIDGE_PORT},fork,reuseaddr" \
        "TCP:127.0.0.1:${OPENCLAW_INTERNAL_PORT}" &

  # The Control UI needs the gateway token in its URL; print it once the
  # gateway answers, so the line is there to click.
  (
    for _ in $(seq 1 60); do
      if openclaw dashboard --no-open --json >/tmp/dashboard.json 2>/dev/null; then
        # The URL it prints carries the container's own port; rewrite it to the
        # published one, keeping the token fragment that authenticates the UI.
        token="$(jq -r '.url // empty' /tmp/dashboard.json 2>/dev/null | sed -n 's/.*#//p')"
        if [ -n "$token" ]; then
          echo "openclaw: Control UI http://localhost:${OPENCLAW_PORT}/#${token}" >&2
          break
        fi
      fi
      sleep 2
    done
  ) &

  echo "openclaw: serving http://localhost:${OPENCLAW_PORT} (container loopback ${OPENCLAW_INTERNAL_PORT} via bridge ${OPENCLAW_BRIDGE_PORT})" >&2
  set -- gateway run --bind loopback --port "$OPENCLAW_INTERNAL_PORT" "$@"
fi

exec openclaw "$@"
