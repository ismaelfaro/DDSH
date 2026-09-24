# shellcheck shell=bash
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
# Egress control for residents with `egress: allowlist`.
#
#   host 127.0.0.1:<port> ─► gate ─(internal net)─► resident web UI
#   resident ─(internal net, HTTP(S)_PROXY)─► gate ─► allowlisted domains only
#
# The resident sits alone on an internal network with no route out; the gate
# is its only neighbour, bridging both directions and logging every decision.

AD_GATE_IMAGE="agentdorm-gate:local"
AD_GATE_LISTEN=7000

ad_gate_name()    { printf 'agentdorm-%s-gate\n' "$1"; }
ad_gate_network() { printf 'agentdorm-%s-int\n' "$1"; }

# Model provider endpoints are always allowed for the keys that are set --
# a resident that cannot reach its model cannot do anything at all.
ad_gate_default_allow() {
  [ -n "$(ad_env OPENROUTER_API_KEY)" ] && echo "openrouter.ai"
  [ -n "$(ad_env OPENAI_API_KEY)" ]     && echo "api.openai.com"
  [ -n "$(ad_env ANTHROPIC_API_KEY)" ]  && echo "api.anthropic.com"
  [ -n "$(ad_env DEEPSEEK_API_KEY)" ]   && echo "api.deepseek.com"
  [ -n "$(ad_env GEMINI_API_KEY)" ]     && echo "generativelanguage.googleapis.com"
  [ -n "$(ad_env MINIMAX_API_KEY)" ]    && echo "api.minimax.io"
  [ -n "$(ad_env NOUS_API_KEY)" ]       && echo "inference-api.nousresearch.com"
  return 0
}

# ad_gate_up <resident> <host-port> <target-host> <target-port> <allow...>
ad_gate_up() {
  local res="$1" port="$2" target="$3:$4" gate net
  shift 4
  gate="$(ad_gate_name "$res")"
  net="$(ad_gate_network "$res")"

  if ! docker image inspect "$AD_GATE_IMAGE" >/dev/null 2>&1; then
    ad_log "building $AD_GATE_IMAGE ..."
    docker build -t "$AD_GATE_IMAGE" "$AD_ROOT/gate" >&2 || ad_die "build of $AD_GATE_IMAGE failed"
  fi
  docker network inspect "$net" >/dev/null 2>&1 \
    || docker network create --internal --label "$AD_LABEL=network" "$net" >/dev/null
  ad_ensure_network
  docker rm -f "$gate" >/dev/null 2>&1 || true

  # Start on the normal network (so the port can be published), then join the
  # resident's internal network under the name its proxy settings point at.
  local publish=()
  # Workers have no UI to carry: the gate is then only their egress proxy.
  [ -n "$port" ] && publish=(-p "127.0.0.1:$port:$AD_GATE_LISTEN")
  docker run -d --init --name "$gate" --network "$AD_NETWORK" \
    ${publish[@]+"${publish[@]}"} \
    --label "$AD_LABEL.gate-for=$res" \
    -e "GATE_ALLOW=$*" -e "GATE_TARGET=${port:+$target}" -e "GATE_LISTEN=${port:+$AD_GATE_LISTEN}" \
    "$AD_GATE_IMAGE" >/dev/null || ad_die "could not start the egress gate for $res"
  docker network connect --alias "$gate" "$net" "$gate" \
    || ad_die "could not attach the gate to $net"
}

ad_gate_down() {
  docker rm -f "$(ad_gate_name "$1")" >/dev/null 2>&1 || true
  docker network rm "$(ad_gate_network "$1")" >/dev/null 2>&1 || true
}
