# SWAPBOARD API Documentation

For market makers and trading bots.

## Contract

**Network:** Sepolia Testnet
**Address:** `0xBe3D7A555aa633263110d10d37AB40Ef3a2b8BBa`

### ABI

```json
[
  {
    "type": "function",
    "name": "createOrder",
    "inputs": [
      { "name": "tokenA", "type": "address" },
      { "name": "amountA", "type": "uint256" },
      { "name": "tokenB", "type": "address" },
      { "name": "amountB", "type": "uint256" }
    ],
    "outputs": [{ "name": "orderId", "type": "uint256" }],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "fillOrder",
    "inputs": [{ "name": "orderId", "type": "uint256" }],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "cancelOrder",
    "inputs": [{ "name": "orderId", "type": "uint256" }],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "getOrder",
    "inputs": [{ "name": "orderId", "type": "uint256" }],
    "outputs": [{
      "name": "",
      "type": "tuple",
      "components": [
        { "name": "maker", "type": "address" },
        { "name": "partialFillAllowed", "type": "bool" },
        { "name": "tokenA", "type": "address" },
        { "name": "tokenB", "type": "address" },
        { "name": "amountA", "type": "uint128" },
        { "name": "amountB", "type": "uint128" },
        { "name": "availableA", "type": "uint128" },
        { "name": "availableB", "type": "uint128" }
      ]
    }],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getOrders",
    "inputs": [{ "name": "orderIds", "type": "uint256[]" }],
    "outputs": [{
      "name": "result",
      "type": "tuple[]",
      "components": [
        { "name": "maker", "type": "address" },
        { "name": "partialFillAllowed", "type": "bool" },
        { "name": "tokenA", "type": "address" },
        { "name": "tokenB", "type": "address" },
        { "name": "amountA", "type": "uint128" },
        { "name": "amountB", "type": "uint128" },
        { "name": "availableA", "type": "uint128" },
        { "name": "availableB", "type": "uint128" }
      ]
    }],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "canFill",
    "inputs": [{ "name": "orderId", "type": "uint256" }],
    "outputs": [{ "name": "", "type": "bool" }],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getNextOrderId",
    "inputs": [],
    "outputs": [{ "name": "", "type": "uint256" }],
    "stateMutability": "view"
  },
  {
    "type": "function",
    "name": "getWeth",
    "inputs": [],
    "outputs": [{ "name": "", "type": "address" }],
    "stateMutability": "view"
  },
  {
    "type": "event",
    "name": "OrderCreated",
    "inputs": [
      { "name": "orderId", "type": "uint256", "indexed": true },
      { "name": "maker", "type": "address", "indexed": true },
      { "name": "tokenA", "type": "address", "indexed": false },
      { "name": "amountA", "type": "uint128", "indexed": false },
      { "name": "tokenB", "type": "address", "indexed": false },
      { "name": "amountB", "type": "uint128", "indexed": false },
      { "name": "partialFillAllowed", "type": "bool", "indexed": true }
    ]
  },
  {
    "type": "event",
    "name": "OrderFilled",
    "inputs": [
      { "name": "orderId", "type": "uint256", "indexed": true },
      { "name": "taker", "type": "address", "indexed": true },
      { "name": "amountA", "type": "uint128", "indexed": false },
      { "name": "amountB", "type": "uint128", "indexed": false }
    ]
  },
  {
    "type": "event",
    "name": "OrderCanceled",
    "inputs": [
      { "name": "orderId", "type": "uint256", "indexed": true }
    ]
  },
  {
    "type": "event",
    "name": "OrderModified",
    "inputs": [
      { "name": "orderId", "type": "uint256", "indexed": true },
      { "name": "availableA", "type": "uint128", "indexed": false },
      { "name": "availableB", "type": "uint128", "indexed": false }
    ]
  },
  {
    "type": "event",
    "name": "OrderPartialFillUpdated",
    "inputs": [
      { "name": "orderId", "type": "uint256", "indexed": true },
      { "name": "partialFillAllowed", "type": "bool", "indexed": true }
    ]
  }
]
```

## Subgraph

**Endpoint:** `https://api.goldsky.com/api/public/project_cmk2ptqkv97cw01xi85vph3la/subgraphs/swapboard-sepolia/1.0.0/gn`

### Query: Open Orders

```graphql
query OpenOrders($first: Int!, $skip: Int!) {
  orders(
    first: $first
    skip: $skip
    orderBy: orderId
    orderDirection: desc
    where: { active: true }
  ) {
    orderId
    maker
    amountA
    amountB
    tokenA {
      address
      symbol
      decimals
    }
    tokenB {
      address
      symbol
      decimals
    }
  }
}
```

