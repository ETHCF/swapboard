/**
 * @fileoverview Swapboard v2 subgraph event handlers.
 * @description AssemblyScript handlers for indexing Swapboard v2 contract events into
 *              Order, Fill, Token, Pair, Account, and GlobalStats entities.
 * @author Zak Cole (numbergroup.xyz) for Ethereum Community Foundation
 * @license AGPL-3.0-only
 *
 * Event handlers:
 * - handleOrderCreated:  creates an Order, bumps token/pair/account/global counters
 * - handleOrderFilled:   records a Fill, decrements remaining amounts, and closes the
 *                        order once tokenA or tokenB is exhausted
 * - handleOrderCanceled: closes the order; `availableA` is what was refunded to the maker
 *
 * v2 orders may be filled in multiple parts, so `handleOrderFilled` can run several
 * times for one order (and several times in one transaction, via `fillOrders`).
 * Counters that describe "is this order still on the board" therefore only move on the
 * transition that actually closes the order.
 */

import { Address, log } from "@graphprotocol/graph-ts";
import { OrderCanceled, OrderCreated, OrderFilled } from "../generated/Swapboard/Swapboard";
import { Fill, Order, Pair, Token } from "../generated/schema";
import {
  ONE_BI,
  STATUS_CANCELED,
  STATUS_FILLED,
  STATUS_OPEN,
  STATUS_PARTIALLY_FILLED,
  ZERO_BI,
} from "./constants";
import {
  fillFraction,
  getOrCreateAccount,
  getOrCreateGlobalStats,
  getOrCreatePair,
  getOrCreateToken,
  priceOf,
} from "./helpers";

/**
 * Handles OrderCreated: records the new order and opens it on the board.
 */
export function handleOrderCreated(event: OrderCreated): void {
  let orderId = event.params.orderId;
  let id = orderId.toString();
  let timestamp = event.block.timestamp;

  let maker = getOrCreateAccount(event.params.maker, timestamp);
  let tokenA = getOrCreateToken(event.params.tokenA, timestamp);
  let tokenB = getOrCreateToken(event.params.tokenB, timestamp);
  let pair = getOrCreatePair(tokenA.id, tokenB.id);

  let amountA = event.params.amountA;
  let amountB = event.params.amountB;

  let order = new Order(id);
  order.orderId = orderId;
  order.maker = maker.id;
  order.tokenA = tokenA.id;
  order.tokenB = tokenB.id;
  order.pair = pair.id;
  order.amountA = amountA;
  order.amountB = amountB;
  order.availableA = amountA;
  order.availableB = amountB;
  order.filledA = ZERO_BI;
  order.filledB = ZERO_BI;
  order.filledFraction = fillFraction(ZERO_BI, amountA);
  order.partialFillAllowed = event.params.partialFillAllowed;
  order.status = STATUS_OPEN;
  order.active = true;
  order.priceBPerA = priceOf(amountA, tokenA.decimals, amountB, tokenB.decimals);
  order.priceAPerB = priceOf(amountB, tokenB.decimals, amountA, tokenA.decimals);
  order.fillCount = 0;
  order.createdAt = timestamp;
  order.createdBlock = event.block.number;
  order.createdTx = event.transaction.hash;
  order.updatedAt = timestamp;
  order.filledAt = null;
  order.filledTx = null;
  order.canceledAt = null;
  order.canceledTx = null;
  order.save();

  tokenA.ordersSelling = tokenA.ordersSelling.plus(ONE_BI);
  tokenA.openOrdersSelling = tokenA.openOrdersSelling.plus(ONE_BI);
  tokenA.save();

  tokenB.ordersBuying = tokenB.ordersBuying.plus(ONE_BI);
  tokenB.openOrdersBuying = tokenB.openOrdersBuying.plus(ONE_BI);
  tokenB.save();

  pair.orderCount = pair.orderCount.plus(ONE_BI);
  pair.openOrderCount = pair.openOrderCount.plus(ONE_BI);
  pair.save();

  maker.ordersCreated = maker.ordersCreated.plus(ONE_BI);
  maker.ordersOpen = maker.ordersOpen.plus(ONE_BI);
  maker.save();

  // Loaded last: the getOrCreate* helpers above bump cardinality counters on GlobalStats.
  let stats = getOrCreateGlobalStats();
  stats.totalOrders = stats.totalOrders.plus(ONE_BI);
  stats.openOrders = stats.openOrders.plus(ONE_BI);
  stats.updatedAt = timestamp;
  stats.save();

  log.info("Order {} created by {} - selling {} {} for {} {}", [
    id,
    maker.id,
    amountA.toString(),
    tokenA.symbol,
    amountB.toString(),
    tokenB.symbol,
  ]);
}

