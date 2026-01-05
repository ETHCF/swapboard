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
- [Node.js](https://nodejs.org/) v20+
- [pnpm](https://pnpm.io/)
- [Docker](https://www.docker.com/) (required for subgraph and e2e tests)

### Build

```bash
# Contracts
cd contracts && forge build

# Subgraph
cd subgraph && pnpm install && pnpm build

# Frontend
cd frontend && npm install puppeteer

# E2E (optional)
cd e2e && npm install
```

### Test

```bash
# Default: contract + subgraph + frontend tests
./test.sh

# Fast: contract tests only (no Docker)
./test.sh --fast

# Full E2E: includes Docker stack with Graph Node
./test.sh --e2e

# All tests including full E2E
./test.sh --all

# Individual test suites
cd contracts && forge test -vvv           # 84 tests
cd subgraph && pnpm test                  # 22 tests (Docker)
cd frontend && node test.js               # 25 tests
cd e2e && npm run e2e                     # Full stack (Docker)
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

1. Configure environment:
```bash
cd contracts
cp .env.example .env
# Edit .env with your values
```

2. Deploy contract:
```bash
source .env
forge script script/Deploy.s.sol \
  --rpc-url $MAINNET_RPC_URL \
  --broadcast \
  --verify
```

3. Update addresses:
   - `frontend/app.js` - CONFIG.CONTRACT_ADDRESS
   - `subgraph/subgraph.yaml` - source.address and startBlock

4. Deploy subgraph:
```bash
cd subgraph
pnpm deploy
```

5. Update subgraph URL:
   - `frontend/app.js` - CONFIG.SUBGRAPH_URL

6. Deploy frontend to IPFS:
```bash
ipfs add -r frontend/
ipfs pin add <CID>
```

7. Update ENS contenthash (optional):
```bash
# Set contenthash to ipfs://<CID> via ENS manager
```

## Contract

The OTCBoard contract allows:

- **createOrder**: Deposit tokenA, specify tokenB amount wanted
- **fillOrder**: Pay tokenB, receive tokenA
- **cancelOrder**: Maker reclaims tokenA

All operations are atomic. No partial fills. No admin functions.

## Security

- Reentrancy protection via OpenZeppelin
- Fee-on-transfer token detection for tokenA
- SafeERC20 for all transfers
- No proxy, no upgrades, no owner

## License

MIT
