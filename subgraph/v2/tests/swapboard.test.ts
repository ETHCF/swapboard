/**
 * @fileoverview Matchstick unit tests for the Swapboard v2 subgraph handlers.
 * @author Zak Cole (numbergroup.xyz) for Ethereum Community Foundation
 * @license AGPL-3.0-only
 */

import {
  afterAll,
  assert,
  beforeEach,
  clearStore,
  createMockedFunction,
  describe,
  newMockEvent,
  test,
} from "matchstick-as/assembly/index";
import { Address, BigInt, ethereum } from "@graphprotocol/graph-ts";
import { handleOrderCanceled, handleOrderCreated, handleOrderFilled } from "../src/mapping";
import { OrderCanceled, OrderCreated, OrderFilled } from "../generated/Swapboard/Swapboard";
import { Order } from "../generated/schema";

const TKA_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
const TKB_ADDRESS = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
const TKC_ADDRESS = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
const BROKEN_ADDRESS = "0x1111111111111111111111111111111111111111";
const ETH_ADDRESS = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
const MAKER_ADDRESS = "0x1234567890123456789012345678901234567890";
const TAKER_ADDRESS = "0x0987654321098765432109876543210987654321";

const TKA = TKA_ADDRESS.toLowerCase();
const TKB = TKB_ADDRESS.toLowerCase();
const TKC = TKC_ADDRESS.toLowerCase();
const ETH = ETH_ADDRESS.toLowerCase();
const MAKER = MAKER_ADDRESS.toLowerCase();
const TAKER = TAKER_ADDRESS.toLowerCase();

/** 100 TKA (18 decimals) */
const HUNDRED_A = "100000000000000000000";
/** 200 TKB (6 decimals) */
const TWO_HUNDRED_B = "200000000";
/** 1000 TKA */
const THOUSAND_A = "1000000000000000000000";
/** 500 TKB */
const FIVE_HUNDRED_B = "500000000";
/** 250 TKA */
const QUARTER_A = "250000000000000000000";
/** 125 TKB */
const QUARTER_B = "125000000";
/** 750 TKA */
const REST_A = "750000000000000000000";
/** 375 TKB */
const REST_B = "375000000";

const PAIR_AB = TKA + "-" + TKB;

function mockERC20(address: string, symbol: string, name: string, decimals: i32): void {
  let addr = Address.fromString(address);
  createMockedFunction(addr, "symbol", "symbol():(string)").returns([ethereum.Value.fromString(symbol)]);
  createMockedFunction(addr, "name", "name():(string)").returns([ethereum.Value.fromString(name)]);
  createMockedFunction(addr, "decimals", "decimals():(uint8)").returns([ethereum.Value.fromI32(decimals)]);
}

function mockERC20Reverts(address: string): void {
  let addr = Address.fromString(address);
  createMockedFunction(addr, "symbol", "symbol():(string)").reverts();
  createMockedFunction(addr, "name", "name():(string)").reverts();
  createMockedFunction(addr, "decimals", "decimals():(uint8)").reverts();
}

/** Mocks the tokens used across most tests: TKA/18, TKB/6, TKC/18. */
function mockTokens(): void {
  mockERC20(TKA_ADDRESS, "TKA", "Token A", 18);
  mockERC20(TKB_ADDRESS, "TKB", "Token B", 6);
  mockERC20(TKC_ADDRESS, "TKC", "Token C", 18);
}

function createOrderCreatedEvent(
  orderId: i32,
  maker: string,
  tokenA: string,
  amountA: string,
  tokenB: string,
  amountB: string,
  partialFillAllowed: boolean
): OrderCreated {
  let event = changetype<OrderCreated>(newMockEvent());
  event.parameters = new Array();

  event.parameters.push(
    new ethereum.EventParam("orderId", ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(orderId)))
  );
  event.parameters.push(new ethereum.EventParam("maker", ethereum.Value.fromAddress(Address.fromString(maker))));
  event.parameters.push(new ethereum.EventParam("tokenA", ethereum.Value.fromAddress(Address.fromString(tokenA))));
  event.parameters.push(
    new ethereum.EventParam("amountA", ethereum.Value.fromUnsignedBigInt(BigInt.fromString(amountA)))
  );
  event.parameters.push(new ethereum.EventParam("tokenB", ethereum.Value.fromAddress(Address.fromString(tokenB))));
  event.parameters.push(
    new ethereum.EventParam("amountB", ethereum.Value.fromUnsignedBigInt(BigInt.fromString(amountB)))
  );
  event.parameters.push(
    new ethereum.EventParam("partialFillAllowed", ethereum.Value.fromBoolean(partialFillAllowed))
  );

  return event;
}

