# LoomLoop in a container.
# https://github.com/ismaelfaro/loomloop
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

RUN apt-get update && apt-get install -y --no-install-recommends \
        bash git curl ca-certificates less procps jq \
    && rm -rf /var/lib/apt/lists/*

COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Not on PyPI: install from GitHub at a pinned commit, with the [llm] extra for
# the Claude-backed BrainLoop. Bump with
#   docker build --build-arg LOOMLOOP_REF=<commit|branch|tag> -t loomloop:local .
ARG LOOMLOOP_REF=105b1090320b6e79a0a41cc0005034da9f7d570c
RUN git clone --quiet https://github.com/ismaelfaro/loomloop.git /opt/loomloop-src \
    && git -C /opt/loomloop-src checkout --quiet "$LOOMLOOP_REF" \
    && uv pip install --system --no-cache "/opt/loomloop-src[llm]" \
    && python -c "import loomloop" \
    && cp -a /opt/loomloop-src/examples /opt/loomloop-examples

RUN useradd -m -u 1000 agent && mkdir -p /loomloop /workspace && chown agent:agent /loomloop /workspace

ENV DORM_WORKER_LOGS=/loomloop/worker-logs

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY agent-task /usr/local/bin/agent-task
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/agent-task

USER agent
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
