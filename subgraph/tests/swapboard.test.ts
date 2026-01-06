import {
  assert,
  describe,
  test,
  clearStore,
  afterAll,
  beforeEach,
  createMockedFunction,
} from "matchstick-as/assembly/index";
import { Address, BigInt, Bytes, ethereum } from "@graphprotocol/graph-ts";
import { handleOrderCreated, handleOrderFilled, handleOrderCanceled } from "../src/mapping";
import { OrderCreated, OrderFilled, OrderCanceled } from "../generated/Swapboard/Swapboard";
import { newMockEvent } from "matchstick-as";

const WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
const USDC_ADDRESS = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
const DAI_ADDRESS = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
const MAKER_ADDRESS = "0x1234567890123456789012345678901234567890";
const TAKER_ADDRESS = "0x0987654321098765432109876543210987654321";

function mockERC20(address: string, symbol: string, name: string, decimals: i32): void {
  let addr = Address.fromString(address);
  createMockedFunction(addr, "symbol", "symbol():(string)")
    .returns([ethereum.Value.fromString(symbol)]);
  createMockedFunction(addr, "name", "name():(string)")
    .returns([ethereum.Value.fromString(name)]);
  createMockedFunction(addr, "decimals", "decimals():(uint8)")
    .returns([ethereum.Value.fromI32(decimals)]);
}

function mockERC20Reverts(address: string): void {
  let addr = Address.fromString(address);
  createMockedFunction(addr, "symbol", "symbol():(string)").reverts();
  createMockedFunction(addr, "name", "name():(string)").reverts();
  createMockedFunction(addr, "decimals", "decimals():(uint8)").reverts();
}

function createOrderCreatedEvent(
  orderId: i32,
  maker: string,
  tokenA: string,
  amountA: string,
  tokenB: string,
  amountB: string
): OrderCreated {
  let event = changetype<OrderCreated>(newMockEvent());
  event.parameters = new Array();

  event.parameters.push(
    new ethereum.EventParam("orderId", ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(orderId)))
  );
  event.parameters.push(
    new ethereum.EventParam("maker", ethereum.Value.fromAddress(Address.fromString(maker)))
  );
  event.parameters.push(
    new ethereum.EventParam("tokenA", ethereum.Value.fromAddress(Address.fromString(tokenA)))
  );
  event.parameters.push(
    new ethereum.EventParam("amountA", ethereum.Value.fromUnsignedBigInt(BigInt.fromString(amountA)))
  );
  event.parameters.push(
    new ethereum.EventParam("tokenB", ethereum.Value.fromAddress(Address.fromString(tokenB)))
  );
  event.parameters.push(
    new ethereum.EventParam("amountB", ethereum.Value.fromUnsignedBigInt(BigInt.fromString(amountB)))
  );

  return event;
}