### Query: Orders by Token Pair

```graphql
query OrdersByPair($tokenA: String!, $tokenB: String!) {
  orders(
    first: 100
    orderBy: orderId
    orderDirection: desc
    where: {
      active: true
      tokenA_: { address: $tokenA }
      tokenB_: { address: $tokenB }
    }
  ) {
    orderId
    maker
    amountA
    amountB
  }
}
```

### Query: Orders by Maker

```graphql
query OrdersByMaker($maker: Bytes!) {
  orders(
    first: 100
    orderBy: orderId
    orderDirection: desc
    where: { maker: $maker }
  ) {
    orderId
    amountA
    amountB
    active
    taker
    tokenA {
      symbol
    }
    tokenB {
      symbol
    }
  }
}
```

### Query: Global Stats

```graphql
query Stats {
  globalStats(id: "global") {
    totalOrders
    filledOrders
    cancelledOrders
    activeOrders
  }
}
```

### Query: Token Volume

```graphql
query TokenVolume {
  tokens(first: 20, orderBy: volumeSold, orderDirection: desc) {
    address
    symbol
    decimals
    volumeSold
    volumeBought
    ordersSelling
    ordersBuying
  }
}
```

## Examples

### JavaScript: Create Order

```javascript
const { ethers } = require("ethers");

const CONTRACT_ADDRESS = "0x...";
const CONTRACT_ABI = [...]; // See above

async function createOrder(
  provider,
  signer,
  tokenA,
  amountA,
  tokenB,
  amountB
) {
  const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, signer);

  // Approve tokenA first
  const tokenContract = new ethers.Contract(tokenA, [
    "function approve(address spender, uint256 amount) returns (bool)"
  ], signer);

  const approveTx = await tokenContract.approve(CONTRACT_ADDRESS, amountA);
  await approveTx.wait();

  // Create order
  const tx = await contract.createOrder(tokenA, amountA, tokenB, amountB);
  const receipt = await tx.wait();

  // Get orderId from event
  const event = receipt.logs.find(
    log => log.topics[0] === ethers.id("OrderCreated(uint256,address,address,uint128,address,uint128,bool)")
  );
  const orderId = BigInt(event.topics[1]);

  return orderId;
}
```

### JavaScript: Fill Order

```javascript
async function fillOrder(provider, signer, orderId) {
  const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, signer);

  // Get order details
  const order = await contract.getOrder(orderId);

  // Approve tokenB
  const tokenContract = new ethers.Contract(order.tokenB, [
    "function approve(address spender, uint256 amount) returns (bool)"
  ], signer);

  const approveTx = await tokenContract.approve(CONTRACT_ADDRESS, order.availableB);
  await approveTx.wait();

  // Fill: send exact remaining tokenB, require at least remaining tokenA
  const tx = await contract.fillOrder(orderId, order.availableB, order.availableA, 0);
  await tx.wait();
}
```

### JavaScript: Monitor New Orders

```javascript
async function monitorOrders(provider) {
  const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, provider);

  contract.on("OrderCreated", (orderId, maker, tokenA, amountA, tokenB, amountB, partialFillAllowed) => {
    console.log(`New order ${orderId}: ${amountA} ${tokenA} for ${amountB} ${tokenB} (partial=${partialFillAllowed})`);
  });

  contract.on("OrderFilled", (orderId, taker) => {
    console.log(`Order ${orderId} filled by ${taker}`);
  });

  contract.on("OrderCanceled", (orderId) => {
    console.log(`Order ${orderId} canceled`);
  });

  contract.on("OrderModified", (orderId, availableA, availableB) => {
    console.log(`Order ${orderId} modified: remaining ${availableA}/${availableB}`);
  });

  contract.on("OrderPartialFillUpdated", (orderId, partialFillAllowed) => {
    console.log(`Order ${orderId} partialFillAllowed=${partialFillAllowed}`);
  });
}
```

### Python: Query Subgraph

