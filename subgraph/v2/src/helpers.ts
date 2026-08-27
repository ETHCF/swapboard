/**
 * @fileoverview Entity loaders and numeric helpers for the Swapboard v2 subgraph.
 * @author Zak Cole (numbergroup.xyz) for Ethereum Community Foundation
 * @license AGPL-3.0-only
 *
 * The `getOrCreate*` helpers bump the corresponding GlobalStats cardinality
 * counters when they create an entity. Handlers must therefore call
 * `getOrCreateGlobalStats()` *after* every other `getOrCreate*` call in the
 * handler, so they read back the incremented values.
 */

import { Address, BigDecimal, BigInt, log } from "@graphprotocol/graph-ts";
import { ERC20 } from "../generated/Swapboard/ERC20";
import { Account, GlobalStats, Pair, Token } from "../generated/schema";
import {
  DEFAULT_DECIMALS,
  ETH_DECIMALS,
  ETH_NAME,
  ETH_SENTINEL,
  ETH_SYMBOL,
  GLOBAL_STATS_ID,
  MAX_DECIMALS,
  MAX_NAME_LENGTH,
  MAX_SYMBOL_LENGTH,
  ONE_BI,
  UNKNOWN_NAME,
  UNKNOWN_SYMBOL,
  ZERO_BD,
  ZERO_BI,
} from "./constants";

/**
 * Returns 10^decimals as a BigDecimal.
 * @param decimals - Exponent, expected to be within [0, MAX_DECIMALS]
 */
export function exponentToBigDecimal(decimals: i32): BigDecimal {
  let scale = BigInt.fromI32(1);
  let ten = BigInt.fromI32(10);
  for (let i = 0; i < decimals; i++) {
    scale = scale.times(ten);
  }
  return scale.toBigDecimal();
}

/**
 * Converts a base-unit amount into human units.
 * @param amount - Amount in base units
 * @param decimals - Token decimals
 */
export function toDecimal(amount: BigInt, decimals: i32): BigDecimal {
  if (decimals < 0 || decimals > MAX_DECIMALS) {
    return ZERO_BD;
  }
  return amount.toBigDecimal().div(exponentToBigDecimal(decimals));
}

/**
 * Price of one unit of tokenA denominated in tokenB, in human units.
 * Returns 0 when the price cannot be represented (zero amountA, absurd decimals).
 * @param amountA - tokenA amount in base units
 * @param decimalsA - tokenA decimals
 * @param amountB - tokenB amount in base units
 * @param decimalsB - tokenB decimals
 */
export function priceOf(amountA: BigInt, decimalsA: i32, amountB: BigInt, decimalsB: i32): BigDecimal {
  if (amountA.equals(ZERO_BI)) {
    return ZERO_BD;
  }
  let a = toDecimal(amountA, decimalsA);
  let b = toDecimal(amountB, decimalsB);
  if (a.equals(ZERO_BD)) {
    return ZERO_BD;
  }
  return b.div(a);
}

/**
 * Fraction of an order that has been filled, expressed over tokenA.
 * @param filledA - tokenA already taken from the order
 * @param amountA - original tokenA deposited
 */
export function fillFraction(filledA: BigInt, amountA: BigInt): BigDecimal {
  if (amountA.equals(ZERO_BI)) {
    return ZERO_BD;
  }
  return filledA.toBigDecimal().div(amountA.toBigDecimal());
}

/** Gets or creates the GlobalStats singleton. */
export function getOrCreateGlobalStats(): GlobalStats {
  let stats = GlobalStats.load(GLOBAL_STATS_ID);
  if (stats == null) {
    stats = new GlobalStats(GLOBAL_STATS_ID);
    stats.totalOrders = ZERO_BI;
    stats.openOrders = ZERO_BI;
    stats.partiallyFilledOrders = ZERO_BI;
    stats.filledOrders = ZERO_BI;
    stats.canceledOrders = ZERO_BI;
    stats.totalFills = ZERO_BI;
    stats.totalTokens = ZERO_BI;
    stats.totalPairs = ZERO_BI;
    stats.totalAccounts = ZERO_BI;
    stats.updatedAt = ZERO_BI;
  }
  return stats;
}

/**
 * Gets or creates an Account, refreshing its activity timestamps.
 * @param address - Account address
 * @param timestamp - Block timestamp of the event being handled
 */
