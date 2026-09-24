# nanoLoop in AgentDorm

[nanoLoop](https://github.com/ismaelfaro/nanoLoop) is a tiny autonomous engineering harness: an OpenRouter model driving a LangChain DeepAgents crew through **Plan → Build → Review → Test → Ship**, with session memory, a Markdown knowledge graph, and reusable skills. Part of [AgentDorm](../../README.md).

It has no web UI, so it is a **worker** agent: a one-off `run` is one task in your terminal, and a resident takes every message in its dorm inbox as a task and replies with the result.

```
host                                     container
──────────────────────────────────────   ─────────────────────────────────
<folder you launch from>/   ──────────►  /workspace   HARNESS_WORKDIR: what the crew edits
agents/nanoloop/.harness/   ──────────►  /nanoloop    sessions, Memory/, Skills/, worker logs
residents/<name>/.harness/  ──────────►  /nanoloop    (for a resident, its own copy)
```

## One task on the current folder

```bash
export OPENROUTER_API_KEY=sk-or-...
cd /path/to/project
agentdorm run nanoloop "Scaffold a FastAPI service with a health check and a passing test"
agentdorm run nanoloop list            # saved sessions
agentdorm run nanoloop resume <id>     # continue one
agentdorm run nanoloop interactive "…" # human-in-the-loop gates on
```

## As a resident

```bash
agentdorm new builder --agent nanoloop \
  --description "Backend engineering: FastAPI services, tests, CI."
agentdorm up builder
agentdorm send builder -s "health check" "Add /healthz to the API and a test for it"
agentdorm inbox                        # the reply, with the tail of the run
```

Any other resident can delegate the same way from its own shell (`dorm send builder "…"`) or through the `dorm` MCP tools. The reply goes back to whoever asked.

## Configuration

| Variable | Meaning |
|---|---|
| `OPENROUTER_API_KEY` | Required. nanoLoop talks to every model through OpenRouter. |
| `HARNESS_MODEL` | Model slug (upstream default `openrouter/owl-alpha`). Any tool-calling model works; `nvidia/nemotron-3.5-lightning:free` is a free one. |
| `HARNESS_SUBAGENT_MODEL` | Optional cheaper model for the role subagents. |
| `HARNESS_FALLBACK_MODEL` | Optional model to fall back to when the primary keeps failing. |

Pin a different nanoLoop commit with `docker build --build-arg NANOLOOP_REF=<ref> -t nanoloop:local agents/nanoloop`.

## Notes

- **Identity.** nanoLoop has no persona slot, but its crew recalls from the Markdown memory graph before planning. A resident's description is seeded once as `Memory/identity.md` (`type: user`); the crew's own `remember` calls grow the graph from there.
- **Sandboxing.** Upstream's `run.sh` wraps nanoLoop in NVIDIA OpenShell. Here the container is the sandbox: the crew sees `/workspace` and its own state, nothing else of your machine. For outbound control, give the resident `egress: allowlist`.
- **Worker replies are never tasks.** Answers carry an `In-Reply-To` header and are filed, not run, so two workers cannot bounce messages at each other.