```python
import requests

SUBGRAPH_URL = "https://api.goldsky.com/api/public/project_cmk2ptqkv97cw01xi85vph3la/subgraphs/swapboard-sepolia/1.0.0/gn"

def get_open_orders(token_a=None, token_b=None, limit=100):
    where = "active: true"
    if token_a:
        where += f', tokenA_: {{ address: "{token_a.lower()}" }}'
    if token_b:
        where += f', tokenB_: {{ address: "{token_b.lower()}" }}'

    query = f"""
    {{
      orders(
        first: {limit}
        orderBy: orderId
        orderDirection: desc
        where: {{ {where} }}
      ) {{
        orderId
        maker
        amountA
        amountB
        tokenA {{ address symbol decimals }}
        tokenB {{ address symbol decimals }}
      }}
    }}
    """

    response = requests.post(SUBGRAPH_URL, json={"query": query})
    return response.json()["data"]["orders"]
```

### Foundry: Create Order Script

```solidity
// script/CreateOrder.s.sol
pragma solidity ^0.8.36;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISwapboard {
    function createOrder(
        address tokenA,
        uint256 amountA,
        address tokenB,
        uint256 amountB
    ) external returns (uint256);
}

contract CreateOrder is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address board = vm.envAddress("BOARD_ADDRESS");
        address tokenA = vm.envAddress("TOKEN_A");
        address tokenB = vm.envAddress("TOKEN_B");
        uint256 amountA = vm.envUint("AMOUNT_A");
        uint256 amountB = vm.envUint("AMOUNT_B");

        vm.startBroadcast(pk);

        IERC20(tokenA).approve(board, amountA);
        uint256 orderId = ISwapboard(board).createOrder(tokenA, amountA, tokenB, amountB);

        vm.stopBroadcast();
    }
}
```

Run with:

```bash
PRIVATE_KEY=0x... \
BOARD_ADDRESS=0x... \
TOKEN_A=0x... \
TOKEN_B=0x... \
AMOUNT_A=1000000000000000000 \
AMOUNT_B=3000000000 \
forge script script/CreateOrder.s.sol --rpc-url $RPC_URL --broadcast
```

## Error Codes

| Error | Selector | Description |
| ------- | ---------- | ------------- |
| `ZeroAddress()` | `0xd92e233d` | Token address is zero |
| `ZeroAmount()` | `0x1f2a2005` | Amount is zero. On `modifyOrder` / `modifyOrders`, also thrown when either remaining (`availableA` / `availableB`) is set to 0 — use `cancelOrder` / `cancelOrders` instead. Empty `modifyOrders` also reverts |
| `NoChange()` | `0xa88ee577` | Modification would leave the order unchanged (including any item in a `modifyOrders` batch) |
| `SameToken()` | `0x201b580a` | tokenA and tokenB are identical |
| `BalanceMismatch(uint256,uint256)` | `0x6e65ed84` | Transfer mismatch on tokenA deposit or ERC20 tokenB payment to maker (fee-on-transfer, mid-transfer rebase, or phantom token) |
| `OrderNotFound(uint256)` | `0x4e90badc` | Order doesn't exist, or was filled/cancelled (both `delete` storage) |
| `NotMaker(uint256,address,address)` | `0x98cd7222` | Caller is not order maker |
| `SelfFill()` | `0x9d7a930f` | Maker attempted to fill their own order. Banned so tokenB can always be pulled directly to a distinct maker (`transferFrom(self, self)` does not increase the recipient, so an exact-receive check would fail) |
| `ETHAmountMismatch(uint256,uint256)` | `0x8230dc8f` | `msg.value` does not match the required ETH amount |
| `OrderStateMismatch(uint256)` | `0x457802f0` | `modifyOrder` / `modifyOrders` race: snapshot amounts do not match on-chain `amountA`/`amountB`/`availableA`/`availableB` (re-read via `getOrder`) |
| `DuplicateOrderId(uint256)` | `0x54b9c511` | Same `orderId` appears more than once in a `cancelOrders` or `modifyOrders` batch |
| `FillAmountTooHigh(uint256,uint128,uint128)` | `0x535a34f0` | Requested `amountB` exceeds remaining liquidity (`fillOrder` / `fillOrders`) |
| `FillAmountMismatch(uint256,uint128,uint128)` | `0x19113a72` | Quoted tokenA receive is below the taker's `minAmountA` (`fillOrder`) |
| `PermitOnNative()` | `0x62898bac` | EIP-2612 / Permit2 signature supplied for the native ETH sentinel |
| `InvalidPermit()` | `0xddafbaef` | Batch EIP-2612 permit entry has `v == 0` |
| `UnusedPermit()` | `0xb1df4e7e` | EIP-2612 permit was not used by any pull (batch unused entry or refund-only `modifyOrder`) |
| `DuplicatePermitToken(address)` | `0xc87bfe90` | Same token appears more than once in a permit batch |
| `InvalidPermit2()` | `0x32d1c8da` | Batch Permit2 entry has an empty signature |
| `UnusedPermit2()` | `0xc1abc68b` | Permit2 signature was not used by any pull (batch unused entry or refund-only `modifyOrder`) |
| `TooManyPermit2()` | `0x35d2fb43` | Permit2 batch has more than 256 entries |

