# AgentDorm egress gate: the only way out for an egress-restricted resident.
#
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
# tinyproxy enforces a domain allowlist on everything the resident sends out
# (HTTP and HTTPS CONNECT alike), and logs each allow/deny; socat carries the
# resident's web UI to the published host port, because a container on an
# internal network cannot publish one itself.
FROM alpine:3.20
RUN apk add --no-cache tinyproxy socat
COPY gate-entrypoint.sh /usr/local/bin/gate-entrypoint.sh
RUN chmod +x /usr/local/bin/gate-entrypoint.sh
ENTRYPOINT ["/usr/local/bin/gate-entrypoint.sh"]
