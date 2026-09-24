# shellcheck shell=bash
# dsh-specific behaviour for the AgentDorm launcher (sourced by lib/agent.sh).

# dsh 0.1.5+ admits the browser only with the token it prints at startup
# (`dsh web: http://127.0.0.1:3080/?token=...`). Read it from the container's
# log and point the URL at the published host port. $1 = container, $2 = port.
agent_url() {
  local token
  token="$(docker logs "$1" 2>&1 | sed -n 's/^dsh web: .*[?&]token=\([A-Za-z0-9_-]*\).*/\1/p' | tail -n 1)"
  if [ -n "$token" ]; then
    printf 'http://localhost:%s/?token=%s\n' "$2" "$token"
  else
    printf 'http://localhost:%s/\n' "$2"
  fi
}
