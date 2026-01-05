#!/bin/bash
set -e

echo "========================================="
echo "SWAPBOARD TEST SUITE"
echo "========================================="
echo ""

echo "1. Contract Unit Tests"
echo "-----------------------------------------"
cd contracts && forge test --summary
cd ..
echo ""

echo "2. Subgraph Build"
echo "-----------------------------------------"
cd subgraph && pnpm build
cd ..
echo ""

echo "3. E2E Tests (requires Anvil)"
echo "-----------------------------------------"
cd e2e && pnpm test
cd ..
echo ""

echo "========================================="
echo "ALL TESTS PASSED"
echo "========================================="
