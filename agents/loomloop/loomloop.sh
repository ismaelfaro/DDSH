#!/usr/bin/env bash
# Kept so existing commands, docs and PATH shims keep working: this is exactly
# `agentdorm run loomloop`. The old env vars still apply (LOOMLOOP_PORT, LOOMLOOP_DETACH, ...).
set -euo pipefail
_src="${BASH_SOURCE[0]:-$0}"
while [ -L "$_src" ]; do
  _dir="$(cd "$(dirname "$_src")" && pwd)"
  _src="$(readlink "$_src")"
  [ "${_src#/}" = "$_src" ] && _src="$_dir/$_src"
done
exec "$(cd "$(dirname "$_src")/../.." && pwd)/bin/agentdorm" run loomloop "$@"
