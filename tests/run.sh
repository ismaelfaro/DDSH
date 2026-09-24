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
# Tests that need no Docker: the YAML reader, naming, the commons and its CLI,
# the worker loop, the MCP server, identity seeding, and resident bookkeeping.
# Plain bash, no framework, so it runs on macOS's bash 3.2 as well as in CI.
#
#   tests/run.sh            all tests
#   tests/run.sh dorm       only tests whose name contains "dorm"
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AD_ROOT="$ROOT"
export AD_ROOT
FILTER="${1:-}"
PASS=0 FAIL=0 FAILED=""
TMP="$(mktemp -d "${TMPDIR:-/tmp}/agentdorm-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

for _lib in common yaml agent commons identity gate resident; do
  # shellcheck source=/dev/null
  . "$ROOT/lib/$_lib.sh"
done
# The libs die on error; in tests, a die inside a subshell is a failed test.

eq() { # eq <expected> <actual> <label>
  if [ "$1" = "$2" ]; then return 0; fi
  printf '    expected: %s\n    actual:   %s\n' "$1" "$2" >&2
  return 1
}
# `! cmd` never trips `set -e`, so negative checks need an explicit failure.
refute() {
  if "$@"; then echo "    expected failure: $*" >&2; return 1; fi
  return 0
}
has() { # has <haystack> <needle>
  case "$1" in *"$2"*) return 0 ;; esac
  printf '    %s\n    does not contain: %s\n' "$1" "$2" >&2
  return 1
}

run_test() {
  local name="$1"
  [ -n "$FILTER" ] && case "$name" in *"$FILTER"*) ;; *) return 0 ;; esac
  # Not `if ( ... )`: bash disables errexit for everything inside an if
  # condition, subshells included, so a failing check would go unnoticed.
  local rc
  ( set -e; "$name" ) 2>"$TMP/err"
  rc=$?
  if [ "$rc" = 0 ]; then
    PASS=$((PASS + 1)); printf '  ok    %s\n' "$name"
  else
    FAIL=$((FAIL + 1)); FAILED="$FAILED $name"; printf '  FAIL  %s\n' "$name"; sed 's/^/        /' "$TMP/err"
  fi
}

fresh_home() { # a clean AGENTDORM_HOME per test
  AGENTDORM_HOME="$TMP/home-$1"; export AGENTDORM_HOME
  rm -rf "$AGENTDORM_HOME"; mkdir -p "$AGENTDORM_HOME"
}

# ------------------------------------------------------------------ yaml

test_yaml_scalars() {
  f="$TMP/a.yaml"
  printf 'name: quantum\nagent: hermes   # comment\nport: 9219\nquoted: "a # b"\nsingle: '"'"'x y'"'"'\n' > "$f"
  eq quantum "$(ad_yaml_get "$f" name)"
  eq hermes "$(ad_yaml_get "$f" agent)"
  eq 9219 "$(ad_yaml_get "$f" port)"
  eq "a # b" "$(ad_yaml_get "$f" quoted)"
  eq "x y" "$(ad_yaml_get "$f" single)"
  eq "" "$(ad_yaml_get "$f" missing)"
}

test_yaml_block_and_list() {
  f="$TMP/b.yaml"
  printf 'description: |\n  line one\n\n  line three\nallow:\n  - arxiv.org\n  - "*.qiskit.org"\nlast: x\n' > "$f"
  eq "line one

line three" "$(ad_yaml_get "$f" description)"
  eq "arxiv.org
*.qiskit.org" "$(ad_yaml_get "$f" allow)"
  eq x "$(ad_yaml_get "$f" last)"
}

test_yaml_key_prefix_is_not_a_match() {
  f="$TMP/c.yaml"
  printf 'portal: no\nport: 1\n' > "$f"
  eq 1 "$(ad_yaml_get "$f" port)"
}

# ------------------------------------------------------------------ names

test_slug() {
  eq "my-project" "$(ad_slug "My Project")"
  eq "a.b_c" "$(ad_slug "a.b_c")"
  eq "workspace" "$(ad_slug "///")"
}

