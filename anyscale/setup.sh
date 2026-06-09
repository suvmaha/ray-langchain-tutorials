#!/usr/bin/env bash
# setup.sh — Register this EKS cluster with Anyscale.
# Run from the repo root: ./anyscale/setup.sh
#
# Prerequisites:
#   - EKS cluster is running:  ./cluster/create.sh
#   - kubectl is configured:   aws eks update-kubeconfig --region <region> --name <cluster>
#   - Anyscale CLI installed:  pip install -U anyscale
#   - Authenticated:           anyscale login
#
# What this does:
#   1. Validates EKS cluster + OIDC provider
#   2. Creates CloudFormation stack (S3 bucket + IAM role via IRSA)
#   3. Registers the Anyscale cloud with the control plane
#   4. Installs the Anyscale operator via Helm
#   5. Runs functional verification

set -euo pipefail

export AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export AWS_DEFAULT_REGION="${AWS_REGION}"
export EKS_CLUSTER_NAME="eks-ray-platform"
export ANYSCALE_CLOUD_NAME="${ANYSCALE_CLOUD_NAME:-eks-ray-cloud}"

echo "── Prerequisites ───────────────────────────────────────────────────────"
printf "  Cluster  : %s\n" "${EKS_CLUSTER_NAME}"
printf "  Region   : %s\n" "${AWS_REGION}"
printf "  Cloud    : %s\n" "${ANYSCALE_CLOUD_NAME}"
echo ""

echo "── Configuring kubectl ──────────────────────────────────────────────────"
aws eks update-kubeconfig --region "${AWS_REGION}" --name "${EKS_CLUSTER_NAME}"
kubectl get nodes
echo ""

echo "── Setting up Anyscale on EKS ──────────────────────────────────────────"
echo "Prompts to watch for:"
echo "  Name       → type '${ANYSCALE_CLOUD_NAME}' (the cloud name for this cluster)"
echo "  Namespace  → press Enter to accept 'anyscale-operator'"
echo "  Ingress    → type 'n' — nginx ingress is already installed by cluster/create.sh"
echo ""

anyscale cloud setup \
    --provider aws \
    --region "${AWS_REGION}" \
    --name "${ANYSCALE_CLOUD_NAME}" \
    --stack k8s \
    --cluster-name "${EKS_CLUSTER_NAME}" \
    --functional-verify

echo ""
echo "── Verify ──────────────────────────────────────────────────────────────"
anyscale cloud verify --name "${ANYSCALE_CLOUD_NAME}"

echo ""
echo "Anyscale is ready on ${EKS_CLUSTER_NAME}."
echo ""
echo "Run tutorials:"
echo "  ./tutorials/README.md   # index of all tutorials with commands"
