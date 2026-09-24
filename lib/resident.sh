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
# Residents: named, long-lived agents with a domain, their own state, a fixed
# port, and a room in the commons.
#
#   residents/<name>/resident.yaml   what it is (committed-shaped, human-edited)
#   residents/<name>/.harness/       its memory, skills, sessions, settings
#   residents/<name>/workspace/      its work root, unless resident.yaml says otherwise
#   residents/<name>/snapshots/      tarballs from `agentdorm snapshot`

ad_residents_dir() { printf '%s/residents\n' "$(ad_home)"; }
ad_resident_dir()  { printf '%s/%s\n' "$(ad_residents_dir)" "$1"; }
ad_resident_container() { printf 'agentdorm-%s\n' "$1"; }

ad_residents() {
  local d
  for d in "$(ad_residents_dir)"/*/; do
    [ -f "$d/resident.yaml" ] && basename "$d"
  done
  return 0
}

ad_valid_resident_name() {
  case "$1" in
    ''|-*|*[!a-z0-9-]*) return 1 ;;
    owner|all) return 1 ;;  # reserved addresses in the commons
    *) [ "${#1}" -le 32 ] ;;
  esac
}

# Read resident.yaml into RES_* variables.
ad_load_resident() {
  local name="$1" dir f ws
  dir="$(ad_resident_dir "$name")"
  f="$dir/resident.yaml"
  [ -f "$f" ] || ad_die "no resident '$name' (create it: agentdorm new $name --agent <agent> --description \"...\")"
  RES_NAME="$name"
  RES_DIR="$dir"
  RES_AGENT="$(ad_yaml_get "$f" agent)"
  RES_PORT="$(ad_yaml_get "$f" port)"
  RES_DESCRIPTION="$(ad_yaml_get "$f" description)"
  RES_EGRESS="$(ad_yaml_get "$f" egress)"
  RES_ALLOW="$(ad_yaml_get "$f" allow | grep -v '^\[\]$' | tr '\n' ' ' || true)"
  ws="$(ad_yaml_get "$f" workspace)"
  [ -n "$RES_AGENT" ] || ad_die "$f: 'agent:' is required"
  ad_is_number "$RES_PORT" || ad_die "$f: 'port:' must be a number"
  case "${RES_EGRESS:-open}" in open|allowlist) ;; *) ad_die "$f: 'egress:' must be open or allowlist" ;; esac
  [ -n "$RES_EGRESS" ] || RES_EGRESS="open"
  case "$ws" in
    '') RES_WORKSPACE="$dir/workspace" ;;
    /*) RES_WORKSPACE="$ws" ;;
    '~'/*) RES_WORKSPACE="$HOME/${ws#\~/}" ;;
    *)  RES_WORKSPACE="$dir/$ws" ;;
  esac
}

# Every port some resident has claimed, one per line.
ad_claimed_ports() {
  local r
  for r in $(ad_residents); do
    ad_yaml_get "$(ad_resident_dir "$r")/resident.yaml" port
  done
}

# Residents get ports from <agent default + 100> upward, clear of the range
# plain `agentdorm run` instances auto-bump through.
ad_next_resident_port() {
  local port=$(( $1 + 100 )) i=0 claimed
  claimed=" $(ad_claimed_ports | tr '\n' ' ') "
  while [ "$i" -lt 200 ]; do
    case "$claimed" in *" $port "*) ;; *) ad_port_busy "$port" || { echo "$port"; return 0; } ;; esac
    port=$((port + 1)); i=$((i + 1))
  done
  return 1
}

ad_resident_status() {
  local s
  s="$(docker inspect -f '{{.State.Status}}' "$(ad_resident_container "$1")" 2>/dev/null | tr -d '[:space:]' || true)"
  printf '%s\n' "${s:-stopped}"
}

# Start one resident, detached. Idempotent: a running resident is left alone.
ad_resident_up() {
  local name="$1" container summary
  ad_load_resident "$name"
  ad_load_agent "$RES_AGENT"
  container="$(ad_resident_container "$name")"
  if [ "$(ad_resident_status "$name")" = "running" ]; then
    ad_log "$name already running: $(ad_resident_url "$name")"
    return 0
  fi
  ad_port_busy "$RES_PORT" && ad_die "$name: port $RES_PORT is in use${RES_PORT:+ ($(ad_port_holder "$RES_PORT"))}. Change 'port:' in $RES_DIR/resident.yaml"

  mkdir -p "$RES_WORKSPACE" "$RES_DIR/.harness"
  ad_ensure_image
  ad_seed_identity "$AGENT_IDENTITY" "$name" "$RES_DESCRIPTION" "$RES_DIR/.harness" "$RES_WORKSPACE"
  summary="$(printf '%s' "$RES_DESCRIPTION" | head -n 1 | cut -c1-100)"

  if [ "$RES_EGRESS" = "allowlist" ]; then
    # shellcheck disable=SC2046
    ad_gate_up "$name" "$RES_PORT" "$name" "$AGENT_CONTAINER_PORT" \
      $(ad_gate_default_allow) $RES_ALLOW
  fi

  LAUNCH_NAME="$container"
  LAUNCH_DORM_NAME="$name"
  LAUNCH_WORKSPACE="$RES_WORKSPACE"
  LAUNCH_STATE="$RES_DIR/.harness"
  LAUNCH_PORT="$RES_PORT"
  LAUNCH_DETACH=1
  LAUNCH_RESIDENT="$name"
  LAUNCH_EGRESS="$RES_EGRESS"
  LAUNCH_SUMMARY="$summary"
  ad_launch
  ad_log "$name ($RES_AGENT) up: $(ad_resident_url "$name")"
}

ad_resident_down() {
  local name="$1"
  docker rm -f "$(ad_resident_container "$name")" >/dev/null 2>&1 || true
  ad_gate_down "$name"
  ad_log "$name stopped"
}

ad_resident_url() {
  local name="$1"
  ad_load_resident "$name"
  ad_load_agent "$RES_AGENT"
  if [ "$(ad_resident_status "$name")" = "running" ] && command -v agent_url >/dev/null 2>&1; then
    agent_url "$(ad_resident_container "$name")" "$RES_PORT"
  else
    printf 'http://localhost:%s%s\n' "$RES_PORT" "$AGENT_URL_PATH"
  fi
}

# ad_resident_new <name> <agent> <description> <port|''> <workspace|''> <egress|''> <allow...>
ad_resident_new() {
  local name="$1" agent="$2" desc="$3" port="$4" ws="$5" egress="${6:-open}" dir f a
  shift 6
  ad_valid_resident_name "$name" || ad_die "resident names are lowercase letters, digits and dashes (max 32); 'owner' and 'all' are reserved"
  dir="$(ad_resident_dir "$name")"
  [ -e "$dir/resident.yaml" ] && ad_die "resident '$name' already exists: $dir/resident.yaml"
  ad_load_agent "$agent"
  if [ -z "$port" ]; then
    port="$(ad_next_resident_port "$AGENT_PORT")" || ad_die "no free port found; pass --port"
  fi
  mkdir -p "$dir"
  f="$dir/resident.yaml"
  {
    echo "# AgentDorm resident. Edit freely; takes effect on the next 'agentdorm up'."
    echo "# The description seeds the agent's identity ONCE, on first start. After that"
    echo "# the agent owns its identity file and refines it itself."
    echo "name: $name"
    echo "agent: $agent"
    echo "port: $port"
    [ -n "$ws" ] && echo "workspace: $ws"
    echo "description: |"
    printf '%s\n' "$desc" | sed 's/^/  /'
    echo "# open: normal internet access. allowlist: only model providers for the keys"
    echo "# you have set, plus the domains under 'allow:'. Every request is logged:"
    echo "#   agentdorm logs $name --gate"
    echo "egress: $egress"
    if [ "$#" -gt 0 ]; then
      echo "allow:"
      for a in "$@"; do echo "  - $a"; done
    else
      echo "allow: []"
    fi
  } > "$f"
  ad_log "created $f"
  ad_log "start it with: agentdorm up $name"
}
