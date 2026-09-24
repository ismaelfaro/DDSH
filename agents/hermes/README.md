# Hermes in Docker

Runs [Hermes Agent](https://github.com/NousResearch/hermes-agent) (`hermes dashboard`) in a container, pointed at any folder on your machine. Part of [AgentDorm](../../README.md); same layout as the `dsh` agent next to it.

```
host                                    container
─────────────────────────────────────   ─────────────────────────────────
<folder you launch from>/  ──────────►  /workspace      (agent's work root)
agents/hermes/.harness/    ──────────►  /hermes         ($HERMES_HOME config)
agents/hermes/.deps/        ──────────►  /opt/hermes     (the Hermes venv)
127.0.0.1:$HERMES_PORT     ◄──────────  19119 (socat) → 9119 (hermes, loopback)
```

Licensed under the [Apache License 2.0](../../LICENSE). The upstream agent it packages is MIT-licensed.

## Requirements

- Docker
- Bash (macOS's built-in bash 3.2 is fine)
- An API key for whichever provider you use (Nous Portal, OpenRouter, OpenAI, …)

## Quick start

```bash
export OPENROUTER_API_KEY=sk-or-...

cd /path/to/project                 # the folder the agent will work in
hermes                  # = agentdorm run hermes; the first run builds the image
```

Open http://localhost:9119. The agent sees only the folder you launched from.

Any other Hermes command runs through the same script:

```bash
agentdorm run hermes model         # pick a provider/model
agentdorm run hermes chat          # TUI instead of the dashboard
```

## Config

`HERMES_PORT` changes the host port. `--build-arg HERMES_VERSION=0.20.6` pins the agent version instead of tracking the latest PyPI release.

Provider keys are passed straight through from your environment (`NOUS_API_KEY`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `OPENROUTER_API_KEY`, `OPENROUTER_BASE_URL`, `OPENROUTER_MODELS`). They are never written into the image. Whatever you configure with `hermes model` lands in `.harness/`, so it survives container removal.

## As a resident

A named, long-lived hermes with its own memory, port and dorm inbox:

```bash
agentdorm new <name> --agent hermes --description "the domain it should master"
agentdorm up <name>
agentdorm url <name>
```

Its state lives in `residents/<name>/.harness/` instead of `agents/hermes/.harness/`. See the [root README](../../README.md#residents).

## Notes

- **The Files tab shows `/workspace`.** By default it browses the container's home directory, which is mounted nowhere — folders created there would vanish with the container. `HERMES_DASHBOARD_FILES_ROOT` pins it to the folder you launched from.

- The dashboard stores API keys and ships no authentication, so it binds container loopback only. A `socat` bridge on `19119` carries the published port, which the host maps to `127.0.0.1`. Do not republish it on `0.0.0.0`.
- The venv is built at `/opt/hermes` in the image, copied to a seed directory, and restored into the persistent `.deps/` mount on first start — console-script shebangs bake in the venv path, so it must be built where it finally runs.
- Installed from PyPI (`hermes-agent`), which can trail the GitHub `main` branch by a release.
