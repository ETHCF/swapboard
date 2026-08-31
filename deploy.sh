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

SUBGRAPH_VERSION="${SUBGRAPH_VERSION:-v2}"
SUBGRAPH_DIR="$SCRIPT_DIR/subgraph/$SUBGRAPH_VERSION"
SUBGRAPH_YAML="$SUBGRAPH_DIR/subgraph.yaml"

if [[ ! -d "$SUBGRAPH_DIR" ]]; then
    error "No such subgraph: $SUBGRAPH_DIR (set SUBGRAPH_VERSION to v1 or v2)"
fi

log "Subgraph version: $SUBGRAPH_VERSION"

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

# The deployment coordinates live in lib.js, on VERSION_CAPS — not app.js.
FRONTEND_JS="$SCRIPT_DIR/frontend/lib.js"

# Rewrites one marker-anchored string literal in the frontend config.
#
# The frontend serves v1 and v2 side by side, so it holds a contract address and
# a subgraph URL per version. Each value carries a trailing `// deploy:<ver>:<key>`
# marker; this anchors on that marker so only the version being deployed is
# touched, and verifies the write landed. A silent no-op is exactly how the
# previous version of this script shipped deploys that looked green and changed
# nothing — so both the missing marker and the failed write are hard errors.
patch_frontend_config() {
    local marker=$1 value=$2

    grep -qF "// $marker" "$FRONTEND_JS" \
        || error "Marker '$marker' not found in $FRONTEND_JS"

    # Escape what sed treats as special in a replacement: a backslash, the `&`
    # backreference, and the `|` delimiter. Verification below greps for the
    # unescaped value, so a botched escape fails the run rather than corrupting
    # the config.
    local escaped=${value//\\/\\\\}
    escaped=${escaped//&/\\&}
    escaped=${escaped//|/\\|}

    sed -i.bak "s|\"[^\"]*\"\(,\{0,1\} *// $marker\)|\"$escaped\"\1|" "$FRONTEND_JS"
    rm -f "$FRONTEND_JS.bak"

    grep -F "\"$value\"" "$FRONTEND_JS" | grep -qF "// $marker" \
        || error "Failed to write $marker into $FRONTEND_JS"

    log "Updated $marker -> $value"
}

patch_frontend_config "deploy:$SUBGRAPH_VERSION:contract" "$CONTRACT_ADDRESS"

# ============================================================
# STEP 4: Deploy Subgraph
# ============================================================

# Goldsky subgraph to publish under, as <name>/<version>. v1 is already live at
# Swapboard/1.0.0; v2 gets its own name so the two index side by side.
if [[ -z "${GOLDSKY_SUBGRAPH:-}" ]]; then
    case "$SUBGRAPH_VERSION" in
        v1) GOLDSKY_SUBGRAPH="Swapboard/1.0.0" ;;
        v2) GOLDSKY_SUBGRAPH="swapboard-v2/2.0.0" ;;
        *)  error "Set GOLDSKY_SUBGRAPH explicitly for subgraph version $SUBGRAPH_VERSION" ;;
    esac
fi

if [[ "$SKIP_SUBGRAPH" != "true" ]]; then
    log "Step 4: Deploying subgraph to Goldsky as $GOLDSKY_SUBGRAPH..."

    # The Goldsky CLI reads GOLDSKY_API_KEY from the environment, so there is no
    # separate auth step.
    check_env "GOLDSKY_API_KEY"

    command -v goldsky > /dev/null 2>&1 \
        || error "goldsky CLI not found. Install it with: pnpm add -g @goldskycom/cli"

    cd "$SUBGRAPH_DIR"

    # Generate and build
    pnpm codegen
    pnpm build

    # Deploy
    SUBGRAPH_OUTPUT=$(goldsky subgraph deploy "$GOLDSKY_SUBGRAPH" --path . 2>&1) || {
        echo "$SUBGRAPH_OUTPUT"
        error "Subgraph deployment failed"
    }

    SUBGRAPH_URL=$(echo "$SUBGRAPH_OUTPUT" \
        | grep -oE "https://api\.goldsky\.com/api/public/project_[A-Za-z0-9]+/subgraphs/[^[:space:]]+" \
        | head -1)

    cd "$SCRIPT_DIR"

    if [[ -z "$SUBGRAPH_URL" ]]; then
        echo "$SUBGRAPH_OUTPUT"
        # Deliberately not falling back to a placeholder: writing one into the
        # frontend would replace a working URL with a broken one.
        warn "Could not extract subgraph URL from Goldsky output."
        warn "Find it in the Goldsky dashboard, then re-run with SKIP_SUBGRAPH=true SUBGRAPH_URL=<url>."
    else
        log "Subgraph deployed: $SUBGRAPH_URL"
        echo "SUBGRAPH_URL=$SUBGRAPH_URL" >> "$SCRIPT_DIR/.deploy.env"
    fi
