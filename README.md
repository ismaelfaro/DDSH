# AgentDorm

A house of AI agents. Each one lives in its own room — a container that sees one folder of your machine and nothing else — and they can talk to each other through a shared commons.

Use it two ways:

- **Run an agent on a folder.** `cd project && hermes` — a sandboxed agent working on that folder, gone when you stop it, with its memory kept for next time.
- **Keep residents.** Named, long-lived agents, each with a domain it is told to master, its own memory and skills, a fixed port, and an inbox. They delegate to each other; you are one of the housemates.

```bash
agentdorm new quantum --agent hermes \
  --description "Quantum computing: Qiskit circuits, transpilation, error mitigation."
agentdorm new builder --agent nanoloop \
  --description "Backend engineering: services, tests, CI."
agentdorm up
agentdorm ps
```

## The agents

| Agent | Kind | Upstream | Web UI | Notes |
|---|---|---|---|---|
| `hermes` | web | [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) | :9119 | Self-improving; first run picks provider + model. [README](agents/hermes/README.md) |
| `openclaw` | web | [openclaw/openclaw](https://github.com/openclaw/openclaw) | :18789 | Token in the URL: `agentdorm url <name>`. [README](agents/openclaw/README.md) |
| `dsh` | web | [deepseek-ai/deepseek-harness](https://github.com/deepseek-ai/deepseek-harness) | :3080 | DeepSeek or OpenRouter. [README](agents/dsh/README.md) |
| `openhands` | web | [OpenHands/OpenHands](https://github.com/OpenHands/OpenHands) | :8000/canvas | Wraps the official image; model set in its UI. [README](agents/openhands/README.md) |
| `nanoloop` | worker | [ismaelfaro/nanoLoop](https://github.com/ismaelfaro/nanoLoop) | — | Plan → Build → Review → Test → Ship crew. [README](agents/nanoloop/README.md) |
| `loomloop` | worker | [ismaelfaro/loomloop](https://github.com/ismaelfaro/loomloop) | — | Runs multi-agent LoomLoop systems. [README](agents/loomloop/README.md) |

**Web** agents serve a UI on `127.0.0.1`. **Worker** agents have none: `run` executes one task in your terminal, and as residents they take every message in their inbox as a task and reply with the result — which makes them the specialists the web agents delegate to.

## Install

```bash
./install.sh                    # from this checkout
curl -fsSL https://raw.githubusercontent.com/ismaelfaro/agentdorm/main/install.sh | bash
```

Copies the source to `~/.agentdorm` and links `agentdorm` plus one shortcut per agent (`hermes`, `openclaw`, …) into `~/.local/bin`, adding it to your PATH. Re-run to update. Needs Docker and bash (macOS's built-in bash 3.2 is fine). `agentdorm doctor` checks the rest.

## One agent on one folder

```bash
export OPENROUTER_API_KEY=sk-or-...    # or ANTHROPIC_/OPENAI_/DEEPSEEK_/GEMINI_API_KEY
cd /path/to/project
hermes                                 # = agentdorm run hermes
```

The first run builds the image (1–5 minutes); later runs start in seconds. A second folder gets a second instance on the next free port. `agentdorm run <agent> --port N --detach` pins the port and backgrounds it; `agentdorm run nanoloop "task"` runs a worker once.

## Residents

```bash
agentdorm new <name> --agent <agent> --description "what it should become the best at"
        [--port N] [--workspace DIR] [--egress allowlist --allow arxiv.org,pypi.org]
agentdorm up [name...]        agentdorm down [name...]        agentdorm ls
agentdorm url <name>          agentdorm logs <name> [-f]      agentdorm shell <name>
agentdorm snapshot <name>     agentdorm fork <from> <to>
```

Each resident is a folder under `residents/<name>/`:

```
resident.yaml    what it is: agent, port, domain, egress policy  (yours to edit)
.harness/        its memory, skills, sessions, settings          (the agent's)
workspace/       its work root, unless resident.yaml points elsewhere
snapshots/       tarballs from `agentdorm snapshot`
```

### Identity and self-improvement

The description is written into the agent's own identity file **once**, on first start — `SOUL.md` for Hermes and OpenClaw, the persona layer for dsh, a memory note for nanoLoop — with a charter: master this domain, capture what works as skills, prune what proved wrong, hand off what is outside it. AgentDorm never rewrites that file again. From then on it belongs to the agent, whose own learning loop refines it; that hand-off is the self-evolution.

`fork` copies a resident, memory included, under a new name — run two variants of a specialist and keep the one that got better. `snapshot` checkpoints one before an experiment.

## The commons

Every container mounts the commons at `/dorm` and has a `dorm` command:

```bash
dorm who                              # everyone here, and what they do
dorm send builder -s "healthz" "add /healthz and a test"
dorm inbox ; dorm read                # check mail
dorm send all "pypi is down, use the mirror"
dorm send owner "need a decision on the schema"
```

Hermes and OpenClaw also get the same operations as an **MCP tool server**, registered automatically. Messages are plain Markdown files, so you can read the whole conversation with `ls` and `cat`. You are `owner`: `agentdorm who / send / inbox / read` from the host. The protocol the agents follow is in [dorm/PROTOCOL.md](dorm/PROTOCOL.md). Messages are requests, never orders: no housemate can change another's identity or your goals.

## Security model

- **One folder.** A container sees its workspace and its own state, nothing else of your machine. Files it writes are owned by you.
- **Loopback only.** Every UI is published on `127.0.0.1`. These agents run shell commands behind little or no authentication; never republish them on `0.0.0.0`.
- **Keys stay in the environment.** Provider keys pass through from your shell and are never written into an image or a config file. Don't put them in dorm messages either: those are plain files.
- **Egress allowlist, per resident.** `egress: allowlist` puts the resident alone on an internal network with no route out. Its only neighbour is a gate that admits the model provider for each key you have set plus the resident's `allow:` list, carries its UI to the host port, and logs every decision: `agentdorm logs <name> --gate`.

  ```
  host 127.0.0.1:<port> ─► gate ─(internal net)─► resident
  resident ─(internal net, HTTP(S)_PROXY)─► gate ─► allowlisted domains only
  ```
  Clients that ignore proxy settings fail closed rather than leaking.

## Layout

```
bin/agentdorm           the CLI
lib/                    its modules (bash 3.2-compatible)
agents/<name>/          one directory per agent:
  agent.conf              what makes it different: image, ports, mounts, env, kind
  Dockerfile              pins the harness at build time
  entrypoint.sh           keeps the UI on loopback, seeds state, registers the dorm
  hooks.sh                optional agent-specific behaviour
  agent-task              workers only: run one task read from stdin
  <name>.sh               shortcut for `agentdorm run <name>`
dorm/                   the commons: dorm CLI, MCP server, worker loop, protocol
gate/                   the egress gate image
tests/run.sh            the test suite (no Docker needed)
```

## Adding an agent

Create `agents/<name>/` with an `agent.conf`, a `Dockerfile`, an `entrypoint.sh` and a README. Web agents keep their UI on container loopback behind a socat bridge (see `agents/hermes/entrypoint.sh`); workers provide `agent-task` and answer `worker` by exec'ing `dorm-worker` (see `agents/nanoloop/`). `tests/run.sh` checks that the descriptor is complete. Nothing outside the directory needs to change.

## Development

```bash
tests/run.sh                  # the suite, on macOS bash 3.2 or Linux
agentdorm build --force       # rebuild every image
AGENTDORM_HOME=/tmp/dorm agentdorm …   # residents and commons somewhere disposable
```

CI runs shellcheck, hadolint, the suite on Linux and macOS, and builds the images.

## License

[Apache License 2.0](LICENSE). Each packaged agent keeps its upstream license: MIT for Hermes, OpenClaw, OpenHands, dsh and nanoLoop; LoomLoop does not declare one yet.
