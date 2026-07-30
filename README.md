# Swapboard

[![CI](https://github.com/ETHCF/swapboard/actions/workflows/ci.yml/badge.svg)](https://github.com/ETHCF/swapboard/actions/workflows/ci.yml)

Trustless OTC bulletin board for ERC20 token swaps on Ethereum.

No admin. No fees. No upgrades. No keys. No backend.

## Architecture

```
contracts/     Solidity smart contract (Foundry)
subgraph/      The Graph indexer
frontend/      Static HTML/CSS/JS
e2e/           Full stack integration tests
docs/          API documentation
```

## Quick Start

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Node.js](https://nodejs.org/) v22+
- [pnpm](https://pnpm.io/)
- [Docker](https://www.docker.com/) (required for subgraph and e2e tests)

### Build

```bash
make install
make build
```

### Lint

```bash
make lint
```

### Test

```bash
# Default: lint + contract + subgraph + frontend tests
./test.sh

# Fast: lint + contract + frontend unit tests only (no Docker)
./test.sh --fast

# Full E2E: includes Docker stack with Graph Node
./test.sh --e2e

# All tests including full E2E
./test.sh --all

# Make targets
make test            # contract + subgraph + e2e package tests
make test-contracts  # Foundry tests only
```

### E2E Test Stack

The full E2E tests spin up:

- Anvil (local Ethereum node)
- PostgreSQL (Graph Node storage)
- IPFS (subgraph deployment)
- Graph Node (indexer)

Then execute real transactions, wait for indexing, and verify the frontend displays correct data from the subgraph.

```bash
# Manual control
cd e2e
./setup.sh    # Start stack, deploy contract + subgraph
node e2e.test.js  # Run tests
./teardown.sh # Stop stack
```

### Deploy

Automated deployment script handles contract, subgraph, and frontend:

```bash
# 1. Configure environment
cp .env.example .env
# Edit .env with your private key, RPC URLs, and Graph auth token

# 2. Deploy everything to Sepolia (testnet)
./deploy.sh sepolia

# Or deploy to mainnet
./deploy.sh mainnet
```

The script will:

1. Deploy the contract and verify on Etherscan
2. Update subgraph config with contract address and start block
3. Build and deploy subgraph to The Graph Studio
4. Update frontend config with contract address and subgraph URL
5. Upload frontend to IPFS (if ipfs CLI available)
6. Print summary with all addresses and URLs

**Partial deployments:**

```bash
# Skip steps if already done
SKIP_CONTRACT=true ./deploy.sh sepolia    # Reuse existing contract
SKIP_SUBGRAPH=true ./deploy.sh sepolia    # Skip subgraph deploy
SKIP_FRONTEND=true ./deploy.sh sepolia    # Skip IPFS upload
```

**Manual deployment:**

See `deploy.sh` for the individual commands if you prefer manual control.

**ENS contenthash (optional):**

After IPFS deployment, update ENS contenthash via the ENS manager UI to `ipfs://<CID>`.

## Contract

The Swapboard contract allows:

- **createOrder**: Deposit tokenA, specify tokenB amount wanted
- **fillOrder**: Pay tokenB, receive tokenA
- **cancelOrder**: Maker reclaims tokenA

All operations are atomic. No partial fills. No admin functions.

## Security

- Reentrancy protection via OpenZeppelin
- Fee-on-transfer token detection for tokenA
- SafeERC20 for all transfers
- No proxy, no upgrades, no owner

## Author

Built by [Zak Cole](https://x.com/0xzak) at [Number Group](https://numbergroup.xyz) for the [Ethereum Community Foundation](https://ethcf.org).

## License

AGPL-3.0-only
