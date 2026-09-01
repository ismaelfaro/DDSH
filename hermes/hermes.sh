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
# Run the Hermes Agent dashboard against the CURRENT directory.
#   ./hermes.sh            # serve http://localhost:9119 over $PWD
#   HERMES_PORT=9200 ./hermes.sh
#   ./hermes.sh chat       # any other hermes command
#   HERMES_SETUP=always ./hermes.sh   # re-run the provider/model picker
#   HERMES_DETACH=1 ./hermes.sh       # run in the background
set -euo pipefail

IMAGE="${HERMES_IMAGE:-hermes-web:local}"
PORT="${HERMES_PORT:-9119}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Persistent host folders, both owned by the container's `hermes` user (1000).
#   .harness — $HERMES_HOME: profile, skills, memories, sessions, settings
#   .DHC     — /opt/hermes: the Hermes venv, seeded from the image on first start
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
FPRINT="$(cat "$HERE/Dockerfile" "$HERE/entrypoint.sh" "$HERE/configure-model.sh" | shasum -a 256 | cut -d' ' -f1)"
if ! docker image inspect "$IMAGE" >/dev/null 2>&1 \
   || [ "$(docker image inspect -f '{{ index .Config.Labels "hermes-fingerprint" }}' "$IMAGE" 2>/dev/null || true)" != "$FPRINT" ]; then
  echo "building $IMAGE ..." >&2
  docker build --label "hermes-fingerprint=$FPRINT" -t "$IMAGE" "$HERE"
fi

# Interactive only when there is a terminal to attach to.
TTY=()
[ -t 0 ] && TTY=(-it)

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
    -v "$DHC_DIR:/opt/hermes" \
    --entrypoint /usr/local/bin/entrypoint.sh \
    "$IMAGE" setup-model || echo "hermes: setup skipped; falling back to the environment" >&2
fi

NAME="hermes-$(basename "$PWD")-$PORT"

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
  -v "$HARNESS_DIR:/hermes" \
  -v "$DHC_DIR:/opt/hermes" \
  -w /workspace \
  "$IMAGE" "${@:-dashboard}"
