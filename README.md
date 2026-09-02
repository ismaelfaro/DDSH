# DeepHarness

Autonomous coding agents, each in a container, each pointed at whatever folder you launch it from.

Every harness here follows the same shape, so switching between them is a different script name and nothing else:

| | dsh | Hermes |
|---|---|---|
| Upstream | [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness) | [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) |
| Runtime | Node 22 (pnpm) | Python 3.12 (uv) + Node 22 |
| Launch | [`agents/dsh/dsh.sh`](agents/dsh/dsh.sh) | [`agents/hermes/hermes.sh`](agents/hermes/hermes.sh) |
| Web UI | http://localhost:3080 | http://localhost:9119 |
| Docs | [agents/dsh/README.md](agents/dsh/README.md) | [agents/hermes/README.md](agents/hermes/README.md) |

## The shared contract

```
host                                      container
───────────────────────────────────────   ──────────────────────────────────
<folder you launch from>/    ──────────►  /workspace   the agent's work root,
                                                       and all it can see
agents/<name>/.harness/      ──────────►  the harness config home
agents/<name>/.DHC/          ──────────►  the harness dependency tree
127.0.0.1:<port>             ◄──────────  socat bridge → loopback web UI
```

- **The work folder is where you run the script**, not where the script lives. The container sees that folder and nothing else of your machine, and files it writes land there owned by you.
- **State outlives containers.** `.harness/` (settings, credentials, sessions, skills) and `.DHC/` (installed dependencies) are bind mounts next to each agent, so `docker rm` costs nothing and a rebuild does not re-download the world. Both are gitignored.
- **Loopback only.** These agents execute shell commands with no authentication in front of them. Each web UI binds container loopback; a `socat` bridge carries the published port, which is mapped to the host's `127.0.0.1`. Do not republish on `0.0.0.0`.
- **Keys stay in the environment.** Provider API keys are passed through from your shell and never written into an image or a config file.

## Quick start

```bash
export OPENROUTER_API_KEY=sk-or-...        # or the provider you use

cd /path/to/your/project                   # the folder the agent works in
/path/to/DeepHarness/agents/hermes/hermes.sh
```

First run builds the image (1-3 minutes); later runs start in seconds. Each agent's README covers its own flags, providers, and quirks.

## Adding another harness

Copy the closest `agents/<name>/` directory and keep the four pieces: a `Dockerfile` that installs the harness at build time, an `entrypoint.sh` that binds loopback behind a socat bridge, a `<name>.sh` runner that mounts `$PWD` plus the two state directories, and a `README.md`. Nothing else in the repository needs to know about it.

## License

[Apache License 2.0](LICENSE). Each packaged harness keeps its own upstream license (both are MIT today).
