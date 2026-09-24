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

# Port published out of the container. Hermes itself always binds loopback.
HERMES_PORT="${HERMES_PORT:-9119}"
# Internal loopback port the dashboard serves on.
HERMES_INTERNAL_PORT="${HERMES_INTERNAL_PORT:-9119}"
# Port socat listens on for the published-port NAT.
HERMES_BRIDGE_PORT="${HERMES_BRIDGE_PORT:-19119}"

# /opt/hermes may be a host bind mount (.deps). Fill it from the image's seed on
# first start, and REPLACE it whenever the image was rebuilt (the seed stamp
# differs): otherwise an upgrade would keep running the old copy persisted in
# .deps. Replaced wholesale, not merged, so no stale package shadows a new one.
refresh_seed() {
  seed=/opt/hermes-seed target=/opt/hermes
  if [ -f "$target/.agentdorm-seed" ] && cmp -s "$seed/.agentdorm-seed" "$target/.agentdorm-seed"; then
    return 0
  fi
  if [ -n "$(ls -A "$target" 2>/dev/null)" ]; then
    echo "hermes: image changed; refreshing $target from it ..." >&2
  else
    echo "hermes: seeding $target from the image (first start) ..." >&2
  fi
  find "$target" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  cp -a "$seed/." "$target/"
}
refresh_seed

# `setup-model` is the interactive two-step picker hermes.sh runs on a fresh
# .harness; it writes the config and exits without starting anything.
if [ "${1:-}" = "setup-model" ]; then
  exec /usr/local/bin/configure-model.sh --interactive
fi

# The container can only see the folder hermes.sh was launched from, mounted
# at /workspace, so pin the agent's terminal there on every start: `terminal.cwd`
# defaults to "." (the process cwd, which is already /workspace) but an explicit
# path is what the UI shows, and it cannot drift to a directory that does not
# exist in here.
hermes config set terminal.cwd /workspace >/dev/null 2>&1 || true
echo "hermes: workspace ${HOST_WORKSPACE:-(host folder)} -> /workspace (and \$HOME)" >&2

# Inside an AgentDorm, register the commons as an MCP tool server so the agent
# gets typed `send`/`inbox`/`read`/`who` tools. The MCP client starts servers
# with a minimal environment, so DORM_NAME is written into the entry itself;
# rewriting it on every start keeps it right if the resident is renamed.
if [ -n "${DORM_NAME:-}" ] && [ -x /usr/local/bin/dorm-mcp ]; then
  /opt/hermes/bin/python - <<'PYEOF' || echo "hermes: could not register the dorm MCP server" >&2
import os, pathlib, yaml
path = pathlib.Path(os.environ.get("HERMES_HOME", "/hermes")) / "config.yaml"
cfg = (yaml.safe_load(path.read_text()) if path.exists() else None) or {}
servers = cfg.get("mcp_servers")
if not isinstance(servers, dict):
    servers = {}
servers["dorm"] = {
    "command": "/usr/local/bin/dorm-mcp",
    "args": [],
    "env": {"DORM_NAME": os.environ["DORM_NAME"], "DORM_DIR": "/dorm",
            "PATH": "/usr/local/bin:/usr/bin:/bin"},
}
cfg["mcp_servers"] = servers
path.write_text(yaml.safe_dump(cfg, sort_keys=False, default_flow_style=False))
PYEOF
fi

# Otherwise resolve provider + model from the environment and persist them to
# $HERMES_HOME/config.yaml (see configure-model.sh for the rules).
/usr/local/bin/configure-model.sh || true

if [ "${1:-}" = "dashboard" ]; then
  shift
  # The dashboard stores API keys and ships no auth, so it must never bind
  # 0.0.0.0. It stays on container loopback and socat bridges the published
  # port, which the host maps to 127.0.0.1 only.
  socat "TCP-LISTEN:${HERMES_BRIDGE_PORT},fork,reuseaddr" \
        "TCP:127.0.0.1:${HERMES_INTERNAL_PORT}" &
  echo "hermes: serving http://localhost:${HERMES_PORT} (container loopback ${HERMES_INTERNAL_PORT} via bridge ${HERMES_BRIDGE_PORT})" >&2

  # No browser inside the container.
  set -- dashboard --no-open --host 127.0.0.1 --port "$HERMES_INTERNAL_PORT" "$@"
fi

exec hermes "$@"
