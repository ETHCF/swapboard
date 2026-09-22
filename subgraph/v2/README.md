# Swapboard v2 Subgraph

The Graph indexer for the Swapboard v2 contract (`contracts/src/Swapboard.sol`).
Consumed by the v2 UI.

For the indexer that serves the deployed v1 contract, see [`../v1`](../v1).

## What changed from v1

| | v1 | v2 |
| --- | --- | --- |
| Fills | one `OrderFilled` per order | many, when `partialFillAllowed` |
| Amounts | `uint256` | `uint128` |
| Native ETH | not supported | `0xEeee…eEeE` sentinel, indexed as a `Token` with `isNative: true` |
| Batching | — | `createOrders` / `fillOrders` / `cancelOrders` / `modifyOrders` emit several events per transaction |
| Fill history | none | one `Fill` entity per `OrderFilled` |
| Live orders | write-once | makers can reprice (`modifyOrder`) and flip the partial-fill flag (`setPartialFillAllowed`) |

## Entities

- **`Order`** — one per `OrderCreated`. `amountA`/`amountB` are the current totals;
  `availableA`/`availableB` shrink with each fill; `filledA`/`filledB` and
  `filledFraction` accumulate. `status` is `OPEN`, `PARTIALLY_FILLED`, `FILLED`, or
  `CANCELED`, and `active` is true for the first two. A modify rewrites the totals and
  resets the fill progress (see below), so `lifetimeFilledA`/`lifetimeFilledB` carry the
  totals that survive a reset.
- **`Fill`** — one per `OrderFilled`, immutable, keyed by `<txHash>-<logIndex>` so batch
  fills in one transaction stay distinct. Carries the amounts, the price, and what was
  left on the order afterwards.
- **`OrderModification`** — one per `OrderModified`, immutable, keyed the same way.
  Carries the order's amounts and price on both sides of the change plus the signed
  `escrowDeltaA`, and is the only record of what the order looked like beforehand.
- **`Token`** — one per asset seen, including native ETH. Metadata is read from the ERC20
  once, on first sight, and falls back to `UNKNOWN` / `Unknown Token` / `18` decimals if
  the call reverts. `openOrdersSelling` / `openOrdersBuying` count only fillable orders.
- **`Pair`** — directional: selling tokenA for tokenB. `tokenB -> tokenA` is a separate
  entity.
- **`Account`** — any address that has made or taken an order, with its own order and fill
  counters plus `orders`, `fillsTaken`, and `fillsReceived` collections.
- **`GlobalStats`** — board-wide totals under the id `global`.

### Notes for consumers

- `Fill.amountA` / `Fill.amountB` are what actually moved. Every fill (`fillOrder` /
  `fillOrders`, including the permit and Permit2 overloads) names an exact `amountB`, and
  `amountA` is its floored pro-rata share of the remaining tokenA. Paying the last of
  tokenB takes exactly the last of tokenA, so a `FILLED` order ends with `availableA` and
  `availableB` both `0`. Use `filledFraction` to show fill progress.
- The contract rejects a maker filling their own order, so a `Fill`'s `taker` and `maker`
  are always different accounts.
- On a `CANCELED` order, `availableA` is the amount refunded to the maker.
- `modifyOrder` resets the order's totals to the maker's new remainings — the contract
  does not preserve fill progress in `amountA`/`amountB` — so the subgraph zeroes
  `filledA`, `filledB`, and `filledFraction` and returns a `PARTIALLY_FILLED` order to
  `OPEN`. Anything showing an order's whole trading history should read `fills`,
  `fillCount`, or `lifetimeFilledA`/`lifetimeFilledB`, none of which are reset.
- A modify never opens or closes an order, so the open-order counters on `Token`, `Pair`,
  `Account`, and `GlobalStats` do not move on one — even though escrow does.
- `setPartialFillAllowed` only flips `Order.partialFillAllowed`. It stamps `modifiedAt` /
  `modifiedTx` like a modify does, but writes no `OrderModification` and leaves amounts,
  progress, and `modifyCount` alone.
- `priceBPerA` / `priceAPerB` are decimal-adjusted human-unit prices, suitable for sorting.
  They are `0` when the price is not representable (zero amount, absurd `decimals`).

## Example queries

Open orders on the board, cheapest first:

```graphql
{
  orders(where: { active: true }, orderBy: priceBPerA, orderDirection: asc, first: 50) {
    orderId
    maker { id }
    tokenA { symbol decimals }
    tokenB { symbol decimals }
    amountA
    availableA
    filledFraction
    partialFillAllowed
    priceBPerA
  }
}
```

One account's orders and fills:

```graphql
{
  account(id: "0x...") {
    ordersOpen
    fillsTakenCount
    orders(orderBy: createdAt, orderDirection: desc) { orderId status filledFraction }
    fillsTaken(orderBy: timestamp, orderDirection: desc) { orderId amountA amountB }
  }
}
```

Repricing history for one order:

```graphql
{
  order(id: "42") {
    amountA
    availableA
    lifetimeFilledA
    modifyCount
    modifications(orderBy: timestamp, orderDirection: desc) {
      previousAvailableA
      availableA
      escrowDeltaA
      previousPriceBPerA
      priceBPerA
      resetFillProgress
      timestamp
    }
  }
}
```

Recent trade history for a pair:

```graphql
{
  pair(id: "0xtokenA-0xtokenB") {
    fillCount
    volumeA
    volumeB
    fills(orderBy: timestamp, orderDirection: desc, first: 25) {
      taker { id }
      amountA
      amountB
      priceBPerA
      timestamp
    }
  }
}
```

## Development

```bash
pnpm install
pnpm codegen     # regenerate types from schema.graphql + abis/
pnpm build       # codegen + compile to build/
pnpm test        # codegen + matchstick in Docker
pnpm test:local  # codegen + matchstick natively (needs a supported platform)
```

`abis/Swapboard.json` is generated from the Foundry artifact. Regenerate it after changing
the contract:

```bash
forge inspect --root ../../contracts Swapboard abi --json > abis/Swapboard.json
```

Adding or removing an event there also means updating `eventHandlers` in `subgraph.yaml`.

`subgraph.yaml` ships a placeholder address and `startBlock: 0`; `deploy.sh` rewrites both
after the contract is deployed.

## Deployment

Hosted on [Goldsky](https://app.goldsky.com/), same as v1 (which lives at
`Swapboard/1.0.0`). v2 publishes under its own name so the two index side by side:

```bash
pnpm add -g @goldskycom/cli
export GOLDSKY_API_KEY=...        # Goldsky dashboard -> Settings -> API Keys
pnpm deploy                       # -> goldsky subgraph deploy swapboard-v2/2.0.0
```

`../../deploy.sh` does this as part of a full release, and additionally patches the
resulting query URL into `frontend/lib.js`. The frontend keeps one contract address and
one subgraph URL **per protocol version**, on `VERSION_CAPS`; each is tagged with a
`// deploy:v2:contract` / `// deploy:v2:subgraph` marker that `deploy.sh` anchors on, so
deploying v2 never disturbs the live v1 configuration. Renaming or reflowing those marker
comments will break the deploy — it fails loudly rather than silently writing nothing.
