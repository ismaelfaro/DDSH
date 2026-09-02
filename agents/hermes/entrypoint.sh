#!/usr/bin/env bash
# Copyright 2026 DeepHarness contributors
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

# /opt/hermes may be a host bind mount (.DHC). On first start it is empty, so
# copy the image's seed venv into it once; afterwards anything Hermes installs
# for itself persists across containers.
if [ ! -x /opt/hermes/bin/hermes ]; then
  echo "hermes: seeding /opt/hermes from the image (first start only) ..." >&2
  cp -a /opt/hermes-seed/. /opt/hermes/
fi

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
echo "hermes: workspace ${HOST_WORKSPACE:-(host folder)} -> /workspace" >&2

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
