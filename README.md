# Ray + LangChain Tutorials on AWS EKS

Hands-on tutorials for running LangChain agents and LangGraph workflows at scale on Ray and Amazon EKS. Most LangGraph tutorials run single-process on a laptop — these run distributed across a GPU cluster.

## The Stack

```
AWS EKS  (your infrastructure)
    └── Ray  (distributed compute engine)
            └── LangGraph  (agentic orchestration)
                    └── LLMs  (Llama, Claude, GPT)
                            └── LangSmith  (observability)
```

## Tutorials

| Tutorial | What It Covers |
|----------|---------------|
| [langchain-hello-agent](tutorials/langchain-hello-agent/) | First LangChain agent on Ray — tools, model, invoke |
| [langgraph-workflow](tutorials/langgraph-workflow/) | Stateful LangGraph graph distributed across Ray workers |
| [langgraph-multi-agent](tutorials/langgraph-multi-agent/) | Parallel agent runs at scale with Ray Data |
| [langsmith-observability](tutorials/langsmith-observability/) | Trace distributed agent runs with LangSmith |
| [langgraph-gpu-llm](tutorials/langgraph-gpu-llm/) | LangGraph + vLLM on GPU — self-hosted LLM, no OpenAI dependency |

## Prerequisites

| Tool | Purpose |
|------|---------|
| AWS CLI | configured for your account |
| eksctl ≥ 0.195 | EKS cluster creation |
| kubectl | Kubernetes operations |
| helm ≥ 3 | Operator installation |
| Python 3.11+ | CDK, tutorial scripts |

## Cluster Setup

```bash
# 1. Create EKS cluster
./cluster/create.sh

# 2. Run tutorials
#    See each tutorial's README for instructions

# 3. Tear down cluster when done
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
| NAT gateway | ~$1/day |
| EKS control plane | ~$0.10/hr |
| EC2 nodes | Per use, scale to zero when idle |

Run `./cluster/destroy.sh` when done to stop all charges.