test_resident_names() {
  ad_valid_resident_name quantum
  ad_valid_resident_name web-2
  refute ad_valid_resident_name Quantum
  refute ad_valid_resident_name owner
  refute ad_valid_resident_name all
  refute ad_valid_resident_name -x
  refute ad_valid_resident_name "a/b"
}

test_every_agent_conf_loads() {
  for a in $(ad_agents); do
    ( ad_load_agent "$a"
      [ -n "$AGENT_IMAGE" ] && [ -n "$AGENT_STATE_MOUNT" ] && [ -n "$AGENT_WORKSPACE_MOUNTS" ]
      case "$AGENT_KIND" in
        web) ad_is_number "$AGENT_PORT" && ad_is_number "$AGENT_CONTAINER_PORT" ;;
        worker) [ -f "$AGENT_DIR/agent-task" ] ;;
        *) false ;;
      esac
      for f in $AGENT_FINGERPRINT_FILES; do [ -f "$AGENT_DIR/$f" ]; done
    ) || { echo "agent $a: incomplete agent.conf" >&2; return 1; }
  done
}

# ------------------------------------------------------------------ dorm CLI

dorm_as() { local who="$1"; shift; DORM_DIR="$AGENTDORM_HOME/commons" DORM_NAME="$who" sh "$ROOT/dorm/dorm" "$@"; }

test_dorm_send_inbox_read() {
  fresh_home dorm1
  ad_commons_dir >/dev/null
  AGENT_URL_PATH=/ AGENT_CONTAINER_PORT=1 AGENT_KIND=web ad_commons_register alice hermes c 1 "maths"
  AGENT_URL_PATH=/ AGENT_CONTAINER_PORT=1 AGENT_KIND=web ad_commons_register bob hermes c 2 "physics"
  dorm_as alice send bob -s "hi" "hello bob" >/dev/null
  has "$(dorm_as bob inbox)" "from alice"
  out="$(dorm_as bob read)"
  has "$out" "Subject: hi"
  has "$out" "hello bob"
  has "$(dorm_as bob inbox)" "no unread"
}

test_dorm_stdin_and_reply_header() {
  fresh_home dorm2
  ad_commons_dir >/dev/null
  echo "body from stdin" | dorm_as alice send bob --reply-to X1 -s "Re: q" >/dev/null
  out="$(dorm_as bob read)"
  has "$out" "In-Reply-To: X1"
  has "$out" "body from stdin"
}

test_dorm_broadcast_skips_sender() {
  fresh_home dorm3
  ad_commons_dir >/dev/null
  for n in alice bob carol; do
    AGENT_URL_PATH=/ AGENT_CONTAINER_PORT=1 AGENT_KIND=web ad_commons_register "$n" hermes c 1 x
  done
  has "$(dorm_as alice send all "news")" "sent to all (3)"   # bob, carol, owner
  has "$(dorm_as bob inbox)" "from alice"
  has "$(dorm_as alice inbox)" "no unread"
  has "$(dorm_as alice board)" "news"
}

test_dorm_rejects_bad_input() {
  fresh_home dorm4
  ad_commons_dir >/dev/null
  refute dorm_as alice send "../etc" "x" 2>/dev/null
  empty_send() { printf '   \n' | dorm_as alice send bob 2>/dev/null; }
  refute empty_send
}

test_dorm_owner_registered() {
  fresh_home dorm5
  ad_commons_dir >/dev/null
  has "$(dorm_as someone who)" "owner"
}

# ------------------------------------------------------------------ worker

