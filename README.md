# Swapboard

Trustless OTC bulletin board for ERC20 token swaps on Ethereum.

No admin. No fees. No upgrades. No keys. No backend.

## Architecture

```
contracts/     Solidity smart contract (Foundry)
subgraph/      The Graph indexer
frontend/      Static HTML/CSS/JS
e2e/           End-to-end tests
docs/          API documentation
```

## Quick Start

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Node.js](https://nodejs.org/) v18+
- [pnpm](https://pnpm.io/)

### Build

```bash
# Contracts
cd contracts && forge build

# Subgraph
cd subgraph && pnpm install && pnpm build

# E2E tests
cd e2e && pnpm install
```

### Test

```bash
# All tests
./test.sh

# Contract tests only
cd contracts && forge test -vvv

# E2E tests (starts Anvil automatically)
cd e2e && pnpm test
```

### Deploy

1. Deploy contract:
```bash
cd contracts
PRIVATE_KEY=0x... forge script script/Deploy.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify
```

2. Update addresses:
   - `frontend/app.js` - CONFIG.CONTRACT_ADDRESS
   - `subgraph/subgraph.yaml` - source.address and startBlock

3. Deploy subgraph:
```bash
cd subgraph
pnpm deploy
```

4. Update subgraph URL:
   - `frontend/app.js` - CONFIG.SUBGRAPH_URL

5. Deploy frontend to IPFS:
```bash
# Install IPFS CLI if needed: https://docs.ipfs.tech/install/command-line/
ipfs add -r frontend/
# Note the CID from output, then pin it:
ipfs pin add <CID>
```

6. Update ENS contenthash (optional):
```bash
# Set contenthash to ipfs://<CID> via ENS manager or CLI
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
