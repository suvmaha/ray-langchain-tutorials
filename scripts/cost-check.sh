#!/usr/bin/env bash
# cost-check.sh — Read-only audit of billable AWS resources.
# Run after teardown to confirm zero spend, or anytime you're unsure.
#
# Usage: ./scripts/cost-check.sh [--region us-east-1]

set -euo pipefail

REGION="${AWS_DEFAULT_REGION:-us-east-1}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --region) REGION="$2"; shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

ISSUES=0

ok()    { echo "  ✅  $*"; }
warn()  { echo "  ⚠️   $*"; ISSUES=$((ISSUES + 1)); }
header(){ echo ""; echo "── $* ──────────────────────────────────────────────────────"; }

echo "AWS Cost Check — region: ${REGION}"
echo "$(date '+%Y-%m-%d %H:%M:%S')"

# ── EKS clusters ────────────────────────────────────────────────────────────
header "EKS clusters  (~\$0.10/hr each)"
CLUSTERS=$(aws eks list-clusters --region "${REGION}" --query "clusters" --output text 2>/dev/null || echo "")
if [[ -z "${CLUSTERS}" ]]; then
    ok "No EKS clusters"
else
    for C in ${CLUSTERS}; do warn "EKS cluster running: ${C}"; done
fi

# ── EC2 instances ────────────────────────────────────────────────────────────
header "EC2 instances  (per-instance rate)"
INSTANCES=$(aws ec2 describe-instances \
    --region "${REGION}" \
    --filters "Name=instance-state-name,Values=running,pending,stopping" \
    --query "Reservations[].Instances[].[InstanceId,InstanceType,Tags[?Key=='Name'].Value|[0]]" \
    --output text 2>/dev/null || echo "")
if [[ -z "${INSTANCES}" ]]; then
    ok "No running EC2 instances"
else
    while IFS=$'\t' read -r id type name; do
        warn "EC2 running: ${id}  ${type}  ${name:-<no name>}"
    done <<< "${INSTANCES}"
fi

# ── NAT gateways ─────────────────────────────────────────────────────────────
header "NAT gateways  (~\$1/day each)"
NATS=$(aws ec2 describe-nat-gateways \
    --region "${REGION}" \
    --filter "Name=state,Values=available,pending" \
    --query "NatGateways[].[NatGatewayId,VpcId]" \
    --output text 2>/dev/null || echo "")
if [[ -z "${NATS}" ]]; then
    ok "No active NAT gateways"
else
    while IFS=$'\t' read -r id vpc; do
        warn "NAT gateway active: ${id}  vpc=${vpc}"
    done <<< "${NATS}"
fi

# ── Load balancers ────────────────────────────────────────────────────────────
header "Load balancers  (~\$0.008/hr + data)"
LBS=$(aws elbv2 describe-load-balancers \
    --region "${REGION}" \
    --query "LoadBalancers[?State.Code!='failed'].[LoadBalancerName,Type,State.Code]" \
    --output text 2>/dev/null || echo "")
if [[ -z "${LBS}" ]]; then
    ok "No load balancers"
else
    while IFS=$'\t' read -r name type state; do
        warn "Load balancer: ${name}  type=${type}  state=${state}"
    done <<< "${LBS}"
fi

# ── Elastic IPs ───────────────────────────────────────────────────────────────
header "Elastic IPs  (\$0.005/hr when unassociated)"
EIPS=$(aws ec2 describe-addresses \
    --region "${REGION}" \
    --query "Addresses[?AssociationId==null].[AllocationId,PublicIp]" \
    --output text 2>/dev/null || echo "")
if [[ -z "${EIPS}" ]]; then
    ok "No unassociated Elastic IPs"
else
    while IFS=$'\t' read -r alloc ip; do
        warn "Unassociated EIP: ${ip}  (${alloc})"
    done <<< "${EIPS}"
fi

# ── EBS volumes ───────────────────────────────────────────────────────────────
header "EBS volumes  (\$0.08/GB-month when unattached)"
VOLS=$(aws ec2 describe-volumes \
    --region "${REGION}" \
    --filters "Name=status,Values=available" \
    --query "Volumes[].[VolumeId,Size,VolumeType]" \
    --output text 2>/dev/null || echo "")
if [[ -z "${VOLS}" ]]; then
    ok "No unattached EBS volumes"
else
    while IFS=$'\t' read -r id size type; do
        warn "Unattached EBS volume: ${id}  ${size}GB  ${type}"
    done <<< "${VOLS}"
fi

# ── CloudFormation stacks ─────────────────────────────────────────────────────
header "CloudFormation stacks  (indicates live resources)"
CF_STACKS=$(aws cloudformation list-stacks \
    --region "${REGION}" \
    --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE UPDATE_IN_PROGRESS DELETE_FAILED \
    --query "StackSummaries[].StackName" \
    --output text 2>/dev/null || echo "")
FOUND_CF=0
for S in ${CF_STACKS}; do
    # CDKToolkit is the CDK bootstrap stack — permanent, not a billable resource
    [[ "${S}" == "CDKToolkit" ]] && continue
    warn "CloudFormation stack: ${S}"
    FOUND_CF=1
done
[[ "${FOUND_CF}" -eq 0 ]] && ok "No active CloudFormation stacks"

# ── S3 buckets ────────────────────────────────────────────────────────────────
header "S3 buckets  (storage cost, usually small)"
BUCKETS=$(aws s3api list-buckets \
    --query "Buckets[].Name" \
    --output text 2>/dev/null || echo "")
if [[ -z "${BUCKETS}" ]]; then
    ok "No S3 buckets"
else
    for B in ${BUCKETS}; do
        COUNT=$(aws s3api list-objects-v2 --bucket "${B}" --region "${REGION}" \
            --max-items 1 --query "length(Contents)" --output text 2>/dev/null || echo "0")
        if [[ "${COUNT}" != "0" && "${COUNT}" != "None" ]]; then
            warn "Non-empty S3 bucket: ${B}"
        else
            ok "Empty S3 bucket: ${B}"
        fi
    done
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "─────────────────────────────────────────────────────────────────────────"
if [[ "${ISSUES}" -eq 0 ]]; then
    echo "✅  All clear — no billable resources found in ${REGION}"
else
    echo "⚠️   ${ISSUES} billable resource(s) found in ${REGION} — review above"
fi
echo ""
