# Cluster

Creates an EKS cluster with self-managed Karpenter for running Ray and Anyscale workloads.

## What Gets Created

| Resource | Detail |
|----------|--------|
| EKS cluster | Standard mode, Kubernetes 1.35 |
| System node group | 2x m5.xlarge (fixed, runs Karpenter + system pods) |
| Karpenter | Self-managed, installed via Helm — provisions workload nodes on demand |
| Anyscale NodePool | On-demand m/c/r-family instances, scale to zero when idle |
| nginx ingress | Exposes Ray head node so Anyscale can register DNS |
| GPU NodePool | Optional — g6 instances (NVIDIA L4), apply when tutorials need GPUs |
| VPC | Provisioned by CDK in `infra/` — 2 AZs, public + private subnets |

Workload nodes scale to zero when idle. New nodes provision automatically when Anyscale schedules Ray workers.

## Why Self-Managed Karpenter (Not EKS Auto Mode)

EKS Auto Mode uses AWS-managed Karpenter, which restricts the `eks.amazonaws.com` label domain in NodePool requirements. Anyscale's operator uses `eks.amazonaws.com/capacityType=ON_DEMAND` as a node selector — that label is blocked in Auto Mode's managed Karpenter. Self-managed Karpenter has no such restriction.

## Why This Cluster for Ray and Anyscale

Ray distributes Python workloads across a cluster of machines. Anyscale manages that cluster — scheduling jobs, scaling workers, persisting logs. EKS is where those Ray workers actually run.

- **Anyscale path** — register this cluster with `../anyscale/setup.sh`. Anyscale's control plane manages Ray workloads over HTTPS. Your data stays in your AWS account.
- **KubeRay path** — install the open-source Ray operator with `../kuberay/install.sh`. Full control, no Anyscale account needed.

## Scripts

```bash
./cluster/create.sh                            # Deploy VPC (CDK) + EKS cluster + Karpenter + nginx ingress
INSTALL_GPU_NODEPOOL=true ./cluster/create.sh  # Same + apply GPU NodePool for LLM tutorials
./cluster/destroy.sh                           # Tear down cluster + VPC
```

## Files

| File | Purpose |
|------|---------|
| `cluster.yaml.template` | eksctl cluster definition (VPC, system node group, Karpenter IRSA) |
| `karpenter-iam-policy.json.template` | IAM policy for Karpenter controller — created in STEP 3 |
| `karpenter-nodepool.yaml.template` | EC2NodeClass + Anyscale NodePool — applied in STEP 10 |
| `gpu-nodepool.yaml` | Optional GPU NodePool (g6/L4) — applied in STEP 12 |
| `nvidia-device-plugin.yaml` | NVIDIA device plugin DaemonSet — exposes `nvidia.com/gpu` resource on GPU nodes |

## Next Steps

```bash
# Anyscale path
./anyscale/setup.sh

# KubeRay path
./kuberay/install.sh
```
