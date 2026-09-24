# DeepSeek Harness (dsh) web UI in a container.
# https://github.com/deepseek-ai/deepseek-harness
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

# Tooling the agent harness expects in its shell (bash tool, git, search, http),
# plus Python 3 for data/science work (Qiskit, numpy, matplotlib).
RUN apt-get update && apt-get install -y --no-install-recommends \
        bash git curl ca-certificates ripgrep less procps unzip openssh-client jq socat \
        python3 python3-pip python3-venv \
    && rm -rf /var/lib/apt/lists/* \
    && corepack enable

# Python packages live in a dedicated venv on PATH. Kept in the IMAGE (not the
# persistent /opt/dsh mount): upgrades ship with image rebuilds, and a stale
# host-owned site-packages can't break the harness tooling.
ENV DSH_VENV=/opt/pyvenv
RUN python3 -m venv "$DSH_VENV" \
    && "$DSH_VENV/bin/pip" install --no-cache-dir --upgrade pip \
    && "$DSH_VENV/bin/pip" install --no-cache-dir qiskit qiskit-aer matplotlib numpy \
    && "$DSH_VENV/bin/python" -c "import qiskit; print('qiskit', qiskit.__version__)"

ENV PNPM_HOME=/home/node/.pnpm
ENV PATH=/opt/dsh/node_modules/.bin:/opt/pyvenv/bin:/home/node/.pnpm:/home/node/.pnpm/bin:$PATH
# Config volume: profiles, plugins, storages, agent presets all live here.
ENV DSH_HOME=/dsh

RUN mkdir -p /dsh /workspace /opt/dsh /opt/dsh-seed "$PNPM_HOME" \
    && chown -R node:node /dsh /workspace /opt/dsh /opt/dsh-seed "$PNPM_HOME"
USER node

# Harness version baked into the image. Change it with:
#   docker build --build-arg DSH_VERSION=0.1.0-rc.8 -t dsh-web:local .
# Pinned to the release AgentDorm was last verified with; bump deliberately.
ARG DSH_VERSION=0.1.5-rc.3
ENV DSH_VERSION=${DSH_VERSION}

# Installed once here into a SEED tree: `npx @deepseek-ai/dsh` re-resolves the
# tree at every start (minutes of wall clock, enough npm heap to OOM a default
# Docker VM). The seed is copied into the persistent `/opt/dsh` mount by the
# entrypoint on first start, so dependencies survive container removal.
# node-linker=hoisted keeps npm's flat layout, which the Cordis plugin loader
# needs: it imports plugin packages by bare specifier from its own directory.
WORKDIR /opt/dsh-seed
RUN --mount=type=cache,target=/pnpm-store,uid=1000,gid=1000 \
    corepack prepare pnpm@latest --activate \
    && pnpm config set --global store-dir /pnpm-store \
    && pnpm config set --global fetch-retries 8 \
    && pnpm config set --global fetch-retry-maxtimeout 120000 \
    && pnpm config set --global network-concurrency 8 \
    && printf '{"name":"dsh-host","private":true}' > package.json \
    && pnpm add --config.node-linker=hoisted \
        --allow-build=@deepseek-ai/dsh-subprocess-local \
        --allow-build=node-pty --allow-build=koffi \
        --allow-build=protobufjs --allow-build=@google/genai \
        "@deepseek-ai/dsh@${DSH_VERSION}" \
    && ./node_modules/.bin/dsh --version \
    && date -u +%Y%m%dT%H%M%S.%N > /opt/dsh-seed/.agentdorm-seed

COPY --chown=node:node entrypoint.sh /usr/local/bin/entrypoint.sh

WORKDIR /workspace
EXPOSE 3080
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["web"]
