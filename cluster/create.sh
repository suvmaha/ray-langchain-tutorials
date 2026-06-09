#!/usr/bin/env bash
# create.sh — Deploy VPC with CDK, then create EKS cluster with self-managed Karpenter.
# Run from the repo root: ./cluster/create.sh
#
# Steps:
#   1.  CDK deploys VPC (2 AZs, 1 NAT gateway)
#   2.  Read CDK outputs (VPC ID, subnet IDs, AZs)
#   3.  Create Karpenter IAM policy + node role (prerequisites for eksctl)
#   4.  Generate cluster.yaml.template → cluster/cluster.yaml
#   5.  Create EKS cluster (eksctl: system node group + Karpenter IRSA role)
#   6.  Associate IAM OIDC provider (enables IRSA)
#   7.  Add Karpenter node role to EKS aws-auth (nodes can join the cluster)
#   8.  Tag subnets + cluster security group for Karpenter node discovery
#   9.  Install Karpenter via Helm
#  10.  Apply EC2NodeClass + Anyscale NodePool
#  11.  Install nginx ingress controller (required for Anyscale DNS registration)
#  12.  Optionally apply GPU NodePool (g6/L4 — for LLM tutorials)
#  13.  Verify
#
# Default:              ./cluster/create.sh
# With GPU NodePool:    INSTALL_GPU_NODEPOOL=true ./cluster/create.sh

set -euo pipefail

_SCRIPT="${BASH_SOURCE[0]}"
case "${_SCRIPT}" in
    /*)  ;;
    */*) _SCRIPT="${PWD}/${_SCRIPT}" ;;
    *)   _SCRIPT="$(command -v "${_SCRIPT}")" ;;
esac
REPO_ROOT="$(cd "$(dirname "${_SCRIPT}")/.." && pwd)"
STACK_NAME="EksRayStack"
KARPENTER_VERSION="${KARPENTER_VERSION:-1.3.3}"

# ── Cluster parameters (override via env vars) ─────────────────────────────

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --output text --query 'Account')
export AWS_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
export EKS_CLUSTER_NAME="eks-ray-platform"
export K8S_VERSION="${K8S_VERSION:-1.35}"
INSTALL_GPU_NODEPOOL="${INSTALL_GPU_NODEPOOL:-false}"

echo ""
echo "── Pre-flight: Check for leftover AWS resources ────────────────────────"
PREFLIGHT_FAIL=false

