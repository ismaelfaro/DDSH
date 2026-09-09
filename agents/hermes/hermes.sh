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
# Run the Hermes Agent dashboard against the CURRENT directory.
#   ./hermes.sh            # serve http://localhost:9119 over $PWD
#                          # (if 9119 is busy, the next free port is used)
#   HERMES_PORT=9200 ./hermes.sh      # exact port; errors out if it is busy
#   ./hermes.sh chat       # any other hermes command
#   HERMES_SETUP=always ./hermes.sh   # re-run the provider/model picker
#   HERMES_DETACH=1 ./hermes.sh       # run in the background
set -euo pipefail

# --- AgentDorm portable preflight (macOS first, Linux/BSD/Git-Bash OK) ---
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

IMAGE="${HERMES_IMAGE:-hermes-web:local}"
PORT="${HERMES_PORT:-9119}"
# An explicit HERMES_PORT is honoured as-is; only the default is auto-bumped.
PORT_EXPLICIT="${HERMES_PORT+1}"
# Resolve HERE even when invoked via a symlink (no readlink -f on macOS).
_SOURCE="${BASH_SOURCE[0]:-$0}"
while [ -L "$_SOURCE" ]; do
  _DIR="$(cd "$(dirname "$_SOURCE")" && pwd)"
  _SOURCE="$(readlink "$_SOURCE")"
  case "$_SOURCE" in /*) ;; *) _SOURCE="$_DIR/$_SOURCE" ;; esac
done
HERE="$(cd "$(dirname "$_SOURCE")" && pwd)"

# Persistent host folders, both owned by the container's `hermes` user (1000).
#   .harness — $HERMES_HOME: profile, skills, memories, sessions, settings
#   .deps    — /opt/hermes: the Hermes venv, seeded from the image on first start
HARNESS_DIR="$HERE/.harness"
DEPS_DIR="$HERE/.deps"
# .DHC was this directory's name before the project was renamed.
[ -d "$HERE/.DHC" ] && [ ! -d "$DEPS_DIR" ] && mv "$HERE/.DHC" "$DEPS_DIR"
mkdir -p "$HARNESS_DIR" "$DEPS_DIR"

# Bind-mount permissions only matter on Linux; Docker Desktop maps any host
# uid into the VM, so the check is noise there.
if [ "$(uname)" != "Darwin" ] && [ "$(id -u)" != "0" ]; then
  for d in "$HARNESS_DIR" "$DEPS_DIR"; do
    if [ "$(stat -c %u "$d")" != "1000" ]; then
      sudo -n chown -R 1000:1000 "$d" 2>/dev/null \
        || echo "warning: $d not writable by uid 1000; run 'sudo chown -R 1000:1000 \"$d\"' if the container fails to start" >&2
    fi
  done
fi

# Rebuild when the image is missing OR Dockerfile/entrypoint.sh changed since
# the last build (fingerprint label), so an outdated image can't shadow fixes.
FPRINT="$(cat "$HERE/Dockerfile" "$HERE/entrypoint.sh" "$HERE/configure-model.sh" | sha256_stdin)"
if ! docker image inspect "$IMAGE" >/dev/null 2>&1 \
   || [ "$(docker image inspect -f '{{ index .Config.Labels "hermes-fingerprint" }}' "$IMAGE" 2>/dev/null || true)" != "$FPRINT" ]; then
  echo "building $IMAGE ..." >&2
  docker build --label "hermes-fingerprint=$FPRINT" -t "$IMAGE" "$HERE"
fi

# Interactive only when there is a terminal to attach to.
TTY=()
if [ -t 0 ]; then TTY=(-it); fi

# HERMES_DETACH=1 leaves the dashboard running in the background instead of
# holding the terminal (stop it with `docker rm -f <name>`).
RUN_MODE=()
if [ -n "${HERMES_DETACH:-}" ]; then
  RUN_MODE=(-d)
  TTY=()
fi

# First run in a terminal with nothing configured yet: pick provider + model
# in two steps and write them to .harness/config.yaml. Everything afterwards
# is owned by the dashboard, `hermes model`, or the agent itself.
if [ -t 0 ] && [ "${HERMES_SETUP:-auto}" != "never" ] \
   && { [ "${HERMES_SETUP:-auto}" = "always" ] \
        || ! grep -qE '^[[:space:]]+default:' "$HARNESS_DIR/config.yaml" 2>/dev/null; }; then
  docker run --rm -it --init \
    -e NOUS_API_KEY -e OPENAI_API_KEY -e ANTHROPIC_API_KEY \
    -e OPENROUTER_API_KEY -e OPENROUTER_BASE_URL -e DEEPSEEK_API_KEY \
    -e GEMINI_API_KEY -e MINIMAX_API_KEY \
    -e HERMES_BASE_URL -e HERMES_CONTEXT_LENGTH -e HERMES_FALLBACKS \
    -v "$HARNESS_DIR:/hermes" \
    -v "$DEPS_DIR:/opt/hermes" \
    --entrypoint /usr/local/bin/entrypoint.sh \
    "$IMAGE" setup-model || echo "hermes: setup skipped; falling back to the environment" >&2
fi

# The container name is derived from $PWD, so the same port can still be held
# by a hermes started from a different directory, or by an unrelated process.
# Find who has it, so we can bump past it instead of surfacing a raw daemon
# "Bind for 127.0.0.1:$PORT failed" much further down.
port_holder() {
  docker ps --filter "publish=$1" --format '{{.Names}}' 2>/dev/null | head -n 1
}
# Portable port probe: bash /dev/tcp first, then nc, then python3.
# (The old inline /dev/tcp-only check breaks under zsh/sh and minimal shells.)
port_busy() {
  [ -n "$(port_holder "$1")" ] && return 0
  if (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; then
    exec 3>&- 3<&- 2>/dev/null || true
    return 0
  fi
  if command -v nc >/dev/null 2>&1 && nc -z 127.0.0.1 "$1" 2>/dev/null; then
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    python3 -c 'import socket,sys; s=socket.socket(); s.settimeout(0.5); sys.exit(0 if s.connect_ex(("127.0.0.1", int(sys.argv[1])))==0 else 1)' "$1" 2>/dev/null && return 0
  fi
  return 1
}

if port_busy "$PORT"; then
  HOLDER="$(port_holder "$PORT")"
  if [ -n "$PORT_EXPLICIT" ]; then
    echo "error: port 127.0.0.1:$PORT is already in use${HOLDER:+ by container $HOLDER}." >&2
    [ -n "$HOLDER" ] && echo "  stop it:        docker rm -f $HOLDER" >&2
    echo "  or use another: HERMES_PORT=$((PORT + 1)) $0" >&2
    exit 1
  fi
  BUSY="$PORT"
  for _ in 1 2 3 4 5 6 7 8 9; do
    PORT=$((PORT + 1))
    port_busy "$PORT" || break
  done
  if port_busy "$PORT"; then
    echo "error: ports $BUSY-$PORT are all in use; pass HERMES_PORT=<free port>." >&2
    exit 1
  fi
  echo "hermes: port $BUSY busy${HOLDER:+ (container $HOLDER)}; using $PORT instead" >&2
fi

# Docker container names allow [a-zA-Z0-9_.-]; slugify $PWD's basename.
_SLUG="$(basename "$PWD" | tr -c 'a-zA-Z0-9_.-' '-' | cut -c1-64)"
[ -n "$_SLUG" ] || _SLUG="workspace"
NAME="hermes-$_SLUG-$PORT"

# A previous crashed run can leave its name behind; reuse is fine if stopped.
# If one is still RUNNING (e.g. a crashed entrypoint left socat alive), say
# so plainly instead of surfacing a raw daemon conflict.
if ! docker rm "$NAME" >/dev/null 2>&1 && docker container inspect "$NAME" >/dev/null 2>&1; then
  echo "error: container $NAME is already running (port 127.0.0.1:$PORT busy)." >&2
  echo "  stop it first:  docker rm -f $NAME" >&2
  exit 1
fi

# $PWD is mounted twice on purpose. /workspace is the path the UI shows and
# terminal.cwd points at; /home/hermes is the container user's HOME, so a file
# the agent writes to `~` (or to a bare relative path from a tool that starts in
# HOME) lands in the launch folder too, not in a container-only directory that
# disappears with `--rm`. Side effect: the agent's dotfiles (.bash_history,
# .cache, ...) are now created in that folder as well.
exec docker run --rm --init ${RUN_MODE[@]+"${RUN_MODE[@]}"} ${TTY[@]+"${TTY[@]}"} \
  --name "$NAME" \
  -p "127.0.0.1:${PORT}:19119" \
  -e NOUS_API_KEY \
  -e OPENAI_API_KEY \
  -e ANTHROPIC_API_KEY \
  -e OPENROUTER_API_KEY \
  -e OPENROUTER_BASE_URL \
  -e DEEPSEEK_API_KEY \
  -e HERMES_PROVIDER \
  -e HERMES_MODEL \
  -e HERMES_MODELS \
  -e HERMES_MODEL_PREFER \
  -e HERMES_MODEL_REWRITE \
  -e HERMES_BASE_URL \
  -e HERMES_CONTEXT_LENGTH \
  -e HERMES_FALLBACKS \
  -e GEMINI_API_KEY \
  -e MINIMAX_API_KEY \
  -e HERMES_PORT="$PORT" \
  -e HOST_WORKSPACE="$PWD" \
  -v "$PWD:/workspace" \
  -v "$PWD:/home/hermes" \
  -v "$HARNESS_DIR:/hermes" \
  -v "$DEPS_DIR:/opt/hermes" \
  -w /workspace \
  "$IMAGE" "${@:-dashboard}"
