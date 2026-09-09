# OpenClaw's Gateway + Control UI in a container.
# https://github.com/openclaw/openclaw
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
FROM node:22-bookworm-slim

# Tooling the agent expects in its shell, plus socat for the port bridge.
RUN apt-get update && apt-get install -y --no-install-recommends \
        bash git curl ca-certificates ripgrep less procps unzip openssh-client jq socat \
        python3 \
    && rm -rf /var/lib/apt/lists/*

# Config volume: the Gateway's state directory — config, sessions, memory,
# pairings, plugins, credentials.
ENV OPENCLAW_STATE_DIR=/openclaw
# The agent's work root is the folder the runner was launched from.
ENV OPENCLAW_WORKSPACE_DIR=/workspace
# Installed into /opt/openclaw, a persistent mount seeded from the image, so
# plugins and updates OpenClaw installs for itself survive container removal.
ENV PATH=/opt/openclaw/bin:$PATH
ENV NPM_CONFIG_PREFIX=/opt/openclaw

RUN mkdir -p /openclaw /workspace /opt/openclaw /opt/openclaw-seed \
    && chown -R node:node /openclaw /workspace /opt/openclaw /opt/openclaw-seed
USER node

# Version baked into the image seed. Change it with:
#   docker build --build-arg OPENCLAW_VERSION=2026.8.2 -t openclaw-web:local .
ARG OPENCLAW_VERSION=latest
ENV OPENCLAW_VERSION=${OPENCLAW_VERSION}

# Built at its final path and copied to the seed: npm bakes absolute paths into
# the global bin shims, so the tree must be created where it will finally run.
RUN npm install -g --no-fund --no-audit "openclaw@${OPENCLAW_VERSION}" \
    && openclaw --version \
    && cp -a /opt/openclaw/. /opt/openclaw-seed/

COPY --chown=node:node entrypoint.sh /usr/local/bin/entrypoint.sh

WORKDIR /workspace
EXPOSE 18790
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["gateway"]
