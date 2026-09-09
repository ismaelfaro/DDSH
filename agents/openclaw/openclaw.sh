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
# Run the OpenClaw Control UI against the CURRENT directory.
#   ./openclaw.sh            # serve http://localhost:18789 over $PWD
#   OPENCLAW_PORT=9200 ./openclaw.sh
#   ./openclaw.sh doctor     # any other openclaw command
#   OPENCLAW_DETACH=1 ./openclaw.sh       # run in the background
set -euo pipefail

# --- DeepHarness portable preflight (macOS first, Linux/BSD/Git-Bash OK) ---
command -v docker >/dev/null 2>&1 || {
  echo "error: docker not found. Install Docker Desktop (macOS/Windows) or Docker Engine (Linux)," >&2
  echo "  then re-run: $0" >&2
  exit 1
}
docker info >/dev/null 2>&1 || {
  echo "error: docker daemon not responding. Start Docker Desktop (or 'sudo systemctl start docker' on Linux)," >&2
  echo "  then re-run: $0" >&2
  exit 1
}

# sha256 of stdin, using whatever the host has (macOS: shasum, Linux: sha256sum).
sha256_stdin() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha256 -r | cut -d' ' -f1
  else python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())'
  fi
}

IMAGE="${OPENCLAW_IMAGE:-openclaw-web:local}"
PORT="${OPENCLAW_PORT:-18789}"
# Resolve HERE even when invoked via a symlink (no readlink -f on macOS).
_SOURCE="${BASH_SOURCE[0]:-$0}"
while [ -L "$_SOURCE" ]; do
  _DIR="$(cd "$(dirname "$_SOURCE")" && pwd)"
  _SOURCE="$(readlink "$_SOURCE")"
  case "$_SOURCE" in /*) ;; *) _SOURCE="$_DIR/$_SOURCE" ;; esac
done
HERE="$(cd "$(dirname "$_SOURCE")" && pwd)"

# Persistent host folders, both owned by the container's `openclaw` user (1000).
#   .harness — $OPENCLAW_STATE_DIR: config, sessions, memory, plugins, creds
#   .DHC     — /opt/openclaw: the Hermes venv, seeded from the image on first start
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
FPRINT="$(cat "$HERE/Dockerfile" "$HERE/entrypoint.sh" | sha256_stdin)"
if ! docker image inspect "$IMAGE" >/dev/null 2>&1 \
   || [ "$(docker image inspect -f '{{ index .Config.Labels "openclaw-fingerprint" }}' "$IMAGE" 2>/dev/null || true)" != "$FPRINT" ]; then
  echo "building $IMAGE ..." >&2
  docker build --label "openclaw-fingerprint=$FPRINT" -t "$IMAGE" "$HERE"
fi

# Interactive only when there is a terminal to attach to.
TTY=()
if [ -t 0 ]; then TTY=(-it); fi

# OPENCLAW_DETACH=1 leaves the dashboard running in the background instead of
# holding the terminal (stop it with `docker rm -f <name>`).
RUN_MODE=()
if [ -n "${OPENCLAW_DETACH:-}" ]; then
  RUN_MODE=(-d)
  TTY=()
fi

# Docker container names allow [a-zA-Z0-9_.-]; slugify $PWD's basename.
_SLUG="$(basename "$PWD" | tr -c 'a-zA-Z0-9_.-' '-' | cut -c1-64)"
[ -n "$_SLUG" ] || _SLUG="workspace"
NAME="openclaw-$_SLUG-$PORT"

# A previous crashed run can leave its name behind; reuse is fine if stopped.
# If one is still RUNNING (e.g. a crashed entrypoint left socat alive), say
# so plainly instead of surfacing a raw daemon conflict.
if ! docker rm "$NAME" >/dev/null 2>&1 && docker container inspect "$NAME" >/dev/null 2>&1; then
  echo "error: container $NAME is already running (port 127.0.0.1:$PORT busy)." >&2
  echo "  stop it first:  docker rm -f $NAME" >&2
  exit 1
fi

exec docker run --rm --init ${RUN_MODE[@]+"${RUN_MODE[@]}"} ${TTY[@]+"${TTY[@]}"} \
  --name "$NAME" \
  -p "127.0.0.1:${PORT}:18790" \
  -e NOUS_API_KEY \
  -e OPENAI_API_KEY \
  -e ANTHROPIC_API_KEY \
  -e OPENROUTER_API_KEY \
  -e OPENROUTER_BASE_URL \
  -e DEEPSEEK_API_KEY \
  -e GEMINI_API_KEY \
  -e MINIMAX_API_KEY \
  -e OPENCLAW_PORT="$PORT" \
  -e HOST_WORKSPACE="$PWD" \
  -v "$PWD:/workspace" \
  -v "$HARNESS_DIR:/openclaw" \
  -v "$DHC_DIR:/opt/openclaw" \
  -w /workspace \
  "$IMAGE" "${@:-gateway}"