function createOrderFilledEvent(orderId: i32, taker: string): OrderFilled {
  let event = changetype<OrderFilled>(newMockEvent());
  event.parameters = new Array();

  event.parameters.push(
    new ethereum.EventParam("orderId", ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(orderId)))
  );
  event.parameters.push(
    new ethereum.EventParam("taker", ethereum.Value.fromAddress(Address.fromString(taker)))
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

describe("Swapboard Subgraph", () => {
  beforeEach(() => {
    clearStore();
    mockERC20(WETH_ADDRESS, "WETH", "Wrapped Ether", 18);
    mockERC20(USDC_ADDRESS, "USDC", "USD Coin", 6);
    mockERC20(DAI_ADDRESS, "DAI", "Dai Stablecoin", 18);
  });

  afterAll(() => {
    clearStore();
  });

  // ========================================
  // Order Entity Tests
  // ========================================

  test("OrderCreated creates Order entity with all fields", () => {
    let event = createOrderCreatedEvent(
      0,
      MAKER_ADDRESS,
      WETH_ADDRESS,
      "10000000000000000000",
      USDC_ADDRESS,
      "30000000000"
    );

    handleOrderCreated(event);

    assert.entityCount("Order", 1);
    assert.fieldEquals("Order", "0", "orderId", "0");
    assert.fieldEquals("Order", "0", "maker", MAKER_ADDRESS.toLowerCase());
    assert.fieldEquals("Order", "0", "amountA", "10000000000000000000");
    assert.fieldEquals("Order", "0", "amountB", "30000000000");
    assert.fieldEquals("Order", "0", "active", "true");
    assert.fieldEquals("Order", "0", "tokenA", WETH_ADDRESS.toLowerCase());
    assert.fieldEquals("Order", "0", "tokenB", USDC_ADDRESS.toLowerCase());
  });

  test("OrderCreated sets timestamp and tx hash", () => {
    let event = createOrderCreatedEvent(
      0,
      MAKER_ADDRESS,
      WETH_ADDRESS,
      "10000000000000000000",
      USDC_ADDRESS,
      "30000000000"
    );

    handleOrderCreated(event);

    // createdAt and createdTx should be set (non-null)
    assert.fieldEquals("Order", "0", "createdAt", event.block.timestamp.toString());
    assert.fieldEquals("Order", "0", "createdTx", event.transaction.hash.toHexString());
  });


  // ========================================
  // Token Entity Tests
  // ========================================

  test("OrderCreated creates Token entities with all fields", () => {
    let event = createOrderCreatedEvent(
      0,
      MAKER_ADDRESS,
      WETH_ADDRESS,
      "10000000000000000000",
      USDC_ADDRESS,
      "30000000000"
    );

    handleOrderCreated(event);

    assert.entityCount("Token", 2);

    // WETH token
    assert.fieldEquals("Token", WETH_ADDRESS.toLowerCase(), "symbol", "WETH");
    assert.fieldEquals("Token", WETH_ADDRESS.toLowerCase(), "name", "Wrapped Ether");
    assert.fieldEquals("Token", WETH_ADDRESS.toLowerCase(), "decimals", "18");
    assert.fieldEquals("Token", WETH_ADDRESS.toLowerCase(), "address", WETH_ADDRESS.toLowerCase());
    assert.fieldEquals("Token", WETH_ADDRESS.toLowerCase(), "volumeSold", "0");
    assert.fieldEquals("Token", WETH_ADDRESS.toLowerCase(), "volumeBought", "0");

    // USDC token
    assert.fieldEquals("Token", USDC_ADDRESS.toLowerCase(), "symbol", "USDC");
    assert.fieldEquals("Token", USDC_ADDRESS.toLowerCase(), "name", "USD Coin");
    assert.fieldEquals("Token", USDC_ADDRESS.toLowerCase(), "decimals", "6");
    assert.fieldEquals("Token", USDC_ADDRESS.toLowerCase(), "address", USDC_ADDRESS.toLowerCase());
  });

  test("OrderCreated updates Token order counts", () => {
    let event = createOrderCreatedEvent(
      0,
      MAKER_ADDRESS,
      WETH_ADDRESS,
      "10000000000000000000",
      USDC_ADDRESS,
      "30000000000"
    );

    handleOrderCreated(event);

    assert.fieldEquals("Token", WETH_ADDRESS.toLowerCase(), "ordersSelling", "1");
    assert.fieldEquals("Token", WETH_ADDRESS.toLowerCase(), "ordersBuying", "0");
    assert.fieldEquals("Token", USDC_ADDRESS.toLowerCase(), "ordersSelling", "0");
    assert.fieldEquals("Token", USDC_ADDRESS.toLowerCase(), "ordersBuying", "1");
  });

  test("Token reuses existing entity on second order", () => {
    let event1 = createOrderCreatedEvent(
      0,
      MAKER_ADDRESS,
      WETH_ADDRESS,
      "10000000000000000000",
      USDC_ADDRESS,
      "30000000000"
    );
    handleOrderCreated(event1);

    let event2 = createOrderCreatedEvent(
      1,
      MAKER_ADDRESS,
      WETH_ADDRESS,
      "5000000000000000000",
      USDC_ADDRESS,
      "15000000000"
    );
    handleOrderCreated(event2);

    assert.entityCount("Token", 2);
    assert.fieldEquals("Token", WETH_ADDRESS.toLowerCase(), "ordersSelling", "2");
    assert.fieldEquals("Token", USDC_ADDRESS.toLowerCase(), "ordersBuying", "2");
  });

  // ========================================
  // GlobalStats Tests
  // ========================================

  test("OrderCreated updates GlobalStats", () => {
    let event = createOrderCreatedEvent(
      0,
      MAKER_ADDRESS,
      WETH_ADDRESS,
      "10000000000000000000",
      USDC_ADDRESS,
      "30000000000"
    );

    handleOrderCreated(event);

    assert.fieldEquals("GlobalStats", "global", "totalOrders", "1");
    assert.fieldEquals("GlobalStats", "global", "activeOrders", "1");
    assert.fieldEquals("GlobalStats", "global", "filledOrders", "0");
    assert.fieldEquals("GlobalStats", "global", "cancelledOrders", "0");
  });

  // ========================================
  // PairStats Tests
  // ========================================

  test("OrderCreated creates PairStats entity", () => {
    let event = createOrderCreatedEvent(
      0,
      MAKER_ADDRESS,
      WETH_ADDRESS,
      "10000000000000000000",
      USDC_ADDRESS,
      "30000000000"
    );

    handleOrderCreated(event);

    let pairId = WETH_ADDRESS.toLowerCase() + "-" + USDC_ADDRESS.toLowerCase();
    assert.entityCount("PairStats", 1);
    assert.fieldEquals("PairStats", pairId, "orderCount", "1");
    assert.fieldEquals("PairStats", pairId, "tradeCount", "0");
    assert.fieldEquals("PairStats", pairId, "tokenA", WETH_ADDRESS.toLowerCase());
    assert.fieldEquals("PairStats", pairId, "tokenB", USDC_ADDRESS.toLowerCase());
  });

  test("OrderCreated increments PairStats orderCount", () => {
    for (let i = 0; i < 3; i++) {
      let event = createOrderCreatedEvent(
        i,
        MAKER_ADDRESS,
        WETH_ADDRESS,
        "10000000000000000000",
        USDC_ADDRESS,
        "30000000000"
      );
      handleOrderCreated(event);
    }

    let pairId = WETH_ADDRESS.toLowerCase() + "-" + USDC_ADDRESS.toLowerCase();
    assert.fieldEquals("PairStats", pairId, "orderCount", "3");
    assert.fieldEquals("PairStats", pairId, "tradeCount", "0");
  });

  test("OrderFilled increments PairStats tradeCount", () => {
    let createEvent = createOrderCreatedEvent(
      0,
      MAKER_ADDRESS,
      WETH_ADDRESS,
      "10000000000000000000",
      USDC_ADDRESS,
      "30000000000"
    );
    handleOrderCreated(createEvent);

    let fillEvent = createOrderFilledEvent(0, TAKER_ADDRESS);
    handleOrderFilled(fillEvent);

    let pairId = WETH_ADDRESS.toLowerCase() + "-" + USDC_ADDRESS.toLowerCase();
    assert.fieldEquals("PairStats", pairId, "orderCount", "1");
    assert.fieldEquals("PairStats", pairId, "tradeCount", "1");
  });

  test("Different pairs create separate PairStats", () => {
    let event1 = createOrderCreatedEvent(
      0,
      MAKER_ADDRESS,
      WETH_ADDRESS,
      "10000000000000000000",
      USDC_ADDRESS,
      "30000000000"
    );
    handleOrderCreated(event1);

    let event2 = createOrderCreatedEvent(
      1,
      MAKER_ADDRESS,
      WETH_ADDRESS,
      "10000000000000000000",
      DAI_ADDRESS,
      "30000000000000000000"
    );
    handleOrderCreated(event2);

    assert.entityCount("PairStats", 2);

    let pair1Id = WETH_ADDRESS.toLowerCase() + "-" + USDC_ADDRESS.toLowerCase();
    let pair2Id = WETH_ADDRESS.toLowerCase() + "-" + DAI_ADDRESS.toLowerCase();

    assert.fieldEquals("PairStats", pair1Id, "orderCount", "1");
    assert.fieldEquals("PairStats", pair2Id, "orderCount", "1");
  });

  test("Reverse pair is tracked separately", () => {
    let event1 = createOrderCreatedEvent(
      0,
      MAKER_ADDRESS,
      WETH_ADDRESS,
      "10000000000000000000",
      USDC_ADDRESS,
      "30000000000"
    );
    handleOrderCreated(event1);

    let event2 = createOrderCreatedEvent(
      1,
      MAKER_ADDRESS,
      USDC_ADDRESS,
      "30000000000",
      WETH_ADDRESS,
      "10000000000000000000"
    );
    handleOrderCreated(event2);

    assert.entityCount("PairStats", 2);

    let pair1Id = WETH_ADDRESS.toLowerCase() + "-" + USDC_ADDRESS.toLowerCase();
    let pair2Id = USDC_ADDRESS.toLowerCase() + "-" + WETH_ADDRESS.toLowerCase();

    assert.fieldEquals("PairStats", pair1Id, "orderCount", "1");
    assert.fieldEquals("PairStats", pair2Id, "orderCount", "1");
  });

  // ========================================
  // OrderFilled Tests
  // ========================================

  test("OrderFilled updates Order entity", () => {
    let createEvent = createOrderCreatedEvent(
      0,
      MAKER_ADDRESS,
      WETH_ADDRESS,
      "10000000000000000000",
      USDC_ADDRESS,
      "30000000000"
    );
    handleOrderCreated(createEvent);

    let fillEvent = createOrderFilledEvent(0, TAKER_ADDRESS);
    handleOrderFilled(fillEvent);

    assert.fieldEquals("Order", "0", "active", "false");
    assert.fieldEquals("Order", "0", "taker", TAKER_ADDRESS.toLowerCase());
    assert.fieldEquals("Order", "0", "filledAt", fillEvent.block.timestamp.toString());
    assert.fieldEquals("Order", "0", "filledTx", fillEvent.transaction.hash.toHexString());
  });

  test("OrderFilled updates GlobalStats", () => {
    let createEvent = createOrderCreatedEvent(
      0,
      MAKER_ADDRESS,
      WETH_ADDRESS,
      "10000000000000000000",
      USDC_ADDRESS,
      "30000000000"
    );
    handleOrderCreated(createEvent);

    let fillEvent = createOrderFilledEvent(0, TAKER_ADDRESS);
    handleOrderFilled(fillEvent);

    assert.fieldEquals("GlobalStats", "global", "totalOrders", "1");
    assert.fieldEquals("GlobalStats", "global", "activeOrders", "0");
    assert.fieldEquals("GlobalStats", "global", "filledOrders", "1");
    assert.fieldEquals("GlobalStats", "global", "cancelledOrders", "0");
  });

  test("OrderFilled updates Token volumes", () => {
    let createEvent = createOrderCreatedEvent(
      0,
      MAKER_ADDRESS,
      WETH_ADDRESS,
      "10000000000000000000",
      USDC_ADDRESS,
      "30000000000"
    );
    handleOrderCreated(createEvent);

    let fillEvent = createOrderFilledEvent(0, TAKER_ADDRESS);
    handleOrderFilled(fillEvent);

    assert.fieldEquals("Token", WETH_ADDRESS.toLowerCase(), "volumeSold", "10000000000000000000");
    assert.fieldEquals("Token", USDC_ADDRESS.toLowerCase(), "volumeBought", "30000000000");
  });

  test("OrderFilled accumulates Token volumes", () => {
    for (let i = 0; i < 3; i++) {
      let createEvent = createOrderCreatedEvent(
        i,
        MAKER_ADDRESS,
        WETH_ADDRESS,
        "10000000000000000000",
        USDC_ADDRESS,
        "30000000000"
      );
      handleOrderCreated(createEvent);

      let fillEvent = createOrderFilledEvent(i, TAKER_ADDRESS);
      handleOrderFilled(fillEvent);
    }

    assert.fieldEquals("Token", WETH_ADDRESS.toLowerCase(), "volumeSold", "30000000000000000000");
    assert.fieldEquals("Token", USDC_ADDRESS.toLowerCase(), "volumeBought", "90000000000");
  });

  // ========================================
  // OrderCanceled Tests
  // ========================================

  test("OrderCanceled updates Order entity", () => {
    let createEvent = createOrderCreatedEvent(
      0,
      MAKER_ADDRESS,
      WETH_ADDRESS,
      "10000000000000000000",
      USDC_ADDRESS,
      "30000000000"
    );
    handleOrderCreated(createEvent);

    let cancelEvent = createOrderCanceledEvent(0);
    handleOrderCanceled(cancelEvent);

    assert.fieldEquals("Order", "0", "active", "false");
    assert.fieldEquals("Order", "0", "cancelledAt", cancelEvent.block.timestamp.toString());
    assert.fieldEquals("Order", "0", "cancelledTx", cancelEvent.transaction.hash.toHexString());
  });

  test("OrderCanceled updates GlobalStats", () => {
    let createEvent = createOrderCreatedEvent(
      0,
      MAKER_ADDRESS,
      WETH_ADDRESS,
      "10000000000000000000",
      USDC_ADDRESS,
      "30000000000"
    );
    handleOrderCreated(createEvent);

    let cancelEvent = createOrderCanceledEvent(0);
    handleOrderCanceled(cancelEvent);

    assert.fieldEquals("GlobalStats", "global", "totalOrders", "1");
    assert.fieldEquals("GlobalStats", "global", "activeOrders", "0");
    assert.fieldEquals("GlobalStats", "global", "filledOrders", "0");
    assert.fieldEquals("GlobalStats", "global", "cancelledOrders", "1");
  });

  test("OrderCanceled does not update Token volumes", () => {
    let createEvent = createOrderCreatedEvent(
      0,
      MAKER_ADDRESS,
      WETH_ADDRESS,
      "10000000000000000000",
      USDC_ADDRESS,
      "30000000000"
    );
    handleOrderCreated(createEvent);

    let cancelEvent = createOrderCanceledEvent(0);
    handleOrderCanceled(cancelEvent);

    assert.fieldEquals("Token", WETH_ADDRESS.toLowerCase(), "volumeSold", "0");
    assert.fieldEquals("Token", USDC_ADDRESS.toLowerCase(), "volumeBought", "0");
  });

  test("OrderCanceled does not update PairStats tradeCount", () => {
    let createEvent = createOrderCreatedEvent(
      0,
      MAKER_ADDRESS,
      WETH_ADDRESS,
      "10000000000000000000",
      USDC_ADDRESS,
      "30000000000"
    );
    handleOrderCreated(createEvent);

    let cancelEvent = createOrderCanceledEvent(0);
    handleOrderCanceled(cancelEvent);

    let pairId = WETH_ADDRESS.toLowerCase() + "-" + USDC_ADDRESS.toLowerCase();
    assert.fieldEquals("PairStats", pairId, "orderCount", "1");
    assert.fieldEquals("PairStats", pairId, "tradeCount", "0");
  });

  // ========================================
  // ERC20 Fallback Tests
  // ========================================

  test("Token uses fallback values when ERC20 calls revert", () => {
    let badTokenAddress = "0xDeadBeef00000000000000000000000000000000";
    mockERC20Reverts(badTokenAddress);

    let event = createOrderCreatedEvent(
      0,
      MAKER_ADDRESS,
      badTokenAddress,
      "10000000000000000000",
      USDC_ADDRESS,
      "30000000000"
    );

    handleOrderCreated(event);

    assert.fieldEquals("Token", badTokenAddress.toLowerCase(), "symbol", "UNKNOWN");
    assert.fieldEquals("Token", badTokenAddress.toLowerCase(), "name", "Unknown Token");
    assert.fieldEquals("Token", badTokenAddress.toLowerCase(), "decimals", "18");
  });

  // ========================================
  // Complex Scenario Tests
  // ========================================

  test("Multiple orders track correctly", () => {
    for (let i = 0; i < 3; i++) {
      let event = createOrderCreatedEvent(
        i,
        MAKER_ADDRESS,
        WETH_ADDRESS,
        "10000000000000000000",
        USDC_ADDRESS,
        "30000000000"
      );
      handleOrderCreated(event);
    }

    assert.entityCount("Order", 3);
    assert.fieldEquals("GlobalStats", "global", "totalOrders", "3");
    assert.fieldEquals("GlobalStats", "global", "activeOrders", "3");
    assert.fieldEquals("Token", WETH_ADDRESS.toLowerCase(), "ordersSelling", "3");
  });

  test("Mixed fill and cancel operations", () => {
    for (let i = 0; i < 4; i++) {
      let event = createOrderCreatedEvent(
        i,
        MAKER_ADDRESS,
        WETH_ADDRESS,
        "10000000000000000000",
        USDC_ADDRESS,
        "30000000000"
      );
      handleOrderCreated(event);
    }

    handleOrderFilled(createOrderFilledEvent(0, TAKER_ADDRESS));
    handleOrderFilled(createOrderFilledEvent(2, TAKER_ADDRESS));
    handleOrderCanceled(createOrderCanceledEvent(1));

    assert.fieldEquals("GlobalStats", "global", "totalOrders", "4");
    assert.fieldEquals("GlobalStats", "global", "activeOrders", "1");
    assert.fieldEquals("GlobalStats", "global", "filledOrders", "2");
    assert.fieldEquals("GlobalStats", "global", "cancelledOrders", "1");

    assert.fieldEquals("Order", "0", "active", "false");
    assert.fieldEquals("Order", "1", "active", "false");
    assert.fieldEquals("Order", "2", "active", "false");
    assert.fieldEquals("Order", "3", "active", "true");

    // Volume only from filled orders
    assert.fieldEquals("Token", WETH_ADDRESS.toLowerCase(), "volumeSold", "20000000000000000000");
    assert.fieldEquals("Token", USDC_ADDRESS.toLowerCase(), "volumeBought", "60000000000");

    // PairStats tradeCount only from filled orders
    let pairId = WETH_ADDRESS.toLowerCase() + "-" + USDC_ADDRESS.toLowerCase();
    assert.fieldEquals("PairStats", pairId, "orderCount", "4");
    assert.fieldEquals("PairStats", pairId, "tradeCount", "2");
  });
});
