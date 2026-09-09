# AgentDorm

Autonomous coding agents, each in a container, each pointed at whatever folder you launch it from.

Every harness here follows the same shape, so switching between them is a different script name and nothing else:

| | dsh | Hermes | OpenClaw | OpenHands |
|---|---|---|---|---|
| Upstream | [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness) | [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) | [openclaw/openclaw](https://github.com/openclaw/openclaw) | [OpenHands/OpenHands](https://github.com/OpenHands/OpenHands) |
| Runtime | Node 22 (pnpm) | Python 3.12 (uv) + Node 22 | Node 22 (npm) | official image |
| Launch | [`agents/dsh/dsh.sh`](agents/dsh/dsh.sh) | [`agents/hermes/hermes.sh`](agents/hermes/hermes.sh) | [`agents/openclaw/openclaw.sh`](agents/openclaw/openclaw.sh) | [`agents/openhands/openhands.sh`](agents/openhands/openhands.sh) |
| Web UI | http://localhost:3080 | http://localhost:9119 | http://localhost:18789 (token in URL) | http://localhost:8000/canvas |
| Model setup | env / `settings.yaml` | env, or the picker on first run | onboarded from env on first start | in the UI |
| Docs | [dsh](agents/dsh/README.md) | [hermes](agents/hermes/README.md) | [openclaw](agents/openclaw/README.md) | [openhands](agents/openhands/README.md) |

## The shared contract

```
host                                      container
───────────────────────────────────────   ──────────────────────────────────
<folder you launch from>/    ──────────►  /workspace   the agent's work root,
                                                       and all it can see
agents/<name>/.harness/      ──────────►  the harness config home
agents/<name>/.deps/          ──────────►  the harness dependency tree
127.0.0.1:<port>             ◄──────────  socat bridge → loopback web UI
```

- **The work folder is where you run the script**, not where the script lives. The container sees that folder and nothing else of your machine, and files it writes land there owned by you.
- **State outlives containers.** `.harness/` (settings, credentials, sessions, skills) and, where the harness installs things for itself, `.deps/` (its dependency tree) are bind mounts next to each agent, so `docker rm` costs nothing and a rebuild does not re-download the world. Both are gitignored.
- **Loopback only.** These agents execute shell commands with little or no authentication in front of them. Every web UI is published to the host's `127.0.0.1` and nothing else. Three of them refuse to bind anything but container loopback, so a `socat` bridge carries the published port; OpenHands binds `0.0.0.0` inside its own container and needs no hop. Do not republish any of them on `0.0.0.0`.
- **Keys stay in the environment.** Provider API keys are passed through from your shell and never written into an image or a config file.

## Install (macOS first)

```bash
# from this checkout
./install.sh
# or straight from the internet
curl -fsSL https://raw.githubusercontent.com/ismaelfaro/agentdorm/main/install.sh | bash
```

This copies the repo to `~/.agentdorm` (no sessions, keys, or dependency
trees — those stay where they were) and links `dsh`, `hermes`, `openclaw`,
`openhands` into `~/.local/bin`, adding it to PATH via `~/.zshrc`.
Re-running it updates the copy. It warns — but does not stop — when Docker
is missing; the runners re-check Docker on every start.

## Quick start

```bash
export OPENROUTER_API_KEY=sk-or-...        # or the provider you use

cd /path/to/your/project-a                 # the folder the agent works in
hermes                                     # installed shim; or ./agents/hermes/hermes.sh

cd /path/to/your/project-b                 # a second folder = a second instance
hermes                                     # hermes auto-bumps a busy default port
```

Each folder you launch from becomes an isolated instance (own container,
own workspace mount). `hermes` moves to the next free port when the default
is busy; the others take an explicit one: `DSH_PORT=3090 dsh`,
`OPENCLAW_PORT=9200 openclaw`, `OPENHANDS_PORT=9200 openhands`.

First run builds the image (1-3 minutes); later runs start in seconds. Each agent's README covers its own flags, providers, and quirks.

## Adding another harness

Copy the closest `agents/<name>/` directory and keep the four pieces: a `Dockerfile` that pins the harness at build time (installing it, or wrapping an official image as OpenHands does), an `entrypoint.sh` that keeps the UI off the network, a `<name>.sh` runner that mounts `$PWD` plus the state directories, and a `README.md`. Nothing else in the repository needs to know about it.

## License

[Apache License 2.0](LICENSE). Each packaged harness keeps its own upstream license (both are MIT today).
