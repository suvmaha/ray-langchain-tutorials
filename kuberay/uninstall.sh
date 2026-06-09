#!/usr/bin/env bash
# uninstall.sh — Remove KubeRay operator and all Ray resources.
# Run from the repo root: ./kuberay/uninstall.sh

set -euo pipefail

echo "── Removing all RayJobs and RayClusters ────────────────────────────────"
kubectl delete rayjobs --all --all-namespaces 2>/dev/null || true
kubectl delete rayclusters --all --all-namespaces 2>/dev/null || true

echo ""
echo "── Uninstalling KubeRay operator ───────────────────────────────────────"
helm uninstall kuberay-operator -n ray-system 2>/dev/null || true
kubectl delete namespace ray-system --ignore-not-found

echo "  ✅  KubeRay operator removed."
