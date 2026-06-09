#!/usr/bin/env bash
set -euo pipefail

TUTORIAL_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
    echo "ERROR: ANTHROPIC_API_KEY is not set."
    echo "  export ANTHROPIC_API_KEY=<your-key>"
    exit 1
fi

cd "${TUTORIAL_DIR}"

# Secret — dry-run + apply so re-runs don't fail on "already exists"
kubectl create secret generic langchain-secrets \
    --from-literal=ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}" \
    --dry-run=client -o yaml | kubectl apply -f -

# ConfigMap — inject agent.py into the Ray pods
kubectl create configmap langchain-hello-agent-code \
    --from-file=agent.py=agent.py \
    --dry-run=client -o yaml | kubectl apply -f -

# Submit the RayJob
kubectl apply -f rayjob.yaml

echo ""
echo "RayJob submitted. Monitor with:"
echo "  kubectl get rayjob langchain-hello-agent -w"
echo "  kubectl logs -l ray.io/node-type=head -n default --follow"
