# SWAPBOARD API Documentation

For market makers and trading bots.

## Contract

**Network:** Ethereum Mainnet
**Address:** `0x0000000000000000000000000000000000000000` (update after deployment)

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
        { "name": "tokenA", "type": "address" },
        { "name": "amountA", "type": "uint256" },
        { "name": "tokenB", "type": "address" },
        { "name": "amountB", "type": "uint256" },
        { "name": "active", "type": "bool" }
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
        { "name": "tokenA", "type": "address" },
        { "name": "amountA", "type": "uint256" },
        { "name": "tokenB", "type": "address" },
        { "name": "amountB", "type": "uint256" },
        { "name": "active", "type": "bool" }
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
    "name": "nextOrderId",
    "inputs": [],
    "outputs": [{ "name": "", "type": "uint256" }],
    "stateMutability": "view"
  },
  {
    "type": "event",
    "name": "OrderCreated",
    "inputs": [
      { "name": "orderId", "type": "uint256", "indexed": true },
      { "name": "maker", "type": "address", "indexed": true },
      { "name": "tokenA", "type": "address", "indexed": false },
      { "name": "amountA", "type": "uint256", "indexed": false },
      { "name": "tokenB", "type": "address", "indexed": false },
      { "name": "amountB", "type": "uint256", "indexed": false }
    ]
  },
  {
    "type": "event",
    "name": "OrderFilled",
    "inputs": [
      { "name": "orderId", "type": "uint256", "indexed": true },
      { "name": "taker", "type": "address", "indexed": true }
    ]
  },
  {
    "type": "event",
    "name": "OrderCanceled",
    "inputs": [
      { "name": "orderId", "type": "uint256", "indexed": true }
    ]
  }
]
```

## Subgraph

**Endpoint:** `https://api.studio.thegraph.com/query/YOUR_ID/swapboard/version/latest`

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
    log => log.topics[0] === ethers.id("OrderCreated(uint256,address,address,uint256,address,uint256)")
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

  const approveTx = await tokenContract.approve(CONTRACT_ADDRESS, order.amountB);
  await approveTx.wait();

  // Fill order
  const tx = await contract.fillOrder(orderId);
  await tx.wait();
}
```

### JavaScript: Monitor New Orders

```javascript
async function monitorOrders(provider) {
  const contract = new ethers.Contract(CONTRACT_ADDRESS, CONTRACT_ABI, provider);

  contract.on("OrderCreated", (orderId, maker, tokenA, amountA, tokenB, amountB) => {
    console.log(`New order ${orderId}: ${amountA} ${tokenA} for ${amountB} ${tokenB}`);
  });

  contract.on("OrderFilled", (orderId, taker) => {
    console.log(`Order ${orderId} filled by ${taker}`);
  });

  contract.on("OrderCanceled", (orderId) => {
    console.log(`Order ${orderId} canceled`);
  });
}
```

### Python: Query Subgraph

```python
import requests

SUBGRAPH_URL = "https://api.studio.thegraph.com/query/YOUR_ID/swapboard/version/latest"

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
pragma solidity ^0.8.24;

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

## Notes

- All amounts are in base units (wei-style). Multiply by 10^decimals.
- Orders can be front-run. Consider using Flashbots for fills.
- Fee-on-transfer tokens for tokenA are rejected at creation.
- Fee-on-transfer tokens for tokenB: maker receives less than amountB.
- No partial fills. Orders are filled completely or not at all.
- Self-fills are allowed (maker can fill own order).
- No expiry. Orders remain active until filled or canceled.
- Contract has no admin functions. No pause. No upgrades.
