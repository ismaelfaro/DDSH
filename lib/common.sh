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
# Shared helpers. Everything under lib/ targets bash 3.2 -- the /bin/bash that
# ships with macOS -- so no associative arrays, mapfile, or ${var,,}, and every
# possibly-empty array is expanded as ${a[@]+"${a[@]}"} to survive `set -u`.

# Label every container we start carries; `ps`, `stop` and `logs` find ours by it.
AD_LABEL="agentdorm"
# The network every AgentDorm container joins, so residents can reach each other
# by container name.
AD_NETWORK="${AGENTDORM_NETWORK:-agentdorm}"

ad_log()  { printf 'agentdorm: %s\n' "$*" >&2; }
ad_warn() { printf 'agentdorm: WARNING - %s\n' "$*" >&2; }
ad_die()  { printf 'agentdorm: error: %s\n' "$*" >&2; exit 1; }

# Repo root, resolved through symlinks (macOS has no `readlink -f`), so the CLI
# works when invoked through a shim in ~/.local/bin.
ad_resolve_root() {
  local src dir
  src="$1"
  while [ -L "$src" ]; do
    dir="$(cd "$(dirname "$src")" && pwd)"
    src="$(readlink "$src")"
    case "$src" in /*) ;; *) src="$dir/$src" ;; esac
  done
  # bin/agentdorm -> repo root is one level up.
  cd "$(dirname "$src")/.." && pwd
}

# Where residents and the commons live. Defaults inside the checkout; point it
# elsewhere to keep state out of a git working tree.
ad_home() { printf '%s\n' "${AGENTDORM_HOME:-$AD_ROOT}"; }

ad_require_docker() {
  command -v docker >/dev/null 2>&1 || ad_die "docker not found. Install Docker Desktop (macOS/Windows) or Docker Engine (Linux)."
  docker info >/dev/null 2>&1 || ad_die "docker daemon not responding. Start Docker Desktop (or: sudo systemctl start docker)."
}

# sha256 of stdin with whatever the host has (macOS: shasum, Linux: sha256sum).
ad_sha256() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 | cut -d' ' -f1
  elif command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1
  elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha256 -r | cut -d' ' -f1
  else python3 -c 'import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())'
  fi
}

# Docker names allow [a-zA-Z0-9_.-]. Lowercased so names stay predictable.
ad_slug() {
  local s
  s="$(printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -c 'a-z0-9_.-' '-' | sed 's/^-*//; s/-*$//' | cut -c1-48)"
  [ -n "$s" ] || s="workspace"
  printf '%s\n' "$s"
}

# Name of the container currently publishing a host port, if it is one of ours
# or anyone else's.
ad_port_holder() {
  docker ps --filter "publish=$1" --format '{{.Names}}' 2>/dev/null | head -n 1
}

# Is 127.0.0.1:<port> taken? Docker's own view first (it knows about stopped-
# but-reserved publishes), then a portable probe: bash /dev/tcp, nc, python3.
ad_port_busy() {
  [ -n "$(ad_port_holder "$1")" ] && return 0
  if (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; then
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

# First free port at or after $1, trying ten. Prints it, or fails.
ad_free_port() {
  local port="$1" i=0
  while [ "$i" -lt 10 ]; do
    ad_port_busy "$port" || { printf '%s\n' "$port"; return 0; }
    port=$((port + 1)); i=$((i + 1))
  done
  return 1
}

ad_is_number() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

# Create the shared network once. Plain bridge: residents keep internet access
# unless their egress is restricted (see lib/gate.sh).
ad_ensure_network() {
  docker network inspect "$AD_NETWORK" >/dev/null 2>&1 \
    || docker network create --label "$AD_LABEL=network" "$AD_NETWORK" >/dev/null
}

# Bind mounts on Linux must be writable by the container user; Docker Desktop
# maps any host uid into its VM, so this is only needed there.
ad_fix_ownership() {
  local uid="$1" d
  shift
  [ "$(uname)" = "Darwin" ] && return 0
  [ "$(id -u)" = "0" ] && return 0
  for d in "$@"; do
    [ -d "$d" ] || continue
    if [ "$(stat -c %u "$d" 2>/dev/null)" != "$uid" ]; then
      sudo -n chown -R "$uid:$uid" "$d" 2>/dev/null \
        || ad_warn "$d is not writable by uid $uid; run: sudo chown -R $uid:$uid \"$d\""
    fi
  done
}

# Stop a container gracefully: SIGTERM, up to 30s to shut down, then removal.
# Agents flush state and release locks on SIGTERM -- OpenClaw's gateway, for
# one, otherwise leaves a state-directory lease that blocks the next start for
# minutes. `docker rm -f` alone is SIGKILL.
ad_stop_container() {
  docker stop -t 30 "$1" >/dev/null 2>&1 || true
  docker rm -f "$1" >/dev/null 2>&1 || true
}