/**
 * Handles OrderFilled: records the fill and, when the order runs out of tokenA or
 * tokenB, takes it off the board.
 *
 * The contract closes an order as soon as either side is exhausted, so tokenA dust
 * left on a closed order is expected and stays visible in `availableA`.
 */
export function handleOrderFilled(event: OrderFilled): void {
  let id = event.params.orderId.toString();
  let order = Order.load(id);
  if (order == null) {
    log.error("OrderFilled: order {} not found", [id]);
    return;
  }

  let tokenA = Token.load(order.tokenA);
  let tokenB = Token.load(order.tokenB);
  let pair = Pair.load(order.pair);
  if (tokenA == null || tokenB == null || pair == null) {
    log.error("OrderFilled: missing token or pair entity for order {}", [id]);
    return;
  }

  let timestamp = event.block.timestamp;
  let amountA = event.params.amountA;
  let amountB = event.params.amountB;

  order.availableA = order.availableA.minus(amountA);
  order.availableB = order.availableB.minus(amountB);
  order.filledA = order.filledA.plus(amountA);
  order.filledB = order.filledB.plus(amountB);
  order.filledFraction = fillFraction(order.filledA, order.amountA);
  order.fillCount = order.fillCount + 1;
  order.updatedAt = timestamp;

  let closed = order.availableA.equals(ZERO_BI) || order.availableB.equals(ZERO_BI);
  let wasPartiallyFilled = order.status == STATUS_PARTIALLY_FILLED;

  if (closed) {
    order.status = STATUS_FILLED;
    order.active = false;
    order.filledAt = timestamp;
    order.filledTx = event.transaction.hash;
  } else {
    order.status = STATUS_PARTIALLY_FILLED;
  }
  order.save();

  let taker = getOrCreateAccount(event.params.taker, timestamp);

  let fill = new Fill(event.transaction.hash.toHexString() + "-" + event.logIndex.toString());
  fill.order = order.id;
  fill.orderId = order.orderId;
  fill.taker = taker.id;
  fill.maker = order.maker;
  fill.tokenA = tokenA.id;
  fill.tokenB = tokenB.id;
  fill.pair = pair.id;
  fill.amountA = amountA;
  fill.amountB = amountB;
  fill.priceBPerA = priceOf(amountA, tokenA.decimals, amountB, tokenB.decimals);
  fill.remainingA = order.availableA;
  fill.remainingB = order.availableB;
  fill.closedOrder = closed;
  fill.timestamp = timestamp;
  fill.blockNumber = event.block.number;
  fill.transactionHash = event.transaction.hash;
  fill.logIndex = event.logIndex;
  fill.save();

  tokenA.volumeSold = tokenA.volumeSold.plus(amountA);
  tokenA.fillCount = tokenA.fillCount.plus(ONE_BI);
  tokenB.volumeBought = tokenB.volumeBought.plus(amountB);
  tokenB.fillCount = tokenB.fillCount.plus(ONE_BI);

  pair.fillCount = pair.fillCount.plus(ONE_BI);
  pair.volumeA = pair.volumeA.plus(amountA);
  pair.volumeB = pair.volumeB.plus(amountB);
  pair.lastTradeAt = timestamp;

  if (closed) {
    tokenA.openOrdersSelling = tokenA.openOrdersSelling.minus(ONE_BI);
    tokenB.openOrdersBuying = tokenB.openOrdersBuying.minus(ONE_BI);
    pair.openOrderCount = pair.openOrderCount.minus(ONE_BI);
    pair.filledOrderCount = pair.filledOrderCount.plus(ONE_BI);
  }

  tokenA.save();
  tokenB.save();
  pair.save();

  taker.fillsTakenCount = taker.fillsTakenCount.plus(ONE_BI);
  taker.save();

  // Reloaded after the taker is saved so a maker filling their own order still sees
  // both increments.
  let maker = getOrCreateAccount(Address.fromString(order.maker), timestamp);
  maker.fillsReceivedCount = maker.fillsReceivedCount.plus(ONE_BI);
  if (closed) {
    maker.ordersOpen = maker.ordersOpen.minus(ONE_BI);
    maker.ordersFilled = maker.ordersFilled.plus(ONE_BI);
  }
  maker.save();

  let stats = getOrCreateGlobalStats();
  stats.totalFills = stats.totalFills.plus(ONE_BI);
  if (closed) {
    stats.openOrders = stats.openOrders.minus(ONE_BI);
    stats.filledOrders = stats.filledOrders.plus(ONE_BI);
    if (wasPartiallyFilled) {
      stats.partiallyFilledOrders = stats.partiallyFilledOrders.minus(ONE_BI);
    }
  } else if (!wasPartiallyFilled) {
    stats.partiallyFilledOrders = stats.partiallyFilledOrders.plus(ONE_BI);
  }
  stats.updatedAt = timestamp;
  stats.save();

  log.info("Order {} filled by {} for {} of {} tokenA ({})", [
    id,
    taker.id,
    amountA.toString(),
    order.amountA.toString(),
    closed ? "closed" : "partial",
  ]);
}