CLUSTER_STATUS=$(aws eks describe-cluster --name "${EKS_CLUSTER_NAME}" --region "${AWS_REGION}" \
    --query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND")
CDK_STACK_STATUS=$(aws cloudformation describe-stacks --stack-name "${STACK_NAME}" \
    --region "${AWS_REGION}" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "NOT_FOUND")

if [[ "${CLUSTER_STATUS}" != "NOT_FOUND" ]]; then
    echo "  ❌  EKS cluster already exists (${CLUSTER_STATUS}) — run ./cluster/destroy.sh first"
    PREFLIGHT_FAIL=true
else
    echo "  ✅  No existing EKS cluster"
fi

if [[ "${CDK_STACK_STATUS}" != "NOT_FOUND" ]]; then
    echo "  ❌  CDK stack already exists (${CDK_STACK_STATUS}) — run ./cluster/destroy.sh first"
    PREFLIGHT_FAIL=true
else
    echo "  ✅  No existing CDK stack"
fi

if [[ "${PREFLIGHT_FAIL}" == "true" ]]; then
    echo ""
    echo "Pre-flight failed. Aborting to avoid partial state."
    exit 1
fi
echo ""

echo "── STEP 1: Deploy VPC with CDK ─────────────────────────────────────────"
cd "${REPO_ROOT}/infra"
python3 -m venv .venv 2>/dev/null || true
source .venv/bin/activate
pip install -q -r requirements.txt
cdk deploy --require-approval never
deactivate

echo ""
echo "── STEP 2: Read CDK outputs ────────────────────────────────────────────"

get_output() {
    aws cloudformation describe-stacks \
        --stack-name "${STACK_NAME}" \
        --region "${AWS_REGION}" \
        --query "Stacks[0].Outputs[?OutputKey=='${1}'].OutputValue" \
        --output text
}

export VPC_ID=$(get_output "VpcId")
PRIVATE_SUBNETS=$(get_output "PrivateSubnetIds")
PUBLIC_SUBNETS=$(get_output "PublicSubnetIds")

export PRIVATE_SUBNET_1=$(echo "${PRIVATE_SUBNETS}" | cut -d',' -f1)
export PRIVATE_SUBNET_2=$(echo "${PRIVATE_SUBNETS}" | cut -d',' -f2)
export PUBLIC_SUBNET_1=$(echo "${PUBLIC_SUBNETS}" | cut -d',' -f1)
export PUBLIC_SUBNET_2=$(echo "${PUBLIC_SUBNETS}" | cut -d',' -f2)

export AZ_1=$(aws ec2 describe-subnets --subnet-ids "${PRIVATE_SUBNET_1}" --region "${AWS_REGION}" \
    --query "Subnets[0].AvailabilityZone" --output text)
export AZ_2=$(aws ec2 describe-subnets --subnet-ids "${PRIVATE_SUBNET_2}" --region "${AWS_REGION}" \
    --query "Subnets[0].AvailabilityZone" --output text)

echo ""
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║            EKS Ray Platform — Architecture Summary                  ║"
echo "╠══════════════════════════════════════════════════════════════════════╣"
printf "║  Cluster name   : %-50s║\n" "${EKS_CLUSTER_NAME}"
printf "║  AWS account    : %-50s║\n" "${AWS_ACCOUNT_ID}"
printf "║  Region         : %-50s║\n" "${AWS_REGION}"
printf "║  Kubernetes     : %-50s║\n" "${K8S_VERSION}"
echo "╠══════════════════════════════════════════════════════════════════════╣"
printf "║  VPC            : %-50s║\n" "${VPC_ID}"
printf "║  Private subnet : %-50s║\n" "${PRIVATE_SUBNET_1} (${AZ_1})"
printf "║  Private subnet : %-50s║\n" "${PRIVATE_SUBNET_2} (${AZ_2})"
printf "║  Public subnet  : %-50s║\n" "${PUBLIC_SUBNET_1} (${AZ_1})"
printf "║  Public subnet  : %-50s║\n" "${PUBLIC_SUBNET_2} (${AZ_2})"
echo "╠══════════════════════════════════════════════════════════════════════╣"
printf "║  Node mode      : %-50s║\n" "Self-managed Karpenter ${KARPENTER_VERSION}"
printf "║  System nodes   : %-50s║\n" "2x m5.large (fixed)"
printf "║  Workload nodes : %-50s║\n" "Karpenter on-demand (scale to zero)"
printf "║  GPU NodePool   : %-50s║\n" "${INSTALL_GPU_NODEPOOL} (set INSTALL_GPU_NODEPOOL=true for LLM jobs)"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""

read -r -p "Proceed with cluster creation? (y/n): " confirm
if [[ "${confirm}" != "y" ]]; then
    echo "Aborted. VPC remains deployed."
    echo "Run 'cdk destroy' in infra/ to remove it."
    exit 0
fi
CREATE_START=$(date +%s)
CREATE_START_LABEL=$(date '+%H:%M:%S')

echo ""
echo "── STEP 3: Create Karpenter IAM policy + node role ─────────────────────"
# These must exist before eksctl runs — the IRSA service account in cluster.yaml.template
# references KarpenterControllerPolicy-${EKS_CLUSTER_NAME}.

POLICY_NAME="KarpenterControllerPolicy-${EKS_CLUSTER_NAME}"
NODE_ROLE_NAME="KarpenterNodeRole-${EKS_CLUSTER_NAME}"
INSTANCE_PROFILE_NAME="KarpenterNodeInstanceProfile-${EKS_CLUSTER_NAME}"

POLICY_DOC=$(envsubst < "${REPO_ROOT}/cluster/karpenter-iam-policy.json.template")
if aws iam get-policy --policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}" &>/dev/null; then
    echo "  IAM policy ${POLICY_NAME} already exists — skipping."