function createOrderFilledEvent(
  orderId: i32,
  taker: string,
  amountA: string,
  amountB: string,
  logIndex: i32
): OrderFilled {
  let event = changetype<OrderFilled>(newMockEvent());
  event.parameters = new Array();
  event.logIndex = BigInt.fromI32(logIndex);

  event.parameters.push(
    new ethereum.EventParam("orderId", ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(orderId)))
  );
  event.parameters.push(new ethereum.EventParam("taker", ethereum.Value.fromAddress(Address.fromString(taker))));
  event.parameters.push(
    new ethereum.EventParam("amountA", ethereum.Value.fromUnsignedBigInt(BigInt.fromString(amountA)))
  );
  event.parameters.push(
    new ethereum.EventParam("amountB", ethereum.Value.fromUnsignedBigInt(BigInt.fromString(amountB)))
  );

  return event;
}

function createOrderCanceledEvent(orderId: i32): OrderCanceled {
  let event = changetype<OrderCanceled>(newMockEvent());
  event.parameters = new Array();

  event.parameters.push(
    new ethereum.EventParam("orderId", ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(orderId)))
  );

  return event;
}

/** Creates order 0: 100 TKA for 200 TKB, full fills only. */
function createFullFillOrder(): OrderCreated {
  let event = createOrderCreatedEvent(0, MAKER_ADDRESS, TKA_ADDRESS, HUNDRED_A, TKB_ADDRESS, TWO_HUNDRED_B, false);
  handleOrderCreated(event);
  return event;
}

/** Creates order 1: 1000 TKA for 500 TKB, partial fills allowed. */
function createPartialFillOrder(): OrderCreated {
  let event = createOrderCreatedEvent(1, MAKER_ADDRESS, TKA_ADDRESS, THOUSAND_A, TKB_ADDRESS, FIVE_HUNDRED_B, true);
  handleOrderCreated(event);
  return event;
}

