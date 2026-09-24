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
# Install AgentDorm so the agents run from ANY folder:
#
#   From a checkout:   ./install.sh
#   From the internet: curl -fsSL https://raw.githubusercontent.com/ismaelfaro/agentdorm/main/install.sh | bash
#
# What it does:
#   1. Puts the repo at ~/.agentdorm (clone, or reuses the checkout you run it from).
#   2. Symlinks `dsh`, `hermes`, `openclaw`, `openhands` into ~/.local/bin.
#   3. Adds ~/.local/bin to PATH (via ~/.zshrc on macOS, ~/.bashrc elsewhere).
#
# Afterwards every folder is a potential instance:
#   cd /path/to/project-a && hermes     # port 9119 (auto-bumps if busy)
#   cd /path/to/project-b && hermes     # next free port, own container
#
# Options (or env vars):
#   --dir DIR        repo location            [AGENTDORM_DIR, default ~/.agentdorm]
#   --bin-dir DIR    where the shims go       [AGENTDORM_BIN_DIR, default ~/.local/bin]
#   --repo URL       git remote to clone from [default https://github.com/ismaelfaro/agentdorm.git]
#   --no-path        skip the PATH tweak, just print what to add
#   -h, --help       this text
#
# macOS-first: defaults target Apple Silicon + Intel via ~/.local/bin and
# ~/.zshrc. Linux/BSD/Git-Bash follow the same layout with ~/.bashrc.
set -euo pipefail

REPO_URL="https://github.com/ismaelfaro/agentdorm.git"
# The DEEPHARNESS_* names are what this project was called before; they are
# honoured so an existing install keeps working after the rename.
DEST="${AGENTDORM_DIR:-${DEEPHARNESS_DIR:-$HOME/.agentdorm}}"
BIN_DIR="${AGENTDORM_BIN_DIR:-${DEEPHARNESS_BIN_DIR:-$HOME/.local/bin}}"
NO_PATH="${AGENTDORM_NO_PATH:-${DEEPHARNESS_NO_PATH:-}}"

usage() { sed -n '2,/^set -euo/p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dir)     DEST="$2"; shift 2 ;;
    --bin-dir) BIN_DIR="$2"; shift 2 ;;
    --repo)    REPO_URL="$2"; shift 2 ;;
    --no-path) NO_PATH=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "error: unknown flag $1 (see --help)" >&2; exit 1 ;;
  esac
done

# An install from before the rename lives in the old directory; say so rather
# than silently building a second copy next to it.
if [ -d "$HOME/.deepharness" ] && [ "$DEST" = "$HOME/.agentdorm" ] && [ ! -d "$DEST" ]; then
  echo "agentdorm: found a previous install at ~/.deepharness (this project was renamed)." >&2
  echo "agentdorm: keep its agent state with:  mv ~/.deepharness ~/.agentdorm" >&2
  echo "agentdorm: continuing with a fresh install at $DEST" >&2
fi

log()  { echo "agentdorm: $*" >&2; }
warn() { echo "agentdorm: WARNING - $*" >&2; }

# --- 1. OS report (informational; layout below is the same everywhere) ---
OS="$(uname -s)"
ARCH="$(uname -m)"
if [ "$OS" = "Darwin" ]; then
  if command -v sw_vers >/dev/null 2>&1; then
    log "macOS $(sw_vers -productVersion) ($ARCH)"
  else
    log "macOS ($ARCH)"
  fi
else
  log "$OS ($ARCH) - same layout as macOS"
fi

# --- 2. Find a repo source: this checkout, or clone it ---
SCRIPT_SRC="${BASH_SOURCE[0]:-$0}"
case "$SCRIPT_SRC" in
  *install.sh) SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SRC")" && pwd)" ;;
  *) SCRIPT_DIR="$PWD" ;;
esac

if [ -f "$SCRIPT_DIR/bin/agentdorm" ] && [ -d "$SCRIPT_DIR/agents" ]; then
  log "using checkout at $SCRIPT_DIR"
  if [ "$SCRIPT_DIR" != "$DEST" ]; then
    # Copy the checkout WITHOUT state: .harness/.deps hold credentials,
    # sessions and GBs of dependencies; they get rebuilt per agent.
    command -v tar >/dev/null 2>&1 || { echo "error: tar not found" >&2; exit 1; }
    mkdir -p "$DEST"
    if git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      # Exactly the source: tracked files plus new ones not yet committed, and
      # nothing .gitignore excludes (state, residents, agent scaffold, junk).
      log "syncing source files to $DEST ..."
      (cd "$SCRIPT_DIR" && git ls-files -z --cached --others --exclude-standard) \
        | (cd "$SCRIPT_DIR" && tar --null -T - -cf -) | tar -xf - -C "$DEST"
    else
      log "syncing to $DEST (excluding agent state) ..."
      tar -cf - --exclude=.git --exclude=.harness --exclude=.deps --exclude=.DHC \
        --exclude=./residents --exclude=./commons -C "$SCRIPT_DIR" . | tar -xf - -C "$DEST"
    fi
  fi
  SRC="$DEST"
