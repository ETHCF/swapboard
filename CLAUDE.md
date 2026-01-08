# Swapboard - Project Context for Claude

## Overview
Swapboard is a trustless, fee-free peer-to-peer OTC trading platform for ERC20 tokens on Ethereum. The contract is immutable with no admin rights.

## Architecture

```
swapboard/
├── contracts/          # Foundry project - Solidity smart contracts
├── subgraph/           # The Graph subgraph for indexing orders
├── frontend/           # Static HTML/CSS/JS frontend (GitHub Pages)
├── e2e/                # End-to-end tests
└── docs/               # Documentation
```

## Key Components

### Smart Contract (`contracts/`)
- `src/Swapboard.sol` - Main contract for order creation, filling, and cancellation
- Uses Foundry for testing and deployment
- Deployed on Sepolia testnet

### Subgraph (`subgraph/`)
- Indexes OrderCreated, OrderFilled, OrderCanceled events
- Deployed via Goldsky
- GraphQL schema with Order entity containing nested Token objects

### Frontend (`frontend/`)
- Pure static site: `index.html`, `style.css`, `app.js`, `mock.js`
- No build step - deploys directly to GitHub Pages via `.github/workflows/pages.yml`
- Uses ethers.js v6 (loaded from CDN)
- Queries subgraph for order data
- `mock.js` provides simulated wallet/contract for local testing without MetaMask

## Frontend Patterns

### Styling
- CSS variables for theming (`:root` for light, `body.dark-mode` for dark)
- Dark mode toggle persists to localStorage (`swapboard-theme`)
- Mobile-responsive with card layout for orders table

### State Management
- Global variables: `userAddress`, `signer`, `contract`, `provider`
- Filters stored in `currentFilters` object, persisted to localStorage
- Sort preferences in `currentSort`, persisted to localStorage

### Key Functions
- `connectWallet()` - MetaMask connection with network switching
- `disconnectWallet()` - Clears wallet state
- `loadOrders()` - Fetches orders from subgraph with filters/pagination
- `querySubgraph()` - GraphQL query wrapper with error handling
- `parseContractError()` - Converts technical errors to user-friendly messages

### Wallet Dropdown Menu
When connected, clicking the wallet address shows a dropdown with:
- Copy Address, View on Etherscan
- My Open/Filled/Cancelled Orders (filter shortcuts)
- Export My Orders (CSV)
- Switch Wallet, Disconnect

## Deployment

### Frontend
Push to `main` branch triggers `.github/workflows/pages.yml` which deploys `frontend/` to GitHub Pages.

### Contract
Use Foundry: `forge script script/Deploy.s.sol --broadcast`

### Subgraph
Use Goldsky CLI: `goldsky subgraph deploy swapboard-sepolia/1.0.0`

## Common Tasks

### Adding new token filter
1. Add UI element in `index.html`
2. Add filter logic in `loadOrders()` GraphQL query
3. Persist preference in `saveFilterPreferences()`

### Updating error messages
Edit `parseContractError()` in `app.js` - add pattern match for error string and return friendly message.

### Modifying styles
Use CSS variables defined in `:root` and `body.dark-mode` blocks at top of `style.css`.

## Testing
- Contract: `forge test`
- E2E: See `e2e/` directory
- Frontend: Open `frontend/index.html` locally (uses mock.js for wallet simulation)
