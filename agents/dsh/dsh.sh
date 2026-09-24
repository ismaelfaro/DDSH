#!/usr/bin/env bash
# Kept so existing commands, docs and PATH shims keep working: this is exactly
# `agentdorm run dsh`. The old env vars still apply (DSH_PORT, DSH_DETACH, ...).
set -euo pipefail
_src="${BASH_SOURCE[0]:-$0}"
while [ -L "$_src" ]; do
  _dir="$(cd "$(dirname "$_src")" && pwd)"
  _src="$(readlink "$_src")"
  [ "${_src#/}" = "$_src" ] && _src="$_dir/$_src"
done
exec "$(cd "$(dirname "$_src")/../.." && pwd)/bin/agentdorm" run dsh "$@"
