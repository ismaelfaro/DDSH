# shellcheck shell=bash
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
# One code path for every agent. What differs between them -- image, ports,
# mount points, env passthrough -- is data in agents/<name>/agent.conf; the few
# behaviours that are genuinely agent-specific live in agents/<name>/hooks.sh.

# Every agent that has a descriptor, one per line.
ad_agents() {
  local d
  for d in "$AD_ROOT"/agents/*/; do
    [ -f "$d/agent.conf" ] && basename "$d"
  done
}

# Load agents/<name>/agent.conf (and hooks.sh) into AGENT_* variables.
ad_load_agent() {
  local name="$1" dir="$AD_ROOT/agents/$1"
  [ -f "$dir/agent.conf" ] || ad_die "unknown agent '$name' (known: $(ad_agents | tr '\n' ' '))"
  # Reset, so a value from a previously loaded agent can't leak through.
  AGENT_TITLE="" AGENT_UPSTREAM="" AGENT_IMAGE="" AGENT_PORT="" AGENT_CONTAINER_PORT=""
  AGENT_URL_PATH="/" AGENT_STATE_MOUNT="" AGENT_DEPS_MOUNT="" AGENT_WORKSPACE_MOUNTS=""
  AGENT_CMD="" AGENT_UID=1000 AGENT_FINGERPRINT_FILES="Dockerfile entrypoint.sh"
  AGENT_ENV="" AGENT_IDENTITY="none"
  unset -f agent_pre_run agent_url 2>/dev/null || true
  # shellcheck source=/dev/null
  . "$dir/agent.conf"
  # shellcheck source=/dev/null
  [ -f "$dir/hooks.sh" ] && . "$dir/hooks.sh"
  AGENT_NAME="$name"
  AGENT_DIR="$dir"
  # Legacy per-agent env prefix (HERMES_PORT, DSH_DETACH, ...), kept working.
  AGENT_PREFIX="$(printf '%s' "$name" | tr 'a-z-' 'A-Z_')"
  # An image override in the environment wins, e.g. HERMES_IMAGE=hermes-web:dev.
  local override
  override="$(ad_env "${AGENT_PREFIX}_IMAGE")"
  [ -n "$override" ] && AGENT_IMAGE="$override"
  return 0
}

# Value of an environment variable named by $1 ('' when unset). bash 3.2 has
# no ${!name:-} under set -u without this guard.
ad_env() { eval "printf '%s' \"\${$1:-}\""; }

# Build the image when it is missing or its inputs changed since the last build.
# The fingerprint label keeps the key the per-agent scripts used, so images
# built before the CLI existed are recognised instead of rebuilt.
ad_ensure_image() {
  local fp current f
  fp="$(cd "$AGENT_DIR" && for f in $AGENT_FINGERPRINT_FILES; do cat "$f"; done | ad_sha256)"
  current="$(docker image inspect -f "{{ index .Config.Labels \"${AGENT_NAME}-fingerprint\" }}" "$AGENT_IMAGE" 2>/dev/null || true)"
  if [ "${1:-}" = "--force" ] || [ "$current" != "$fp" ]; then
    ad_log "building $AGENT_IMAGE ..."
    docker build --label "${AGENT_NAME}-fingerprint=$fp" -t "$AGENT_IMAGE" "$AGENT_DIR" >&2 \
      || ad_die "build of $AGENT_IMAGE failed"
  fi
}

# Launch one agent container. Callers fill LAUNCH_* first:
#   LAUNCH_NAME        container name
#   LAUNCH_DORM_NAME   name other agents address it by in the commons
#   LAUNCH_WORKSPACE   host folder mounted as the work root
#   LAUNCH_STATE       host folder for $AGENT_STATE_MOUNT
#   LAUNCH_PORT        host port (127.0.0.1 only)
#   LAUNCH_DETACH      non-empty -> background
#   LAUNCH_RESIDENT    resident name, '' for a plain `run`
#   LAUNCH_EGRESS      'open' (default) or 'allowlist' (see lib/gate.sh)
# and pass the agent's own arguments. Foreground runs exec docker and never return.
ad_launch() {
  local deps="$AGENT_DIR/.deps" m first="" port_args net_args
  local -a args env_args mount_args tty cmd
  args=() env_args=() mount_args=() tty=() cmd=()

  # .DHC was the deps folder's name before the project was renamed.
  if [ -d "$AGENT_DIR/.DHC" ] && [ ! -d "$deps" ]; then mv "$AGENT_DIR/.DHC" "$deps"; fi
  mkdir -p "$LAUNCH_STATE"
  [ -n "$AGENT_DEPS_MOUNT" ] && mkdir -p "$deps"
  ad_fix_ownership "$AGENT_UID" "$LAUNCH_STATE" "$deps"

  for m in $AGENT_WORKSPACE_MOUNTS; do
    [ -z "$first" ] && first="$m"
    mount_args+=(-v "$LAUNCH_WORKSPACE:$m")
  done
  mount_args+=(-v "$LAUNCH_STATE:$AGENT_STATE_MOUNT")
  [ -n "$AGENT_DEPS_MOUNT" ] && mount_args+=(-v "$deps:$AGENT_DEPS_MOUNT")

  # The commons: a shared folder every agent can read and write, plus the
  # `dorm` CLI that speaks its message format.
  local commons
  commons="$(ad_commons_dir)"
  ad_commons_register "$LAUNCH_DORM_NAME" "$AGENT_NAME" "$LAUNCH_NAME" "$LAUNCH_PORT"
  mount_args+=(-v "$commons:/dorm" -v "$AD_ROOT/dorm/dorm:/usr/local/bin/dorm:ro"
               -v "$AD_ROOT/dorm/dorm-mcp:/usr/local/bin/dorm-mcp:ro")

  local var
  for var in $AGENT_ENV; do env_args+=(-e "$var"); done
  env_args+=(-e "${AGENT_PREFIX}_PORT=$LAUNCH_PORT"
             -e "HOST_WORKSPACE=$LAUNCH_WORKSPACE"
             -e "DORM_NAME=$LAUNCH_DORM_NAME"
             -e "DORM_AGENT=$AGENT_NAME"
             -e "DORM_RESIDENT=${LAUNCH_RESIDENT:-}")

  if [ -n "$LAUNCH_DETACH" ]; then
    args+=(-d)
  elif [ -t 0 ] && [ -t 1 ]; then
    tty=(-it)
  fi

  ad_ensure_network
  if [ "${LAUNCH_EGRESS:-open}" = "allowlist" ]; then
    # Egress-restricted: no route out except the resident's gate, which also
    # publishes its port (internal networks cannot publish). See lib/gate.sh.
    net_args="--network $(ad_gate_network "$LAUNCH_RESIDENT")"
    port_args=""
    env_args+=(-e "HTTP_PROXY=http://$(ad_gate_name "$LAUNCH_RESIDENT"):8888"
               -e "HTTPS_PROXY=http://$(ad_gate_name "$LAUNCH_RESIDENT"):8888"
               -e "http_proxy=http://$(ad_gate_name "$LAUNCH_RESIDENT"):8888"
               -e "https_proxy=http://$(ad_gate_name "$LAUNCH_RESIDENT"):8888"
               -e "NO_PROXY=localhost,127.0.0.1" -e "no_proxy=localhost,127.0.0.1"
               -e "NODE_USE_ENV_PROXY=1")
  else
    net_args="--network $AD_NETWORK"
    port_args="127.0.0.1:${LAUNCH_PORT}:${AGENT_CONTAINER_PORT}"
  fi

  if [ "$#" -gt 0 ]; then cmd=("$@")
  elif [ -n "$AGENT_CMD" ]; then cmd=("$AGENT_CMD")
  fi

  # A stopped leftover with the same name is fine to replace; a running one
  # means the caller should stop it first.
  if ! docker rm "$LAUNCH_NAME" >/dev/null 2>&1 && docker container inspect "$LAUNCH_NAME" >/dev/null 2>&1; then
    ad_die "container $LAUNCH_NAME is already running. Stop it with: agentdorm stop $LAUNCH_NAME"
  fi

  # shellcheck disable=SC2086
  set -- docker run --rm --init ${args[@]+"${args[@]}"} ${tty[@]+"${tty[@]}"} \
    --name "$LAUNCH_NAME" $net_args --network-alias "$LAUNCH_DORM_NAME" \
    ${port_args:+-p "$port_args"} \
    --label "$AD_LABEL.agent=$AGENT_NAME" \
    --label "$AD_LABEL.resident=${LAUNCH_RESIDENT:-}" \
    --label "$AD_LABEL.dorm-name=$LAUNCH_DORM_NAME" \
    --label "$AD_LABEL.port=$LAUNCH_PORT" \
    --label "$AD_LABEL.workspace=$LAUNCH_WORKSPACE" \
    --label "$AD_LABEL.url-path=$AGENT_URL_PATH" \
    ${env_args[@]+"${env_args[@]}"} ${mount_args[@]+"${mount_args[@]}"} \
    -w "$first" "$AGENT_IMAGE" ${cmd[@]+"${cmd[@]}"}

  if [ -n "$LAUNCH_DETACH" ]; then
    "$@" >/dev/null || ad_die "could not start $LAUNCH_NAME"
    return 0
  fi
  exec "$@"
}

# Resolve the host port for a launch: an explicit one must be free; the default
# walks forward to the next free port so a second instance just works.
ad_pick_port() {
  local wanted="$1" explicit="$2" holder free
  if ad_port_busy "$wanted"; then
    holder="$(ad_port_holder "$wanted")"
    if [ -n "$explicit" ]; then
      ad_die "port 127.0.0.1:$wanted is already in use${holder:+ by $holder}. Pick another with --port."
    fi
    free="$(ad_free_port "$wanted")" || ad_die "ports $wanted-$((wanted + 9)) are all in use; pass --port <free port>."
    ad_log "port $wanted busy${holder:+ ($holder)}; using $free instead"
    printf '%s\n' "$free"
    return 0
  fi
  printf '%s\n' "$wanted"
}
