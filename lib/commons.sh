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
# The commons: one host folder mounted at /dorm in every agent. The file format
# is owned by dorm/dorm; this side only creates the folder and keeps the
# directory of who lives here.

ad_commons_dir() {
  local d
  d="$(ad_home)/commons"
  if [ ! -d "$d/directory" ]; then
    mkdir -p "$d/directory" "$d/inbox" "$d/board"
    # Containers run as different uids; the commons is local-only and shared
    # by design, so everyone may write.
    chmod 0777 "$d" "$d/directory" "$d/inbox" "$d/board" 2>/dev/null || true
  fi
  # The human is a member too, so agents can `dorm send owner ...`.
  if [ ! -f "$d/directory/owner" ]; then
    printf 'agent=human\nsummary=The human who runs this dorm. Ask when you need a decision.\n' > "$d/directory/owner"
    mkdir -p "$d/inbox/owner/new" "$d/inbox/owner/read" "$d/inbox/owner/tmp"
    chmod -R 0777 "$d/inbox/owner" 2>/dev/null || true
    chmod 0666 "$d/directory/owner" 2>/dev/null || true
  fi
  # Refresh the protocol on every launch so agents read the current version.
  cp "$AD_ROOT/dorm/PROTOCOL.md" "$d/PROTOCOL.md" 2>/dev/null || true
  printf '%s\n' "$d"
}

# ad_commons_register <dorm-name> <agent> <container> <host-port> [summary]
ad_commons_register() {
  local d f summary="${5:-${LAUNCH_SUMMARY:-}}"
  d="$(ad_commons_dir)"
  f="$d/directory/$1"
  {
    printf 'agent=%s\n' "$2"
    printf 'container=%s\n' "$3"
    printf 'host_url=http://localhost:%s%s\n' "$4" "$AGENT_URL_PATH"
    printf 'internal_url=http://%s:%s\n' "$1" "$AGENT_CONTAINER_PORT"
    printf 'resident=%s\n' "${LAUNCH_RESIDENT:-}"
    printf 'summary=%s\n' "$summary"
    printf 'registered=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } > "$f"
  chmod 0666 "$f" 2>/dev/null || true
  mkdir -p "$d/inbox/$1/new" "$d/inbox/$1/read" "$d/inbox/$1/tmp"
  chmod -R 0777 "$d/inbox/$1" 2>/dev/null || true
}

# Run the dorm CLI from the host, as $1 (default: "owner", the human).
ad_dorm_host() {
  local as="$1"
  shift
  DORM_DIR="$(ad_commons_dir)" DORM_NAME="$as" sh "$AD_ROOT/dorm/dorm" "$@"
}