else
    aws iam create-policy \
        --policy-name "${POLICY_NAME}" \
        --policy-document "${POLICY_DOC}" \
        --output text --query 'Policy.Arn'
    echo "  Created: ${POLICY_NAME}"
fi

NODE_TRUST='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
if aws iam get-role --role-name "${NODE_ROLE_NAME}" &>/dev/null; then
    echo "  IAM role ${NODE_ROLE_NAME} already exists — skipping."
else
    aws iam create-role \
        --role-name "${NODE_ROLE_NAME}" \
        --assume-role-policy-document "${NODE_TRUST}" \
        --output text --query 'Role.Arn'
    aws iam attach-role-policy --role-name "${NODE_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy
    aws iam attach-role-policy --role-name "${NODE_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy
    aws iam attach-role-policy --role-name "${NODE_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly
    aws iam attach-role-policy --role-name "${NODE_ROLE_NAME}" \
        --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
    echo "  Created: ${NODE_ROLE_NAME}"
fi

if aws iam get-instance-profile --instance-profile-name "${INSTANCE_PROFILE_NAME}" &>/dev/null; then
    echo "  Instance profile ${INSTANCE_PROFILE_NAME} already exists — skipping."
else
    aws iam create-instance-profile --instance-profile-name "${INSTANCE_PROFILE_NAME}"
    aws iam add-role-to-instance-profile \
        --instance-profile-name "${INSTANCE_PROFILE_NAME}" \
        --role-name "${NODE_ROLE_NAME}"
    echo "  Created: ${INSTANCE_PROFILE_NAME}"
fi

echo ""
echo "── STEP 4: Generate eksctl cluster config ──────────────────────────────"
envsubst < "${REPO_ROOT}/cluster/cluster.yaml.template" > "${REPO_ROOT}/cluster/cluster.yaml"
echo "Written: cluster/cluster.yaml"

echo ""
echo "── STEP 5: Create EKS cluster with eksctl ──────────────────────────────"
eksctl create cluster -f "${REPO_ROOT}/cluster/cluster.yaml"

echo ""
echo "── STEP 6: Associate IAM OIDC provider ─────────────────────────────────"
eksctl utils associate-iam-oidc-provider \
    --cluster "${EKS_CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --approve
echo "OIDC provider associated — IRSA enabled."

echo ""
echo "── STEP 7: Add Karpenter node role to EKS auth ─────────────────────────"
eksctl create iamidentitymapping \
    --cluster "${EKS_CLUSTER_NAME}" \
    --region "${AWS_REGION}" \
    --arn "arn:aws:iam::${AWS_ACCOUNT_ID}:role/${NODE_ROLE_NAME}" \
    --username "system:node:{{EC2PrivateDNSName}}" \
    --group system:bootstrappers \
    --group system:nodes
echo "Karpenter node role added to aws-auth."

echo ""
echo "── STEP 8: Tag subnets + cluster SG for Karpenter discovery ────────────"
# EC2NodeClass discovers subnets and security groups by this tag at runtime.

for SUBNET_ID in "${PRIVATE_SUBNET_1}" "${PRIVATE_SUBNET_2}"; do
    aws ec2 create-tags \
        --resources "${SUBNET_ID}" \
        --tags "Key=karpenter.sh/discovery,Value=${EKS_CLUSTER_NAME}" \
        --region "${AWS_REGION}"
    echo "  Tagged subnet: ${SUBNET_ID}"
done

CLUSTER_SG=$(aws eks describe-cluster --name "${EKS_CLUSTER_NAME}" --region "${AWS_REGION}" \
    --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)
aws ec2 create-tags \
    --resources "${CLUSTER_SG}" \
    --tags "Key=karpenter.sh/discovery,Value=${EKS_CLUSTER_NAME}" \
    --region "${AWS_REGION}"
