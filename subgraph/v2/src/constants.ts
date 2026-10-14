/**
 * @fileoverview Shared constants for the Swapboard v2 subgraph.
 * @author Zak Cole (numbergroup.xyz) for Ethereum Community Foundation
 * @license AGPL-3.0-only
 */

import { BigDecimal, BigInt } from "@graphprotocol/graph-ts";

/** ID of the GlobalStats singleton. */
export const GLOBAL_STATS_ID = "global";

/**
 * Canonical placeholder address representing native ETH (`ISwapboard.getEth()`),
 * lowercased to match `Address.toHexString()`.
 */
export const ETH_SENTINEL = "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee";

export const ETH_SYMBOL = "ETH";
export const ETH_NAME = "Ether";
export const ETH_DECIMALS = 18;

/** Fallbacks used when an ERC20 metadata call reverts. */
export const UNKNOWN_SYMBOL = "UNKNOWN";
export const UNKNOWN_NAME = "Unknown Token";
export const DEFAULT_DECIMALS = 18;

/** Caps on indexed metadata strings, to keep pathological tokens from bloating the store. */
export const MAX_SYMBOL_LENGTH = 32;
export const MAX_NAME_LENGTH = 128;

/**
 * Upper bound on decimals we will build a scaling factor for. Beyond this the
 * price fields fall back to zero rather than looping to build a huge exponent.
 */
export const MAX_DECIMALS = 36;

export const ZERO_BI = BigInt.fromI32(0);
export const ONE_BI = BigInt.fromI32(1);
export const ZERO_BD = BigDecimal.fromString("0");

/** Order status values, mirroring the `OrderStatus` enum in schema.graphql. */
export const STATUS_OPEN = "OPEN";
export const STATUS_PARTIALLY_FILLED = "PARTIALLY_FILLED";
export const STATUS_FILLED = "FILLED";
export const STATUS_CANCELED = "CANCELED";