elif [ -f "$DEST/bin/agentdorm" ] || [ -d "$DEST/agents/dsh" ]; then
  log "using existing install at $DEST"
  if command -v git >/dev/null 2>&1 && [ -d "$DEST/.git" ]; then
    log "updating $DEST ..."
    (cd "$DEST" && git pull --ff-only) || warn "git pull failed; keeping current files"
  fi
  SRC="$DEST"
else
  if ! command -v git >/dev/null 2>&1; then
    echo "error: git not found and no checkout present." >&2
    echo "  macOS: xcode-select --install   | Linux: use your package manager" >&2
    exit 1
  fi
  log "cloning $REPO_URL -> $DEST ..."
  mkdir -p "$(dirname "$DEST")"
  git clone "$REPO_URL" "$DEST"
  SRC="$DEST"
fi

# --- 3. Docker: warn now, fail later (runners re-check on every start) ---
if ! command -v docker >/dev/null 2>&1; then
  warn "docker not found. First run will refuse to start until it exists."
  if [ "$OS" = "Darwin" ]; then
    warn "macOS: brew install --cask docker   (or https://www.docker.com/products/docker-desktop)"
  else
    warn "see https://docs.docker.com/engine/install/"
  fi
elif ! docker info >/dev/null 2>&1; then
  warn "docker installed but daemon not responding."
  if [ "$OS" = "Darwin" ]; then
    warn "start Docker Desktop, then re-run any agent."
  else
    warn "try: sudo systemctl start docker"
  fi
else
  log "docker OK ($(docker --version))"
fi

# --- 4. Executable bits (lost by some zips / Windows checkouts) ---
chmod +x "$SRC/install.sh" "$SRC/bin/agentdorm" "$SRC/dorm/dorm" "$SRC/dorm/dorm-mcp" 2>/dev/null || true
for runner in "$SRC"/agents/*/*.sh; do chmod +x "$runner" 2>/dev/null || true; done

# --- 5. Shims on PATH ---
# `agentdorm` is the CLI; one shim per agent (hermes, dsh, ...) keeps the old
# one-word commands working -- each is `agentdorm run <agent>`.
mkdir -p "$BIN_DIR"
ln -sfn "$SRC/bin/agentdorm" "$BIN_DIR/agentdorm"
LINKED="agentdorm"
for conf in "$SRC"/agents/*/agent.conf; do
  a="$(basename "$(dirname "$conf")")"
  if [ -f "$SRC/agents/$a/$a.sh" ]; then
    ln -sfn "$SRC/agents/$a/$a.sh" "$BIN_DIR/$a"
    LINKED="$LINKED $a"
  fi
done
log "shims linked in $BIN_DIR: $LINKED"

# --- 6. PATH wiring ---
path_on_path() {
  case ":$PATH:" in *":$BIN_DIR:"*) return 0 ;; *) return 1 ;; esac
}

if path_on_path; then
  log "$BIN_DIR already on PATH"
elif [ -n "$NO_PATH" ]; then
  log "add to PATH manually:  export PATH=\"$BIN_DIR:\$PATH\""
else
  RC=""
  if [ -n "${ZDOTDIR:-}" ] && [ -f "$ZDOTDIR/.zshrc" ]; then RC="$ZDOTDIR/.zshrc"
  elif [ -f "$HOME/.zshrc" ] && { [ "$OS" = "Darwin" ] || [ -n "${ZSH_VERSION:-}" ]; }; then RC="$HOME/.zshrc"
  elif [ -f "$HOME/.bashrc" ]; then RC="$HOME/.bashrc"
  else RC="$HOME/.profile"
  fi
  LINE="export PATH=\"$BIN_DIR:\$PATH\"  # AgentDorm install.sh"
  if [ -f "$RC" ] && grep -qF "$BIN_DIR" "$RC" 2>/dev/null; then
    log "$BIN_DIR already referenced in $RC"
  else
    printf '\n%s\n' "$LINE" >> "$RC"
    log "appended PATH entry to $RC (restart shell or: export PATH=\"$BIN_DIR:\$PATH\")"
  fi
fi

# --- 7. Done ---
echo
echo "Installed. Try:"
echo
echo "  export OPENROUTER_API_KEY=sk-or-...        # or your provider key"
echo "  cd /path/to/project && hermes              # one agent on this folder"
echo
echo "  agentdorm new quantum --agent hermes \\"
echo "    --description \"Quantum computing: Qiskit, transpilation, error mitigation\""
echo "  agentdorm up                               # start every resident"
echo "  agentdorm ps                               # where each one is"
echo "  agentdorm doctor                           # if anything looks wrong"