echo "  Tagged cluster SG: ${CLUSTER_SG}"

echo ""
echo "── STEP 9: Install Karpenter via Helm ──────────────────────────────────"

ECR_PASSWORD=$(aws ecr-public get-login-password --region us-east-1)
echo "${ECR_PASSWORD}" | docker login --username AWS --password-stdin public.ecr.aws
echo "${ECR_PASSWORD}" | helm registry login --username AWS --password-stdin public.ecr.aws
echo "Authenticated to public ECR."

CLUSTER_ENDPOINT=$(aws eks describe-cluster --name "${EKS_CLUSTER_NAME}" \
    --region "${AWS_REGION}" --query 'cluster.endpoint' --output text)
KARPENTER_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${EKS_CLUSTER_NAME}-karpenter"

helm upgrade --install karpenter \
    oci://public.ecr.aws/karpenter/karpenter \
    --version "${KARPENTER_VERSION}" \
    --namespace karpenter --create-namespace \
    --set "settings.clusterName=${EKS_CLUSTER_NAME}" \
    --set "settings.clusterEndpoint=${CLUSTER_ENDPOINT}" \
    --set "replicas=1" \
    --set "controller.resources.requests.cpu=200m" \
    --set "controller.resources.requests.memory=512Mi" \
    --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${KARPENTER_ROLE_ARN}" \
    --set "tolerations[0].key=CriticalAddonsOnly" \
    --set "tolerations[0].operator=Exists" \
    --set "tolerations[0].effect=NoSchedule" \
    --wait

echo "Karpenter ${KARPENTER_VERSION} installed."

echo ""
echo "── STEP 10: Apply EC2NodeClass + Anyscale NodePool ─────────────────────"
envsubst < "${REPO_ROOT}/cluster/karpenter-nodepool.yaml.template" | kubectl apply -f -
echo "EC2NodeClass and Anyscale NodePool applied."

echo ""
echo "── STEP 11: Install nginx ingress controller ───────────────────────────"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
helm repo update ingress-nginx
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    --namespace ingress-nginx --create-namespace \
    --set controller.replicaCount=1 \
    --set controller.config.allow-snippet-annotations=true \
    --set controller.config.annotations-risk-level=Critical \
    --wait
echo "nginx ingress controller installed — Anyscale can register DNS for Ray head nodes."

echo ""
echo "── STEP 12: Apply GPU NodePool + NVIDIA device plugin (optional) ───────"
if [[ "${INSTALL_GPU_NODEPOOL}" == "true" ]]; then
    kubectl apply -f "${REPO_ROOT}/cluster/gpu-nodepool.yaml"
    echo "GPU NodePool (g6/L4) applied — Karpenter will provision nodes on demand."

    kubectl apply -f "${REPO_ROOT}/cluster/nvidia-device-plugin.yaml"
    echo "NVIDIA device plugin installed — exposes nvidia.com/gpu resource on GPU nodes."
else
    echo "Skipped (INSTALL_GPU_NODEPOOL=false)."
    echo "For LLM tutorials: INSTALL_GPU_NODEPOOL=true ./cluster/create.sh"
fi

echo ""
echo "── STEP 13: Verify ─────────────────────────────────────────────────────"
kubectl get nodes
echo ""
CREATE_END=$(date +%s)
CREATE_ELAPSED=$(( CREATE_END - CREATE_START ))
CREATE_MIN=$(( CREATE_ELAPSED / 60 ))
CREATE_SEC=$(( CREATE_ELAPSED % 60 ))

echo "EKS cluster ${EKS_CLUSTER_NAME} is ready."
echo ""
echo "⏱  Started : ${CREATE_START_LABEL}"
echo "⏱  Finished: $(date '+%H:%M:%S')"
echo "⏱  Elapsed : ${CREATE_MIN}m ${CREATE_SEC}s"
echo ""
echo "Next steps:"
echo "  ./anyscale/setup.sh     # wire Anyscale to this cluster"
