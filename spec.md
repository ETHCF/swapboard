# OTC Bulletin Board

## What It Does

Maker deposits tokens. Sets a condition. Anyone who meets the condition gets the tokens.

**Condition:** "I have X amount of TokenA that I would like to sell for Y amount of TokenB"

---

## Philosophy

Fully decentralized. No counterparty risk. No admin. No upgrades. No keys. No backend. No company. No employees. No fees. No token. No VC. No bullshit.

Just a contract and a frontend.

---

## Users

### Maker

I want to:
- Deposit my TokenA into the contract
- Set a condition: "Transfer X amount of TokenB to me to claim these"
- Receive TokenB directly to my wallet when someone fills
- Withdraw my TokenA anytime if unfilled

Note: Condition enforces "taker transfers X", not "maker receives X". For FOT tokenB, maker receives less.

### Taker

I want to:
- Call the contract to fill an order
- Contract pulls TokenB from me and sends it to maker
- Contract sends TokenA to me
- All in one transaction

---

## Example

```
1. Maker approves contract to spend 100 WETH
2. Maker calls createOrder(WETH, 100, USDC, 250000)
3. Contract holds 100 WETH
4. Taker approves contract to spend 250,000 USDC
5. Taker calls fillOrder(orderId)
6. Contract sends 250,000 USDC to maker, 100 WETH to taker
```

Native ETH not supported. Users wrap/unwrap via WETH contract directly.

---

## Order

```
maker       - who deposited
tokenA      - what they deposited
amountA     - how much they deposited
tokenB      - what they want
amountB     - how much they want (the condition)
active      - whether it can still be filled
```

---

## Functions

```solidity
createOrder(address tokenA, uint256 amountA, address tokenB, uint256 amountB) → uint256 orderId
fillOrder(uint256 orderId)
cancelOrder(uint256 orderId)
getOrder(uint256 orderId) → Order struct
getOrders(uint256[] orderIds) → Order[] structs (recommend max 100 per call)
canFill(uint256 orderId) → bool (equivalent to orders[orderId].active)
```

State variables (auto-generated getters):
```solidity
uint256 public nextOrderId;
mapping(uint256 => Order) public orders;
```

All amounts are base units (wei-style). Frontend handles decimal conversion.

---

## Rules

- Full fill only (no partial fills, ever)
- Condition cannot change after creation
- Only maker can cancel
- Contract handles all transfers
- Atomic: both transfers succeed or both fail
- No admin, no fees, no oracles
- ERC20 only (no native ETH, use WETH)
- tokenA and tokenB must not be address(0)
- tokenA and tokenB must be different
- tokenA and tokenB must be contracts (code.length > 0)

---

## createOrder Sequence

```
1. Revert if tokenA == address(0) or tokenB == address(0) (ZeroAddress)
2. Revert if amountA == 0 or amountB == 0 (ZeroAmount)
3. Revert if tokenA == tokenB (SameToken)
4. Revert if tokenA.code.length == 0 or tokenB.code.length == 0 (NotAContract)
5. balanceBefore = tokenA.balanceOf(this)
6. SafeERC20.safeTransferFrom(tokenA, msg.sender, this, amountA)
7. balanceAfter = tokenA.balanceOf(this)
8. if (balanceAfter < balanceBefore) revert BalanceMismatch(amountA, 0)
9. received = balanceAfter - balanceBefore
10. if (received != amountA) revert BalanceMismatch(amountA, received)
11. orderId = nextOrderId++
12. orders[orderId] = Order(msg.sender, tokenA, amountA, tokenB, amountB, true)
13. emit OrderCreated(orderId, msg.sender, tokenA, amountA, tokenB, amountB)
14. return orderId
```

Note: Function is non-payable. EVM rejects any msg.value > 0.

---

## fillOrder Sequence

```
1. Revert if order.maker == address(0) (OrderNotFound)
2. Revert if !order.active (OrderNotActive)
3. order.active = false
4. SafeERC20.safeTransferFrom(tokenB, msg.sender, order.maker, order.amountB)
5. SafeERC20.safeTransfer(tokenA, msg.sender, order.amountA)
6. emit OrderFilled(orderId, msg.sender)
```

Note: Function is non-payable. Condition is "taker transfers amountB", not "maker receives amountB". For FOT tokenB, maker receives less than amountB.

