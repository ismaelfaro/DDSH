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
#
# Run the DeepSeek Harness web UI against the CURRENT directory.
#   ./dsh.sh              # serve http://localhost:3080 over $PWD
#   DSH_PORT=3090 ./dsh.sh
#   ./dsh.sh plugin --profile web add <pkg>   # any other dsh command
set -euo pipefail

IMAGE="${DSH_IMAGE:-dsh-web:local}"
PORT="${DSH_PORT:-3080}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Persistent host folders, both owned by the container's `node` user (1000).
#   .harness — $DSH_HOME: profiles, plugins, settings, credentials
#   .DHC     — /opt/dsh: the harness dependency tree, seeded on first start
HARNESS_DIR="$HERE/.harness"
DHC_DIR="$HERE/.DHC"
mkdir -p "$HARNESS_DIR" "$DHC_DIR"

# Bind-mount permissions only matter on Linux; Docker Desktop maps any host
# uid into the VM, so the check is noise there.
if [ "$(uname)" != "Darwin" ] && [ "$(id -u)" != "0" ]; then
  for d in "$HARNESS_DIR" "$DHC_DIR"; do
    if [ "$(stat -c %u "$d")" != "1000" ]; then
      sudo -n chown -R 1000:1000 "$d" 2>/dev/null \
        || echo "warning: $d not writable by uid 1000; run 'sudo chown -R 1000:1000 \"$d\"' if the container fails to start" >&2
    fi
  done
fi

# Rebuild when the image is missing OR Dockerfile/entrypoint.sh changed since
# the last build (fingerprint label), so an outdated image can't shadow fixes.
FPRINT="$(cat "$HERE/Dockerfile" "$HERE/entrypoint.sh" | shasum -a 256 | cut -d' ' -f1)"
if ! docker image inspect "$IMAGE" >/dev/null 2>&1 \
   || [ "$(docker image inspect -f '{{ index .Config.Labels "dsh-fingerprint" }}' "$IMAGE" 2>/dev/null || true)" != "$FPRINT" ]; then
  echo "building $IMAGE ..." >&2
  docker build --label "dsh-fingerprint=$FPRINT" -t "$IMAGE" "$HERE"
fi

# Interactive only when there is a terminal to attach to.
TTY=()
[ -t 0 ] && TTY=(-it)

NAME="dsh-$(basename "$PWD")-$PORT"

# A previous crashed run can leave its name behind; reuse is fine if stopped.
# If one is still RUNNING (e.g. a crashed entrypoint left socat alive), say
# so plainly instead of surfacing a raw daemon conflict.
if ! docker rm "$NAME" >/dev/null 2>&1 && docker container inspect "$NAME" >/dev/null 2>&1; then
  echo "error: container $NAME is already running (port 127.0.0.1:$PORT busy)." >&2
  echo "  stop it first:  docker rm -f $NAME" >&2
  exit 1
fi

exec docker run --rm --init ${TTY[@]+"${TTY[@]}"} \
  --name "$NAME" \
  -p "127.0.0.1:${PORT}:13080" \
  -e DEEPSEEK_API_KEY \
  -e OPENROUTER_API_KEY \
  -e OPENROUTER_BASE_URL \
  -e OPENROUTER_MODELS \
  -e DSH_TRUSTED_HOSTS \
  -e DSH_PORT="$PORT" \
  -v "$PWD:/workspace" \
  -v "$HARNESS_DIR:/dsh" \
  -v "$DHC_DIR:/opt/dsh" \
  -w /workspace \
  "$IMAGE" "${@:-web}"
