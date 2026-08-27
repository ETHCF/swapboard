#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== E2E Teardown ==="

cd "$SCRIPT_DIR"

# Stop and remove containers
docker compose down -v --remove-orphans

# Clean up generated files
rm -f .env.e2e
rm -f ../subgraph/v1/subgraph.e2e.yaml

echo "=== E2E Teardown Complete ==="