describe("handleOrderCreated", () => {
  beforeEach(() => {
    clearStore();
    mockTokens();
  });

  afterAll(() => {
    clearStore();
  });

  test("stores the order with full amounts available", () => {
    let event = createFullFillOrder();

    assert.entityCount("Order", 1);
    assert.fieldEquals("Order", "0", "orderId", "0");
    assert.fieldEquals("Order", "0", "maker", MAKER);
    assert.fieldEquals("Order", "0", "tokenA", TKA);
    assert.fieldEquals("Order", "0", "tokenB", TKB);
    assert.fieldEquals("Order", "0", "pair", PAIR_AB);
    assert.fieldEquals("Order", "0", "amountA", HUNDRED_A);
    assert.fieldEquals("Order", "0", "amountB", TWO_HUNDRED_B);
    assert.fieldEquals("Order", "0", "availableA", HUNDRED_A);
    assert.fieldEquals("Order", "0", "availableB", TWO_HUNDRED_B);
    assert.fieldEquals("Order", "0", "filledA", "0");
    assert.fieldEquals("Order", "0", "filledB", "0");
    assert.fieldEquals("Order", "0", "filledFraction", "0");
    assert.fieldEquals("Order", "0", "fillCount", "0");
    assert.fieldEquals("Order", "0", "partialFillAllowed", "false");
    assert.fieldEquals("Order", "0", "status", "OPEN");
    assert.fieldEquals("Order", "0", "active", "true");
    assert.fieldEquals("Order", "0", "createdAt", event.block.timestamp.toString());
    assert.fieldEquals("Order", "0", "createdBlock", event.block.number.toString());
    assert.fieldEquals("Order", "0", "createdTx", event.transaction.hash.toHexString());
    assert.fieldEquals("Order", "0", "updatedAt", event.block.timestamp.toString());
  });

  test("records the partialFillAllowed flag", () => {
    createPartialFillOrder();

    assert.fieldEquals("Order", "1", "partialFillAllowed", "true");
  });

  test("leaves fill and cancel fields unset", () => {
    createFullFillOrder();

    let order = Order.load("0");
    assert.assertNotNull(order);
    assert.assertTrue(order!.filledAt === null);
    assert.assertTrue(order!.filledTx === null);
    assert.assertTrue(order!.canceledAt === null);
    assert.assertTrue(order!.canceledTx === null);
  });

  test("prices the order in both directions using token decimals", () => {
    // 100 TKA (18 decimals) for 200 TKB (6 decimals) => 2 TKB per TKA.
    createFullFillOrder();

    assert.fieldEquals("Order", "0", "priceBPerA", "2");
    assert.fieldEquals("Order", "0", "priceAPerB", "0.5");
  });

  test("creates both tokens with metadata from the contract", () => {
    createFullFillOrder();

    assert.entityCount("Token", 2);
    assert.fieldEquals("Token", TKA, "symbol", "TKA");
    assert.fieldEquals("Token", TKA, "name", "Token A");
    assert.fieldEquals("Token", TKA, "decimals", "18");
    assert.fieldEquals("Token", TKA, "address", TKA);
    assert.fieldEquals("Token", TKA, "isNative", "false");
    assert.fieldEquals("Token", TKB, "symbol", "TKB");
    assert.fieldEquals("Token", TKB, "decimals", "6");
  });

  test("falls back to placeholder metadata when the token reverts", () => {
    mockERC20Reverts(BROKEN_ADDRESS);
    handleOrderCreated(
      createOrderCreatedEvent(0, MAKER_ADDRESS, BROKEN_ADDRESS, HUNDRED_A, TKB_ADDRESS, TWO_HUNDRED_B, false)
    );

    let broken = BROKEN_ADDRESS.toLowerCase();
    assert.fieldEquals("Token", broken, "symbol", "UNKNOWN");
    assert.fieldEquals("Token", broken, "name", "Unknown Token");
    assert.fieldEquals("Token", broken, "decimals", "18");
  });

  test("models the ETH sentinel as a native token without contract calls", () => {
    handleOrderCreated(
      createOrderCreatedEvent(0, MAKER_ADDRESS, ETH_ADDRESS, "1000000000000000000", TKA_ADDRESS, HUNDRED_A, false)
    );

    assert.fieldEquals("Token", ETH, "symbol", "ETH");
    assert.fieldEquals("Token", ETH, "name", "Ether");
    assert.fieldEquals("Token", ETH, "decimals", "18");
    assert.fieldEquals("Token", ETH, "isNative", "true");
    assert.fieldEquals("Order", "0", "priceBPerA", "100");
  });

  test("counts open orders per token side", () => {
    createFullFillOrder();
    createPartialFillOrder();

    assert.fieldEquals("Token", TKA, "ordersSelling", "2");
    assert.fieldEquals("Token", TKA, "openOrdersSelling", "2");
    assert.fieldEquals("Token", TKA, "ordersBuying", "0");
    assert.fieldEquals("Token", TKB, "ordersBuying", "2");
    assert.fieldEquals("Token", TKB, "openOrdersBuying", "2");
    assert.fieldEquals("Token", TKB, "ordersSelling", "0");
  });

  test("creates one directional pair per token ordering", () => {
    createFullFillOrder();
    handleOrderCreated(
      createOrderCreatedEvent(1, MAKER_ADDRESS, TKB_ADDRESS, TWO_HUNDRED_B, TKA_ADDRESS, HUNDRED_A, false)
    );

    assert.entityCount("Pair", 2);
    assert.fieldEquals("Pair", PAIR_AB, "orderCount", "1");
    assert.fieldEquals("Pair", PAIR_AB, "openOrderCount", "1");
    assert.fieldEquals("Pair", TKB + "-" + TKA, "orderCount", "1");
  });

  test("reuses the pair across orders", () => {
    createFullFillOrder();
    createPartialFillOrder();

    assert.entityCount("Pair", 1);
    assert.fieldEquals("Pair", PAIR_AB, "orderCount", "2");
    assert.fieldEquals("Pair", PAIR_AB, "openOrderCount", "2");
    assert.fieldEquals("Pair", PAIR_AB, "fillCount", "0");
  });

  test("creates the maker account and counts its open orders", () => {
    let event = createFullFillOrder();
    createPartialFillOrder();

    assert.entityCount("Account", 1);
    assert.fieldEquals("Account", MAKER, "address", MAKER);
    assert.fieldEquals("Account", MAKER, "ordersCreated", "2");
    assert.fieldEquals("Account", MAKER, "ordersOpen", "2");
    assert.fieldEquals("Account", MAKER, "ordersFilled", "0");
    assert.fieldEquals("Account", MAKER, "ordersCanceled", "0");
    assert.fieldEquals("Account", MAKER, "firstSeenAt", event.block.timestamp.toString());
  });

  test("updates global stats", () => {
    createFullFillOrder();
    createPartialFillOrder();

    assert.fieldEquals("GlobalStats", "global", "totalOrders", "2");
    assert.fieldEquals("GlobalStats", "global", "openOrders", "2");
    assert.fieldEquals("GlobalStats", "global", "partiallyFilledOrders", "0");
    assert.fieldEquals("GlobalStats", "global", "filledOrders", "0");
    assert.fieldEquals("GlobalStats", "global", "canceledOrders", "0");
    assert.fieldEquals("GlobalStats", "global", "totalFills", "0");
    assert.fieldEquals("GlobalStats", "global", "totalTokens", "2");
    assert.fieldEquals("GlobalStats", "global", "totalPairs", "1");
    assert.fieldEquals("GlobalStats", "global", "totalAccounts", "1");
  });
});

