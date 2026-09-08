#!/usr/bin/env bash
# Copyright 2026 DeepHarness contributors
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

OPENHANDS_PORT="${OPENHANDS_PORT:-8000}"

echo "openhands: workspace ${HOST_WORKSPACE:-(host folder)} -> /projects" >&2
echo "openhands: serving http://localhost:${OPENHANDS_PORT}/canvas" >&2

# No socat bridge here, unlike the other agents: this image's static server
# already binds 0.0.0.0 inside the container, and the runner publishes it to
# the host's 127.0.0.1 only. Nothing in it refuses an all-interfaces bind, so
# there is no loopback hop to work around -- keep the host mapping loopback.
exec tini -- /opt/agent-canvas/entrypoint.sh "$@"
