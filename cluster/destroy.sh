#!/usr/bin/env bash
# destroy.sh — Tear down EKS cluster and VPC.
# Run from the repo root: ./cluster/destroy.sh
#
# Prerequisites:
#   - If using Anyscale: run ./anyscale/teardown.sh first
#   - If using KubeRay: run ./kuberay/uninstall.sh first
#
# Order:
#   1. Delete EKS cluster (eksctl)
#   2. Delete Karpenter IAM resources (policy, node role, instance profile)
#   3. Destroy CDK stack (VPC)
#   4. Optionally delete ray-* ECR repositories

set -euo pipefail

CLUSTER_NAME="eks-ray-platform"
REGION="${AWS_DEFAULT_REGION:-us-east-1}"
STACK_NAME="EksRayStack"
DESTROY_START=$(date +%s)
DESTROY_START_LABEL=$(date '+%H:%M:%S')
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --output text --query 'Account')
POLICY_NAME="KarpenterControllerPolicy-${CLUSTER_NAME}"
NODE_ROLE_NAME="KarpenterNodeRole-${CLUSTER_NAME}"
INSTANCE_PROFILE_NAME="KarpenterNodeInstanceProfile-${CLUSTER_NAME}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "── STEP 1: Delete EKS cluster with eksctl ──────────────────────────────"
CLUSTER_STATUS=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${REGION}" \
    --query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND")
if [[ "${CLUSTER_STATUS}" == "NOT_FOUND" ]]; then
    echo "EKS cluster not found — skipping."
else
    eksctl delete cluster --name "${CLUSTER_NAME}" --region "${REGION}" --wait
fi

echo ""
echo "── STEP 2: Delete Karpenter IAM resources ──────────────────────────────"

# Remove ALL instance profiles from KarpenterNodeRole — this covers both the
# manually-created KarpenterNodeInstanceProfile-* and any auto-created profiles
# Karpenter generates at runtime (eks-ray-platform_<hash>). Without this,
# the role deletion fails with DeleteConflict.
if aws iam get-role --role-name "${NODE_ROLE_NAME}" &>/dev/null; then
    ATTACHED_PROFILES=$(aws iam list-instance-profiles-for-role \
        --role-name "${NODE_ROLE_NAME}" \
        --query 'InstanceProfiles[].InstanceProfileName' \
        --output text 2>/dev/null || echo "")
    for IP in ${ATTACHED_PROFILES}; do
        aws iam remove-role-from-instance-profile \
            --instance-profile-name "${IP}" --role-name "${NODE_ROLE_NAME}" 2>/dev/null || true
        aws iam delete-instance-profile --instance-profile-name "${IP}"
        echo "  Deleted instance profile: ${IP}"
    done
fi

# Also delete the manually-created profile if it exists but wasn't attached (edge case).
if aws iam get-instance-profile --instance-profile-name "${INSTANCE_PROFILE_NAME}" &>/dev/null; then
    aws iam delete-instance-profile --instance-profile-name "${INSTANCE_PROFILE_NAME}" 2>/dev/null || true
    echo "  Deleted: ${INSTANCE_PROFILE_NAME}"
fi

if aws iam get-role --role-name "${NODE_ROLE_NAME}" &>/dev/null; then
    for POLICY_ARN in \
        arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy \
        arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy \
        arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly \
        arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore; do
        aws iam detach-role-policy --role-name "${NODE_ROLE_NAME}" --policy-arn "${POLICY_ARN}" 2>/dev/null || true
    done
    aws iam delete-role --role-name "${NODE_ROLE_NAME}"
    echo "  Deleted: ${NODE_ROLE_NAME}"
else
    echo "  Node role not found — skipping."
fi

POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"
if aws iam get-policy --policy-arn "${POLICY_ARN}" &>/dev/null; then
    for VERSION in $(aws iam list-policy-versions --policy-arn "${POLICY_ARN}" \
            --query 'Versions[?!IsDefaultVersion].VersionId' --output text); do
        aws iam delete-policy-version --policy-arn "${POLICY_ARN}" --version-id "${VERSION}"
    done
    aws iam delete-policy --policy-arn "${POLICY_ARN}"
    echo "  Deleted: ${POLICY_NAME}"
else
    echo "  Controller policy not found — skipping."
fi

echo ""
echo "── STEP 3: Destroy CDK stack (VPC) ─────────────────────────────────────"

# Delete stale ENIs before CDK destroy — VPC CNI and terminated Karpenter nodes
# leave ENIs in 'available' state that block subnet deletion (DELETE_FAILED).
VPC_ID=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" \
    --region "${REGION}" \
    --query "Stacks[0].Outputs[?OutputKey=='VpcId'].OutputValue" \
    --output text 2>/dev/null || echo "")
