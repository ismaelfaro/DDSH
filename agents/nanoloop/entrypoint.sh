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
set -euo pipefail

# The shipped example skills, copied once; after that the skills folder is the
# resident's to grow.
if [ ! -d /nanoloop/Skills ]; then
  cp -a /opt/nanoloop-skills /nanoloop/Skills
fi
mkdir -p /nanoloop/Memory

echo "nanoloop: workspace ${HOST_WORKSPACE:-(host folder)} -> /workspace; memory and sessions in the state volume" >&2
if [ -z "${OPENROUTER_API_KEY:-}" ]; then
  echo "nanoloop: WARNING - OPENROUTER_API_KEY is not set; nanoLoop talks to models through OpenRouter" >&2
fi

case "${1:-}" in
  worker) exec dorm-worker ;;           # resident: every inbox message is a task
  '')     exec nanoloop ;;               # no task: nanoLoop prints its usage
  *)      exec nanoloop "$@" ;;          # `agentdorm run nanoloop "task"`, `list`, `resume <id>`, ...
esac
