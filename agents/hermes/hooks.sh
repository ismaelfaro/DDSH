# shellcheck shell=bash
# Hermes-specific behaviour for the AgentDorm launcher (sourced by lib/agent.sh).

# First run in a terminal with nothing configured yet: pick provider + model in
# two steps and write them to the state dir's config.yaml. Afterwards the
# dashboard, `hermes model`, or the agent itself owns that choice.
#   HERMES_SETUP=always  re-run the picker     HERMES_SETUP=never  skip it
agent_pre_run() {
  local state="$1" deps="$2" setup
  setup="$(ad_env HERMES_SETUP)"
  [ -t 0 ] || return 0
  [ "$setup" = "never" ] && return 0
  if [ "$setup" != "always" ] && grep -qE '^[[:space:]]+default:' "$state/config.yaml" 2>/dev/null; then
    return 0
  fi
  local -a env_args=()
  local var
  for var in $AGENT_ENV; do env_args+=(-e "$var"); done
  docker run --rm -it --init ${env_args[@]+"${env_args[@]}"} \
    -v "$state:$AGENT_STATE_MOUNT" -v "$deps:$AGENT_DEPS_MOUNT" \
    --entrypoint /usr/local/bin/entrypoint.sh \
    "$AGENT_IMAGE" setup-model || ad_warn "hermes: setup skipped; falling back to the environment"
}
