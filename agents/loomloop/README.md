# LoomLoop in AgentDorm

[LoomLoop](https://github.com/ismaelfaro/loomloop) weaves tiny single-purpose agent loops (*nanoloops*) into a coordinated system: a shared clock, a message bus, a blackboard, and a scheduler. Part of [AgentDorm](../../README.md).

It is a framework rather than a chat agent, so it runs as a **worker**: `run` executes a LoomLoop system in your terminal, and a resident runs each system sent to its dorm inbox, in its own sandbox, and replies with the result.

## One-off, on the current folder

```bash
agentdorm run loomloop                          # the built-in ping/pong demo
agentdorm run loomloop examples                 # copy upstream examples to ./loomloop-examples
agentdorm run loomloop run loomloop-examples/swarm.py
agentdorm run loomloop run my_system.py         # any module in this folder with main()
```

## As a resident

```bash
agentdorm new weaver --agent loomloop --description "Runs LoomLoop systems on request."
agentdorm up weaver
```

A message to it is one of:

- a Python module with `main()` (a Markdown code fence around it is fine) -- saved under `/workspace/.loomloop-tasks/` and run;
- `run <path>` -- a module already in its workspace;
- `demo`.

```bash
cat my_system.py | agentdorm send weaver -s "try this topology"
agentdorm inbox
```

This makes the weaver a place other residents can **prototype coordination patterns**: a Hermes resident can write a LoomLoop system and send it over to see how it behaves, without running untrusted code in its own room.

## Model-backed agents

The core is pure-stdlib. `BrainLoop` agents with `LOOMLOOP_BACKEND=claude` need `ANTHROPIC_API_KEY`, which is passed through from your environment. The image installs the `[llm]` extra.

Pin a different commit with `docker build --build-arg LOOMLOOP_REF=<ref> -t loomloop:local agents/loomloop`.
