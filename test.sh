#!/usr/bin/env bash
set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

show_help() {
  echo "Usage: ./test.sh [options]"
  echo ""
  echo "Options:"
  echo "  --all       Run all tests including full e2e (requires Docker)"
  echo "  --e2e       Run only full e2e tests (requires Docker)"
  echo "  --fast      Run contract + frontend unit tests only (no Docker)"
  echo "  --help      Show this help"
  echo ""
  echo "Default: Run contract, subgraph, frontend unit, and frontend e2e tests"
}

run_contract_tests() {
  echo "1. Contract Tests (Foundry)"
  echo "-----------------------------------------"
  cd "$ROOT_DIR/contracts" && forge test --summary
  cd "$ROOT_DIR"
  echo ""
}

run_subgraph_tests() {
  echo "2. Subgraph Tests (Matchstick)"
  echo "-----------------------------------------"
  cd "$ROOT_DIR/subgraph"
  pnpm install --silent
  pnpm build
  if docker info > /dev/null 2>&1; then
    pnpm test
  else
    echo "ERROR: Docker required for subgraph tests"
    exit 1
  fi
  cd "$ROOT_DIR"
  echo ""
}

run_frontend_unit_tests() {
  echo "3. Frontend Unit Tests (Jest)"
  echo "-----------------------------------------"
  cd "$ROOT_DIR/frontend"
  pnpm install --silent
  pnpm run test:unit
  cd "$ROOT_DIR"
  echo ""
}

run_frontend_e2e_tests() {
  echo "4. Frontend E2E Tests (Puppeteer)"
  echo "-----------------------------------------"
  cd "$ROOT_DIR/frontend" && node test.js
  cd "$ROOT_DIR"
  echo ""
}

run_full_e2e_tests() {
  echo "5. Full E2E Tests (Docker Stack)"
  echo "-----------------------------------------"
  cd "$ROOT_DIR/e2e"

  if ! docker info > /dev/null 2>&1; then
    echo "ERROR: Docker required for e2e tests"
    exit 1
  fi

  pnpm install --silent
  pnpm run e2e
  cd "$ROOT_DIR"
  echo ""
}

# Parse arguments
case "${1:-}" in
  --help|-h)
    show_help
    exit 0
    ;;
  --e2e)
    echo "========================================="
    echo "SWAPBOARD E2E TESTS"
    echo "========================================="
    echo ""
    run_full_e2e_tests
    ;;
  --fast)
    echo "========================================="
    echo "SWAPBOARD FAST TESTS"
    echo "========================================="
    echo ""
    run_contract_tests
    run_frontend_unit_tests
    ;;
  --all)
    echo "========================================="
    echo "SWAPBOARD FULL TEST SUITE"
    echo "========================================="
    echo ""
    run_contract_tests
    run_subgraph_tests
    run_frontend_unit_tests
    run_frontend_e2e_tests
    run_full_e2e_tests
    ;;
  *)
    echo "========================================="
    echo "SWAPBOARD TEST SUITE"
    echo "========================================="
    echo ""
    run_contract_tests
    run_subgraph_tests
    run_frontend_unit_tests
    run_frontend_e2e_tests
    ;;
esac

echo "========================================="
echo "ALL TESTS PASSED"
echo "========================================="