describe("handleOrderFilled", () => {
  beforeEach(() => {
    clearStore();
    mockTokens();
  });

  afterAll(() => {
    clearStore();
  });

  test("closes an order filled in full", () => {
    createFullFillOrder();
    let fill = createOrderFilledEvent(0, TAKER_ADDRESS, HUNDRED_A, TWO_HUNDRED_B, 1);
    handleOrderFilled(fill);

    assert.fieldEquals("Order", "0", "status", "FILLED");
    assert.fieldEquals("Order", "0", "active", "false");
    assert.fieldEquals("Order", "0", "availableA", "0");
    assert.fieldEquals("Order", "0", "availableB", "0");
    assert.fieldEquals("Order", "0", "filledA", HUNDRED_A);
    assert.fieldEquals("Order", "0", "filledB", TWO_HUNDRED_B);
    assert.fieldEquals("Order", "0", "filledFraction", "1");
    assert.fieldEquals("Order", "0", "fillCount", "1");
    assert.fieldEquals("Order", "0", "filledAt", fill.block.timestamp.toString());
    assert.fieldEquals("Order", "0", "filledTx", fill.transaction.hash.toHexString());
  });

  test("keeps a partially filled order fillable", () => {
    createPartialFillOrder();
    handleOrderFilled(createOrderFilledEvent(1, TAKER_ADDRESS, QUARTER_A, QUARTER_B, 1));

    assert.fieldEquals("Order", "1", "status", "PARTIALLY_FILLED");
    assert.fieldEquals("Order", "1", "active", "true");
    assert.fieldEquals("Order", "1", "availableA", REST_A);
    assert.fieldEquals("Order", "1", "availableB", REST_B);
    assert.fieldEquals("Order", "1", "filledA", QUARTER_A);
    assert.fieldEquals("Order", "1", "filledB", QUARTER_B);
    assert.fieldEquals("Order", "1", "filledFraction", "0.25");
    assert.fieldEquals("Order", "1", "fillCount", "1");

    let order = Order.load("1");
    assert.assertNotNull(order);
    assert.assertTrue(order!.filledAt === null);
  });

  test("closes the order once the remainder is filled", () => {
    createPartialFillOrder();
    handleOrderFilled(createOrderFilledEvent(1, TAKER_ADDRESS, QUARTER_A, QUARTER_B, 1));
    handleOrderFilled(createOrderFilledEvent(1, TAKER_ADDRESS, REST_A, REST_B, 2));

    assert.fieldEquals("Order", "1", "status", "FILLED");
    assert.fieldEquals("Order", "1", "active", "false");
    assert.fieldEquals("Order", "1", "availableA", "0");
    assert.fieldEquals("Order", "1", "availableB", "0");
    assert.fieldEquals("Order", "1", "filledFraction", "1");
    assert.fieldEquals("Order", "1", "fillCount", "2");
    assert.entityCount("Fill", 2);
  });

  test("closes the order when tokenB is exhausted but tokenA dust remains", () => {
    createPartialFillOrder();
    // Ceiled tokenB payment consumes the whole tokenB side while tokenA dust is left behind.
    handleOrderFilled(createOrderFilledEvent(1, TAKER_ADDRESS, REST_A, FIVE_HUNDRED_B, 1));

    assert.fieldEquals("Order", "1", "status", "FILLED");
    assert.fieldEquals("Order", "1", "active", "false");
    assert.fieldEquals("Order", "1", "availableB", "0");
    assert.fieldEquals("Order", "1", "availableA", QUARTER_A);
    assert.fieldEquals("Order", "1", "filledFraction", "0.75");
  });

  test("records a Fill per event", () => {
    createPartialFillOrder();
    let event = createOrderFilledEvent(1, TAKER_ADDRESS, QUARTER_A, QUARTER_B, 3);
    handleOrderFilled(event);

    let fillId = event.transaction.hash.toHexString() + "-3";
    assert.entityCount("Fill", 1);
    assert.fieldEquals("Fill", fillId, "order", "1");
    assert.fieldEquals("Fill", fillId, "orderId", "1");
    assert.fieldEquals("Fill", fillId, "taker", TAKER);
    assert.fieldEquals("Fill", fillId, "maker", MAKER);
    assert.fieldEquals("Fill", fillId, "tokenA", TKA);
    assert.fieldEquals("Fill", fillId, "tokenB", TKB);
    assert.fieldEquals("Fill", fillId, "pair", PAIR_AB);
    assert.fieldEquals("Fill", fillId, "amountA", QUARTER_A);
    assert.fieldEquals("Fill", fillId, "amountB", QUARTER_B);
    assert.fieldEquals("Fill", fillId, "priceBPerA", "0.5");
    assert.fieldEquals("Fill", fillId, "remainingA", REST_A);
    assert.fieldEquals("Fill", fillId, "remainingB", REST_B);
    assert.fieldEquals("Fill", fillId, "closedOrder", "false");
    assert.fieldEquals("Fill", fillId, "timestamp", event.block.timestamp.toString());
    assert.fieldEquals("Fill", fillId, "blockNumber", event.block.number.toString());
    assert.fieldEquals("Fill", fillId, "transactionHash", event.transaction.hash.toHexString());
    assert.fieldEquals("Fill", fillId, "logIndex", "3");
  });

  test("keeps batch fills in the same transaction distinct", () => {
    createFullFillOrder();
    createPartialFillOrder();
    handleOrderFilled(createOrderFilledEvent(0, TAKER_ADDRESS, HUNDRED_A, TWO_HUNDRED_B, 1));
    handleOrderFilled(createOrderFilledEvent(1, TAKER_ADDRESS, QUARTER_A, QUARTER_B, 2));

    assert.entityCount("Fill", 2);
    assert.fieldEquals("GlobalStats", "global", "totalFills", "2");
  });

  test("accrues token volume per fill, not per order", () => {
    createPartialFillOrder();
    handleOrderFilled(createOrderFilledEvent(1, TAKER_ADDRESS, QUARTER_A, QUARTER_B, 1));

    assert.fieldEquals("Token", TKA, "volumeSold", QUARTER_A);
    assert.fieldEquals("Token", TKA, "volumeBought", "0");
    assert.fieldEquals("Token", TKA, "fillCount", "1");
    assert.fieldEquals("Token", TKB, "volumeBought", QUARTER_B);
    assert.fieldEquals("Token", TKB, "volumeSold", "0");
    assert.fieldEquals("Token", TKB, "fillCount", "1");
  });

  test("holds open order counts until the order closes", () => {
    createPartialFillOrder();
    handleOrderFilled(createOrderFilledEvent(1, TAKER_ADDRESS, QUARTER_A, QUARTER_B, 1));

    assert.fieldEquals("Token", TKA, "openOrdersSelling", "1");
    assert.fieldEquals("Token", TKB, "openOrdersBuying", "1");
    assert.fieldEquals("Pair", PAIR_AB, "openOrderCount", "1");
    assert.fieldEquals("Pair", PAIR_AB, "filledOrderCount", "0");
    assert.fieldEquals("Account", MAKER, "ordersOpen", "1");
    assert.fieldEquals("GlobalStats", "global", "openOrders", "1");
    assert.fieldEquals("GlobalStats", "global", "partiallyFilledOrders", "1");
    assert.fieldEquals("GlobalStats", "global", "filledOrders", "0");

    handleOrderFilled(createOrderFilledEvent(1, TAKER_ADDRESS, REST_A, REST_B, 2));

    assert.fieldEquals("Token", TKA, "openOrdersSelling", "0");
    assert.fieldEquals("Token", TKB, "openOrdersBuying", "0");
    assert.fieldEquals("Pair", PAIR_AB, "openOrderCount", "0");
    assert.fieldEquals("Pair", PAIR_AB, "filledOrderCount", "1");
    assert.fieldEquals("Account", MAKER, "ordersOpen", "0");
    assert.fieldEquals("Account", MAKER, "ordersFilled", "1");
    assert.fieldEquals("GlobalStats", "global", "openOrders", "0");
    assert.fieldEquals("GlobalStats", "global", "partiallyFilledOrders", "0");
    assert.fieldEquals("GlobalStats", "global", "filledOrders", "1");
  });

  test("accumulates pair trade volume", () => {
    createPartialFillOrder();
    let event = createOrderFilledEvent(1, TAKER_ADDRESS, QUARTER_A, QUARTER_B, 1);
    handleOrderFilled(event);
    handleOrderFilled(createOrderFilledEvent(1, TAKER_ADDRESS, QUARTER_A, QUARTER_B, 2));

    assert.fieldEquals("Pair", PAIR_AB, "fillCount", "2");
    assert.fieldEquals("Pair", PAIR_AB, "volumeA", "500000000000000000000");
    assert.fieldEquals("Pair", PAIR_AB, "volumeB", "250000000");
    assert.fieldEquals("Pair", PAIR_AB, "lastTradeAt", event.block.timestamp.toString());
  });

  test("counts fills for taker and maker accounts", () => {
    createFullFillOrder();
    handleOrderFilled(createOrderFilledEvent(0, TAKER_ADDRESS, HUNDRED_A, TWO_HUNDRED_B, 1));

    assert.entityCount("Account", 2);
    assert.fieldEquals("Account", TAKER, "fillsTakenCount", "1");
    assert.fieldEquals("Account", TAKER, "fillsReceivedCount", "0");
    assert.fieldEquals("Account", TAKER, "ordersCreated", "0");
    assert.fieldEquals("Account", MAKER, "fillsReceivedCount", "1");
    assert.fieldEquals("Account", MAKER, "fillsTakenCount", "0");
    assert.fieldEquals("GlobalStats", "global", "totalAccounts", "2");
  });

  test("counts both sides when the maker fills their own order", () => {
    createFullFillOrder();
    handleOrderFilled(createOrderFilledEvent(0, MAKER_ADDRESS, HUNDRED_A, TWO_HUNDRED_B, 1));

    assert.entityCount("Account", 1);
    assert.fieldEquals("Account", MAKER, "fillsTakenCount", "1");
    assert.fieldEquals("Account", MAKER, "fillsReceivedCount", "1");
    assert.fieldEquals("Account", MAKER, "ordersFilled", "1");
    assert.fieldEquals("Account", MAKER, "ordersOpen", "0");
  });

  test("ignores fills for orders that were never indexed", () => {
    handleOrderFilled(createOrderFilledEvent(42, TAKER_ADDRESS, HUNDRED_A, TWO_HUNDRED_B, 1));

    assert.entityCount("Order", 0);
    assert.entityCount("Fill", 0);
  });
});

