/**
 * @fileoverview Swapboard Shared Library
 * @description Pure functions and utilities extracted for testing.
 *              This module exports functions used by both app.js and tests.
 * @author Zak Cole (numbergroup.xyz) for Ethereum Community Foundation
 * @license AGPL-3.0-only
 */

// ============================================================================
// Configuration
// ============================================================================

// Deployment coordinates are per-version and live on VERSION_CAPS below, not
// here: v1 and v2 are served side by side, so a single CONTRACT_ADDRESS /
// SUBGRAPH_URL would have to be wrong for one of them.
const CONFIG = {
  PAGE_SIZE: 200,
  REQUEST_TIMEOUT: 30000,
  DEBOUNCE_DELAY: 500,
  SHOW_MARKET_DEVIATION: false,
  // v2 batch limits: the most orders that fit in a single transaction.
  // Seeded conservatively; retune once real gas numbers land.
  MAX_BATCH_FILL: 15,
  MAX_BATCH_CANCEL: 25,
  MAX_BATCH_CREATE: 10,
};

const EXPECTED_CHAIN_ID = 1;

/**
 * Sentinel address representing native ETH in v2 orders.
 * Native ETH has no contract, so orders carry this well-known placeholder.
 * @constant {string}
 */
const NATIVE_ETH = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";

const COINGECKO_ID_MAP = {
  "0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee": "ethereum",
  "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2": "weth",
  "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48": "usd-coin",
  "0xdac17f958d2ee523a2206206994597c13d831ec7": "tether",
  "0x6b175474e89094c44da98b954eedeac495271d0f": "dai",
  "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599": "wrapped-bitcoin",
  "0x514910771af9ca656af840dff83e8264ecf986ca": "chainlink",
  "0x7fc66500c84a76ad7e9c93437bfc5ac33e2ddae9": "aave",
  "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984": "uniswap",
  "0xae7ab96520de3a18e5e111b5eaab095312d7fe84": "staked-ether",
  "0x7d1afa7b718fb893db30a3abc0cfc608aacfebb0": "matic-network",
  "0x6982508145454ce325ddbe47a25d4ec3d2311933": "pepe",
  "0x95ad61b0a150d79219dcf64e1e6cc01f0b64c4ce": "shiba-inu",
};

// ============================================================================
// Utility Functions
// ============================================================================

/**
 * Escapes HTML special characters to prevent XSS.
 * @param {string|null|undefined} str - String to escape
 * @returns {string} HTML-safe string
 */
