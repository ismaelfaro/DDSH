# shellcheck shell=bash
# OpenClaw-specific behaviour for the AgentDorm launcher (sourced by lib/agent.sh).

# The Control UI only lets you in with the gateway token in the URL fragment,
# so ask the running gateway for it. $1 = container, $2 = published host port.
agent_url() {
  local frag
  frag="$(docker exec "$1" openclaw dashboard --no-open --json 2>/dev/null \
    | sed -n 's/.*"url":"[^"#]*#\([^"]*\)".*/\1/p')"
  if [ -n "$frag" ]; then
    printf 'http://localhost:%s/#%s\n' "$2" "$frag"
  else
    printf 'http://localhost:%s/  (token not ready yet; retry in a moment)\n' "$2"
  fi
}