if [[ -n "${VPC_ID}" ]]; then
    STALE_ENIS=$(aws ec2 describe-network-interfaces \
        --region "${REGION}" \
        --filters "Name=vpc-id,Values=${VPC_ID}" "Name=status,Values=available" \
        --query 'NetworkInterfaces[].NetworkInterfaceId' \
        --output text 2>/dev/null || echo "")
    if [[ -n "${STALE_ENIS}" ]]; then
        echo "  Deleting stale ENIs in VPC ${VPC_ID}:"
        for ENI in ${STALE_ENIS}; do
            aws ec2 delete-network-interface --network-interface-id "${ENI}" --region "${REGION}"
            echo "    Deleted: ${ENI}"
        done
    else
        echo "  No stale ENIs found."
    fi

    # Delete the EKS cluster security group left behind after eksctl delete cluster.
    # CDK cannot delete it (CDK didn't create it) so it blocks VPC deletion.
    EKS_SGS=$(aws ec2 describe-security-groups \
        --region "${REGION}" \
        --filters "Name=vpc-id,Values=${VPC_ID}" \
                  "Name=group-name,Values=eks-cluster-sg-${CLUSTER_NAME}-*" \
        --query 'SecurityGroups[].GroupId' \
        --output text 2>/dev/null || echo "")
    if [[ -n "${EKS_SGS}" ]]; then
        echo "  Deleting EKS cluster security group(s):"
        for SG in ${EKS_SGS}; do
            aws ec2 delete-security-group --group-id "${SG}" --region "${REGION}"
            echo "    Deleted: ${SG}"
        done
    else
        echo "  No EKS cluster security groups found."
    fi
fi

cd "${REPO_ROOT}/infra"
source .venv/bin/activate
cdk destroy --force
deactivate

echo ""
echo "── STEP 4: ECR repositories ────────────────────────────────────────────"
REPOS=$(aws ecr describe-repositories --region "${REGION}" \
    --query "repositories[?starts_with(repositoryName,'ray-')].repositoryName" \
    --output text 2>/dev/null || echo "")
if [[ -z "${REPOS}" ]]; then
    echo "No ray-* ECR repositories found."
else
    echo "Found ray-* ECR repositories:"
    for repo in ${REPOS}; do echo "  ${repo}"; done
    echo ""
    read -r -p "Delete these ECR repositories? (y/N): " delete_ecr
    if [[ "${delete_ecr}" == "y" || "${delete_ecr}" == "Y" ]]; then
        for repo in ${REPOS}; do
            aws ecr delete-repository --repository-name "${repo}" --region "${REGION}" --force
            echo "  Deleted: ${repo}"
        done
    else
        echo "ECR repositories kept."
    fi
fi

echo ""
echo "── Final check ─────────────────────────────────────────────────────────"
CLUSTER_STATUS=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${REGION}" \
    --query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND")
CDK_STACK=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" \
    --region "${REGION}" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")
EKSCTL_STACK=$(aws cloudformation describe-stacks \
    --stack-name "eksctl-${CLUSTER_NAME}-cluster" \
    --region "${REGION}" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")

EC2_NODES=$(aws ec2 describe-instances --region "${REGION}" \
    --filters "Name=tag:aws:eks:cluster-name,Values=${CLUSTER_NAME}" "Name=instance-state-name,Values=running,pending,stopping" \
    --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null \
    | grep -v '^$' | grep -v '^None$' || true)

[[ "${CLUSTER_STATUS}" == "NOT_FOUND" ]] && echo "  ✅  EKS cluster deleted" || echo "  ❌  EKS cluster still exists (${CLUSTER_STATUS})"
[[ "${EKSCTL_STACK}" == "NOT_FOUND" ]] && echo "  ✅  eksctl CloudFormation stack deleted" || echo "  ❌  eksctl stack still exists (${EKSCTL_STACK})"
[[ "${CDK_STACK}" == "NOT_FOUND" ]] && echo "  ✅  CDK VPC stack deleted" || echo "  ❌  CDK stack still exists (${CDK_STACK})"
[[ -z "${EC2_NODES}" ]] && echo "  ✅  No EC2 nodes still running" || echo "  ❌  EC2 nodes still running: ${EC2_NODES}"

DESTROY_END=$(date +%s)
DESTROY_ELAPSED=$(( DESTROY_END - DESTROY_START ))
DESTROY_MIN=$(( DESTROY_ELAPSED / 60 ))
DESTROY_SEC=$(( DESTROY_ELAPSED % 60 ))

echo ""
echo "⏱  Started : ${DESTROY_START_LABEL}"
echo "⏱  Finished: $(date '+%H:%M:%S')"
echo "⏱  Elapsed : ${DESTROY_MIN}m ${DESTROY_SEC}s"
echo ""