function escapeHtml(str) {
  if (str === null || str === undefined) return "";
  const map = {
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#039;",
    "/": "&#x2F;",
  };
  return String(str).replace(/[&<>"'/]/g, (c) => map[c]);
}

/**
 * Validates an Ethereum address format.
 * @param {*} addr - Value to validate
 * @returns {boolean} True if valid 0x-prefixed 40-character hex string
 */
function isValidAddress(addr) {
  if (typeof addr !== "string") return false;
  return /^0x[a-fA-F0-9]{40}$/.test(addr);
}

/**
 * Returns address for display.
 * @param {string} addr - Full Ethereum address
 * @returns {string} Full address or empty string if invalid
 */
function truncateAddress(addr) {
  if (!addr || !isValidAddress(addr)) return "";
  return addr;
}

/**
 * Gets order ID from URL hash if present.
 * Supports formats: #order-123, #order=123, #123
 * @param {string} hash - URL hash
 * @returns {string|null} Order ID or null
 */
function getOrderIdFromHash(hash) {
  if (!hash) return null;

  const dashMatch = hash.match(/^#order-(\d+)$/);
  if (dashMatch) return dashMatch[1];

  const orderMatch = hash.match(/^#order=(\d+)$/);
  if (orderMatch) return orderMatch[1];

  const simpleMatch = hash.match(/^#(\d+)$/);
  if (simpleMatch) return simpleMatch[1];

  return null;
}

/**
 * Creates a shareable URL for an order.
 * @param {string} orderId - Order ID
 * @param {string} baseUrl - Base URL
 * @returns {string} Full URL with hash
 */
function getOrderShareUrl(orderId, baseUrl) {
  const url = new URL(baseUrl);
  url.hash = "order-" + orderId;
  return url.toString();
}

// ============================================================================
// Formatting Functions
// ============================================================================

/**
 * Formats USD value for display.
 * @param {number|null} usdValue
 * @returns {string}
 */
function formatUsd(usdValue) {
  if (usdValue === null || usdValue === undefined) return "$--";
  if (usdValue >= 1000000) {
    return "$" + (usdValue / 1000000).toFixed(2) + "M";
  }
  if (usdValue >= 1000) {
    return "$" + usdValue.toFixed(0).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  }
  if (usdValue >= 1) {
    return "$" + usdValue.toFixed(2);
  }
  if (usdValue >= 0.01) {
    return "$" + usdValue.toFixed(4);
  }
  return "$" + usdValue.toExponential(2);
}

/**
 * Formats a token amount for display.
 * @param {string|bigint} amount - Amount in base units
 * @param {number} decimals - Token decimals
 * @returns {string} Human-readable amount
 */
function formatAmount(amount, decimals) {
  const bn = BigInt(amount);
  const divisor = BigInt(10 ** decimals);
  const whole = bn / divisor;
  const fraction = bn % divisor;
  const fractionStr = fraction.toString().padStart(decimals, "0").slice(0, 4);
  return (
    formatNumber(Number(whole)) +
    (fractionStr !== "0000" ? "." + fractionStr.replace(/0+$/, "") : "")
  );
}

/**
 * Formats a number with comma separators.
 * @param {number} num - Number to format
 * @returns {string}
 */
function formatNumber(num) {
  return String(num).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

/**
 * Formats a timestamp as relative time, staying relative rather than falling
 * back to a date. Subgraph timestamps arrive as strings, so they are coerced here.
 * @param {number|string} timestamp - Unix timestamp in seconds
 * @returns {string} Relative time string, or "" when there is no timestamp
 */
function formatTimeAgo(timestamp) {
  if (!timestamp) return "";

  const now = Math.floor(Date.now() / 1000);
  const ts = typeof timestamp === "string" ? parseInt(timestamp) : timestamp;
  const diff = now - ts;

  if (diff < 0) return "just now"; // Clock skew, not the future

  if (diff < 60) return diff + "s ago";
  if (diff < 3600) return Math.floor(diff / 60) + "m ago";
  if (diff < 86400) return Math.floor(diff / 3600) + "h ago";
  if (diff < 604800) return Math.floor(diff / 86400) + "d ago";
  if (diff < 2592000) return Math.floor(diff / 604800) + "w ago";
  return Math.floor(diff / 2592000) + "mo ago";
}

/**
 * Formats a ratio for price display.
 * @param {number} num - Ratio value
 * @returns {string} Formatted ratio
 */
function formatRatio(num) {
  if (num === 0) return "0";
  if (num >= 1000000) {
    return (num / 1000000).toFixed(2) + "M";
  }
  if (num >= 1000) {
    return num.toFixed(0).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  }
  if (num >= 1) {
    return num.toFixed(4).replace(/\.?0+$/, "");
  }
  if (num >= 0.0001) {
    return num.toFixed(6).replace(/\.?0+$/, "");
  }
  return num.toExponential(2);
}

/**
 * Parses a human-readable amount string to base units.
 * Excess decimals truncate silently unless that would zero the whole amount.
 * @param {string} str - Amount string (e.g., "100.5", "1,000")
 * @param {number} decimals - Token decimals
 * @returns {bigint} Amount in base units; an empty or blank string is 0
 * @throws {Error} On malformed input, or on dust that truncates away entirely
 */
function parseAmount(str, decimals) {
  // Guard before .trim() so a non-string rejects rather than throwing TypeError
  if (typeof str !== "string") {
    throw new Error("Invalid amount format. Use numbers only.");
  }
  str = str.trim();
  if (!str) return BigInt(0);
  const cleaned = str.replace(/,/g, "");
  if (!/^\d+(\.\d+)?$/.test(cleaned)) {
    throw new Error("Invalid amount format. Use numbers only.");
  }
  const parts = cleaned.split(".");
  const intPart = parts[0] || "0";
  let decPart = parts[1] || "";
  if (decPart.length > decimals) {
    // Check if truncation would result in zero
    const truncated = decPart.slice(0, decimals);
    if (intPart === "0" && /^0*$/.test(truncated)) {
      throw new Error(`Too many decimals. This token only supports ${decimals} decimal places.`);
    }
    decPart = truncated;
  } else {
    decPart = decPart.padEnd(decimals, "0");
  }
  return BigInt(intPart + decPart);
}

// ============================================================================
// Price Functions
// ============================================================================

/**
 * Price cache with TTL tracking, shared by every price lookup in the app.
 * @type {Map<string, {usd: number, fetchedAt: number}>}
 */
const priceCache = new Map();

/** How long a fetched price stays usable. */
const PRICE_CACHE_TTL_MS = 60000;

/** In-flight fetch, so concurrent callers coalesce onto one request. */
let priceFetchInProgress = null;

/**
 * Returns cached price if valid, null otherwise.
 * @param {string} coinGeckoId - CoinGecko coin ID
 * @param {Map} [cache] - Price cache map
 * @param {number} [ttlMs] - Cache TTL in milliseconds
 * @returns {{usd: number, fetchedAt: number}|null}
 */
function getCachedPrice(coinGeckoId, cache = priceCache, ttlMs = PRICE_CACHE_TTL_MS) {
  const cached = cache.get(coinGeckoId);
  if (!cached) return null;
  if (Date.now() - cached.fetchedAt > ttlMs) return null;
  return cached;
}

/**
 * Gets USD price for a token address from cache.
 * @param {string} tokenAddress - Ethereum token address
 * @param {Map} [cache] - Price cache map
 * @param {number} [ttlMs] - Cache TTL in milliseconds
 * @returns {number|null} USD price or null if unavailable
 */
function getTokenPrice(tokenAddress, cache = priceCache, ttlMs = PRICE_CACHE_TTL_MS) {
  const id = COINGECKO_ID_MAP[tokenAddress.toLowerCase()];
  if (!id) return null;
  const cached = getCachedPrice(id, cache, ttlMs);
  return cached ? cached.usd : null;
}

/**
 * Fetches prices for multiple CoinGecko IDs in a single request.
 * Implements rate limiting via request coalescing.
 * @param {string[]} coinGeckoIds - Array of CoinGecko coin IDs
 * @param {Map} [cache] - Price cache map to populate
 * @param {number} [ttlMs] - Cache TTL in milliseconds
 * @returns {Promise<void>}
 */
async function fetchPrices(coinGeckoIds, cache = priceCache, ttlMs = PRICE_CACHE_TTL_MS) {
  const idsToFetch = coinGeckoIds.filter((id) => !getCachedPrice(id, cache, ttlMs));
  if (idsToFetch.length === 0) return;

  if (priceFetchInProgress) {
    await priceFetchInProgress;
    return;
  }

  const controller = new AbortController();
  const timeoutId = setTimeout(() => controller.abort(), 10000);

  priceFetchInProgress = (async () => {
    try {
      const url =
        "https://api.coingecko.com/api/v3/simple/price?ids=" +
        idsToFetch.join(",") +
        "&vs_currencies=usd";
      const res = await fetch(url, { signal: controller.signal });
      clearTimeout(timeoutId);

      if (!res.ok) {
        if (res.status === 429) {
          console.warn("[Price] Rate limited by CoinGecko");
        }
        return;
      }

      const data = await res.json();
      const now = Date.now();

      for (const id of idsToFetch) {
        if (data[id] && typeof data[id].usd === "number") {
          cache.set(id, { usd: data[id].usd, fetchedAt: now });
        }
      }
    } catch (e) {
      clearTimeout(timeoutId);
      if (e.name === "AbortError") {
        console.warn("[Price] Request timed out");
      } else {
        console.warn("[Price] Fetch failed:", e.message);
      }
    }
  })();

  await priceFetchInProgress;
  priceFetchInProgress = null;
}

/**
 * CoinGecko coin page for a token, when one is known.
 * Callers build their own anchor element; only the lookup and URL shape live here.
 * @param {string} address - Token address
 * @returns {string|null} Coin page URL, or null when the token is unlisted
 */
function coinGeckoUrl(address) {
  if (typeof address !== "string") return null;
  const id = COINGECKO_ID_MAP[address.toLowerCase()];
  return id ? "https://www.coingecko.com/en/coins/" + id : null;
}

/**
 * Human-readable price of one denominator token in numerator tokens.
 * Both sides are base units, so their decimals divide back out as one factor.
 * @param {string|bigint} amountNum - Numerator amount, in base units
 * @param {string|bigint} amountDen - Denominator amount, in base units
 * @param {number} decNum - Decimals of the numerator token
 * @param {number} decDen - Decimals of the denominator token
 * @returns {number} Price, or 0 when the denominator is zero
 */
function priceRatio(amountNum, amountDen, decNum, decDen) {
  const den = BigInt(amountDen);
  if (den === 0n) return 0;
  return (Number(BigInt(amountNum)) / Number(den)) * Math.pow(10, decDen - decNum);
}

/**
 * Calculates the market rate deviation for an order.
 * @param {Object} order - Order with tokenA/tokenB and amounts
 * @param {function} [getPriceFn] - Function to get token price
 * @returns {{deviation: number, label: string}|null} Deviation percentage and label
 */
function calculateMarketDeviation(order, getPriceFn = getTokenPrice) {
  const priceA = getPriceFn(order.tokenA.address);
  const priceB = getPriceFn(order.tokenB.address);

  if (priceA === null || priceB === null) return null;
  if (priceA === 0 || priceB === 0) return null;

  const amountA = BigInt(order.amountA);
  const amountB = BigInt(order.amountB);

  if (amountA === 0n || amountB === 0n) return null;

  const marketRate = priceA / priceB;
  const humanAmountA = Number(amountA) / Math.pow(10, order.tokenA.decimals);
  const humanAmountB = Number(amountB) / Math.pow(10, order.tokenB.decimals);
  const orderRate = humanAmountB / humanAmountA;

  const deviation = ((orderRate - marketRate) / marketRate) * 100;

  let label;
  if (Math.abs(deviation) < 0.5) {
    label = "~market";
  } else if (deviation > 0) {
    label = "+" + deviation.toFixed(1) + "%";
  } else {
    label = deviation.toFixed(1) + "%";
  }

  return { deviation, label };
}

// ============================================================================
// Token Search Functions
// ============================================================================

/**
 * Searches tokens by symbol or name.
 * `prepend` seeds entries that are not in `tokenList` at all (the app uses it for
 * native ETH); seeded entries count toward `limit` like any other result.
 * @param {string} query - Search query
 * @param {Array} tokenList - List of tokens to search
 * @param {number} limit - Max results
 * @param {Array} [prepend] - Tokens to place ahead of the matches
 * @returns {Array} Matching tokens
 */
function searchTokens(query, tokenList, limit = 10, prepend = []) {
  if (!query || query.length < 1) return [];

  const q = query.toLowerCase();
  const results = [...prepend];

  // Exact symbol matches first
  for (const t of tokenList) {
    if (t.symbol.toLowerCase() === q) {
      results.push(t);
    }
  }

  // Symbol starts with query
  for (const t of tokenList) {
    if (t.symbol.toLowerCase().startsWith(q) && !results.includes(t)) {
      results.push(t);
      if (results.length >= limit) return results;
    }
  }

  // Symbol or name contains query
  for (const t of tokenList) {
    if (
      (t.symbol.toLowerCase().includes(q) || t.name.toLowerCase().includes(q)) &&
      !results.includes(t)
    ) {
      results.push(t);
      if (results.length >= limit) return results;
    }
  }

  return results;
}

// ============================================================================
// Order Helpers
// ============================================================================

/**
 * The lifecycle state of an order, as one word.
 * Once an order is inactive, a recorded taker separates a fill from a cancel.
 * @param {Object} order - Order with `active` and `taker`
 * @returns {"Open"|"Filled"|"Cancelled"}
 */
function orderStatus(order) {
  if (order.active) return "Open";
  return order.taker ? "Filled" : "Cancelled";
}

// ============================================================================
// localStorage Functions
// ============================================================================

const RECENT_TOKENS_KEY = "swapboard_recent_tokens";
const MAX_RECENT_TOKENS = 5;
const FILTERS_KEY = "swapboard_filters";
const SORT_KEY = "swapboard_sort";
const WATCHED_ORDERS_KEY = "swapboard_watched_orders";

/**
 * Gets recent tokens from localStorage.
 * @param {Storage} storage - Storage object
 * @returns {Array<{address: string, symbol: string}>}
 */
function getRecentTokens(storage) {
  try {
    const stored = storage.getItem(RECENT_TOKENS_KEY);
    return stored ? JSON.parse(stored) : [];
  } catch (e) {
    return [];
  }
}

/**
 * Adds a token to recent tokens list.
 * @param {string} address - Token address
 * @param {string} symbol - Token symbol
 * @param {Storage} storage - Storage object
 */
function addRecentToken(address, symbol, storage) {
  if (!address || !symbol) return;

  const recent = getRecentTokens(storage);
  const lowerAddr = address.toLowerCase();

  const filtered = recent.filter((t) => t.address.toLowerCase() !== lowerAddr);
  filtered.unshift({ address, symbol });
  const trimmed = filtered.slice(0, MAX_RECENT_TOKENS);

  try {
    storage.setItem(RECENT_TOKENS_KEY, JSON.stringify(trimmed));
  } catch (e) {
    // Storage unavailable
  }
}

/**
 * Gets watched orders from localStorage.
 * @param {Storage} storage - Storage object
 * @returns {Object}
 */
function getWatchedOrders(storage) {
  try {
    const stored = storage.getItem(WATCHED_ORDERS_KEY);
    return stored ? JSON.parse(stored) : {};
  } catch (e) {
    return {};
  }
}

/**
 * Adds an order to the watch list.
 * @param {Object} order - Order object
 * @param {Storage} storage - Storage object
 */
function watchOrder(order, storage) {
  const watched = getWatchedOrders(storage);
  watched[order.orderId] = {
    status: orderStatus(order),
    symbol: order.tokenA.symbol + "/" + order.tokenB.symbol,
  };
  try {
    storage.setItem(WATCHED_ORDERS_KEY, JSON.stringify(watched));
  } catch (e) {
    // Storage unavailable
  }
}

/**
 * Removes an order from the watch list.
 * @param {string} orderId - Order ID
 * @param {Storage} storage - Storage object
 */
function unwatchOrder(orderId, storage) {
  const watched = getWatchedOrders(storage);
  delete watched[orderId];
  try {
    storage.setItem(WATCHED_ORDERS_KEY, JSON.stringify(watched));
  } catch (e) {
    // Storage unavailable
  }
}

/**
 * Checks if an order is being watched.
 * @param {string} orderId - Order ID
 * @param {Storage} storage - Storage object
 * @returns {boolean}
 */
function isOrderWatched(orderId, storage) {
  const watched = getWatchedOrders(storage);
  return orderId in watched;
}

/**
 * Saves filter preferences to localStorage.
 * @param {Object} filters - Filter object
 * @param {Storage} storage - Storage object
 */
function saveFilterPreferences(filters, storage) {
  try {
    storage.setItem(FILTERS_KEY, JSON.stringify(filters));
  } catch (e) {
    // Storage unavailable
  }
}

/**
 * Loads filter preferences from localStorage.
 * @param {Storage} storage - Storage object
 * @returns {Object|null}
 */
function loadFilterPreferences(storage) {
  try {
    const stored = storage.getItem(FILTERS_KEY);
    return stored ? JSON.parse(stored) : null;
  } catch (e) {
    return null;
  }
}

/**
 * Saves sort preferences to localStorage.
 * @param {Object} sort - Sort object
 * @param {Storage} storage - Storage object
 */
function saveSortPreferences(sort, storage) {
  try {
    storage.setItem(SORT_KEY, JSON.stringify(sort));
  } catch (e) {
    // Storage unavailable
  }
}

/**
 * Loads sort preferences from localStorage.
 * @param {Storage} storage - Storage object
 * @returns {Object|null}
 */
function loadSortPreferences(storage) {
  try {
    const stored = storage.getItem(SORT_KEY);
    return stored ? JSON.parse(stored) : null;
  } catch (e) {
    return null;
  }
}

// ============================================================================
// Sort Functions
// ============================================================================

/**
 * The price of an order in the direction the Price column quotes it.
 * @param {Object} order - Order with tokenA/tokenB and amounts
 * @param {function(string, string): ("A"|"B"|null)} quoteSideFn - Picks the quote side
 * @returns {number} Price in the quoted direction, or 0 when a side is empty
 */
function quotedPrice(order, quoteSideFn) {
  const { tokenA, tokenB, amountA, amountB } = order;
  return quoteSideFn(tokenA.address, tokenB.address) === "A"
    ? priceRatio(amountA, amountB, tokenA.decimals, tokenB.decimals)
    : priceRatio(amountB, amountA, tokenB.decimals, tokenA.decimals);
}

/**
 * Sorts orders by the specified column and direction.
 * Amounts compare in human units, since base units are not comparable across
 * tokens of differing precision. The defaults for the two injected functions
 * match what the app produces before prices load.
 * @param {Array} orders - Orders to sort
 * @param {string} column - Column to sort by
 * @param {string} direction - 'asc' or 'desc'
 * @param {function(string): (number|null)} [getPriceFn] - USD price for a token
 * @param {function(string, string): ("A"|"B"|null)} [quoteSideFn] - Quote side for a pair
 * @returns {Array} Sorted orders
 */
function sortOrders(orders, column, direction, getPriceFn = () => null, quoteSideFn = () => null) {
  const dir = direction === "asc" ? 1 : -1;

  /** Amount in human units, so tokens of differing precision compare. */
  const human = (amount, decimals) => Number(BigInt(amount)) / Math.pow(10, decimals);

  /** USD value of the offered side; -1 sinks orders whose price is unknown. */
  const usdValue = (o) => {
    const price = getPriceFn(o.tokenA.address);
    return price !== null && price !== undefined ? human(o.amountA, o.tokenA.decimals) * price : -1;
  };

  return [...orders].sort((a, b) => {
    let valA, valB;

    switch (column) {
      case "orderId":
        valA = parseInt(a.orderId);
        valB = parseInt(b.orderId);
        break;
      case "maker":
        valA = a.maker.toLowerCase();
        valB = b.maker.toLowerCase();
        break;
      case "tokenA":
        valA = (a.tokenA.symbol || "").toLowerCase();
        valB = (b.tokenA.symbol || "").toLowerCase();
        break;
      case "amountA":
        valA = human(a.amountA, a.tokenA.decimals);
        valB = human(b.amountA, b.tokenA.decimals);
        break;
      case "tokenB":
        valA = (a.tokenB.symbol || "").toLowerCase();
        valB = (b.tokenB.symbol || "").toLowerCase();
        break;
      case "amountB":
        valA = human(a.amountB, a.tokenB.decimals);
        valB = human(b.amountB, b.tokenB.decimals);
        break;
      case "usdVal":
        valA = usdValue(a);
        valB = usdValue(b);
        break;
      case "price":
        valA = quotedPrice(a, quoteSideFn);
        valB = quotedPrice(b, quoteSideFn);
        break;
      default:
        return 0;
    }

    if (typeof valA === "string") {
      return valA.localeCompare(valB) * dir;
    }
    return (valA - valB) * dir;
  });
}

// ============================================================================
// Error Parsing
// ============================================================================

const ERROR_SIGNATURES = {
  "0xd92e233d": "ZeroAddress",
  "0x1f2a2005": "ZeroAmount",
  "0x201b580a": "SameToken",
  "0x8a8b41ec": "NotAContract",
  "0x6e65ed84": "BalanceMismatch",
  "0x4e90badc": "OrderNotFound",
  "0xd2c02610": "OrderNotActive",
  "0x98cd7222": "NotMaker",
  "0x6bdafcae": "ZeroETH",
  "0xcfc02c6e": "NotWETH",
  "0x8230dc8f": "ETHAmountMismatch",
  "0x1c988062": "ETHTransferFailed",
  "0x1ab7da6b": "DeadlineExpired",
};

/**
 * User-facing text per contract error. A function receives the decoded
 * arguments, so an error carrying an order id can name it.
 * @constant {Object<string, string|function(bigint[]): string>}
 */
const ERROR_MESSAGES = {
  ZeroAddress: "Invalid token address",
  ZeroAmount: "Amount too small (check decimal places)",
  SameToken: "Offered and wanted tokens must be different",
  NotAContract: "Token address is not a contract",
  BalanceMismatch: "Token transfer amount mismatch (fee-on-transfer tokens not supported)",
  OrderNotFound: (args) => `Order #${args[0]} not found`,
  OrderNotActive: (args) => `Order #${args[0]} is no longer active`,
  NotMaker: "You are not the maker of this order",
  ZeroETH: "ETH amount cannot be zero",
  NotWETH: "Token is not WETH",
  ETHAmountMismatch: "ETH amount does not match required amount",
  ETHTransferFailed: "ETH transfer to recipient failed",
  DeadlineExpired: "Transaction deadline passed. Please try again.",
};

/**
 * Splits ABI-encoded error arguments into 32-byte words. Every argument these
 * errors carry is a uint256 or address, so words read positionally with no ABI coder.
 * @param {string} data - Error data hex string, selector included
 * @returns {bigint[]} One bigint per word; addresses come back as numbers too
 */
function decodeErrorArgs(data) {
  const body = data.slice(10);
  const args = [];
  for (let i = 0; i + 64 <= body.length; i += 64) {
    try {
      args.push(BigInt("0x" + body.slice(i, i + 64)));
    } catch {
      break;
    }
  }
  return args;
}

/**
 * Decodes a contract error from its revert data.
 * Matches the 4-byte selector rather than an ABI, so it needs no ethers.
 * @param {string} data - Error data hex string
 * @returns {{name: string, message: string}|null} Null when unrecognized
 */
function decodeContractError(data) {
  if (!data || typeof data !== "string") return null;
  if (data === "0x") return null;

  const selector = data.slice(0, 10).toLowerCase();
  const errorName = ERROR_SIGNATURES[selector];
  if (!errorName) return null;

  const template = ERROR_MESSAGES[errorName];
  const message =
    typeof template === "function" ? template(decodeErrorArgs(data)) : template || errorName;

  return { name: errorName, message };
}

/**
 * Revert data out of an exception, wherever the provider happened to put it.
 * ethers v6 uses three different fields, and some providers only the message text.
 * @param {Error} e - Exception object
 * @returns {string|null} Hex revert data, or null when none is present
 */
function extractRevertData(e) {
  const direct = e.data || e.error?.data || e.info?.error?.data;
  if (typeof direct === "string" && direct.startsWith("0x")) return direct;

  const match = (e.message || "").match(/data="(0x[a-fA-F0-9]+)"/);
  return match ? match[1] : null;
}

/**
 * Provider and RPC failures with no revert data, matched on their text.
 * Ordered most specific first: "allowance" must precede the bare "insufficient".
 * @constant {Array<{test: function(string): boolean, message: string}>}
 */
const ERROR_PATTERNS = [
  {
    test: (m) => m.includes("allowance"),
    message: "Token approval failed",
  },
  {
    test: (m) => m.includes("insufficient funds") || m.includes("insufficient funds for gas"),
    message: "Insufficient funds for transaction",
  },
  {
    test: (m) =>
      m.includes("insufficient") ||
      m.includes("exceeds balance") ||
      m.includes("transfer amount exceeds"),
    message: "Insufficient token balance",
  },
  { test: (m) => m.includes("nonce"), message: "Transaction conflict, try again" },
  {
    test: (m) => m.includes("could not decode result data") || m.includes("bad_data"),
    message: "Token contract not found on this network",
  },
  {
    test: (m) => m.includes("missing revert data"),
    message: "Transaction failed. Order may already be filled or cancelled.",
  },
  {
    test: (m) => m.includes("gas") && m.includes("estimation"),
    message: "Transaction would fail. Check order status and try again.",
  },
  {
    test: (m) => m.includes("network") || m.includes("disconnected"),
    message: "Network error. Check your connection.",
  },
  { test: (m) => m.includes("timeout"), message: "Request timed out. Please try again." },
  {
    test: (m) => m.includes("replacement") && m.includes("underpriced"),
    message: "Gas price too low. Try again with higher gas.",
  },
];

/** Longest technical message worth showing the user verbatim. */
const MAX_SHORT_MESSAGE = 100;

/**
 * Turns a transaction exception into something worth showing a user, trying the
 * most trustworthy signal first: revert data, then error codes, then a
 * `reason="..."` string, then text patterns, then a short-enough `shortMessage`.
 * Never falls through to the raw `message`, which is multi-line ethers noise.
 * @param {Error} e - Exception object
 * @returns {string} User-friendly error message
 */
function parseContractError(e) {
  if (!e) return "Transaction failed. Please try again.";

  const decoded = decodeContractError(extractRevertData(e));
  if (decoded) return decoded.message;

  // Before any text matching: a terse code-4001 wallet is still a rejection
  if (e.code === 4001 || e.code === "ACTION_REJECTED") {
    return "Transaction cancelled";
  }

  const msg = (e.reason || e.message || "").toLowerCase();
  if (msg.includes("user rejected") || msg.includes("user denied")) {
    return "Transaction cancelled";
  }

  // A require() string from the chain beats anything matched below it
  const reasonMatch = (e.message || "").match(/reason="([^"]+)"/);
  if (reasonMatch) return reasonMatch[1];

  for (const { test, message } of ERROR_PATTERNS) {
    if (test(msg)) return message;
  }

  if (msg.includes("execution reverted")) {
    return "Transaction failed. The order may no longer be available.";
  }

  if (e.shortMessage && e.shortMessage.length < MAX_SHORT_MESSAGE) {
    return e.shortMessage;
  }
  return "Transaction failed. Please try again.";
}

// ============================================================================
// Configuration Validation
// ============================================================================

/**
 * Validates the application configuration.
 * @param {Object} config - Config object
 * @param {boolean} isLocal - Whether running in local/dev mode
 * @returns {{valid: boolean, errors: string[]}}
 */
function validateConfig(config, isLocal) {
  if (isLocal) {
    return { valid: true, errors: [] };
  }

  const errors = [];
  if (config.CONTRACT_ADDRESS === "0x0000000000000000000000000000000000000000") {
    errors.push("CONTRACT_ADDRESS is not configured");
  }
  if (config.SUBGRAPH_URL.includes("YOUR_ID")) {
    errors.push("SUBGRAPH_URL is not configured");
  }

  return { valid: errors.length === 0, errors };
}

// ============================================================================
// Protocol Version
// ============================================================================
//
// Swapboard v1 is deployed and live; v2 is not. The two differ in three ways
// that reach all the way up into the UI, so the version is resolved once at
// startup and everything downstream reads it through VERSION_CAPS:
//
//   1. Subgraph shape. The deployed v1 subgraph has no partialFill /
//      originalAmountA / originalAmountB, and GraphQL rejects an entire query
//      on one unknown field — so asking for the v2 shape in v1 mode returns
//      nothing at all, not a partial result. orderQueryFields() is the fix.
//   2. Contract surface. v1 has no partial fills and no batch entry points.
//   3. Native ETH. v1 has no NATIVE_ETH sentinel; it reaches ETH by treating
//      a WETH-denominated side as a wrap/unwrap. v2 escrows ETH directly.
//
// ============================================================================

/** localStorage key persisting the user's chosen protocol version. */
const VERSION_STORAGE_KEY = "swapboard_version";

/**
 * Version used when nothing else selects one.
 * v1, because it is the only version with deployed contracts and a subgraph
 * that answers — v2 is opt-in preview until that changes.
 * @constant {number}
 */
const DEFAULT_VERSION = 1;

/** Versions this frontend knows how to speak. */
const SUPPORTED_VERSIONS = [1, 2];

/**
 * What each protocol version can do. The UI gates on these rather than
 * comparing version numbers inline, so adding v3 means adding a row here.
 *
 * @constant {Object<number, Object>}
 */
const VERSION_CAPS = {
  1: {
    version: 1,
    label: "v1",
    /**
     * Deployed Swapboard v1, and the subgraph that indexes it.
     *
     * The trailing `deploy:` markers are load-bearing: deploy.sh anchors its
     * rewrite on them so it patches the slot for the version it just shipped
     * and leaves the other version alone.
     */
    contractAddress: "0x000000fF3D7A2d373615141d7489Ca66683DbecF", // deploy:v1:contract
    subgraphUrl:
      "https://api.goldsky.com/api/public/project_cmmkvehnce9da01u17d657vdt/subgraphs/Swapboard/1.0.0/gn", // deploy:v1:subgraph
    /** Orders are all-or-nothing; no fill-amount controls. */
    partialFill: false,
    /** No multicall entry points; one order per transaction. */
    batch: false,
    /** No NATIVE_ETH sentinel — ETH is reached through WETH wrap/unwrap. */
    nativeEth: false,
    /** Sell form creates exactly one order at a time. */
    multiCreate: false,
    /** Subgraph exposes no original-vs-remaining split. */
    remainingAmounts: false,
    /** Real contracts, so a gas estimate can be encoded and shown. */
    gasEstimate: true,
    /** Real subgraph, so post-transaction indexing can be polled. */
    subgraphPolling: true,
    /** Writes hit chain. */
    live: true,
  },
  2: {
    version: 2,
    label: "v2",
    /**
     * Placeholders until v2 ships: there is no deployed contract and no
     * subgraph indexing one. `live: false` below is what keeps these from
     * being reached, and validateConfig only enforces them once a version
     * goes live. deploy.sh fills both in.
     */
    contractAddress: "0x0000000000000000000000000000000000000000", // deploy:v2:contract
    subgraphUrl:
      "https://api.goldsky.com/api/public/project_YOUR_ID/subgraphs/swapboard-v2/2.0.0/gn", // deploy:v2:subgraph
    partialFill: true,
    batch: true,
    nativeEth: true,
    multiCreate: true,
    remainingAmounts: true,
    // Both off until the v2 contracts and subgraph exist: there is no ABI to
    // encode a gas estimate against, and polling an index that will never
    // update only ever times out.
    gasEstimate: false,
    subgraphPolling: false,
    /** Writes go to the dummy connector. */
    live: false,
  },
};

/**
 * Coerces an arbitrary value to a supported version number.
 * @param {*} value - Candidate version ("1", 2, "v2", ...)
 * @returns {number|null} Supported version, or null when unrecognized
 */
function parseVersion(value) {
  if (value === null || value === undefined) return null;
  const normalized = String(value).trim().toLowerCase().replace(/^v/, "");
  const parsed = Number(normalized);
  return SUPPORTED_VERSIONS.includes(parsed) ? parsed : null;
}

/**
 * Resolves which protocol version to run, in precedence order:
 *   1. `?v=` URL parameter — explicit, and wins so a link can pin a version
 *   2. localStorage — the user's last choice from the header switcher
 *   3. DEFAULT_VERSION
 *
 * Mirrors how mock.js resolves mock mode, so the two behave alike.
 *
 * @param {Object} [sources] - Resolution inputs
 * @param {string} [sources.search] - location.search, e.g. "?v=2"
 * @param {*} [sources.stored] - Persisted preference
 * @returns {{version: number, pinned: boolean}} Resolved version, and whether
 *   the URL pinned it (in which case the switcher must rewrite the URL)
 */
function resolveVersion(sources) {
  const { search = "", stored = null } = sources || {};

  let param = null;
  try {
    param = new URLSearchParams(search).get("v");
  } catch {
    param = null;
  }

  const fromParam = parseVersion(param);
  if (fromParam !== null) return { version: fromParam, pinned: true };

  const fromStore = parseVersion(stored);
  if (fromStore !== null) return { version: fromStore, pinned: false };

  return { version: DEFAULT_VERSION, pinned: false };
}

/**
 * Capability set for a version, falling back to the default version's.
 * @param {number} version - Protocol version
 * @returns {Object} Capability descriptor
 */
function capsFor(version) {
  return VERSION_CAPS[version] || VERSION_CAPS[DEFAULT_VERSION];
}

/**
 * Deployment coordinates for a version, in the shape validateConfig expects.
 *
 * Read through this rather than off a module-level constant: which contract
 * and which subgraph are correct depends entirely on the active version.
 *
 * @param {number} version - Protocol version
 * @returns {{CONTRACT_ADDRESS: string, SUBGRAPH_URL: string}} Deployment coordinates
 */
function deploymentFor(version) {
  const caps = capsFor(version);
  return { CONTRACT_ADDRESS: caps.contractAddress, SUBGRAPH_URL: caps.subgraphUrl };
}

/**
 * Order fields to request from the subgraph for a given version.
 *
 * v2-only fields are omitted in v1 mode because the deployed subgraph errors
 * on unknown fields and returns no data at all.
 *
 * @param {number} version - Protocol version
 * @returns {string[]} Field names, in query order
 */
function orderQueryFields(version) {
  const base = [
    "orderId",
    "maker",
    "amountA",
    "amountB",
    "active",
    "taker",
    "createdAt",
    "filledAt",
  ];
  if (!capsFor(version).remainingAmounts) return base;
  // Slot the v2 additions next to the amounts they qualify.
  return [
    "orderId",
    "maker",
    "amountA",
    "amountB",
    "originalAmountA",
    "originalAmountB",
    "partialFill",
    "active",
    "taker",
    "createdAt",
    "filledAt",
  ];
}

/**
 * Fills in the v2-shaped fields a v1 subgraph never returns, so rendering and
 * fill math stay on one code path regardless of version.
 *
 * A v1 order is all-or-nothing and never partly filled, so its remaining
 * amount is by definition its original amount.
 *
 * @param {Object} order - Raw order from the subgraph
 * @param {number} version - Protocol version the order came from
 * @returns {Object} The same order, normalized in place
 */
function normalizeOrder(order, version) {
  if (!order) return order;
  if (capsFor(version).remainingAmounts) {
    // A missing flag means the order never opted in, so treat it as
    // all-or-nothing rather than assuming partial fills are allowed.
    order.partialFill = order.partialFill === true;
    return order;
  }
  order.partialFill = false;
  order.originalAmountA = order.amountA;
  order.originalAmountB = order.amountB;
  return order;
}

/**
 * Whether an offered token is settled as ETH via msg.value rather than an
 * ERC20 transfer.
 *
 * The two versions disagree on what "offering ETH" means: v1 wraps a WETH
 * side through createOrderWithEth, while v2 escrows native ETH under the
 * NATIVE_ETH sentinel and treats WETH as an ordinary ERC20.
 *
 * @param {string} address - Offered token address
 * @param {number} version - Protocol version
 * @param {function(string): boolean} isWethFn - WETH predicate
 * @returns {boolean}
 */
function offersEthDirectly(address, version, isWethFn) {
  if (typeof address !== "string") return false;
  if (capsFor(version).nativeEth) return isNativeEth(address);
  return typeof isWethFn === "function" ? isWethFn(address) : false;
}

// ============================================================================
// V2: Native ETH
// ============================================================================

/**
 * Checks whether an address is the native ETH sentinel.
 * @param {*} addr - Address to test
 * @returns {boolean}
 */
function isNativeEth(addr) {
  if (typeof addr !== "string") return false;
  return addr.toLowerCase() === NATIVE_ETH.toLowerCase();
}

// ============================================================================
// V2: Batching
// ============================================================================

/**
 * Splits a list into fixed-size chunks, one per transaction.
 * @param {Array} items - Items to split
 * @param {number} size - Maximum chunk size
 * @returns {Array[]} Array of chunks (empty when input is unusable)
 */
function chunkArray(items, size) {
  if (!Array.isArray(items)) return [];
  if (!Number.isInteger(size) || size < 1) return [];

  const chunks = [];
  for (let i = 0; i < items.length; i += size) {
    chunks.push(items.slice(i, i + size));
  }
  return chunks;
}

// ============================================================================
// V2: Multi-select rules
// ============================================================================

/**
 * Classifies an order relative to the connected wallet.
 * A selection is either all the user's own orders (-> Cancel All) or all
 * orders made by other people (-> Fill All); the two can never be mixed.
 * @param {Object} order - Order object
 * @param {string|null} userAddress - Connected wallet address
 * @returns {"own"|"other"|null} Selection mode, or null for an unusable order
 */
function resolveSelectionMode(order, userAddress) {
  if (!order || typeof order.maker !== "string") return null;
  if (!userAddress) return "other";
  return order.maker.toLowerCase() === userAddress.toLowerCase() ? "own" : "other";
}

/**
 * Checks whether two orders trade the same token pair, in the same direction.
 * @param {Object} a - First order
 * @param {Object} b - Second order
 * @returns {boolean}
 */
function isSamePair(a, b) {
  if (!a || !b || !a.tokenA || !a.tokenB || !b.tokenA || !b.tokenB) return false;
  return (
    a.tokenA.address.toLowerCase() === b.tokenA.address.toLowerCase() &&
    a.tokenB.address.toLowerCase() === b.tokenB.address.toLowerCase()
  );
}

/**
 * Decides whether an order may join the current selection.
 *
 * Rules, all anchored on the first selected order:
 *  1. Only open orders are selectable.
 *  2. Own orders and other people's orders cannot be mixed.
 *  3. Selecting other people's orders locks the selection to a single pair.
 *  4. Selecting your own orders allows any mix of pairs.
 *
 * @param {Object} candidate - Order being considered
 * @param {Object|null} firstSelected - First order in the selection, if any
 * @param {string|null} userAddress - Connected wallet address
 * @returns {boolean}
 */
function canSelectOrder(candidate, firstSelected, userAddress) {
  if (!candidate || !candidate.active) return false;
  if (!firstSelected) return true;
  if (candidate.orderId === firstSelected.orderId) return true;

  const anchorMode = resolveSelectionMode(firstSelected, userAddress);
  if (resolveSelectionMode(candidate, userAddress) !== anchorMode) return false;

  // Own orders map to Cancel All, which is pair-agnostic.
  if (anchorMode === "own") return true;

  // Fill All batches a single pair, so every order must match the anchor.
  return isSamePair(candidate, firstSelected);
}

/**
 * Returns the IDs of every selectable order between two rows, inclusive.
 * Backs shift-click range selection over the currently rendered order list.
 * @param {Object[]} sortedOrders - Orders in display order
 * @param {string} anchorId - Order ID of the previous plain click
 * @param {string} targetId - Order ID of the shift-clicked row
 * @param {Object|null} firstSelected - First order in the selection, if any
 * @param {string|null} userAddress - Connected wallet address
 * @returns {string[]} Selectable order IDs in the range
 */
function getShiftRangeIds(sortedOrders, anchorId, targetId, firstSelected, userAddress) {
  if (!Array.isArray(sortedOrders)) return [];

  const from = sortedOrders.findIndex((o) => o.orderId === anchorId);
  const to = sortedOrders.findIndex((o) => o.orderId === targetId);
  if (from === -1 || to === -1) return [];

  return sortedOrders
    .slice(Math.min(from, to), Math.max(from, to) + 1)
    .filter((o) => canSelectOrder(o, firstSelected, userAddress))
    .map((o) => o.orderId);
}

// ============================================================================
// V2: Partial fill math
// ============================================================================

/**
 * Computes how much of the offered token a given fill amount buys.
 *
 * Mirrors the contract's `mulDiv(fillAmountB, amountA, amountB)`, which floors
 * and therefore rounds in the maker's favour. `amountA`/`amountB` on a v2 order
 * are the *remaining* amounts.
 *
 * @param {Object} order - Order with amountA/amountB in base units
 * @param {string|bigint} fillAmountB - Amount of the wanted token being paid
 * @returns {bigint} Amount of the offered token received
 */
function computeReceiveFromFill(order, fillAmountB) {
  const amountA = BigInt(order.amountA);
  const amountB = BigInt(order.amountB);
  const fill = BigInt(fillAmountB);

  if (amountB === 0n || fill <= 0n) return 0n;
  if (fill >= amountB) return amountA;
  return (fill * amountA) / amountB;
}

/**
 * Inverts computeReceiveFromFill: given a desired receive amount, works out
 * what must be paid.
 *
 * Rounds the payment up so the taker receives at least what they asked for,
 * then re-floors to report the amount the contract will actually transfer
 * (the two differ by at most one base unit).
 *
 * @param {Object} order - Order with amountA/amountB in base units
 * @param {string|bigint} receiveAmountA - Desired amount of the offered token
 * @returns {{fillAmountB: bigint, actualAmountA: bigint}}
 */
function computeFillFromReceive(order, receiveAmountA) {
  const amountA = BigInt(order.amountA);
  const amountB = BigInt(order.amountB);
  let want = BigInt(receiveAmountA);
  if (want < 0n) want = 0n;

  if (amountA === 0n || amountB === 0n || want === 0n) {
    return { fillAmountB: 0n, actualAmountA: 0n };
  }
  if (want >= amountA) {
    return { fillAmountB: amountB, actualAmountA: amountA };
  }

  let fillAmountB = (want * amountB + amountA - 1n) / amountA;
  if (fillAmountB > amountB) fillAmountB = amountB;

  return { fillAmountB, actualAmountA: computeReceiveFromFill(order, fillAmountB) };
}

/**
 * Aggregates a batch of same-pair orders for the Fill All confirmation.
 * @param {Object[]} orders - Orders to be filled, all sharing a token pair
 * @returns {{count: number, totalSend: bigint, totalReceive: bigint, avgPrice: number|null}}
 *          avgPrice is wanted-token per offered-token, matching the table's Price column
 */
function summarizeFillBatch(orders) {
  if (!Array.isArray(orders) || orders.length === 0) {
    return { count: 0, totalSend: 0n, totalReceive: 0n, avgPrice: null };
  }

  let totalSend = 0n;
  let totalReceive = 0n;
  for (const order of orders) {
    totalSend += BigInt(order.amountB);
    totalReceive += BigInt(order.amountA);
  }

  let avgPrice = null;
  if (totalReceive > 0n) {
    const decimalsA = orders[0].tokenA.decimals;
    const decimalsB = orders[0].tokenB.decimals;
    avgPrice = (Number(totalSend) / Number(totalReceive)) * Math.pow(10, decimalsA - decimalsB);
  }

  return { count: orders.length, totalSend, totalReceive, avgPrice };
}

// ============================================================================
// Exports
// ============================================================================

// Browser: expose on window.SwapboardLib for use by app.js IIFE
if (typeof window !== "undefined") {
  window.SwapboardLib = {
    // Config
    CONFIG,
    EXPECTED_CHAIN_ID,

    // Utility functions
    escapeHtml,
    isValidAddress,
    truncateAddress,
    getOrderIdFromHash,
    getOrderShareUrl,

    // Formatting
    formatUsd,
    formatAmount,
    formatNumber,
    formatTimeAgo,
    formatRatio,
    parseAmount,

    // Price registry
    COINGECKO_ID_MAP,
    coinGeckoUrl,
    priceRatio,
    PRICE_CACHE_TTL_MS,
    getCachedPrice,
    getTokenPrice,
    fetchPrices,
    calculateMarketDeviation,

    // Token search
    searchTokens,

    // Order helpers
    orderStatus,

    // Sorting
    sortOrders,

    // Error handling
    decodeContractError,
    parseContractError,

    // localStorage
    RECENT_TOKENS_KEY,
    MAX_RECENT_TOKENS,
    FILTERS_KEY,
    SORT_KEY,
    WATCHED_ORDERS_KEY,
    getRecentTokens,
    addRecentToken,
    getWatchedOrders,
    watchOrder,
    unwatchOrder,
    isOrderWatched,
    saveFilterPreferences,
    loadFilterPreferences,
    saveSortPreferences,
    loadSortPreferences,

    // Config validation
    validateConfig,

    // Protocol version
    VERSION_STORAGE_KEY,
    DEFAULT_VERSION,
    SUPPORTED_VERSIONS,
    VERSION_CAPS,
    parseVersion,
    resolveVersion,
    capsFor,
    deploymentFor,
    orderQueryFields,
    normalizeOrder,
    offersEthDirectly,

    // V2: native ETH
    NATIVE_ETH,
    isNativeEth,

    // V2: batching
    chunkArray,

    // V2: multi-select rules
    resolveSelectionMode,
    isSamePair,
    canSelectOrder,
    getShiftRangeIds,

    // V2: partial fill math
    computeReceiveFromFill,
    computeFillFromReceive,
    summarizeFillBatch,
  };
}

// Node.js/Jest: CommonJS exports
if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    // Config
    CONFIG,
    EXPECTED_CHAIN_ID,
    COINGECKO_ID_MAP,
    NATIVE_ETH,

    // Utility functions
    escapeHtml,
    isValidAddress,
    truncateAddress,
    getOrderIdFromHash,
    getOrderShareUrl,

    // Formatting
    formatUsd,
    formatAmount,
    formatNumber,
    formatTimeAgo,
    formatRatio,
    parseAmount,

    // Price functions
    PRICE_CACHE_TTL_MS,
    getCachedPrice,
    getTokenPrice,
    fetchPrices,
    coinGeckoUrl,
    priceRatio,
    calculateMarketDeviation,

    // Token search
    searchTokens,

    // Order helpers
    orderStatus,

    // localStorage functions
    RECENT_TOKENS_KEY,
    MAX_RECENT_TOKENS,
    FILTERS_KEY,
    SORT_KEY,
    WATCHED_ORDERS_KEY,
    getRecentTokens,
    addRecentToken,
    getWatchedOrders,
    watchOrder,
    unwatchOrder,
    isOrderWatched,
    saveFilterPreferences,
    loadFilterPreferences,
    saveSortPreferences,
    loadSortPreferences,

    // Sort functions
    sortOrders,

    // Error handling
    ERROR_SIGNATURES,
    ERROR_MESSAGES,
    ERROR_PATTERNS,
    decodeErrorArgs,
    decodeContractError,
    parseContractError,

    // Config validation
    validateConfig,

    // Protocol version
    VERSION_STORAGE_KEY,
    DEFAULT_VERSION,
    SUPPORTED_VERSIONS,
    VERSION_CAPS,
    parseVersion,
    resolveVersion,
    capsFor,
    deploymentFor,
    orderQueryFields,
    normalizeOrder,
    offersEthDirectly,

    // V2: native ETH
    isNativeEth,

    // V2: batching
    chunkArray,

    // V2: multi-select rules
    resolveSelectionMode,
    isSamePair,
    canSelectOrder,
    getShiftRangeIds,

    // V2: partial fill math
    computeReceiveFromFill,
    computeFillFromReceive,
    summarizeFillBatch,
  };
}
