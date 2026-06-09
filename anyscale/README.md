# Anyscale

Registers your EKS cluster with Anyscale so the control plane can manage Ray workloads on your cluster.

## What This Does

`setup.sh` runs one command — `anyscale cloud setup` — which automatically:

1. Validates your EKS cluster and OIDC provider
2. Creates a CloudFormation stack — S3 bucket for job artifacts + IAM role scoped to your cluster (via IRSA)
3. Registers your cluster as an Anyscale cloud (`eks-ray-cloud`)
4. Installs the Anyscale operator into your cluster via Helm
5. Runs a functional verification job

After setup, your cluster appears in the Anyscale console at console.anyscale.com. Anyscale's control plane communicates with your cluster over HTTPS only — your data and compute stay in your AWS account.

## Prompts to Watch For

The `anyscale cloud setup` command is interactive:

- **Name** — type `eks-ray-cloud` (the cloud name for this cluster)
- **Namespace** — press Enter to accept `anyscale-operator`
- **Ingress** — type `n` — nginx ingress is already installed by `cluster/create.sh`, skip re-installing it here

## Scripts

```bash
./anyscale/setup.sh      # Register cluster with Anyscale (run after cluster/create.sh)
./anyscale/teardown.sh   # Deregister cluster + delete operator + CloudFormation stack
```

> **Important:** Always run `./anyscale/teardown.sh` before `./cluster/destroy.sh` — teardown cleans up the Anyscale operator and CloudFormation stack that setup.sh created.

## What Gets Created in AWS

| Resource | Purpose |
|----------|---------|
| CloudFormation stack | S3 bucket + IAM role for Anyscale |
| S3 bucket | Job artifacts, logs, checkpoints |
| IAM role (IRSA) | Anyscale operator permissions, scoped to your cluster |
| Helm release | Anyscale operator running in `anyscale-operator` namespace |
