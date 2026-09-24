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
#   agentdorm run loomloop                       the built-in ping/pong demo
#   agentdorm run loomloop run my_system.py      main() of a script in this folder
#   agentdorm run loomloop examples              copy the upstream examples here
#   agentdorm run loomloop python                a Python shell with loomloop
set -euo pipefail

echo "loomloop: workspace ${HOST_WORKSPACE:-(host folder)} -> /workspace" >&2

case "${1:-}" in
  worker)   exec dorm-worker ;;
  ''|demo)  shift || true; exec python -m loomloop demo "$@" ;;
  run)      shift; exec python -m loomloop run "$@" ;;
  examples)
    mkdir -p /workspace/loomloop-examples
    cp -an /opt/loomloop-examples/. /workspace/loomloop-examples/
    echo "loomloop: examples copied to ./loomloop-examples (run one: agentdorm run loomloop run loomloop-examples/swarm.py)" >&2 ;;
  *)        exec "$@" ;;
esac