export function getOrCreateAccount(address: Address, timestamp: BigInt): Account {
  let id = address.toHexString();
  let account = Account.load(id);

  if (account == null) {
    account = new Account(id);
    account.address = address;
    account.ordersCreated = ZERO_BI;
    account.ordersOpen = ZERO_BI;
    account.ordersFilled = ZERO_BI;
    account.ordersCanceled = ZERO_BI;
    account.fillsTakenCount = ZERO_BI;
    account.fillsReceivedCount = ZERO_BI;
    account.firstSeenAt = timestamp;

    let stats = getOrCreateGlobalStats();
    stats.totalAccounts = stats.totalAccounts.plus(ONE_BI);
    stats.save();
  }

  account.lastActiveAt = timestamp;
  return account;
}

/**
 * Gets or creates a Token, resolving metadata from the contract on first sight.
 * The native ETH sentinel has no code, so its metadata is hardcoded rather than
 * fetched.
 * @param address - Token address, or the ETH sentinel
 * @param timestamp - Block timestamp of the event being handled
 */
export function getOrCreateToken(address: Address, timestamp: BigInt): Token {
  let id = address.toHexString();
  let existing = Token.load(id);
  if (existing != null) {
    return existing;
  }

  let token = new Token(id);
  token.address = address;
  token.volumeSold = ZERO_BI;
  token.volumeBought = ZERO_BI;
  token.ordersSelling = ZERO_BI;
  token.ordersBuying = ZERO_BI;
  token.openOrdersSelling = ZERO_BI;
  token.openOrdersBuying = ZERO_BI;
  token.fillCount = ZERO_BI;
  token.firstSeenAt = timestamp;
  token.isNative = id == ETH_SENTINEL;

  if (token.isNative) {
    token.symbol = ETH_SYMBOL;
    token.name = ETH_NAME;
    token.decimals = ETH_DECIMALS;
  } else {
    let contract = ERC20.bind(address);

    let symbolResult = contract.try_symbol();
    if (symbolResult.reverted) {
      log.warning("Failed to fetch symbol for token {}", [id]);
      token.symbol = UNKNOWN_SYMBOL;
    } else {
      let symbol = symbolResult.value;
      token.symbol = symbol.length > MAX_SYMBOL_LENGTH ? symbol.substring(0, MAX_SYMBOL_LENGTH) : symbol;
    }

    let nameResult = contract.try_name();
    if (nameResult.reverted) {
      log.warning("Failed to fetch name for token {}", [id]);
      token.name = UNKNOWN_NAME;
    } else {
      let name = nameResult.value;
      token.name = name.length > MAX_NAME_LENGTH ? name.substring(0, MAX_NAME_LENGTH) : name;
    }

    let decimalsResult = contract.try_decimals();
    if (decimalsResult.reverted) {
      log.warning("Failed to fetch decimals for token {}, defaulting to {}", [id, DEFAULT_DECIMALS.toString()]);
      token.decimals = DEFAULT_DECIMALS;
    } else {
      token.decimals = decimalsResult.value;
    }
  }

  let stats = getOrCreateGlobalStats();
  stats.totalTokens = stats.totalTokens.plus(ONE_BI);
  stats.save();

  return token;
}

/**
 * Builds the directional pair ID for a (tokenA, tokenB) ordering.
 * @param tokenAId - tokenA entity ID
 * @param tokenBId - tokenB entity ID
 */
export function pairId(tokenAId: string, tokenBId: string): string {
  return tokenAId + "-" + tokenBId;
}

/**
 * Gets or creates the directional Pair for selling tokenA to get tokenB.
 * @param tokenAId - tokenA entity ID
 * @param tokenBId - tokenB entity ID
 */
export function getOrCreatePair(tokenAId: string, tokenBId: string): Pair {
  let id = pairId(tokenAId, tokenBId);
  let existing = Pair.load(id);
  if (existing != null) {
    return existing;
  }

  let pair = new Pair(id);
  pair.tokenA = tokenAId;
  pair.tokenB = tokenBId;
  pair.orderCount = ZERO_BI;
  pair.openOrderCount = ZERO_BI;
  pair.filledOrderCount = ZERO_BI;
  pair.canceledOrderCount = ZERO_BI;
  pair.fillCount = ZERO_BI;
  pair.volumeA = ZERO_BI;
  pair.volumeB = ZERO_BI;
  pair.lastTradeAt = null;

  let stats = getOrCreateGlobalStats();
  stats.totalPairs = stats.totalPairs.plus(ONE_BI);
  stats.save();

  return pair;
}
