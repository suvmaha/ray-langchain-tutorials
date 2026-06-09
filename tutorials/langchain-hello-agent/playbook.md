# Playbook — LangChain Hello Agent

**Estimated time:** ~40 min (clone ~1 min + cluster ~30 min + job ~5 min + results ~4 min)

Run a LangChain agent as a RayJob on KubeRay + EKS Auto Mode. Three questions run in parallel across Ray workers — the same pattern that scales to thousands.

Execute steps in order — each step leaves the environment ready for the next.

---

## Table of Contents

- [STEP 1 — Verify Tools](#step-1--verify-tools)
- [STEP 2 — Clone the repo](#step-2--clone-the-repo)
- [STEP 3 — Set API Key](#step-3--set-api-key)
- [STEP 4 — Create EKS cluster](#step-4--create-eks-cluster)
- [STEP 5 — Submit the agent job](#step-5--submit-the-agent-job)
- [STEP 6 — Monitor and verify results](#step-6--monitor-and-verify-results)
- [STEP 7 — (Optional) Enable LangSmith tracing](#step-7--optional-enable-langsmith-tracing)
- [STEP 8 — Tear Down](#step-8--tear-down)

---

## STEP 1 — Verify Tools

```bash
aws --version              # aws-cli/2.x
eksctl version             # 0.195+
kubectl version --client   # v1.3x
helm version --short       # v3.x

# Confirm AWS identity
aws sts get-caller-identity

# OUTPUT
{
    "UserId": "AROAXXXXXXXXXXXXXXXXX:session",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:assumed-role/..."
}
```

---

## STEP 2 — Clone the repo

```bash
git clone https://github.com/suvmaha/ray-langchain-tutorials.git
cd ray-langchain-tutorials

# Set REPO_ROOT — all paths in this playbook are relative to here
export REPO_ROOT=$(pwd)
```

**Explore the structure:**

```bash
tree -L 3
```

```
ray-langchain-tutorials/
├── cluster/
│   ├── cluster.yaml.template   ← eksctl Auto Mode config
│   ├── create.sh               ← creates cluster + installs KubeRay
│   └── destroy.sh              ← tears down cluster
├── kuberay/
│   ├── install.sh              ← KubeRay operator via Helm
│   └── uninstall.sh
├── scripts/
│   └── cost-check.sh           ← read-only billing audit
└── tutorials/
    └── langchain-hello-agent/
        ├── agent.py            ← LangChain agent code
        ├── rayjob.yaml         ← KubeRay RayJob spec
        ├── submit.sh           ← creates secret + configmap + applies rayjob
        └── playbook.md         ← you are here
```

---

## STEP 3 — Set API Key

The agent calls Claude Haiku via the Anthropic API. `submit.sh` checks for this and fails fast if missing.

```bash
export ANTHROPIC_API_KEY=<your-anthropic-api-key>

# Verify
echo $ANTHROPIC_API_KEY | cut -c1-8    # e.g. sk-ant-ap
```

> Get your key at: console.anthropic.com → API Keys

---

## STEP 4 — Create EKS cluster

```bash
./cluster/create.sh

# OUTPUT
── Pre-flight checks ───────────────────────────────────────────────────
  ✅  No existing cluster 'eks-ray-platform'
  ✅  eksctl available
  ✅  kubectl available
  ✅  helm available

╔══════════════════════════════════════════════════════════════════════╗
║           Ray LangChain — EKS Auto Mode Cluster                     ║
╠══════════════════════════════════════════════════════════════════════╣
║  Cluster name   : eks-ray-platform                                   ║
║  Region         : us-east-1                                          ║
║  Kubernetes     : 1.35                                               ║
║  Compute        : EKS Auto Mode (scale to zero, on demand)           ║
║  Ray operator   : KubeRay (installed after cluster)                  ║
╚══════════════════════════════════════════════════════════════════════╝

Proceed with cluster creation? (y/n): y

── STEP 1: Generate eksctl cluster config ──────────────────────────────
  Written: cluster/cluster.yaml

── STEP 2: Create EKS Auto Mode cluster (~30 min) ──────────────────────
  ...eksctl output...
  Cluster created.

── STEP 3: Install KubeRay operator ────────────────────────────────────
  ✅  KubeRay operator v1.2.2 installed in ray-system namespace.

── STEP 4: Verify ──────────────────────────────────────────────────────
  ✅  Cluster ready

⏱  Elapsed: ~30m
```

**Verify KubeRay is running:**

```bash
kubectl get deployment kuberay-operator -n ray-system

# NAME               READY   UP-TO-DATE   AVAILABLE
# kuberay-operator   1/1     1            1
```

> **Auto Mode note:** `kubectl get nodes` may return empty until a workload is scheduled — that's expected. Nodes appear on demand.

---

## STEP 5 — Submit the agent job

```bash
./tutorials/langchain-hello-agent/submit.sh

# OUTPUT
secret/langchain-secrets configured
configmap/langchain-hello-agent-code configured
rayjob.ray.io/langchain-hello-agent created

RayJob submitted. Monitor with:
  kubectl get rayjob langchain-hello-agent -w
  kubectl logs -l ray.io/node-type=head -n default --follow
```

**What `submit.sh` does:**

1. Creates a Kubernetes secret with your `ANTHROPIC_API_KEY`
2. Creates a ConfigMap with `agent.py` so the Ray pods can run it without a custom image
3. Applies `rayjob.yaml` — KubeRay spins up a RayCluster, runs the job, shuts it down

**What runs inside Ray:**

```
agent.py
├── ray.init()                                                    — connect to cluster
├── run_agent.remote("What industry is Microsoft in?")           ─┐
├── run_agent.remote("What is 2847 * 3921?")                     ─┤── 3 Ray workers in parallel
└── run_agent.remote("Goldman Sachs industry + 365*24?")         ─┘
        ↓ each worker:
        make_agent()                    — Claude Haiku + 3 tools
        create_agent(model, tools)      — LangGraph ReAct agent
        agent.invoke(question)          — LLM decides which tools to call
        return {"question": ..., "answer": ...}
```

---

## STEP 6 — Monitor and verify results

**Open the Ray Dashboard (in a separate terminal):**

```bash
# Get the head pod name
kubectl get pods -n default -l ray.io/node-type=head

# Port-forward the dashboard
kubectl port-forward -n default svc/langchain-hello-agent-head-svc 8265:8265

# Open in browser: http://localhost:8265
```

The dashboard shows:
- **Jobs** tab — job status, duration, entrypoint
- **Cluster** tab — worker nodes, CPU/memory per node
- **Tasks** tab — individual `run_agent.remote` tasks, which worker ran each one
- **Logs** tab — per-task log output

> Keep the port-forward running while the job is active. It closes when the RayCluster shuts down after the job finishes.

**Watch job state transitions:**

```bash
kubectl get rayjob langchain-hello-agent -w

# NAME                    JOB STATUS   DEPLOYMENT STATUS   START TIME
# langchain-hello-agent   PENDING      Running             ...
# langchain-hello-agent   RUNNING      Running             ...
# langchain-hello-agent   SUCCEEDED    Complete            ...
```

**Read job output (job driver log on the head pod):**

```bash
HEAD_POD=$(kubectl get pod -l ray.io/node-type=head -n default -o jsonpath='{.items[0].metadata.name}')
kubectl exec $HEAD_POD -n default -- \
  bash -c 'cat /tmp/ray/session_latest/logs/job-driver-langchain-hello-agent-*.log'

# OUTPUT
Running 3 agent questions in parallel on Ray...

(run_agent pid=...)   [HumanMessage] What industry is Microsoft in?
(run_agent pid=...)   [AIMessage] [{'name': 'classify_industry', 'input': {'company_name': 'Microsoft'}, ...}]
(run_agent pid=...)   [ToolMessage] Microsoft → Technology
(run_agent pid=...)   [AIMessage] Microsoft is in the Technology industry.

(run_agent pid=..., ip=...)   [HumanMessage] What is 2847 multiplied by 3921?
(run_agent pid=..., ip=...)   [ToolMessage] 11162487.0
(run_agent pid=..., ip=...)   [AIMessage] 2847 multiplied by 3921 equals 11,162,487.

(run_agent pid=..., ip=...)   [HumanMessage] What industry is Goldman Sachs in? Also, what is 365 times 24?
(run_agent pid=..., ip=...)   [ToolMessage] Goldman Sachs → Finance
(run_agent pid=..., ip=...)   [ToolMessage] 8760.0
(run_agent pid=..., ip=...)   [AIMessage] Goldman Sachs is in the Finance industry. 365 times 24 equals 8,760.

============================================================
RESULTS
============================================================

Q: What industry is Microsoft in?
A: Microsoft is in the Technology industry.

Q: What is 2847 multiplied by 3921?
A: 2847 multiplied by 3921 equals 11,162,487.

Q: What industry is Goldman Sachs in? Also, what is 365 times 24?
A: Goldman Sachs is in the Finance industry. 365 times 24 equals 8,760.
```

> Each `(run_agent pid=..., ip=...)` prefix shows which Ray worker handled that task — different IPs confirm the agents ran on separate nodes.

**Confirm job succeeded:**

```bash
kubectl get rayjob langchain-hello-agent

# JOB STATUS: SUCCEEDED
```

> The RayCluster shuts down automatically after the job finishes (`shutdownAfterJobFinishes: true`). Auto Mode scales the nodes back to zero within minutes.

---

## STEP 7 — (Optional) Enable LangSmith Tracing

LangSmith captures every tool call and LLM decision for every agent run — across all Ray workers. No code changes needed.

**Get a LangSmith API key:** smith.langchain.com → Settings → API Keys

```bash
export LANGSMITH_API_KEY=<your-langsmith-key>
export LANGSMITH_PROJECT=langchain-hello-agent
```

**Add LangSmith vars to the Kubernetes secret and resubmit:**

```bash
kubectl create secret generic langchain-secrets \
    --from-literal=ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}" \
    --from-literal=LANGSMITH_TRACING=true \
    --from-literal=LANGSMITH_API_KEY="${LANGSMITH_API_KEY}" \
    --from-literal=LANGSMITH_PROJECT="${LANGSMITH_PROJECT}" \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl delete rayjob langchain-hello-agent --ignore-not-found
kubectl apply -f tutorials/langchain-hello-agent/rayjob.yaml
```

> Update `rayjob.yaml` to also mount `LANGSMITH_TRACING`, `LANGSMITH_API_KEY`, and `LANGSMITH_PROJECT` from the secret — same pattern as `ANTHROPIC_API_KEY`.

**View traces:** smith.langchain.com → Projects → langchain-hello-agent

Each of the 3 parallel runs appears as a separate trace: input → tool calls → tool outputs → final answer.

---

## STEP 8 — Tear Down

```bash
# 1. Clean up RayJob resources
kubectl delete rayjob langchain-hello-agent --ignore-not-found
kubectl delete configmap langchain-hello-agent-code --ignore-not-found
kubectl delete secret langchain-secrets --ignore-not-found

# 2. Destroy cluster
./cluster/destroy.sh

# 3. Confirm zero spend
./scripts/cost-check.sh

# Expected: ✅ All clear — no billable resources found in us-east-1
```

---

## Common Issues

**`ANTHROPIC_API_KEY` not set:**
```
ERROR: ANTHROPIC_API_KEY is not set.
```
Fix: `export ANTHROPIC_API_KEY=<your-key>` then resubmit.

**Job stuck in PENDING:**
```bash
kubectl describe rayjob langchain-hello-agent
kubectl get pods -n default
kubectl describe pod <pending-pod> -n default | grep -A 20 "Events:"
```
Usually: Auto Mode is provisioning nodes (first run takes 2-3 min). Give it time.

**`ImportError` on job start:**
Ray pip-cached a virtualenv from a previous run on the same node. Delete all resources and resubmit:
```bash
kubectl delete rayjob langchain-hello-agent --ignore-not-found
kubectl delete configmap langchain-hello-agent-code --ignore-not-found
kubectl delete secret langchain-secrets --ignore-not-found
./tutorials/langchain-hello-agent/submit.sh
```

**Job output not visible in head pod logs:**
The job driver log is separate from the Ray head process. Read it directly:
```bash
HEAD_POD=$(kubectl get pod -l ray.io/node-type=head -n default -o jsonpath='{.items[0].metadata.name}')
kubectl exec $HEAD_POD -n default -- \
  bash -c 'cat /tmp/ray/session_latest/logs/job-driver-langchain-hello-agent-*.log'
```

**Agent returns wrong answer:**
Check tool call trace — look for `[ToolMessage]` lines to see which tools were called and what they returned.
