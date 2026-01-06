import { BigInt, Address, log } from "@graphprotocol/graph-ts";
import {
  OrderCreated,
  OrderFilled,
  OrderCanceled,
} from "../generated/Swapboard/Swapboard";
import { ERC20 } from "../generated/Swapboard/ERC20";
import { Order, Token, GlobalStats, PairStats } from "../generated/schema";

const GLOBAL_STATS_ID = "global";
const ZERO = BigInt.fromI32(0);
const ONE = BigInt.fromI32(1);

/**
 * Gets or creates the global stats singleton entity.
 */
function getOrCreateGlobalStats(): GlobalStats {
  let stats = GlobalStats.load(GLOBAL_STATS_ID);
  if (stats == null) {
    stats = new GlobalStats(GLOBAL_STATS_ID);
    stats.totalOrders = ZERO;
    stats.filledOrders = ZERO;
    stats.cancelledOrders = ZERO;
    stats.activeOrders = ZERO;
  }
  return stats;
}

/**
 * Gets or creates pair stats for a token pair.
 * @param tokenAId - Token A entity ID (lowercase address)
 * @param tokenBId - Token B entity ID (lowercase address)
 */
function getOrCreatePairStats(tokenAId: string, tokenBId: string): PairStats {
  let id = tokenAId + "-" + tokenBId;
  let stats = PairStats.load(id);
  if (stats == null) {
    stats = new PairStats(id);
    stats.tokenA = tokenAId;
    stats.tokenB = tokenBId;
    stats.orderCount = ZERO;
    stats.tradeCount = ZERO;
  }
  return stats;
}

/**
 * Gets or creates a token entity, fetching metadata from the contract.
 * @param address - The token contract address
 */
function getOrCreateToken(address: Address): Token {
  let id = address.toHexString();
  let token = Token.load(id);

  if (token == null) {
    token = new Token(id);
    token.address = address;
    token.volumeSold = ZERO;
    token.volumeBought = ZERO;
    token.ordersSelling = ZERO;
    token.ordersBuying = ZERO;

    let contract = ERC20.bind(address);

    // Fetch symbol with fallback
    let symbolResult = contract.try_symbol();
    if (symbolResult.reverted) {
      log.warning("Failed to fetch symbol for token {}", [id]);
      token.symbol = "UNKNOWN";
    } else {
      // Truncate to prevent oversized strings
      let sym = symbolResult.value;
      token.symbol = sym.length > 32 ? sym.substring(0, 32) : sym;
    }

    // Fetch name with fallback
    let nameResult = contract.try_name();
    if (nameResult.reverted) {
      log.warning("Failed to fetch name for token {}", [id]);
      token.name = "Unknown Token";
    } else {
      let name = nameResult.value;
      token.name = name.length > 128 ? name.substring(0, 128) : name;
    }

    // Fetch decimals with fallback
    let decimalsResult = contract.try_decimals();
    if (decimalsResult.reverted) {
      log.warning("Failed to fetch decimals for token {}, defaulting to 18", [id]);
      token.decimals = 18;
    } else {
      token.decimals = decimalsResult.value;
    }
  }

  return token;
}

/**
 * Handles OrderCreated events.
 * Creates Order entity, updates Token counters, updates GlobalStats.
 */
export function handleOrderCreated(event: OrderCreated): void {
  let orderId = event.params.orderId.toString();
  let order = new Order(orderId);

  order.orderId = event.params.orderId;
  order.maker = event.params.maker;
  order.amountA = event.params.amountA;
  order.amountB = event.params.amountB;
  order.active = true;
  order.taker = null;
  order.createdAt = event.block.timestamp;
  order.createdTx = event.transaction.hash;
  order.filledAt = null;
  order.filledTx = null;
  order.cancelledAt = null;
  order.cancelledTx = null;

  // Load or create tokenA and increment selling counter
  let tokenA = getOrCreateToken(event.params.tokenA);
  tokenA.ordersSelling = tokenA.ordersSelling.plus(ONE);
  tokenA.save();
  order.tokenA = tokenA.id;

  // Load or create tokenB and increment buying counter
  let tokenB = getOrCreateToken(event.params.tokenB);
  tokenB.ordersBuying = tokenB.ordersBuying.plus(ONE);
  tokenB.save();
  order.tokenB = tokenB.id;

  order.save();

  // Update pair stats
  let pairStats = getOrCreatePairStats(tokenA.id, tokenB.id);
  pairStats.orderCount = pairStats.orderCount.plus(ONE);
  pairStats.save();

  // Update global stats
  let stats = getOrCreateGlobalStats();
  stats.totalOrders = stats.totalOrders.plus(ONE);
  stats.activeOrders = stats.activeOrders.plus(ONE);
  stats.save();

  log.info("Order {} created by {} - selling {} for {}", [
    orderId,
    event.params.maker.toHexString(),
    tokenA.symbol,
    tokenB.symbol
  ]);
}

/**
 * Handles OrderFilled events.
 * Updates Order entity, Token volumes, and GlobalStats.
 */
export function handleOrderFilled(event: OrderFilled): void {
  let orderId = event.params.orderId.toString();
  let order = Order.load(orderId);

  if (order == null) {
    log.error("OrderFilled: Order {} not found", [orderId]);
    return;
  }

  order.active = false;
  order.taker = event.params.taker;
  order.filledAt = event.block.timestamp;
  order.filledTx = event.transaction.hash;
  order.save();

  // Update tokenA volume (amount sold)
  let tokenA = Token.load(order.tokenA);
  if (tokenA != null) {
    tokenA.volumeSold = tokenA.volumeSold.plus(order.amountA);
    tokenA.save();
  } else {
    log.error("OrderFilled: TokenA {} not found for order {}", [order.tokenA, orderId]);
  }

  // Update tokenB volume (amount bought)
  let tokenB = Token.load(order.tokenB);
  if (tokenB != null) {
    tokenB.volumeBought = tokenB.volumeBought.plus(order.amountB);
    tokenB.save();
  } else {
    log.error("OrderFilled: TokenB {} not found for order {}", [order.tokenB, orderId]);
  }

  // Update pair stats
  let pairStats = getOrCreatePairStats(order.tokenA, order.tokenB);
  pairStats.tradeCount = pairStats.tradeCount.plus(ONE);
  pairStats.save();

  // Update global stats
  let stats = getOrCreateGlobalStats();
  stats.filledOrders = stats.filledOrders.plus(ONE);
  stats.activeOrders = stats.activeOrders.minus(ONE);
  stats.save();

  log.info("Order {} filled by {}", [orderId, event.params.taker.toHexString()]);
}

/**
 * Handles OrderCanceled events.
 * Updates Order entity and GlobalStats.
 */
export function handleOrderCanceled(event: OrderCanceled): void {
  let orderId = event.params.orderId.toString();
  let order = Order.load(orderId);

  if (order == null) {
    log.error("OrderCanceled: Order {} not found", [orderId]);
    return;
  }

  order.active = false;
  order.cancelledAt = event.block.timestamp;
  order.cancelledTx = event.transaction.hash;
  order.save();

  // Update global stats
  let stats = getOrCreateGlobalStats();
  stats.cancelledOrders = stats.cancelledOrders.plus(ONE);
  stats.activeOrders = stats.activeOrders.minus(ONE);
  stats.save();

  log.info("Order {} cancelled", [orderId]);
}
