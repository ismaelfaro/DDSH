#!/bin/sh
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
#   GATE_ALLOW    domains the resident may reach, space/newline separated.
#                 `example.com` also admits its subdomains; `*.example.com`
#                 admits only subdomains.
#   GATE_TARGET   host:port of the resident's web UI on the internal network
#   GATE_LISTEN   port this gate serves that UI on (published by the CLI)
#                 Both empty for worker residents, which have no UI.
set -eu

mkdir -p /etc/tinyproxy

# One extended regex per allowed domain, anchored on the host name.
: > /etc/tinyproxy/filter
for d in ${GATE_ALLOW:-}; do
  case "$d" in
    '*.'*) base="${d#\*.}"; esc="$(printf '%s' "$base" | sed 's/[.]/\\./g')"
           printf '\\.%s$\n' "$esc" >> /etc/tinyproxy/filter ;;
    *)     esc="$(printf '%s' "$d" | sed 's/[.]/\\./g')"
           printf '(^|\\.)%s$\n' "$esc" >> /etc/tinyproxy/filter ;;
  esac
done

cat > /etc/tinyproxy/tinyproxy.conf <<CONF
User nobody
Group nobody
Port 8888
Listen 0.0.0.0
Timeout 600
LogLevel Connect
MaxClients 100
# Only the resident on the internal network talks to this proxy.
Allow 10.0.0.0/8
Allow 172.16.0.0/12
Allow 192.168.0.0/16
# Deny everything not on the allowlist; match host names, not full URLs, so
# HTTPS CONNECT is filtered the same way as plain HTTP.
Filter "/etc/tinyproxy/filter"
FilterType ere
FilterURLs Off
FilterDefaultDeny Yes
ConnectPort 443
ConnectPort 80
DisableViaHeader Yes
CONF

echo "gate: allow: $(tr '\n' ' ' < /etc/tinyproxy/filter)" >&2
if [ -n "${GATE_LISTEN:-}" ] && [ -n "${GATE_TARGET:-}" ]; then
  echo "gate: forwarding :${GATE_LISTEN} -> ${GATE_TARGET}" >&2
  socat "TCP-LISTEN:${GATE_LISTEN},fork,reuseaddr" "TCP:${GATE_TARGET}" &
fi
exec tinyproxy -d -c /etc/tinyproxy/tinyproxy.conf
