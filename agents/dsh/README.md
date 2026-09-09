# dsh in Docker

Part of [AgentDorm](../../README.md) — see the root README for the layout every agent here shares.

Runs [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) (`@deepseek-ai/dsh`) in a container, pointed at any folder on your machine.

```
host                                    container
─────────────────────────────────────   ─────────────────────────────────
<folder you launch from>/  ──────────►  /workspace      (agent's work root)
agents/dsh/.harness/       ──────────►  /dsh            ($DSH_HOME config)
agents/dsh/.deps/           ──────────►  /opt/dsh        (dependency tree)
127.0.0.1:$DSH_PORT        ◄──────────  13080 (socat) → 3080 (dsh, loopback)
```

Licensed under the [Apache License 2.0](../../LICENSE). The upstream harness it packages is MIT-licensed ([third-party notices](https://github.com/deepseek-ai/deepseek-harness/blob/master/THIRD_PARTY_NOTICES.md)).

## Requirements

- Docker (Docker Desktop on macOS/Windows, or a Linux engine)
- Bash (for `dsh.sh`)
- An API key — DeepSeek or OpenRouter

## Quick start

```bash
export DEEPSEEK_API_KEY=sk-...

cd /path/to/project          # the folder the agent will work in
/path/to/agentdorm/agents/dsh/dsh.sh         # first run builds the image (~1 min)
```

Open http://localhost:3080. The agent sees only the folder you launched from.

### OpenRouter instead

```bash
export OPENROUTER_API_KEY=sk-or-...
# optional:
export OPENROUTER_MODELS=deepseek/deepseek-chat-v3.1,anthropic/claude-sonnet-4.5
# export OPENROUTER_BASE_URL=https://openrouter.ai/api/v1   (default shown)
```

With `OPENROUTER_API_KEY` set, the entrypoint registers an `openrouter` provider in `$DSH_HOME/settings.yaml` (`api: openai-completions`). Models appear under **Settings → Models** in the web UI. Only the env-var *name* is written to config; the key itself stays in the environment and never lands in a file. If you already maintain an `llm-pi-ai` section in that file, add the provider by hand instead.

### Compose

Working on this repository itself:

```bash
docker compose up
```

## Volumes

| Host path | Container | Purpose |
|---|---|---|
| *launch directory* | `/workspace` | Work volume — everything the agent can read/write |
| `agents/dsh/.harness/` | `/dsh` (`$DSH_HOME`) | Profiles, plugins, `settings.yaml`, credentials |
| `agents/dsh/.deps/` | `/opt/dsh` | Full harness dependency tree |

Both `.harness/` and `.deps/` are created automatically next to `dsh.sh` and survive container removal:

- `.harness/` keeps your settings, plugins, and stored credentials across upgrades.
- `.deps/` is seeded from the image on **first start only**; after that, plugins installed with `dsh plugin add` persist and nothing is reinstalled per boot.

Both folders must be writable by the container's `node` user (uid 1000). On macOS Docker Desktop this just works; on Linux `dsh.sh` attempts a passwordless `chown`, otherwise:

```bash
sudo chown -R 1000:1000 .harness .deps
```

Add both folders to `.gitignore` — they are machine-local state (and `.harness/` can hold credential material).

## Configuration

Copy `.env.example` to `.env` for `docker compose`, or export the variables directly for `dsh.sh`.

| Variable | Default | Purpose |
|---|---|---|
| `DEEPSEEK_API_KEY` | — | DeepSeek API key |
| `OPENROUTER_API_KEY` | — | Enables the OpenRouter provider when set |
| `OPENROUTER_BASE_URL` | `https://openrouter.ai/api/v1` | OpenRouter endpoint override |
| `OPENROUTER_MODELS` | `deepseek/deepseek-chat-v3.1` | Comma-separated model ids to expose |
| `DSH_PORT` | `3080` | Host port of the web UI |
| `DSH_VERSION` | `latest` | Pin the harness version, e.g. `0.1.0-rc.8` |
| `DSH_TRUSTED_HOSTS` | loopback already trusted | Extra Host authorities accepted by the `/api` trust fence, space separated |

API keys are read from your environment at runtime; nothing secret is baked into the image or written to `settings.yaml`.

## CLI passthrough

Any dsh command runs inside the same container setup:

```bash
./dsh.sh plugin --profile web add <package>
./dsh.sh --version
```

The image rebuilds automatically whenever `Dockerfile` or `entrypoint.sh` changes (fingerprint label), so an outdated image can't shadow fixes. Force it manually with `docker build -t dsh-web:local .`

## Security model

- The harness runs shell commands — it is effectively local RCE by design. That is why:
  - `dsh` binds loopback only (`--host 0.0.0.0` is rejected upstream on purpose);
  - the published port is bound to the host's `127.0.0.1`, not `0.0.0.0`;
  - a `socat` bridge inside the container carries the published port (`13080`) to dsh on loopback (`3080`).
- The container sees exactly two host paths: your launch directory (via `/workspace`) and the two state folders above.
- `/workspace` is the ONLY host path the agent can work with. Files it creates land in your folder with your ownership.
- Python 3.11 + Qiskit (with Aer simulator), NumPy, and Matplotlib are baked into the image at `/opt/pyvenv` and on the container `PATH` — the agent can run quantum/data scripts directly. See `examples/bell_state.py`. Python packages ship with image rebuilds; they are not part of the persistent `.deps` tree.
- API keys are read from your environment at runtime; nothing secret is baked into the image.
- Never expose port 3080 beyond loopback without understanding the above.

## Troubleshooting

- **`container ... is already running (port busy)`** — a previous crashed run left a live container (its `socat` bridge can keep it alive even after `exec` fails). Stop it: `docker rm -f dsh-$(basename $PWD)-$DSH_PORT`.
- **Container fails writing to `.harness/` or `.deps/`** (Linux) — fix ownership: `sudo chown -R 1000:1000 .harness .deps`.
- **Provider errors like `MISSING_CREDENTIAL`** — the env var named in `apiKeyEnv` isn't set in the environment that launched the container. Re-export the key and relaunch via `dsh.sh`.
- **Stale behavior after editing scripts** — should rebuild automatically; force with `docker build --no-cache -t dsh-web:local .`
- **Migrating from the old named-volume setup** — copy the old volume contents into `.harness/`: `docker run --rm -v dsh-config:/from -v "$PWD/.harness":/to alpine cp -a /from/. /to/`