describe("handleOrderCanceled", () => {
  beforeEach(() => {
    clearStore();
    mockTokens();
  });

  afterAll(() => {
    clearStore();
  });

  test("closes an untouched order and reports the refund", () => {
    createFullFillOrder();
    let event = createOrderCanceledEvent(0);
    handleOrderCanceled(event);

    assert.fieldEquals("Order", "0", "status", "CANCELED");
    assert.fieldEquals("Order", "0", "active", "false");
    assert.fieldEquals("Order", "0", "availableA", HUNDRED_A);
    assert.fieldEquals("Order", "0", "filledA", "0");
    assert.fieldEquals("Order", "0", "canceledAt", event.block.timestamp.toString());
    assert.fieldEquals("Order", "0", "canceledTx", event.transaction.hash.toHexString());
  });

  test("cancels a partially filled order and keeps the filled amounts", () => {
    createPartialFillOrder();
    handleOrderFilled(createOrderFilledEvent(1, TAKER_ADDRESS, QUARTER_A, QUARTER_B, 1));
    handleOrderCanceled(createOrderCanceledEvent(1));

    assert.fieldEquals("Order", "1", "status", "CANCELED");
    assert.fieldEquals("Order", "1", "active", "false");
    assert.fieldEquals("Order", "1", "filledA", QUARTER_A);
    assert.fieldEquals("Order", "1", "availableA", REST_A);
    assert.fieldEquals("Order", "1", "filledFraction", "0.25");
    assert.fieldEquals("GlobalStats", "global", "partiallyFilledOrders", "0");
  });

  test("releases open counts on every entity", () => {
    createFullFillOrder();
    handleOrderCanceled(createOrderCanceledEvent(0));

    assert.fieldEquals("Token", TKA, "openOrdersSelling", "0");
    assert.fieldEquals("Token", TKA, "ordersSelling", "1");
    assert.fieldEquals("Token", TKB, "openOrdersBuying", "0");
    assert.fieldEquals("Pair", PAIR_AB, "openOrderCount", "0");
    assert.fieldEquals("Pair", PAIR_AB, "canceledOrderCount", "1");
    assert.fieldEquals("Account", MAKER, "ordersOpen", "0");
    assert.fieldEquals("Account", MAKER, "ordersCanceled", "1");
    assert.fieldEquals("GlobalStats", "global", "openOrders", "0");
    assert.fieldEquals("GlobalStats", "global", "canceledOrders", "1");
  });

  test("leaves other open orders alone", () => {
    createFullFillOrder();
    createPartialFillOrder();
    handleOrderCanceled(createOrderCanceledEvent(0));

    assert.fieldEquals("Order", "1", "status", "OPEN");
    assert.fieldEquals("Token", TKA, "openOrdersSelling", "1");
    assert.fieldEquals("Pair", PAIR_AB, "openOrderCount", "1");
    assert.fieldEquals("GlobalStats", "global", "openOrders", "1");
  });

  test("ignores cancels for orders that were never indexed", () => {
    handleOrderCanceled(createOrderCanceledEvent(42));

    assert.entityCount("Order", 0);
  });
});