---

## cancelOrder Sequence

```
1. Revert if order.maker == address(0) (OrderNotFound)
2. Revert if !order.active (OrderNotActive)
3. Revert if msg.sender != order.maker (NotMaker)
4. order.active = false
5. SafeERC20.safeTransfer(tokenA, order.maker, order.amountA)
6. emit OrderCanceled(orderId)
```

Note: Function is non-payable.

---

## Token Flow

```
createOrder:
  TokenA: maker → contract (held in escrow)

fillOrder:
  TokenB: taker → maker (via contract)
  TokenA: contract → taker

cancelOrder:
  TokenA: contract → maker
```

Contract holds tokenA in escrow. TokenB passes through directly to maker.

Note: Contract can receive unsolicited tokens or forced ETH (via selfdestruct). These do not affect order logic but cannot be recovered.

---

## Events

```solidity
event OrderCreated(
    uint256 indexed orderId,
    address indexed maker,
    address tokenA,
    uint256 amountA,
    address tokenB,
    uint256 amountB
);

event OrderFilled(uint256 indexed orderId, address indexed taker);

event OrderCanceled(uint256 indexed orderId);
```

---

## Errors

```solidity
error ZeroAddress();
error ZeroAmount();
error SameToken();
error NotAContract(address token);
error BalanceMismatch(uint256 expected, uint256 received);
error OrderNotFound(uint256 orderId);
error OrderNotActive(uint256 orderId);
error NotMaker(uint256 orderId, address caller, address maker);
```

Note: All functions are non-payable. EVM rejects ETH automatically.

---

## Security

- Reentrancy guard (OpenZeppelin ReentrancyGuard, nonReentrant modifier on createOrder, fillOrder, cancelOrder)
- Safe transfer wrappers (OpenZeppelin SafeERC20, handles non-standard return values)
- State updates before external calls (CEI pattern)
- Reject EOA addresses as tokens (require code.length > 0)
- All functions non-payable (EVM rejects ETH automatically)
- No receive() or fallback() functions
- FOT detection on tokenA: verify received == expected at creation (with underflow guard)

```solidity
uint256 balanceBefore = IERC20(tokenA).balanceOf(address(this));
IERC20(tokenA).transferFrom(maker, address(this), amountA);
uint256 balanceAfter = IERC20(tokenA).balanceOf(address(this));
require(balanceAfter - balanceBefore == amountA, "FOT not supported");
```

**Unsupported tokens (fail at creation):**
- Fee-on-transfer tokens (balance check rejects)
- Rebasing tokens (may fail at fill if balance decreased)

---

## Decentralization

### Contract

- Immutable (no proxy, no upgrades)
- No owner
- No admin functions
- No pause mechanism
- No fee switch
- No privileged roles
- Deployer has no special privileges (permissionless from block 0)
- Contract verified on Etherscan

### Frontend

