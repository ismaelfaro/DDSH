# OpenClaw in Docker

Runs [OpenClaw](https://github.com/openclaw/openclaw)'s Gateway and Control UI in a container, pointed at any folder on your machine. Part of [AgentDorm](../../README.md); same layout as the other agents next to it.

```
host                                    container
─────────────────────────────────────   ─────────────────────────────────
<folder you launch from>/  ──────────►  /workspace     (agent's work root)
agents/openclaw/.harness/  ──────────►  /openclaw      ($OPENCLAW_STATE_DIR)
agents/openclaw/.deps/      ──────────►  /opt/openclaw  (npm install tree)
127.0.0.1:$OPENCLAW_PORT   ◄──────────  18790 (socat) → 18789 (gateway, loopback)
```

Licensed under the [Apache License 2.0](../../LICENSE). OpenClaw itself is MIT-licensed.

## Quick start

```bash
export OPENROUTER_API_KEY=sk-or-...

cd /path/to/your/project
/path/to/agentdorm/agents/openclaw/openclaw.sh
```

The first start onboards without prompts using whichever provider key it finds — `OPENROUTER_API_KEY`, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `DEEPSEEK_API_KEY`, or `GEMINI_API_KEY` — and then prints the Control UI link:

```
openclaw: Control UI http://localhost:18789/#token=<token>
```

**Open that exact URL.** The token in the fragment is what authenticates you; plain `http://localhost:18789` will not let you in. To print it again later:

```bash
docker exec openclaw-<folder>-18789 openclaw dashboard --no-open --json
```

Any other OpenClaw command runs through the same script:

```bash
./openclaw.sh doctor
./openclaw.sh models list
./openclaw.sh channels          # WhatsApp, Telegram, Slack, Discord, ...
```

## Config

`OPENCLAW_PORT` changes the host port. `--build-arg OPENCLAW_VERSION=2026.8.2` pins the version instead of tracking latest. `OPENCLAW_DETACH=1` runs it in the background.

Everything the Gateway stores — config, sessions, memory, pairings, credentials, installed plugins — lives in `.harness/`, so it survives `docker rm`.

## Notes

- **The first start is slow (up to two minutes).** The Gateway refuses to report ready while any plugin still needs capability consent, and onboarding installs provider plugins that ask for it — with no prompt to answer inside a container. The entrypoint therefore starts the Gateway once, reads which plugins it named, accepts those, and marks the state directory done. Later starts skip it.
- **Loopback only.** The Gateway is the control plane for an agent with shell access and its token sits in a URL. It binds container loopback; socat carries the published port, mapped to the host's `127.0.0.1`. Do not republish on `0.0.0.0` — read OpenClaw's [exposure runbook](https://docs.openclaw.ai/gateway/security/exposure-runbook) first if you need remote access.
- **Channels are not wired up.** OpenClaw's messaging integrations need per-channel setup and, for most, inbound network access. Pair them yourself with `./openclaw.sh channels` if you want them.
- Keys are passed through from your environment and never written into the image.
