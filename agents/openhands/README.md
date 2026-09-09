# OpenHands in Docker

Runs [OpenHands Agent Canvas](https://github.com/OpenHands/OpenHands) in a container, pointed at any folder on your machine. Part of [AgentDorm](../../README.md).

```
host                                    container
─────────────────────────────────────   ─────────────────────────────────
<folder you launch from>/  ──────────►  /projects   (agent's work root)
agents/openhands/.harness/ ──────────►  /home/openhands/.openhands
127.0.0.1:$OPENHANDS_PORT  ◄──────────  8000 (canvas + agent server + automation)
```

Licensed under the [Apache License 2.0](../../LICENSE). OpenHands is MIT-licensed.

## Quick start

```bash
cd /path/to/your/project
/path/to/agentdorm/agents/openhands/openhands.sh
```

Open http://localhost:8000/canvas — plain `/` redirects there.

Set the model in the UI (**Settings → LLM**); unlike the other agents here, Agent Canvas keeps provider credentials in its own encrypted settings rather than reading them from the environment at each start. They persist in `.harness/`.

## Config

`OPENHANDS_PORT` changes the host port. `--build-arg OPENHANDS_VERSION=1.16.0` pins the release. `OPENHANDS_DETACH=1` runs it in the background.

## How this one differs

- **It wraps the official image** (`ghcr.io/openhands/agent-canvas`) instead of installing the agent itself: OpenHands publishes a complete one, and rebuilding it here would only add drift. The `Dockerfile` adds our entrypoint and nothing else.
- **No socat bridge.** The other agents refuse to bind anything but loopback, so they need a hop. This image's static server already binds `0.0.0.0` inside the container, and the runner publishes it to the host's `127.0.0.1`. Keep that mapping: the canvas has no authentication in this configuration.
- **The work root is `/projects`, not `/workspace`**, because that is the path Agent Canvas browses. It is the same folder you launched from.
- **One process tree, three services**: agent server (18000), automation (18001), and the static server on 8000 that fronts both. Only 8000 is published.
- **Other agent backends are not wired up.** Agent Canvas can drive Claude Code, Codex, or remote backends over ACP; those need their own credentials and setup in the UI.
