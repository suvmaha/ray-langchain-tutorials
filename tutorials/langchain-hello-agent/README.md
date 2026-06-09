# LangChain Hello Agent

First LangChain agent running as a Ray job on KubeRay + EKS Auto Mode. Three questions run in parallel across Ray workers — the same pattern that scales to thousands.

## What It Does

1. Submits a RayJob to KubeRay on EKS
2. Fires 3 agent questions in parallel as `ray.remote` tasks
3. Each worker: Claude Haiku + 3 tools (add, multiply, classify industry)
4. Agent decides which tools to call, executes them, returns answers

```
Q: What industry is Microsoft in?
A: Microsoft is in the Technology industry.

Q: What is 2847 multiplied by 3921?
A: 2847 multiplied by 3921 is 11,163,087.

Q: What industry is Goldman Sachs in? Also, what is 365 times 24?
A: Goldman Sachs is in the Finance industry. 365 times 24 equals 8,760.
```

## Run It

Follow the [playbook](playbook.md) — step-by-step from cluster creation to teardown.

```bash
export ANTHROPIC_API_KEY=<your-key>
./tutorials/langchain-hello-agent/submit.sh
```

## Compute

CPU only — no GPU needed. Auto Mode provisions nodes on demand and scales to zero when idle.

## Key Concepts

- **`@tool`** — decorates plain Python functions as LangChain tools
- **`create_agent`** — builds a LangGraph ReAct agent: model + tools + prompt
- **`agent.invoke`** — runs the agent loop: LLM decides → tool executes → LLM responds
- **`@ray.remote`** — each agent invocation runs on a separate Ray worker
- **`ray.get(futures)`** — collects results from all parallel workers
- **RayJob** — KubeRay CRD that submits a job to the Ray cluster and shuts it down when done

## What's Next

- **LangGraph Workflow** — stateful graph with nodes distributed across Ray workers