## Methods

### EIP-2612 permits

`createOrder`, `createOrders`, `fillOrder`, `fillOrders`, `modifyOrder`, and `modifyOrders` have overloads that take an EIP-2612 permit as the last argument so allowance can be set in the same transaction as the pull. Existing signatures are unchanged.

```solidity
struct Permit {
    uint256 value;
    uint256 deadline;
    uint8 v;          // 27/28; 0 skips the permit
    bytes32 r;
    bytes32 s;
}

struct TokenPermit {
    address token;
    uint8 v;          // 27/28; 0 reverts InvalidPermit
    uint256 value;
    uint256 deadline;
    bytes32 r;
    bytes32 s;
}
```

Behavior:

- Spender is always this Swapboard. Owner is `msg.sender`.
- Single-path: `v == 0` skips (caller must already have allowance). Native ETH with `v != 0` reverts `PermitOnNative`. A non-skip permit on a refund-only `modifyOrder` (no top-up) reverts `UnusedPermit`.
- Batch: empty array means no permits. `v == 0` reverts `InvalidPermit`. Duplicate `token` reverts `DuplicatePermitToken`. `token == 0` reverts `ZeroAddress`. Native ETH reverts `PermitOnNative`. Unused permit (token not pulled) reverts `UnusedPermit`.
- Token `permit` errors bubble (expired, wrong signer, non-permit token).
- Permits are applied immediately before the corresponding pull (create tokenA, fill tokenB, modify tokenA top-up).
- The `permit` call is skipped whenever the current allowance already covers `value`, so a front-run permit does not brick the call: anyone may submit the signature first, which spends the EIP-2612 nonce but leaves the same allowance, and the pull proceeds. This also means a permit whose `value` is already approved is never validated (no revert on an expired or malformed signature).

```solidity
function createOrder(CreateOrderParams calldata order, Permit calldata permit) external payable returns (uint256);
function createOrders(CreateOrderParams[] calldata orders, TokenPermit[] calldata permits) external payable returns (uint256[] memory);
```

### Permit2 SignatureTransfer

The same six entrypoints also have Permit2 overloads. Users approve the canonical Permit2 contract (`0x000000000022D473030F116dDEE9F6B43aC78BA3`) once per token, then pass a SignatureTransfer signature so Swapboard can pull without a direct ERC20 allowance to Swapboard.

```solidity
struct Permit2Permit {
    uint256 amount;      // signed TokenPermissions.amount
    uint256 nonce;
    uint256 deadline;
    bytes signature;     // empty skips
}

struct TokenPermit2 {
    address token;
    uint256 amount;
    uint256 nonce;
    uint256 deadline;
    bytes signature;     // empty reverts InvalidPermit2
}
```

Behavior:

- Spender in the signed message must be this Swapboard. Owner is `msg.sender`.
- Single-path: empty `signature` skips (classic `transferFrom` / existing Swapboard allowance). Native ETH with a non-empty signature reverts `PermitOnNative`. A non-empty signature on a refund-only `modifyOrder` (no top-up) reverts `UnusedPermit2`.
- Batch: empty array means none. Empty signature → `InvalidPermit2`. Unused Permit2 token (not pulled) → `UnusedPermit2`. More than 256 entries → `TooManyPermit2`. Duplicate `token` → `DuplicatePermitToken`. Zero/native token → `ZeroAddress` / `PermitOnNative`.
- Signed `amount` must cover the exact pull (aggregated for batches). Permit2 / token errors bubble.
- Single fills pull ERC20 tokenB directly to the maker. Batch fills with Permit2 pull each distinct ERC20 tokenB total to Swapboard, then distribute to makers.
- Create/modify pulls go to escrow on Swapboard.
- The Permit2 address is a compile-time constant. On a chain where Permit2 is not deployed, every Permit2 overload reverts with empty returndata (the call target has no code); the other paths are unaffected. `script/Deploy.s.sol` refuses to deploy there and reverts `Permit2NotDeployed(address)`.

```solidity
function createOrder(CreateOrderParams calldata order, Permit2Permit calldata permit) external payable returns (uint256);
function createOrders(CreateOrderParams[] calldata orders, TokenPermit2[] calldata permits) external payable returns (uint256[] memory);
```