test_worker_runs_tasks_and_ignores_replies() {
  fresh_home worker
  d="$(ad_commons_dir)"
  bin="$TMP/workerbin"; mkdir -p "$bin"
  printf '#!/bin/sh\necho "did: $(cat)"\n' > "$bin/agent-task"
  ln -sf "$ROOT/dorm/dorm" "$bin/dorm"
  chmod +x "$bin/agent-task"
  AGENT_URL_PATH=/ AGENT_CONTAINER_PORT=1 AGENT_KIND=worker ad_commons_register w1 nanoloop c "" task
  dorm_as owner send w1 -s "job" "paint the fence" >/dev/null
  dorm_as owner send w1 --reply-to OLD -s "Re: x" "a reply, not a task" >/dev/null
  PATH="$bin:$PATH" DORM_DIR="$d" DORM_NAME=w1 DORM_WORKER_POLL=1 DORM_WORKER_LOGS="$TMP/wlogs" \
    sh "$ROOT/dorm/dorm-worker" 2>"$TMP/worker.err" &
  pid=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    [ -n "$(ls "$d/inbox/owner/new" 2>/dev/null)" ] && break
    sleep 1
  done
  kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
  out="$(dorm_as owner read --all)"
  has "$out" "did: paint the fence"
  has "$out" "In-Reply-To:"
  # exactly one reply: the reply-shaped message was filed, not run
  eq 1 "$(printf '%s\n' "$out" | grep -c '^From: w1')"
  has "$(cat "$TMP/worker.err")" "is a reply; filed, not run"
}

# ------------------------------------------------------------------ MCP

test_dorm_mcp_protocol() {
  command -v python3 >/dev/null 2>&1 || { echo "(no python3; skipped)" >&2; return 0; }
  fresh_home mcp
  d="$(ad_commons_dir)"
  bin="$TMP/mcpbin"; mkdir -p "$bin"; ln -sf "$ROOT/dorm/dorm" "$bin/dorm"
  out="$(printf '%s\n' \
    '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}' \
    '{"jsonrpc":"2.0","method":"notifications/initialized"}' \
    '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' \
    '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"send","arguments":{"to":"owner","subject":"s","body":"via mcp"}}}' \
    '{"jsonrpc":"2.0","id":4,"method":"nope"}' \
    | PATH="$bin:$PATH" DORM_DIR="$d" DORM_NAME=m1 python3 "$ROOT/dorm/dorm-mcp")"
  has "$out" '"serverInfo": {"name": "dorm"'
  has "$out" '"name": "send"'
  has "$out" '"isError": false'
  has "$out" '"code": -32601'
  eq 4 "$(printf '%s\n' "$out" | grep -c jsonrpc)"   # the notification got no reply
  has "$(dorm_as owner read)" "via mcp"
}

# ------------------------------------------------------------------ identity

test_identity_seeded_once_per_mode() {
  s="$TMP/id-state"; w="$TMP/id-ws"; mkdir -p "$s" "$w"
  ad_seed_identity soul-in-state q "Quantum." "$s" "$w" 2>/dev/null
  has "$(cat "$s/SOUL.md")" "You are **q**"
  has "$(cat "$s/SOUL.md")" "Quantum."
  echo "evolved by the agent" > "$s/SOUL.md"
  ad_seed_identity soul-in-state q "Changed." "$s" "$w" 2>/dev/null
  eq "evolved by the agent" "$(cat "$s/SOUL.md")"

  ad_seed_identity soul-in-workspace q "Quantum." "$s" "$w" 2>/dev/null
  [ -f "$w/SOUL.md" ] && [ -f "$w/IDENTITY.md" ]

  ad_seed_identity dsh-persona q "Quantum." "$s" "$w" 2>/dev/null
  has "$(cat "$s/cordis.patch.yml")" "- id: system-prompt"
  has "$(cat "$s/cordis.patch.yml")" "{{model}}"

  ad_seed_identity nanoloop-memory q "Quantum." "$s" "$w" 2>/dev/null
  has "$(head -n 5 "$s/Memory/identity.md")" "type: user"
}

test_dsh_persona_is_valid_yaml() {
  command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null \
    || { echo "(no python3+yaml; skipped)" >&2; return 0; }
  s="$TMP/dsh-state"; mkdir -p "$s"
  ad_seed_identity dsh-persona q "Line one: with a colon.
Line two # not a comment" "$s" "$s" 2>/dev/null
  python3 - "$s/cordis.patch.yml" <<'PY'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
persona = doc[0]["config"]["persona"]
assert doc[0]["id"] == "system-prompt"
assert "Line two # not a comment" in persona, persona
assert persona.startswith("You are a coding agent"), persona[:60]
PY
}

# ------------------------------------------------------------------ residents

