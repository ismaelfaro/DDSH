# nanoLoop in a container.
# https://github.com/ismaelfaro/nanoLoop
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
FROM python:3.12-slim-bookworm

# The crew's builder and QA run real shell commands against the workspace.
RUN apt-get update && apt-get install -y --no-install-recommends \
        bash git curl ca-certificates ripgrep less procps unzip jq build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Not on PyPI yet: install from GitHub at a pinned ref. Bump with
#   docker build --build-arg NANOLOOP_REF=<commit|branch|tag> -t nanoloop-web:local .
ARG NANOLOOP_REF=d4e2c04927c21c4837e6de8a212a49a1683ae42b
RUN git clone --quiet https://github.com/ismaelfaro/nanoLoop.git /opt/nanoloop-src \
    && git -C /opt/nanoloop-src checkout --quiet "$NANOLOOP_REF" \
    && uv pip install --system --no-cache /opt/nanoloop-src \
    && python -c "import nanoloop" \
    && cp -a /opt/nanoloop-src/Skills /opt/nanoloop-skills

RUN useradd -m -u 1000 agent && mkdir -p /nanoloop /workspace && chown agent:agent /nanoloop /workspace

# State volume: sessions (./.nanoloop, relative to the working dir), the
# Markdown memory graph, and skills. The crew's file and shell tools act on
# HARNESS_WORKDIR -- the mounted launch folder -- not on the state.
ENV NANOLOOP_MEMORY_DIR=/nanoloop/Memory \
    NANOLOOP_SKILLS_DIR=/nanoloop/Skills \
    HARNESS_WORKDIR=/workspace \
    DORM_WORKER_LOGS=/nanoloop/worker-logs

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY agent-task /usr/local/bin/agent-task
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/agent-task

USER agent
WORKDIR /nanoloop
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