### `fillOrder`

Taker sends exact `amountB` of tokenB and receives floored proportional tokenA. `minAmountA` is the minimum they will accept.

```solidity
struct FillOrderParams {
    uint256 orderId;
    uint128 amountB;      // exact tokenB to send
    uint128 minAmountA;   // minimum tokenA willing to receive
}

function fillOrder(
    uint256 orderId,
    uint128 amountB,
    uint128 minAmountA,
    uint256 deadline
) external payable;

function fillOrder(
    uint256 orderId,
    uint128 amountB,
    uint128 minAmountA,
    uint256 deadline,
    Permit calldata permit
) external payable;

function fillOrders(
    FillOrderParams[] calldata fills,
    uint256 deadline
) external payable;

function fillOrders(
    FillOrderParams[] calldata fills,
    uint256 deadline,
    TokenPermit[] calldata permits
) external payable;
```

Behavior:

- tokenB in is exact: `amountB`.
- tokenA out is floored: `amountB * availableA / availableB` (full remaining `amountB == availableB` returns all `availableA`).
- Reverts with `FillAmountMismatch` when quoted tokenA is below `minAmountA`.
- Reverts with `FillAmountTooHigh` when `amountB` exceeds `availableB`.
- If tokenB is ETH, `msg.value` must equal `amountB`.
- Empty `fillOrders` reverts with `ZeroAmount`.

### `modifyOrder`

Maker-only. Updates an active order's **remaining** liquidity only (not `partialFillAllowed`).

```solidity
struct OrderAmounts {
    uint128 amountA;
    uint128 amountB;
    uint128 availableA;
    uint128 availableB;
}

struct ModifyOrderParams {
    uint128 availableA;       // desired remaining tokenA in escrow
    uint128 availableB;       // desired remaining tokenB required
}

function modifyOrder(
    uint256 orderId,
    OrderAmounts calldata previousAmounts,
    ModifyOrderParams calldata updatedOrder
) external payable;

function modifyOrder(
    uint256 orderId,
    OrderAmounts calldata previousAmounts,
    ModifyOrderParams calldata updatedOrder,
    Permit calldata permit
) external payable;
```

Behavior:

- Pass `previousAmounts` from a recent `getOrder` snapshot. If any of the four amount fields differs on-chain, the call reverts with `OrderStateMismatch`.
- Callers set **remainings**, not totals. On success, `amountA` / `amountB` are reset to those remainings (on-chain fill % goes to 0; historical fills live in events).
- Maker, token pair, and `partialFillAllowed` are immutable on this path.
- TokenA escrow is refunded when remaining A decreases, or pulled / `msg.value`-topped-up when it increases. For ETH tokenA, `msg.value` must equal the top-up (and must be `0` on refund / no-change / ERC20 tokenA).
- Emits `OrderModified(orderId, availableA, availableB)`.
- **`ZeroAmount` blocks setting remaining to 0** — closing the order and reclaiming escrow requires `cancelOrder` / `cancelOrders`, not a zeroed modify.
- **`NoChange`** when both remainings already match on-chain.

### `modifyOrders`

Maker-only batch of `modifyOrder`. Each entry carries its own snapshot and desired remainings.

```solidity
struct ModifyOrdersParams {
    uint256 orderId;
    OrderAmounts previousAmounts;
    ModifyOrderParams updatedOrder;
}

function modifyOrders(ModifyOrdersParams[] calldata mods) external payable;

function modifyOrders(
    ModifyOrdersParams[] calldata mods,
    TokenPermit[] calldata permits
) external payable;
```

Behavior:

- Same per-order rules as `modifyOrder` (race check, remainings-only, reset totals, `ZeroAmount` / `NoChange` / `OrderStateMismatch` / `NotMaker` / `OrderNotFound`).
- Duplicate `orderId`s revert with `DuplicateOrderId`.
- Empty `mods` reverts with `ZeroAmount`.
- Per unique tokenA (and ETH), top-ups are **netted** against refunds: only the net delta is pulled or sent. Equal opposing flows cancel with no transfer. `msg.value` must equal the net ETH top-up (0 when flat or net refund).
- Emits `OrderModified` once per successfully modified order (before settlement transfers).

### `setPartialFillAllowed`

Maker-only. Sets whether an active order may be filled in parts. Does not change amounts or escrow.

```solidity
function setPartialFillAllowed(uint256 orderId, bool partialFillAllowed) external;
```

