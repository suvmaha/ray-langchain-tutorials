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

**What happens:**

Three LangChain agents run in parallel across three Ray workers. Each agent gets one question and has access to three tools:

- `classify_industry(company_name)` — looks up a company in a hardcoded dict
- `multiply_numbers(a, b)` — Python multiplication
- `add_numbers(a, b)` — Python addition

The LLM (Claude Haiku) decides which tool to call, calls it, gets the result back, and writes the final answer.

The three questions:
1. *"What industry is Microsoft in?"* → LLM calls `classify_industry("Microsoft")` → Technology
2. *"What is 2847 multiplied by 3921?"* → LLM calls `multiply_numbers(2847, 3921)` → 11,163,087
3. *"What industry is Goldman Sachs in? Also, what is 365 times 24?"* → LLM calls both `classify_industry` and `multiply_numbers` in a single turn → Finance + 8,760

That last one is the interesting part — Claude figured out it could batch both tool calls at once rather than making two sequential LLM calls.

The Ray part: all three questions fire simultaneously via `ray.remote`. Each worker is independent, so question 1 doesn't wait for question 2 to finish. At scale you'd run thousands of questions the same way — the pattern doesn't change.

**Pods** — KubeRay creates 5 pods per job:
- 1 head pod (Ray cluster head, runs the job driver)
- 3 worker pods (one per `run_agent.remote` call — `workerGroupSpecs.replicas: 3` in `rayjob.yaml`)
- 1 job submitter pod (KubeRay's internal job tracker, status: Completed)

**Nodes** — Auto Mode provisions EC2 instances on demand when pods go Pending. Each worker pod lands on a separate node. Before the job is submitted, `kubectl get nodes` may show nothing. After the job finishes and the RayCluster shuts down (600s TTL), the pods are deleted and Auto Mode scales nodes back to zero — no idle charges.

```
submit.sh → RayJob created → KubeRay creates RayCluster
  → pods Pending → Auto Mode provisions EC2 nodes
    → pods Running → job executes → SUCCEEDED
      → RayCluster shuts down → pods deleted → nodes scale to zero
```

## Compute

CPU only — no GPU needed. Auto Mode provisions nodes on demand and scales to zero when idle.

## Key Concepts

- **`@tool`** — decorates plain Python functions as LangChain tools
- **`create_agent`** — builds a LangGraph ReAct agent: model + tools
- **`agent.invoke`** — runs the agent loop: LLM decides → tool executes → LLM responds
- **`@ray.remote`** — each agent invocation runs on a separate Ray worker
- **`ray.get(futures)`** — collects results from all parallel workers
- **RayJob** — KubeRay CRD that submits a job to the Ray cluster and shuts it down when done

## What's Next

- **LangGraph Workflow** — stateful graph with nodes distributed across Ray workers
