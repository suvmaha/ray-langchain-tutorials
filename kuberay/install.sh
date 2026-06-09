#!/usr/bin/env bash
# install.sh — Install KubeRay operator via Helm.
# Run from the repo root: ./kuberay/install.sh

set -euo pipefail

KUBERAY_VERSION="${KUBERAY_VERSION:-1.2.2}"

echo "── Installing KubeRay operator v${KUBERAY_VERSION} ────────────────────────────"
helm repo add kuberay https://ray-project.github.io/kuberay-helm/ 2>/dev/null || true
helm repo update kuberay

helm upgrade --install kuberay-operator kuberay/kuberay-operator \
    --namespace ray-system \
    --create-namespace \
    --version "${KUBERAY_VERSION}" \
    --wait

echo ""
kubectl get deployment kuberay-operator -n ray-system
echo ""
echo "  ✅  KubeRay operator v${KUBERAY_VERSION} installed in ray-system namespace."
