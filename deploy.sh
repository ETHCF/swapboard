#!/usr/bin/env bash
set -euo pipefail

# Swapboard Deployment Script
# Deploys contract, subgraph, and frontend in sequence

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[DEPLOY]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# Load environment
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
else
    error "Missing .env file. Copy .env.example and fill in values."
fi

# Validate required vars
check_env() {
    local var_name=$1
    if [[ -z "${!var_name:-}" ]]; then
        error "Missing required environment variable: $var_name"
    fi
}

# Parse arguments
NETWORK="${1:-sepolia}"
SKIP_CONTRACT="${SKIP_CONTRACT:-false}"
SKIP_SUBGRAPH="${SKIP_SUBGRAPH:-false}"
SKIP_FRONTEND="${SKIP_FRONTEND:-false}"

log "Deployment target: $NETWORK"

# ============================================================
# STEP 1: Deploy Contract
# ============================================================

if [[ "$SKIP_CONTRACT" != "true" ]]; then
    log "Step 1: Deploying contract..."

    # Private key loaded from Foundry keystore via --account flag

    if [[ "$NETWORK" == "mainnet" ]]; then
        check_env "MAINNET_RPC_URL"
        RPC_URL="$MAINNET_RPC_URL"
    elif [[ "$NETWORK" == "sepolia" ]]; then
        check_env "SEPOLIA_RPC_URL"
        RPC_URL="$SEPOLIA_RPC_URL"
    else
        error "Unknown network: $NETWORK. Use 'mainnet' or 'sepolia'."
    fi

    cd "$SCRIPT_DIR/contracts"

    # Deploy and capture output
    DEPLOY_OUTPUT=$(forge script script/Deploy.s.sol \
        --rpc-url "$RPC_URL" \
        --account deployer \
        --broadcast \
        --verify 2>&1) || {
        echo "$DEPLOY_OUTPUT"
        error "Contract deployment failed"
    }

    # Extract contract address from output
    CONTRACT_ADDRESS=$(echo "$DEPLOY_OUTPUT" | grep -oE "Swapboard deployed at: 0x[a-fA-F0-9]{40}" | grep -oE "0x[a-fA-F0-9]{40}" | head -1)

    if [[ -z "$CONTRACT_ADDRESS" ]]; then
        echo "$DEPLOY_OUTPUT"
        error "Could not extract contract address from deployment output"
    fi

    # Get deployment block number from broadcast file
    BROADCAST_FILE=$(ls -t broadcast/Deploy.s.sol/*/run-latest.json 2>/dev/null | head -1)
    if [[ -f "$BROADCAST_FILE" ]]; then
        START_BLOCK=$(jq -r '.receipts[0].blockNumber' "$BROADCAST_FILE" | xargs printf "%d")
    else
        warn "Could not find broadcast file, using block 0"
        START_BLOCK=0
    fi

    cd "$SCRIPT_DIR"

    log "Contract deployed at: $CONTRACT_ADDRESS"
    log "Start block: $START_BLOCK"

    # Save for later steps
    echo "CONTRACT_ADDRESS=$CONTRACT_ADDRESS" > "$SCRIPT_DIR/.deploy.env"
    echo "START_BLOCK=$START_BLOCK" >> "$SCRIPT_DIR/.deploy.env"
else
    log "Step 1: Skipping contract deployment (SKIP_CONTRACT=true)"
    if [[ -f "$SCRIPT_DIR/.deploy.env" ]]; then
        source "$SCRIPT_DIR/.deploy.env"
    else
        check_env "CONTRACT_ADDRESS"
        check_env "START_BLOCK"
    fi
fi

log "Using CONTRACT_ADDRESS=$CONTRACT_ADDRESS"
log "Using START_BLOCK=$START_BLOCK"

# ============================================================
# STEP 2: Update Subgraph Config
# ============================================================

log "Step 2: Updating subgraph configuration..."

SUBGRAPH_YAML="$SCRIPT_DIR/subgraph/subgraph.yaml"

# Update contract address
sed -i.bak "s/address: \"0x[a-fA-F0-9]\{40\}\"/address: \"$CONTRACT_ADDRESS\"/" "$SUBGRAPH_YAML"

# Update start block
sed -i.bak "s/startBlock: [0-9]*/startBlock: $START_BLOCK/" "$SUBGRAPH_YAML"

rm -f "$SUBGRAPH_YAML.bak"

log "Updated subgraph.yaml with address and startBlock"

# ============================================================
# STEP 3: Update Frontend Config
# ============================================================

log "Step 3: Updating frontend configuration..."

FRONTEND_JS="$SCRIPT_DIR/frontend/app.js"

# Update contract address
sed -i.bak "s/CONTRACT_ADDRESS: \"0x[a-fA-F0-9]\{40\}\"/CONTRACT_ADDRESS: \"$CONTRACT_ADDRESS\"/" "$FRONTEND_JS"

rm -f "$FRONTEND_JS.bak"

log "Updated app.js with contract address"

# ============================================================
# STEP 4: Deploy Subgraph
# ============================================================

if [[ "$SKIP_SUBGRAPH" != "true" ]]; then
    log "Step 4: Deploying subgraph..."

    check_env "GRAPH_AUTH_TOKEN"

    cd "$SCRIPT_DIR/subgraph"

    # Authenticate
    graph auth --studio "$GRAPH_AUTH_TOKEN"

    # Generate and build
    pnpm codegen
    pnpm build

    # Deploy
    SUBGRAPH_OUTPUT=$(pnpm deploy 2>&1) || {
        echo "$SUBGRAPH_OUTPUT"
        error "Subgraph deployment failed"
    }

    # Extract subgraph URL - format varies, try common patterns
    SUBGRAPH_URL=$(echo "$SUBGRAPH_OUTPUT" | grep -oE "https://api\.(studio\.)?thegraph\.com/query/[^[:space:]]+" | head -1)

    if [[ -z "$SUBGRAPH_URL" ]]; then
        warn "Could not extract subgraph URL from output. Check The Graph Studio for the URL."
        SUBGRAPH_URL="https://api.studio.thegraph.com/query/YOUR_ID/swapboard/version/latest"
    fi

    cd "$SCRIPT_DIR"

    log "Subgraph deployed: $SUBGRAPH_URL"
    echo "SUBGRAPH_URL=$SUBGRAPH_URL" >> "$SCRIPT_DIR/.deploy.env"
else
    log "Step 4: Skipping subgraph deployment (SKIP_SUBGRAPH=true)"
    SUBGRAPH_URL="${SUBGRAPH_URL:-https://api.studio.thegraph.com/query/YOUR_ID/swapboard/version/latest}"
fi

# Update frontend with subgraph URL
sed -i.bak "s|SUBGRAPH_URL: \"[^\"]*\"|SUBGRAPH_URL: \"$SUBGRAPH_URL\"|" "$FRONTEND_JS"
rm -f "$FRONTEND_JS.bak"

log "Updated app.js with subgraph URL"

# ============================================================
# STEP 5: Deploy Frontend to IPFS
# ============================================================

if [[ "$SKIP_FRONTEND" != "true" ]]; then
    log "Step 5: Deploying frontend to IPFS..."

    if command -v ipfs &> /dev/null; then
        cd "$SCRIPT_DIR/frontend"

        # Add to IPFS
        IPFS_OUTPUT=$(ipfs add -r -Q .)
        IPFS_CID="$IPFS_OUTPUT"

        log "Frontend uploaded to IPFS: $IPFS_CID"
        log "Gateway URL: https://ipfs.io/ipfs/$IPFS_CID"

        # Pin if using remote pinning service
        if ipfs pin remote service ls 2>/dev/null | grep -q .; then
            log "Pinning to remote service..."
            ipfs pin remote add --service=pinata "$IPFS_CID" 2>/dev/null || warn "Remote pinning failed, content is local only"
        fi

        echo "IPFS_CID=$IPFS_CID" >> "$SCRIPT_DIR/.deploy.env"

        cd "$SCRIPT_DIR"
    else
        warn "IPFS not installed. Skipping frontend deployment."
        warn "Install IPFS and run: cd frontend && ipfs add -r ."
        IPFS_CID="(not deployed)"
    fi
else
    log "Step 5: Skipping frontend deployment (SKIP_FRONTEND=true)"
    IPFS_CID="${IPFS_CID:-(skipped)}"
fi

# ============================================================
# Summary
# ============================================================

echo ""
echo "=============================================="
echo -e "${GREEN}DEPLOYMENT COMPLETE${NC}"
echo "=============================================="
echo ""
echo "Network:          $NETWORK"
echo "Contract:         $CONTRACT_ADDRESS"
echo "Start Block:      $START_BLOCK"
echo "Subgraph:         $SUBGRAPH_URL"
echo "IPFS CID:         $IPFS_CID"
echo ""
echo "Deployment state saved to .deploy.env"
echo ""

if [[ "$IPFS_CID" != "(not deployed)" && "$IPFS_CID" != "(skipped)" ]]; then
    echo "Frontend accessible at:"
    echo "  https://ipfs.io/ipfs/$IPFS_CID"
    echo "  https://cloudflare-ipfs.com/ipfs/$IPFS_CID"
    echo "  https://$IPFS_CID.ipfs.dweb.link"
    echo ""
fi

echo "Next steps:"
echo "  1. Verify contract on Etherscan (if not auto-verified)"
echo "  2. Wait for subgraph to sync (check The Graph Studio)"
echo "  3. Test frontend at IPFS gateway"
echo "  4. (Optional) Update ENS contenthash to ipfs://$IPFS_CID"
echo ""
