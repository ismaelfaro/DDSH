# OpenHands Agent Canvas in a container.
# https://github.com/OpenHands/OpenHands
#
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
#
# Unlike the other agents here, OpenHands ships a complete image, so this only
# wraps it in the DeepHarness contract. Pin another release with:
#   docker build --build-arg OPENHANDS_VERSION=1.16.0 -t openhands-web:local .
ARG OPENHANDS_VERSION=1.16.0
FROM ghcr.io/openhands/agent-canvas:${OPENHANDS_VERSION}

USER root
COPY entrypoint.sh /usr/local/bin/deepharness-entrypoint.sh
RUN chmod +x /usr/local/bin/deepharness-entrypoint.sh \
    && mkdir -p /projects \
    && chown openhands:openhands /projects

USER openhands
WORKDIR /projects
EXPOSE 8000
# The image's own entrypoint starts the agent server, the automation service,
# and the static server; ours only reports the mapping and hands over to it.
ENTRYPOINT ["/usr/local/bin/deepharness-entrypoint.sh"]
