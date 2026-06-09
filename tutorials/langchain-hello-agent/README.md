# LangChain Hello Agent

First LangChain agent running as a Ray job on Anyscale + EKS. Three questions run in parallel across Ray workers — the same pattern that scales to thousands.

## What It Does

1. Spins up a Ray cluster on EKS via Anyscale
2. Fires 3 agent questions in parallel as `ray.remote` tasks
3. Each worker: Claude Haiku + 3 tools (add, multiply, classify industry)
4. Agent decides which tools to call, executes them, returns answers

```
Q: What industry is Microsoft in?
A: Microsoft is in the Technology industry.

Q: What is 2847 multiplied by 3921?
A: 2847 multiplied by 3921 equals 11,162,487.

Q: What industry is Goldman Sachs in? Also, what is 365 times 24?
A: Goldman Sachs is in the Finance industry. 365 times 24 equals 8,760.
```

## Run It

Follow the [playbook](playbook.md) — it walks through every step from cluster creation to teardown with expected outputs.

```bash
export ANTHROPIC_API_KEY=<your-key>
./tutorials/langchain-hello-agent/submit.sh
```

## Compute

CPU only — no GPU needed. Karpenter provisions on-demand workers as Ray schedules tasks.

| Node | Type |
|------|------|
| Head | 4 CPU, 8 GiB |
| Workers (up to 3) | 2 CPU, 4 GiB each |

## Key Concepts

- **`@tool`** — decorates plain Python functions as LangChain tools
- **`create_tool_calling_agent`** — wires model + tools + prompt into an agent
- **`AgentExecutor`** — runs the agent loop: LLM decides → tool executes → LLM responds
- **`@ray.remote`** — each agent invocation runs on a separate Ray worker
- **`ray.get(futures)`** — collects results from all parallel workers

## What's Next

- **LangGraph Workflow** — stateful graph with nodes distributed across Ray workers
