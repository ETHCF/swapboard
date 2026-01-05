import {
  assert,
  describe,
  test,
  clearStore,
  beforeAll,
  afterAll,
  beforeEach,
  createMockedFunction,
} from "matchstick-as/assembly/index";
import { Address, BigInt, Bytes, ethereum } from "@graphprotocol/graph-ts";
import { handleOrderCreated, handleOrderFilled, handleOrderCanceled } from "../src/mapping";
import { OrderCreated, OrderFilled, OrderCanceled } from "../generated/OTCBoard/OTCBoard";
import { Order, Token, GlobalStats } from "../generated/schema";
import { newMockEvent } from "matchstick-as";

const CONTRACT_ADDRESS = "0x0000000000000000000000000000000000000001";
const WETH_ADDRESS = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
const USDC_ADDRESS = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
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

describe("OTCBoard Subgraph", () => {
  beforeEach(() => {
    clearStore();
    mockERC20(WETH_ADDRESS, "WETH", "Wrapped Ether", 18);
    mockERC20(USDC_ADDRESS, "USDC", "USD Coin", 6);
  });

  afterAll(() => {
    clearStore();
  });

  test("OrderCreated creates Order entity", () => {
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
  });

  test("OrderCreated creates Token entities", () => {
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
    assert.fieldEquals("Token", WETH_ADDRESS.toLowerCase(), "symbol", "WETH");
    assert.fieldEquals("Token", WETH_ADDRESS.toLowerCase(), "decimals", "18");
    assert.fieldEquals("Token", USDC_ADDRESS.toLowerCase(), "symbol", "USDC");
    assert.fieldEquals("Token", USDC_ADDRESS.toLowerCase(), "decimals", "6");
  });

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
  });
});
