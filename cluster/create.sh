#!/usr/bin/env bash
# create.sh — Create an EKS Auto Mode cluster and install KubeRay operator.
# Run from the repo root: ./cluster/create.sh
#
# EKS Auto Mode manages compute, networking, storage, and load balancing.
# No CDK, no Karpenter, no nginx ingress, no addon installs.
#
# Steps:
#   1. Generate cluster.yaml from template
#   2. Create EKS Auto Mode cluster with eksctl (~10 min)
#   3. Install KubeRay operator
#   4. Verify
#
# Override defaults:
#   EKS_CLUSTER_NAME=my-cluster ./cluster/create.sh
#   K8S_VERSION=1.35 ./cluster/create.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

export EKS_CLUSTER_NAME="${EKS_CLUSTER_NAME:-eks-ray-platform}"
export AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export K8S_VERSION="${K8S_VERSION:-1.35}"
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --output text --query 'Account')

echo ""
echo "── Pre-flight checks ───────────────────────────────────────────────────"
PREFLIGHT_FAIL=false

CLUSTER_STATUS=$(aws eks describe-cluster --name "${EKS_CLUSTER_NAME}" \
    --region "${AWS_REGION}" --query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND")
if [[ "${CLUSTER_STATUS}" != "NOT_FOUND" ]]; then
    echo "  ❌  Cluster '${EKS_CLUSTER_NAME}' already exists (${CLUSTER_STATUS}) — run ./cluster/destroy.sh first"
    PREFLIGHT_FAIL=true
else
    echo "  ✅  No existing cluster '${EKS_CLUSTER_NAME}'"
fi

command -v eksctl  &>/dev/null && echo "  ✅  eksctl available"  || { echo "  ❌  eksctl not found";  PREFLIGHT_FAIL=true; }
command -v kubectl &>/dev/null && echo "  ✅  kubectl available" || { echo "  ❌  kubectl not found"; PREFLIGHT_FAIL=true; }
command -v helm    &>/dev/null && echo "  ✅  helm available"    || { echo "  ❌  helm not found";    PREFLIGHT_FAIL=true; }

[[ "${PREFLIGHT_FAIL}" == "true" ]] && echo "" && echo "Pre-flight failed. Aborting." && exit 1

echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║           Ray LangChain — EKS Auto Mode Cluster                     ║"
echo "╠══════════════════════════════════════════════════════════════════════╣"
printf "║  Cluster name   : %-50s║\n" "${EKS_CLUSTER_NAME}"
printf "║  AWS account    : %-50s║\n" "${AWS_ACCOUNT_ID}"
printf "║  Region         : %-50s║\n" "${AWS_REGION}"
printf "║  Kubernetes     : %-50s║\n" "${K8S_VERSION}"
echo "╠══════════════════════════════════════════════════════════════════════╣"
printf "║  Compute        : %-50s║\n" "EKS Auto Mode (scale to zero, on demand)"
printf "║  Load balancing : %-50s║\n" "built-in"
printf "║  Storage        : %-50s║\n" "built-in EBS"
printf "║  Ray operator   : %-50s║\n" "KubeRay (installed after cluster)"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

read -r -p "Proceed with cluster creation? (y/n): " confirm
[[ "${confirm}" != "y" ]] && echo "Aborted." && exit 0

CREATE_START=$(date +%s)
CREATE_START_LABEL=$(date '+%H:%M:%S')

echo ""
echo "── STEP 1: Generate eksctl cluster config ──────────────────────────────"
envsubst < "${SCRIPT_DIR}/cluster.yaml.template" > "${SCRIPT_DIR}/cluster.yaml"
echo "  Written: cluster/cluster.yaml"

echo ""
echo "── STEP 2: Create EKS Auto Mode cluster (~10 min) ──────────────────────"
eksctl create cluster -f "${SCRIPT_DIR}/cluster.yaml"
echo "  Cluster created."

echo ""
echo "── STEP 3: Install KubeRay operator ────────────────────────────────────"
"${REPO_ROOT}/kuberay/install.sh"

echo ""
echo "── STEP 4: Verify ──────────────────────────────────────────────────────"
echo "  Cluster:"
aws eks describe-cluster --name "${EKS_CLUSTER_NAME}" --region "${AWS_REGION}" \
    --query 'cluster.{Status:status,Version:version,AutoMode:computeConfig.enabled}' \
    --output table
echo ""
echo "  KubeRay operator:"
kubectl get deployment kuberay-operator -n ray-system

CREATE_END=$(date +%s)
CREATE_ELAPSED=$(( CREATE_END - CREATE_START ))
CREATE_MIN=$(( CREATE_ELAPSED / 60 ))
CREATE_SEC=$(( CREATE_ELAPSED % 60 ))

echo ""
echo "Cluster '${EKS_CLUSTER_NAME}' is ready."
echo "⏱  Started : ${CREATE_START_LABEL}"
echo "⏱  Finished: $(date '+%H:%M:%S')"
echo "⏱  Elapsed : ${CREATE_MIN}m ${CREATE_SEC}s"
echo ""
echo "Note: Auto Mode nodes appear only when workloads are scheduled."
echo "      kubectl get nodes may show no nodes until a RayJob is submitted."
echo ""
echo "Next: ./tutorials/langchain-hello-agent/submit.sh"
