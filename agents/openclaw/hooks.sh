# shellcheck shell=bash
# OpenClaw-specific behaviour for the AgentDorm launcher (sourced by lib/agent.sh).

# The Control UI only lets you in with the gateway token in the URL fragment.
# The entrypoint prints it once the gateway is ready; read it from the log
# rather than running `openclaw dashboard` inside the container, which tries
# to start a gateway of its own when the real one is still coming up.
# $1 = container, $2 = published host port.
agent_url() {
  local frag
  frag="$(docker logs "$1" 2>&1 | sed -n 's/^openclaw: Control UI http[^#]*#\(.*\)$/\1/p' | tail -n 1)"
  if [ -n "$frag" ]; then
    printf 'http://localhost:%s/#%s\n' "$2" "$frag"
  else
    printf 'http://localhost:%s/  (gateway still starting; run: agentdorm url <name> again shortly)\n' "$2"
  fi
}