else
    log "Step 4: Skipping subgraph deployment (SKIP_SUBGRAPH=true)"
fi

# Update frontend with subgraph URL. Left alone when this run produced no URL,
# so a failed extraction cannot clobber the value already in lib.js.
if [[ -n "${SUBGRAPH_URL:-}" ]]; then
    patch_frontend_config "deploy:$SUBGRAPH_VERSION:subgraph" "$SUBGRAPH_URL"
else
    warn "No SUBGRAPH_URL for $SUBGRAPH_VERSION; leaving frontend subgraph URL unchanged"
fi

# ============================================================
# STEP 5: Generate Build Hashes and Deploy Frontend to IPFS
# ============================================================

if [[ "$SKIP_FRONTEND" != "true" ]]; then
    log "Step 5: Building and deploying frontend to IPFS..."

    DIST_DIR="$SCRIPT_DIR/dist"
    rm -rf "$DIST_DIR"
    mkdir -p "$DIST_DIR"

    # Copy only production files
    PROD_FILES="index.html app.js lib.js style.css mock.js API.html manifest.json sw.js"
    for f in $PROD_FILES; do
        cp "$SCRIPT_DIR/frontend/$f" "$DIST_DIR/$f"
    done

    cd "$DIST_DIR"

    # Generate file hashes for verification
    log "Generating build hashes..."
    HASH_APPJS=$(sha256sum app.js | cut -d' ' -f1)
    HASH_LIBJS=$(sha256sum lib.js | cut -d' ' -f1)
    HASH_CSS=$(sha256sum style.css | cut -d' ' -f1)
    HASH_MOCK=$(sha256sum mock.js | cut -d' ' -f1)

    # Get git commit info
    COMMIT_FULL=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    COMMIT_HASH=$(echo "$COMMIT_FULL" | cut -c1-7)

    # Replace placeholders in index.html
    log "Injecting hashes into index.html..."
    sed -i.bak \
        -e "s/__HASH_APPJS__/${HASH_APPJS:0:16}.../" \
        -e "s/__HASH_LIBJS__/${HASH_LIBJS:0:16}.../" \
        -e "s/__HASH_CSS__/${HASH_CSS:0:16}.../" \
        -e "s/__HASH_MOCK__/${HASH_MOCK:0:16}.../" \
        -e "s/__COMMIT_FULL__/$COMMIT_FULL/" \
        -e "s/__COMMIT_HASH__/$COMMIT_HASH/" \
        index.html

    # Calculate index.html hash after other replacements
    HASH_HTML=$(sha256sum index.html | cut -d' ' -f1)
    sed -i.bak "s/__HASH_HTML__/${HASH_HTML:0:16}.../" index.html
    rm -f index.html.bak

    if command -v ipfs &> /dev/null; then
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
    else
        warn "IPFS not installed. Skipping IPFS upload."
        warn "Install IPFS and run: cd dist && ipfs add -r ."
        IPFS_CID="(not deployed)"
    fi

    cd "$SCRIPT_DIR"
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
echo "Subgraph:         $GOLDSKY_SUBGRAPH ($SUBGRAPH_VERSION)"
echo "Subgraph URL:     ${SUBGRAPH_URL:-(unchanged)}"
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
echo "  2. Wait for subgraph to sync (check the Goldsky dashboard)"
echo "     (frontend/lib.js was patched in place; run 'pnpm format' there before committing)"
echo "  3. Test frontend at IPFS gateway"
echo "  4. (Optional) Update ENS contenthash to ipfs://$IPFS_CID"
echo ""
