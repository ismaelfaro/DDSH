# Hermes Agent dashboard in a container.
# https://github.com/NousResearch/hermes-agent
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
# Node.js: the dashboard's chat pane runs the TUI in a pty, and the TUI (plus
# the browser tools) needs `node` on PATH. Without it Hermes falls back to
# downloading its own copy into $HERMES_HOME and then still cannot find it,
# looping "Install now? [Y/n]" at a prompt no one can answer.
FROM node:22-bookworm-slim AS node

FROM python:3.12-slim-bookworm
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
    && node --version && npm --version

# Tooling the agent expects in its shell (bash tool, git, search, http),
# plus socat for the published-port bridge and ffmpeg for voice notes.
RUN apt-get update && apt-get install -y --no-install-recommends \
        bash git curl ca-certificates ripgrep less procps unzip openssh-client jq socat \
        ffmpeg build-essential \
    && rm -rf /var/lib/apt/lists/*

# Config volume: HERMES_HOME — profile, skills, memories, sessions, settings.
ENV HERMES_HOME=/hermes
# The dashboard's Files tab defaults to the container's home directory, which
# is not mounted anywhere: folders created there would live and die with the
# container. Point it at the workspace, the folder the runner mounted.
ENV HERMES_DASHBOARD_FILES_ROOT=/workspace
# The venv lives in /opt/hermes, a persistent mount seeded from the image, so
# packages Hermes installs for itself survive container removal.
# $HERMES_HOME/node/bin: whatever Hermes installed for itself stays usable.
ENV PATH=/opt/hermes/bin:/hermes/node/bin:$PATH

RUN useradd -m -u 1000 hermes \
    && mkdir -p /hermes /workspace /opt/hermes /opt/hermes-seed \
    && chown -R hermes:hermes /hermes /workspace /opt/hermes /opt/hermes-seed

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv
USER hermes

# Hermes version baked into the image seed. Change it with:
#   docker build --build-arg HERMES_VERSION=0.20.6 -t hermes-web:local .
ARG HERMES_VERSION=
ENV HERMES_VERSION=${HERMES_VERSION}

# Built AT /opt/hermes, then copied to the seed: console-script shebangs bake
# in the venv path, so the tree must be created where it will finally run.
RUN uv venv /opt/hermes \
    && uv pip install --python /opt/hermes/bin/python \
        "hermes-agent${HERMES_VERSION:+==${HERMES_VERSION}}" \
    && /opt/hermes/bin/hermes --version \
    && cp -a /opt/hermes/. /opt/hermes-seed/

COPY --chown=hermes:hermes entrypoint.sh configure-model.sh /usr/local/bin/

WORKDIR /workspace
EXPOSE 19119
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["dashboard"]