test_resident_new_ls_fork_snapshot() {
  fresh_home res
  "$ROOT/bin/agentdorm" new alpha --agent hermes --port 9401 --description "Alpha: the first." </dev/null 2>/dev/null
  "$ROOT/bin/agentdorm" new beta --agent nanoloop --description "Beta tasks." </dev/null 2>/dev/null
  f="$AGENTDORM_HOME/residents/alpha/resident.yaml"
  eq 9401 "$(ad_yaml_get "$f" port)"
  eq "" "$(ad_yaml_get "$AGENTDORM_HOME/residents/beta/resident.yaml" port)"   # worker: no port
  ls_out="$("$ROOT/bin/agentdorm" ls 2>/dev/null)"
  has "$ls_out" "alpha"
  has "$ls_out" "beta"
  refute "$ROOT/bin/agentdorm" new alpha --agent hermes </dev/null 2>/dev/null        # no duplicates
  mkdir -p "$AGENTDORM_HOME/residents/alpha/.harness" && echo mem > "$AGENTDORM_HOME/residents/alpha/.harness/SOUL.md"
  "$ROOT/bin/agentdorm" fork alpha gamma --port 9402 2>/dev/null
  eq gamma "$(ad_yaml_get "$AGENTDORM_HOME/residents/gamma/resident.yaml" name)"
  eq 9402 "$(ad_yaml_get "$AGENTDORM_HOME/residents/gamma/resident.yaml" port)"
  eq mem "$(cat "$AGENTDORM_HOME/residents/gamma/.harness/SOUL.md")"
  "$ROOT/bin/agentdorm" snapshot alpha 2>/dev/null
  [ -n "$(ls "$AGENTDORM_HOME/residents/alpha/snapshots/"*.tar.gz)" ]
}

test_resident_ports_skip_claimed() {
  fresh_home ports
  "$ROOT/bin/agentdorm" new one --agent hermes --description x </dev/null 2>/dev/null
  "$ROOT/bin/agentdorm" new two --agent hermes --description x </dev/null 2>/dev/null
  p1="$(ad_yaml_get "$AGENTDORM_HOME/residents/one/resident.yaml" port)"
  p2="$(ad_yaml_get "$AGENTDORM_HOME/residents/two/resident.yaml" port)"
  [ "$p1" != "$p2" ] || { echo "both residents got port $p1" >&2; return 1; }
}

# ------------------------------------------------------------------ hooks

test_dsh_url_hook_reads_token_from_logs() {
  ad_load_agent dsh
  docker() { printf 'dsh: serving\ndsh web: http://127.0.0.1:3080/?token=abc_DEF-123\n'; }
  eq "http://localhost:3180/?token=abc_DEF-123" "$(agent_url c 3180)"
  docker() { printf 'starting\n'; }
  eq "http://localhost:3180/" "$(agent_url c 3180)"
}

test_openclaw_url_hook_keeps_fragment() {
  ad_load_agent openclaw
  docker() { printf '{"ok":true,"url":"http://127.0.0.1:18789/#token=t0k3n","port":18789}\n'; }
  eq "http://localhost:18800/#token=t0k3n" "$(agent_url c 18800)"
}

# ------------------------------------------------------------------ CLI

test_cli_surface() {
  has "$("$ROOT/bin/agentdorm" help)" "agentdorm new <name>"
  has "$("$ROOT/bin/agentdorm" version)" "agentdorm "
  has "$("$ROOT/bin/agentdorm" agents)" "nanoloop"
  # --help must never start a container
  has "$("$ROOT/bin/agentdorm" run hermes --help)" "usage: agentdorm run hermes"
  refute "$ROOT/bin/agentdorm" frobnicate 2>/dev/null
}

test_shims_point_at_the_cli() {
  for a in $(ad_agents); do
    grep -q "bin/agentdorm\" run $a " "$ROOT/agents/$a/$a.sh" \
      || { echo "agents/$a/$a.sh is not a shim for 'agentdorm run $a'" >&2; return 1; }
  done
}

# ------------------------------------------------------------------ main

echo "agentdorm tests ($(bash --version | head -n 1))"
for t in $(declare -F | awk '{print $3}' | grep '^test_'); do run_test "$t"; done
echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" = 0 ] || { echo "failed:$FAILED"; exit 1; }