Emits `OrderPartialFillUpdated(orderId, partialFillAllowed)`.
Reverts with `NoChange` when the flag already equals the requested value.

### JavaScript: Modify Order

```javascript
async function modifyOrder(signer, orderId, availableA, availableB) {
  const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, signer);
  const order = await contract.getOrder(orderId);

  const previousAmounts = {
    amountA: order.amountA,
    amountB: order.amountB,
    availableA: order.availableA,
    availableB: order.availableB
  };
  const updatedOrder = { availableA, availableB };

  const eth = await contract.getEth();
  let value = 0n;
  if (order.tokenA === eth && availableA > order.availableA) {
    value = availableA - order.availableA;
  }

  const tx = await contract.modifyOrder(orderId, previousAmounts, updatedOrder, { value });
  await tx.wait();
}
```

### JavaScript: Modify Orders (batch)

```javascript
async function modifyOrders(signer, updates) {
  // updates: [{ orderId, availableA, availableB }, ...]
  const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, signer);
  const eth = await contract.getEth();

  let ethNet = 0n;
  const mods = [];
  for (const u of updates) {
    const order = await contract.getOrder(u.orderId);
    mods.push({
      orderId: u.orderId,
      previousAmounts: {
        amountA: order.amountA,
        amountB: order.amountB,
        availableA: order.availableA,
        availableB: order.availableB
      },
      updatedOrder: { availableA: u.availableA, availableB: u.availableB }
    });
    if (order.tokenA === eth) {
      ethNet += BigInt(u.availableA) - BigInt(order.availableA);
    }
  }

  const value = ethNet > 0n ? ethNet : 0n;
  const tx = await contract.modifyOrders(mods, { value });
  await tx.wait();
}
```

### JavaScript: Set Partial Fill Allowed

```javascript
async function setPartialFillAllowed(signer, orderId, partialFillAllowed) {
  const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, signer);
  const tx = await contract.setPartialFillAllowed(orderId, partialFillAllowed);
  await tx.wait();
}
```

## Notes

- All amounts are in base units (wei-style). Multiply by 10^decimals.
- Orders can be front-run. Consider using Flashbots for fills.
- Inbound fee-on-transfer / mid-transfer rebase / phantom transfers are rejected on tokenA deposits, on ERC20 tokenA paid to the taker, on ERC20 tokenA refunded to the maker, and on ERC20 tokenB payments to the maker (`BalanceMismatch`), including multi-maker Permit2 board→maker distribution. ETH payouts use `sendValue` and are not balance-checked.
- Post-deposit rebases (while tokenA sits in escrow) are not checked: a negative rebase can lock fill/cancel; a positive rebase can strand surplus. See `contracts/test/security-research/`.
- Escrowed tokenA of a given address is commingled: that token is the real custodian. Admin seize/burn or a lying `transfer` can take all escrow of that token. Makers of the same scam token share one pool; after a rebase they race whatever balance remains. Other tokens in escrow are not affected.
- Token addresses are not checked for code. An EOA or empty address used as a token can make create, fill, or cancel fail. Makers must verify tokenA and tokenB before creating, and takers before filling.
- Recipients must be able to hold the ERC20 they are paid. A maker that forwards, stakes, or burns tokenB in a transfer hook reverts `BalanceMismatch` and its orders cannot be filled. A taker that does not retain tokenA reverts the same way and the fill does not complete.
- Partial fills are allowed only when `partialFillAllowed` is true (set at create or via `setPartialFillAllowed`).
- The maker cannot fill their own order (`SelfFill`). A self-`transferFrom` of tokenB typically does not increase the recipient, so the exact-receive check would revert even for honest tokens. Supporting self-fill required routing tokenB through the board and back. Banning it keeps every fill payment a single pull to a distinct maker. (Multi-maker Permit2 still hops through the board to split one pull across makers.)
- No expiry. Orders remain active until filled or canceled.
- ETH always goes to `msg.sender` (no recipient override). An address that rejects ETH locks itself out of native-ETH orders: a maker that reverts on receive (or has self-destructed) can never cancel an ETH-tokenA order, so that escrow is stuck, and their ETH-tokenB orders cannot be filled; a taker that rejects ETH cannot fill ETH-tokenA orders. Use an EOA or an ETH-accepting contract for native-ETH orders.
- To close an order or reclaim all escrow, call `cancelOrder` / `cancelOrders`. `modifyOrder` / `modifyOrders` cannot set remaining to 0 (`ZeroAmount`).
- Contract has no admin functions. No pause. No upgrades.