/**
 * Handles OrderCanceled: takes the order off the board. The contract refunds the maker
 * whatever tokenA was still in escrow, which is the order's `availableA`.
 */
export function handleOrderCanceled(event: OrderCanceled): void {
  let id = event.params.orderId.toString();
  let order = Order.load(id);
  if (order == null) {
    log.error("OrderCanceled: order {} not found", [id]);
    return;
  }

  let timestamp = event.block.timestamp;
  let wasPartiallyFilled = order.status == STATUS_PARTIALLY_FILLED;

  order.status = STATUS_CANCELED;
  order.active = false;
  order.canceledAt = timestamp;
  order.canceledTx = event.transaction.hash;
  order.updatedAt = timestamp;
  order.save();

  let tokenA = Token.load(order.tokenA);
  if (tokenA != null) {
    tokenA.openOrdersSelling = tokenA.openOrdersSelling.minus(ONE_BI);
    tokenA.save();
  } else {
    log.error("OrderCanceled: tokenA {} not found for order {}", [order.tokenA, id]);
  }

  let tokenB = Token.load(order.tokenB);
  if (tokenB != null) {
    tokenB.openOrdersBuying = tokenB.openOrdersBuying.minus(ONE_BI);
    tokenB.save();
  } else {
    log.error("OrderCanceled: tokenB {} not found for order {}", [order.tokenB, id]);
  }

  let pair = Pair.load(order.pair);
  if (pair != null) {
    pair.openOrderCount = pair.openOrderCount.minus(ONE_BI);
    pair.canceledOrderCount = pair.canceledOrderCount.plus(ONE_BI);
    pair.save();
  } else {
    log.error("OrderCanceled: pair {} not found for order {}", [order.pair, id]);
  }

  let maker = getOrCreateAccount(Address.fromString(order.maker), timestamp);
  maker.ordersOpen = maker.ordersOpen.minus(ONE_BI);
  maker.ordersCanceled = maker.ordersCanceled.plus(ONE_BI);
  maker.save();

  let stats = getOrCreateGlobalStats();
  stats.openOrders = stats.openOrders.minus(ONE_BI);
  stats.canceledOrders = stats.canceledOrders.plus(ONE_BI);
  if (wasPartiallyFilled) {
    stats.partiallyFilledOrders = stats.partiallyFilledOrders.minus(ONE_BI);
  }
  stats.updatedAt = timestamp;
  stats.save();

  log.info("Order {} canceled, {} tokenA refunded", [id, order.availableA.toString()]);
}
