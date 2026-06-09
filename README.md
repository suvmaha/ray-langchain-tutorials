# Ray + LangChain Tutorials on AWS EKS

Hands-on tutorials for running LangChain agents and LangGraph workflows at scale on Ray and Amazon EKS. Most LangGraph tutorials run single-process on a laptop — these run distributed across a cluster.

## The Stack

```
AWS EKS Auto Mode  (your infrastructure — managed by AWS)
    └── KubeRay   (Ray cluster operator)
            └── LangGraph  (agentic orchestration)
                    └── LLMs  (Claude, Llama, GPT)
                            └── LangSmith  (observability)
```

## Tutorials

| Tutorial | What It Covers |
|----------|---------------|
| [langchain-hello-agent](tutorials/langchain-hello-agent/) | First LangChain agent on Ray — tools, model, parallel invoke |
| [langgraph-workflow](tutorials/langgraph-workflow/) | Stateful LangGraph graph distributed across Ray workers |
| [langgraph-multi-agent](tutorials/langgraph-multi-agent/) | Parallel agent runs at scale with Ray Data |
| [langsmith-observability](tutorials/langsmith-observability/) | Trace distributed agent runs with LangSmith |
| [langgraph-gpu-llm](tutorials/langgraph-gpu-llm/) | LangGraph + vLLM on GPU — self-hosted LLM, no API dependency |

## Prerequisites

| Tool | Purpose |
|------|---------|
| AWS CLI | configured for your account |
| eksctl ≥ 0.195 | EKS cluster creation |
| kubectl | Kubernetes operations |
| helm ≥ 3 | KubeRay operator install |
| Python 3.11+ | tutorial scripts |

## Cluster Lifecycle

```bash
# 1. Create EKS Auto Mode cluster + KubeRay operator (~10 min)
./cluster/create.sh

# 2. Run tutorials
#    See each tutorial's playbook.md

# 3. Tear down
./cluster/destroy.sh
```

## Cost Check

```bash
./scripts/cost-check.sh
```

Read-only audit of billable AWS resources — run after teardown to confirm zero spend.

## Cost

| Resource | Rate |
|----------|------|
| EKS control plane | ~$0.10/hr |
| EC2 nodes | On demand, scale to zero when idle |

Auto Mode scales to zero between jobs — no idle node costs. Run `./cluster/destroy.sh` to stop all charges.
