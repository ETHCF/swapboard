#!/usr/bin/env bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
RPC_URL="${RPC_URL:-http://localhost:18545}"

echo "=== E2E Setup ==="

# Check dependencies
command -v docker >/dev/null 2>&1 || { echo "docker required"; exit 1; }
command -v forge >/dev/null 2>&1 || { echo "forge required"; exit 1; }
command -v cast >/dev/null 2>&1 || { echo "cast required"; exit 1; }

# Start services
echo "Starting Docker services..."
cd "$SCRIPT_DIR"
docker compose up -d

# Wait for Graph Node
echo "Waiting for Graph Node..."
for i in {1..60}; do
  if curl -sf http://localhost:8130 >/dev/null 2>&1; then
    echo "Graph Node ready"
    break
  fi
  if [ $i -eq 60 ]; then
    echo "Graph Node failed to start"
    docker compose logs graph-node
    exit 1
  fi
  sleep 2
done

# Deploy contract
echo "Deploying contract..."
cd "$ROOT_DIR/contracts"

# Ensure full artifacts exist (stale/partial out/ can yield "does not contain bytecode")
forge build

DEPLOYER_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
DEPLOYER_ADDR="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"

# Deploy Swapboard
DEPLOY_OUTPUT=$(forge create src/Swapboard.sol:Swapboard \
  --rpc-url "$RPC_URL" \
  --private-key $DEPLOYER_KEY \
  --broadcast \
  --json)

CONTRACT_ADDR=$(echo "$DEPLOY_OUTPUT" | jq -r '.deployedTo')
DEPLOY_BLOCK=$(cast block-number --rpc-url "$RPC_URL")

echo "Contract deployed at: $CONTRACT_ADDR (block $DEPLOY_BLOCK)"

# Deploy mock tokens for testing
echo "Deploying test tokens..."
TOKENA_OUTPUT=$(forge create test/mocks/MockERC20.sol:MockERC20 \
  --rpc-url "$RPC_URL" \
  --private-key $DEPLOYER_KEY \
  --broadcast \
  --json \
  --constructor-args "Token A" "TKA" 18)
TOKENA_ADDR=$(echo "$TOKENA_OUTPUT" | jq -r '.deployedTo')

TOKENB_OUTPUT=$(forge create test/mocks/MockERC20.sol:MockERC20 \
  --rpc-url "$RPC_URL" \
  --private-key $DEPLOYER_KEY \
  --broadcast \
  --json \
  --constructor-args "Token B" "TKB" 6)
TOKENB_ADDR=$(echo "$TOKENB_OUTPUT" | jq -r '.deployedTo')

echo "TokenA: $TOKENA_ADDR"
echo "TokenB: $TOKENB_ADDR"

# Update subgraph manifest
# NOTE: this stack still exercises the v1 pipeline (v1 subgraph + v1 frontend).
# It needs its own pass onto subgraph/v2 once the v2 UI exists.
echo "Updating subgraph manifest..."
cd "$ROOT_DIR/subgraph/v1"

# Create e2e subgraph.yaml
cat > subgraph.e2e.yaml << EOF
specVersion: 0.0.5
schema:
  file: ./schema.graphql
dataSources:
  - kind: ethereum
    name: Swapboard
    network: mainnet
    source:
      address: "$CONTRACT_ADDR"
      abi: Swapboard
      startBlock: $DEPLOY_BLOCK
    mapping:
      kind: ethereum/events
      apiVersion: 0.0.7
      language: wasm/assemblyscript
      entities:
        - Order
        - Token
        - GlobalStats
        - PairStats
      abis:
        - name: Swapboard
          file: ./abis/Swapboard.json
        - name: ERC20
          file: ./abis/ERC20.json
      eventHandlers:
        - event: OrderCreated(indexed uint256,indexed address,address,uint256,address,uint256)
          handler: handleOrderCreated
        - event: OrderFilled(indexed uint256,indexed address)
          handler: handleOrderFilled
        - event: OrderCanceled(indexed uint256)
          handler: handleOrderCanceled
      file: ./src/mapping.ts
EOF

# Build subgraph
echo "Building subgraph..."
npx graph codegen subgraph.e2e.yaml
npx graph build subgraph.e2e.yaml

# Create subgraph on local node
echo "Creating subgraph on local node..."
curl -sf -X POST http://localhost:8120 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"subgraph_create","params":{"name":"swapboard"},"id":1}' || true

# Deploy subgraph
echo "Deploying subgraph..."
npx graph deploy --node http://localhost:8120 --ipfs http://localhost:5001 --version-label v1 swapboard subgraph.e2e.yaml

# Wait for indexing
echo "Waiting for subgraph to sync..."
for i in {1..30}; do
  SYNC_STATUS=$(curl -sf http://localhost:8130/graphql \
    -H "Content-Type: application/json" \
    -d '{"query":"{ indexingStatusForCurrentVersion(subgraphName: \"swapboard\") { synced health } }"}' \
    | jq -r '.data.indexingStatusForCurrentVersion.synced // "false"')

  if [ "$SYNC_STATUS" = "true" ]; then
    echo "Subgraph synced"
    break
  fi
  if [ $i -eq 30 ]; then
    echo "Subgraph failed to sync"
    exit 1
  fi
  sleep 2
done

# Write config for tests
cat > "$SCRIPT_DIR/.env.e2e" << EOF
RPC_URL=$RPC_URL
SUBGRAPH_URL=http://localhost:8100/subgraphs/name/swapboard
CONTRACT_ADDR=$CONTRACT_ADDR
ETH_ADDR=0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE
TOKENA_ADDR=$TOKENA_ADDR
TOKENB_ADDR=$TOKENB_ADDR
DEPLOYER_KEY=$DEPLOYER_KEY
DEPLOYER_ADDR=$DEPLOYER_ADDR
EOF

echo ""
echo "=== E2E Setup Complete ==="
echo "Contract: $CONTRACT_ADDR"
echo "Subgraph: http://localhost:8100/subgraphs/name/swapboard"
echo "Config: $SCRIPT_DIR/.env.e2e"