describe("multi-token board", () => {
  beforeEach(() => {
    clearStore();
    mockTokens();
  });

  afterAll(() => {
    clearStore();
  });

  test("tracks tokens, pairs, and accounts across a mixed order flow", () => {
    createFullFillOrder();
    createPartialFillOrder();
    handleOrderCreated(
      createOrderCreatedEvent(2, TAKER_ADDRESS, TKC_ADDRESS, HUNDRED_A, TKA_ADDRESS, HUNDRED_A, true)
    );

    handleOrderFilled(createOrderFilledEvent(0, TAKER_ADDRESS, HUNDRED_A, TWO_HUNDRED_B, 1));
    handleOrderFilled(createOrderFilledEvent(1, TAKER_ADDRESS, QUARTER_A, QUARTER_B, 2));
    handleOrderCanceled(createOrderCanceledEvent(2));

    assert.entityCount("Order", 3);
    assert.entityCount("Fill", 2);
    assert.entityCount("Token", 3);
    assert.entityCount("Pair", 2);
    assert.entityCount("Account", 2);

    assert.fieldEquals("GlobalStats", "global", "totalOrders", "3");
    assert.fieldEquals("GlobalStats", "global", "openOrders", "1");
    assert.fieldEquals("GlobalStats", "global", "partiallyFilledOrders", "1");
    assert.fieldEquals("GlobalStats", "global", "filledOrders", "1");
    assert.fieldEquals("GlobalStats", "global", "canceledOrders", "1");
    assert.fieldEquals("GlobalStats", "global", "totalFills", "2");
    assert.fieldEquals("GlobalStats", "global", "totalTokens", "3");
    assert.fieldEquals("GlobalStats", "global", "totalPairs", "2");
    assert.fieldEquals("GlobalStats", "global", "totalAccounts", "2");

    assert.fieldEquals("Token", TKC, "openOrdersSelling", "0");
    assert.fieldEquals("Token", TKA, "openOrdersSelling", "1");
    assert.fieldEquals("Token", TKA, "openOrdersBuying", "0");
    assert.fieldEquals("Account", TAKER, "ordersCreated", "1");
    assert.fieldEquals("Account", TAKER, "ordersCanceled", "1");
    assert.fieldEquals("Account", TAKER, "fillsTakenCount", "2");
  });
});