- Static HTML/CSS/JS
- Hosted on IPFS
- Accessible via ENS + eth.limo (swapboard.eth.limo)
- No backend server
- No database
- No API keys
- No analytics
- No cookies
- Works with any RPC (user's wallet provider)

### Indexing

- The Graph (decentralized subgraph)
- Hosted on The Graph Network (not hosted service)
- Anyone can run their own indexer
- Frontend falls back to direct contract reads if subgraph unavailable
- Note: Direct reads impractical at scale (requires iterating all orderIds). Subgraph effectively required for production.

### Dependencies

- None at runtime
- Frontend talks directly to:
  - User's wallet (RPC)
  - The Graph (subgraph)

### DNS

- No traditional DNS
- ENS name: swapboard.eth
- Access via eth.limo gateway
- Alternative IPFS gateways work too

---

## Frontend

### Design

Brutalist. No frills. HTML table. Monospace font. Minimal CSS.

### Header

```
SWAPBOARD                                              [Connect Wallet]

No frills OTC bulletin board for ERC20 tokens. 0% fee. Immutable. No admin.

[API Docs]
```

### Stats

```
Orders: 156,172 posted | 45,231 filled | 12,000 cancelled
Volume: 12,451 ETH | 3,241 WBTC | 45,123,456 USDC | ...
```

### Filters

```
Selling: [All ▼]  Wanting: [All ▼]  Status: [Open ▼]
```

Status options: Open, Filled, Cancelled, All

### Trade Table

| Trade ID | Account | Selling | Size | Wanting | Size | Ratio |
|----------|---------|---------|------|---------|------|-------|
| 8 | 0x59Cd5F... | USDT | 1,234,567.23 | ETH | 411.52 | 3000 USDT/ETH |
| 7 | 0x59Cd5F... | WBTC | 1.3627 | USDT | 115,830.88 | 85000 USDT/WBTC |

### Columns

```
Trade ID - Order ID from contract
Account  - Maker address (truncated, or ENS if resolved)
Selling  - TokenA symbol
Size     - AmountA in human units (sortable)
Wanting  - TokenB symbol
Size     - AmountB in human units (sortable)
Ratio    - amountB/amountA for display only (sortable)
```

### Actions

- Click row to fill (if connected and not maker)
- Maker sees "Cancel" button on their orders

### Create Order

```
Selling: [Paste Token Address] [Amount Input]
Wanting: [Paste Token Address] [Amount Input]

[Create Order]
```

Token selection: user pastes contract address, frontend fetches symbol/decimals.

Warning displayed: "Verify token addresses carefully. Fake tokens can steal your funds. Only use trusted tokens."

### Pagination

Page numbers (not infinite scroll). Subgraph handles pagination queries.

---

## Deployment

### Contract

1. Deploy OTCBoard.sol to mainnet
2. Verify on Etherscan
3. Contract is permissionless immediately (no keys to burn)

### Subgraph

1. Deploy subgraph to The Graph Network
2. Publish as public good
3. Anyone can index

### Frontend

1. Build static site
2. Pin to IPFS
3. Update ENS contenthash (swapboard.eth → ipfs://...)
4. Burn ENS ownership or lock to multisig then burn
5. Frontend lives forever

### Access

```
Primary:     swapboard.eth.limo
Fallback:    ipfs://Qm.../
Direct:      Any IPFS gateway + CID
Contract:    Etherscan direct interaction
```

---

## Files

```
contracts/
├── src/
│   ├── OTCBoard.sol
│   └── interfaces/
│       └── IOTCBoard.sol
├── test/
│   ├── OTCBoard.t.sol
│   └── mocks/
│       └── MockERC20.sol
├── script/
│   └── Deploy.s.sol
└── foundry.toml

subgraph/
├── schema.graphql
├── subgraph.yaml
├── src/
│   └── mapping.ts
└── package.json

frontend/
├── index.html
├── style.css
└── app.js

docs/
└── API.md
```

---

## API Documentation

For market makers and trading bots:

- Contract ABI and address
- Example subgraph queries (open orders, orders by token, orders by maker)
- Example scripts for creating/filling orders programmatically

---

## Known Behaviors

Documented, not bugs:

- **Front-running**: fillOrder can be front-run via mempool. Inherent to on-chain order books.
- **Dust orders**: No minimum order size. Spam costs gas.
- **Self-fill**: Maker can fill own order. Zero-sum except gas. Could inflate volume stats.
- **No expiry**: Orders live forever until filled or canceled. Stale orders accumulate. Maker must manually cancel.
- **FOT tokenA**: Rejected at creation (balance check).
- **FOT tokenB**: Maker receives less than amountB. Maker's risk (they chose the token).
- **Rebasing tokens**: May fail at fill if balance decreased since creation.
- **Stuck funds**: If tokenA transfer fails during fill or cancel (paused token, broken token), funds stuck until token issue resolved.
- **Blacklist on fill**: If maker is blacklisted by tokenB issuer (e.g., USDC), order cannot be filled. Maker can still cancel.
- **Blacklist on cancel**: If maker is blacklisted by tokenA issuer after deposit, maker cannot cancel or receive funds. Order stuck until blacklist removed.
- **Forced ETH**: ETH sent via selfdestruct cannot be recovered. Does not affect functionality.
- **Malicious tokens**: Contract assumes ERC20 standard compliance. Malicious tokens that lie about balances can cause fund loss. Use trusted tokens only.

---

## After Launch

Nothing. No maintenance. No updates. No team. It either works or it doesn't.

If bugs found: deploy new contract, new frontend, new ENS. Old one stays forever.

