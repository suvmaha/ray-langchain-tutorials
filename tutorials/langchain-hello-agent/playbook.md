# Playbook — LangChain Hello Agent

**Estimated time:** ~25 min (cluster ~15 min + Anyscale setup ~3 min + job ~5 min)

Run a LangChain agent as a Ray job on Anyscale + EKS. Three questions run in parallel across Ray workers — the same pattern that scales to thousands.

Execute steps in order — each step leaves the environment ready for the next.

---

## Table of Contents

- [STEP 1 — Verify Tools](#step-1--verify-tools)
- [STEP 2 — Set API Key](#step-2--set-api-key)
- [STEP 3 — Create EKS cluster](#step-3--create-eks-cluster)
- [STEP 4 — Wire Anyscale](#step-4--wire-anyscale)
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
anyscale --version         # anyscale CLI

# Confirm AWS identity
aws sts get-caller-identity

# OUTPUT
{
    "UserId": "AROAXXXXXXXXXXXXXXXXX:session",
    "Account": "123456789012",
    "Arn": "arn:aws:iam::123456789012:assumed-role/..."
}
```

> Install anyscale CLI: `pipx install anyscale` then `anyscale login`

---

## STEP 2 — Set API Key

The agent calls Claude Haiku via the Anthropic API. Set your key before submitting the job — the submit script checks for it and fails fast if missing.

```bash
export ANTHROPIC_API_KEY=<your-anthropic-api-key>

# Verify it's set
echo $ANTHROPIC_API_KEY | cut -c1-8    # should print first 8 chars, e.g. sk-ant-ap
```

> Get your key at: console.anthropic.com → API Keys

---

## STEP 3 — Create EKS cluster

```bash
./cluster/create.sh

# OUTPUT
╔══════════════════════════════════════════════════════════════════════╗
║              Ray Platform — EKS Cluster                             ║
╠══════════════════════════════════════════════════════════════════════╣
║  Cluster name   : eks-ray-platform                                   ║
║  Region         : us-east-1                                          ║
╚══════════════════════════════════════════════════════════════════════╝

── STEP 1: CDK VPC stack ───────────────────────────────────────────────
  ✅  VPC stack deployed

── STEP 2: EKS cluster ─────────────────────────────────────────────────
  ...eksctl output (~10 min)...
  ✅  Cluster ready

── STEP 3: Karpenter ───────────────────────────────────────────────────
  ✅  Karpenter installed

── STEP 4: nginx ingress ───────────────────────────────────────────────
  ✅  nginx ingress controller installed

⏱  Elapsed: ~15m
```

**Verify nodes are ready:**

```bash
kubectl get nodes

# NAME                                          STATUS   ROLES    AGE
# ip-10-0-x-x.ec2.internal                     Ready    <none>   2m
```

---

## STEP 4 — Wire Anyscale

```bash
./anyscale/setup.sh

# OUTPUT
── STEP 1: Anyscale cloud setup ─────────────────────────────────────────
  ✅  Cloud registered: eks-ray-cloud

── STEP 2: Anyscale operator ────────────────────────────────────────────
  ✅  Operator installed

── STEP 3: Verify ───────────────────────────────────────────────────────
  ✅  Anyscale cloud verified
```

**Verify the operator is running:**

```bash
kubectl get pods -n anyscale-operator

# NAME                    READY   STATUS    RESTARTS   AGE
# anyscale-operator-xxx   1/1     Running   0          60s
```

---

## STEP 5 — Submit the agent job

```bash
./tutorials/langchain-hello-agent/submit.sh

# OUTPUT
Submitting job 'langchain-hello-agent'...
Job submitted. View at: https://console.anyscale.com/jobs
Job ID: prodjob_xxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

**What runs:**

```
agent.py
├── ray.init()                          — connect to Ray cluster
├── run_agent.remote("What industry is Microsoft in?")     ─┐
├── run_agent.remote("What is 2847 * 3921?")               ─┤── 3 Ray workers in parallel
└── run_agent.remote("Goldman Sachs industry + 365*24?")   ─┘
        ↓ each worker:
        make_agent()                    — Claude Haiku + 3 tools
        AgentExecutor.invoke(question)  — LLM decides which tools to call
        return {"question": ..., "answer": ...}
```

**Monitor at:** console.anyscale.com/jobs

---

## STEP 6 — Monitor and verify results

**Stream logs in real time:**

```bash
anyscale job logs --name langchain-hello-agent --follow

# OUTPUT (per worker, interleaved)
Running 3 agent questions in parallel on Ray...

> Entering new AgentExecutor chain...
> Invoking: `classify_industry` with `{'company_name': 'Microsoft'}`
> Microsoft → Technology
> I found that Microsoft is in the Technology industry.
> Finished chain.

> Entering new AgentExecutor chain...
> Invoking: `multiply_numbers` with `{'a': 2847.0, 'b': 3921.0}`
> 11,162,487.0
> The result of 2847 multiplied by 3921 is 11,162,487.
> Finished chain.

...

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

**Check job status:**

```bash
anyscale job status --name langchain-hello-agent

# STATE: SUCCESS
```

**Confirm Ray ran tasks in parallel — check head pod:**

```bash
# Get the head pod name (6/6 Running, no GPU)
kubectl get pods -n anyscale-operator

kubectl exec -it <head-pod> -n anyscale-operator -c ray -- ray status

# OUTPUT
...
Active:
  ...  3.0/3.0 CPU  (3 workers consumed)
...
```

> If STATE is FAILED, check [Common Issues](#common-issues) below.

---

## STEP 7 — (Optional) Enable LangSmith Tracing

LangSmith captures every tool call and LLM decision for every agent run — across all Ray workers. No code changes needed — just two env vars.

**Get a LangSmith API key:** smith.langchain.com → Settings → API Keys

```bash
export LANGSMITH_API_KEY=<your-langsmith-key>
export LANGSMITH_PROJECT=langchain-hello-agent
```

**Resubmit with tracing enabled:**

```bash
cd tutorials/langchain-hello-agent
anyscale job submit \
    --cloud eks-ray-cloud \
    --config-file job.yaml \
    --env ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}" \
    --env LANGSMITH_TRACING=true \
    --env LANGSMITH_API_KEY="${LANGSMITH_API_KEY}" \
    --env LANGSMITH_PROJECT="${LANGSMITH_PROJECT}"
```

**View traces:** smith.langchain.com → Projects → langchain-hello-agent

Each of the 3 parallel runs appears as a separate trace showing: input → tool calls → tool outputs → final answer.

---

## STEP 8 — Tear Down

```bash
# 1. Remove Anyscale
./anyscale/teardown.sh

# 2. Destroy cluster and VPC
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

**Job stuck in STARTING (>5 min):**
```bash
kubectl get pods -n anyscale-operator
kubectl describe pod <pending-pod> -n anyscale-operator | grep -A 20 "Events:"
```
Usually: image pull in progress (first run) or Karpenter provisioning a node. Give it 3-5 min.

**`ModuleNotFoundError: langchain_anthropic`:**
The `runtime_env` pip install failed. Check logs:
```bash
anyscale job logs --name langchain-hello-agent | grep -i "pip\|install\|error"
```
If the image doesn't support runtime_env pip installs, build a custom image with LangChain pre-installed.

**Agent returns wrong answer:**
Check the full tool call trace in the logs — look for `Invoking:` lines to see which tools were called and what they returned.
