#!/usr/bin/env bash
# destroy.sh — Tear down EKS cluster.
# Run from the repo root: ./cluster/destroy.sh
#
# Prerequisites:
#   - Terminate any running RayJobs first: kubectl delete rayjob --all
#   - Or run the tutorial cleanup script if provided

set -euo pipefail

CLUSTER_NAME="eks-ray-platform"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

DESTROY_START=$(date +%s)
DESTROY_START_LABEL=$(date '+%H:%M:%S')

echo "── STEP 1: Uninstall KubeRay operator ──────────────────────────────────"
if helm status kuberay-operator -n ray-system &>/dev/null; then
    "${REPO_ROOT}/kuberay/uninstall.sh"
else
    echo "  KubeRay operator not found — skipping."
fi

echo ""
echo "── STEP 2: Delete EKS cluster with eksctl ──────────────────────────────"
CLUSTER_STATUS=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${REGION}" \
    --query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND")
if [[ "${CLUSTER_STATUS}" == "NOT_FOUND" ]]; then
    echo "  EKS cluster not found — skipping."
else
    eksctl delete cluster --name "${CLUSTER_NAME}" --region "${REGION}" --wait
fi

echo ""
echo "── Final check ─────────────────────────────────────────────────────────"
CLUSTER_STATUS=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${REGION}" \
    --query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND")
EKSCTL_STACK=$(aws cloudformation describe-stacks \
    --stack-name "eksctl-${CLUSTER_NAME}-cluster" \
    --region "${REGION}" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")
EC2_NODES=$(aws ec2 describe-instances --region "${REGION}" \
    --filters "Name=tag:aws:eks:cluster-name,Values=${CLUSTER_NAME}" \
              "Name=instance-state-name,Values=running,pending,stopping" \
    --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null \
    | grep -v '^$' | grep -v '^None$' || true)

[[ "${CLUSTER_STATUS}" == "NOT_FOUND" ]] && echo "  ✅  EKS cluster deleted"          || echo "  ❌  EKS cluster still exists (${CLUSTER_STATUS})"
[[ "${EKSCTL_STACK}"   == "NOT_FOUND" ]] && echo "  ✅  eksctl CloudFormation deleted" || echo "  ❌  eksctl stack still exists (${EKSCTL_STACK})"
[[ -z "${EC2_NODES}"               ]]    && echo "  ✅  No EC2 nodes still running"    || echo "  ❌  EC2 nodes still running: ${EC2_NODES}"

DESTROY_END=$(date +%s)
DESTROY_ELAPSED=$(( DESTROY_END - DESTROY_START ))
DESTROY_MIN=$(( DESTROY_ELAPSED / 60 ))
DESTROY_SEC=$(( DESTROY_ELAPSED % 60 ))

echo ""
echo "⏱  Started : ${DESTROY_START_LABEL}"
echo "⏱  Finished: $(date '+%H:%M:%S')"
echo "⏱  Elapsed : ${DESTROY_MIN}m ${DESTROY_SEC}s"
echo ""
echo "Run: ./scripts/cost-check.sh"
