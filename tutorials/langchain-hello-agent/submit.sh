#!/usr/bin/env bash
set -euo pipefail

TUTORIAL_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
    echo "ERROR: ANTHROPIC_API_KEY is not set."
    echo "  export ANTHROPIC_API_KEY=<your-key>"
    exit 1
fi

cd "${TUTORIAL_DIR}"
anyscale job submit \
    --cloud eks-ray-cloud \
    --config-file job.yaml \
    --env ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY}"
