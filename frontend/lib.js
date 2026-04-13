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

const CONFIG = {
  CONTRACT_ADDRESS: "0x000000fF3D7A2d373615141d7489Ca66683DbecF",
  SUBGRAPH_URL:
    "https://api.goldsky.com/api/public/project_cmmkvehnce9da01u17d657vdt/subgraphs/Swapboard/1.0.0/gn",
  PAGE_SIZE: 200,
  REQUEST_TIMEOUT: 30000,
  DEBOUNCE_DELAY: 500,
  SHOW_MARKET_DEVIATION: false,
};

const EXPECTED_CHAIN_ID = 1;

const COINGECKO_ID_MAP = {
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
  if (usdValue === null || usdValue === undefined) return "$ --";
  if (usdValue >= 1000000) {
    return "$ " + (usdValue / 1000000).toFixed(2) + "M";
  }
  if (usdValue >= 1000) {
    return "$ " + usdValue.toFixed(0).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  }
  if (usdValue >= 1) {
    return "$ " + usdValue.toFixed(2);
  }
  if (usdValue >= 0.01) {
    return "$ " + usdValue.toFixed(4);
  }
  return "$ " + usdValue.toExponential(2);
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
  return num.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

/**
 * Formats a timestamp as relative time.
 * @param {number} timestamp - Unix timestamp in seconds
 * @returns {string} Relative time string
 */
function formatTimeAgo(timestamp) {
  const now = Math.floor(Date.now() / 1000);
  const diff = now - timestamp;

  if (diff < 60) return "just now";
  if (diff < 3600) return Math.floor(diff / 60) + "m ago";
  if (diff < 86400) return Math.floor(diff / 3600) + "h ago";
  if (diff < 604800) return Math.floor(diff / 86400) + "d ago";

  const date = new Date(timestamp * 1000);
  return date.toLocaleDateString();
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
 * Parses a human-readable amount to base units.
 * @param {string} str - Human-readable amount
 * @param {number} decimals - Token decimals
 * @returns {bigint|null} Amount in base units or null if invalid
 */
function parseAmount(str, decimals) {
  if (!str || typeof str !== "string") return null;

  const cleaned = str.trim().replace(/,/g, "");
  if (!/^\d*\.?\d*$/.test(cleaned) || cleaned === "" || cleaned === ".") {
    return null;
  }

  const parts = cleaned.split(".");
  const wholePart = parts[0] || "0";
  let fracPart = parts[1] || "";

  if (fracPart.length > decimals) {
    fracPart = fracPart.slice(0, decimals);
  }

  fracPart = fracPart.padEnd(decimals, "0");

  try {
    return BigInt(wholePart + fracPart);
  } catch (e) {
    return null;
  }
}

// ============================================================================
// Price Functions
// ============================================================================

/**
 * Returns cached price if valid, null otherwise.
 * @param {string} coinGeckoId - CoinGecko coin ID
 * @param {Map} cache - Price cache map
 * @param {number} ttlMs - Cache TTL in milliseconds
 * @returns {{usd: number, fetchedAt: number}|null}
 */
function getCachedPrice(coinGeckoId, cache, ttlMs) {
  const cached = cache.get(coinGeckoId);
  if (!cached) return null;
  if (Date.now() - cached.fetchedAt > ttlMs) return null;
  return cached;
}

/**
 * Gets USD price for a token address from cache.
 * @param {string} tokenAddress - Ethereum token address
 * @param {Map} cache - Price cache map
 * @param {number} ttlMs - Cache TTL in milliseconds
 * @returns {number|null} USD price or null if unavailable
 */
function getTokenPrice(tokenAddress, cache, ttlMs) {
  const id = COINGECKO_ID_MAP[tokenAddress.toLowerCase()];
  if (!id) return null;
  const cached = getCachedPrice(id, cache, ttlMs);
  return cached ? cached.usd : null;
}

/**
 * Calculates the market rate deviation for an order.
 * @param {Object} order - Order with tokenA/tokenB and amounts
 * @param {function} getPriceFn - Function to get token price
 * @returns {{deviation: number, label: string}|null} Deviation percentage and label
 */
function calculateMarketDeviation(order, getPriceFn) {
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
 * @param {string} query - Search query
 * @param {Array} tokenList - List of tokens to search
 * @param {number} limit - Max results
 * @returns {Array} Matching tokens
 */
function searchTokens(query, tokenList, limit = 10) {
  if (!query || query.length < 1) return [];

  const q = query.toLowerCase();
  const results = [];

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
  const status = order.active ? "Open" : order.taker ? "Filled" : "Cancelled";
  watched[order.orderId] = {
    status: status,
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
 * Sorts orders by the specified column and direction.
 * @param {Array} orders - Orders to sort
 * @param {string} column - Column to sort by
 * @param {string} direction - 'asc' or 'desc'
 * @returns {Array} Sorted orders
 */
function sortOrders(orders, column, direction) {
  const sorted = [...orders];

  sorted.sort((a, b) => {
    let aVal, bVal;

    switch (column) {
      case "orderId":
        aVal = parseInt(a.orderId);
        bVal = parseInt(b.orderId);
        break;
      case "maker":
        aVal = a.maker.toLowerCase();
        bVal = b.maker.toLowerCase();
        break;
      case "tokenA":
        aVal = (a.tokenA.symbol || "").toLowerCase();
        bVal = (b.tokenA.symbol || "").toLowerCase();
        break;
      case "amountA":
        aVal = BigInt(a.amountA);
        bVal = BigInt(b.amountA);
        if (aVal < bVal) return direction === "asc" ? -1 : 1;
        if (aVal > bVal) return direction === "asc" ? 1 : -1;
        return 0;
      case "tokenB":
        aVal = (a.tokenB.symbol || "").toLowerCase();
        bVal = (b.tokenB.symbol || "").toLowerCase();
        break;
      case "amountB":
        aVal = BigInt(a.amountB);
        bVal = BigInt(b.amountB);
        if (aVal < bVal) return direction === "asc" ? -1 : 1;
        if (aVal > bVal) return direction === "asc" ? 1 : -1;
        return 0;
      case "usdVal":
        aVal = a._usdValue || 0;
        bVal = b._usdValue || 0;
        break;
      case "price":
        aVal = a._price || 0;
        bVal = b._price || 0;
        break;
      default:
        return 0;
    }

    if (aVal < bVal) return direction === "asc" ? -1 : 1;
    if (aVal > bVal) return direction === "asc" ? 1 : -1;
    return 0;
  });

  return sorted;
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
};

const ERROR_MESSAGES = {
  ZeroAddress: "Token address cannot be zero",
  ZeroAmount: "Amount cannot be zero",
  SameToken: "Cannot swap token for itself",
  NotAContract: "Address is not a contract",
  BalanceMismatch: "Token transfer amount mismatch (fee-on-transfer tokens not supported)",
  OrderNotFound: "Order does not exist",
  OrderNotActive: "Order is not active",
  NotMaker: "Only the order maker can cancel",
  ZeroETH: "ETH amount cannot be zero",
  NotWETH: "Token is not WETH",
  ETHAmountMismatch: "ETH amount does not match required amount",
  ETHTransferFailed: "ETH transfer to recipient failed",
};

/**
 * Decodes a contract error from its data.
 * @param {string} data - Error data hex string
 * @returns {{name: string, message: string}|null}
 */
function decodeContractError(data) {
  if (!data || typeof data !== "string") return null;

  const selector = data.slice(0, 10).toLowerCase();
  const errorName = ERROR_SIGNATURES[selector];

  if (errorName) {
    return {
      name: errorName,
      message: ERROR_MESSAGES[errorName] || errorName,
    };
  }

  return null;
}

/**
 * Parses a contract error from an exception.
 * @param {Error} e - Exception object
 * @returns {string} User-friendly error message
 */
function parseContractError(e) {
  // Check for revert data
  if (e.data) {
    const decoded = decodeContractError(e.data);
    if (decoded) return decoded.message;
  }

  // Check info.error for nested errors
  if (e.info?.error?.data) {
    const decoded = decodeContractError(e.info.error.data);
    if (decoded) return decoded.message;
  }

  // User rejection
  if (e.code === 4001 || e.code === "ACTION_REJECTED") {
    return "Transaction rejected by user";
  }

  // Insufficient funds
  if (e.code === -32000 || e.message?.includes("insufficient funds")) {
    return "Insufficient funds for transaction";
  }

  // Gas estimation failures
  if (e.message?.includes("execution reverted")) {
    const match = e.message.match(/reason="([^"]+)"/);
    if (match) return match[1];
    return "Transaction would fail";
  }

  // Default
  return e.shortMessage || e.message || "Transaction failed";
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
// Exports
// ============================================================================

// Browser: expose on window.SwapboardLib for use by app.js IIFE
if (typeof window !== "undefined") {
  window.SwapboardLib = {
    // Utility functions
    escapeHtml,
    isValidAddress,
    truncateAddress,

    // Formatting
    formatUsd,
    formatAmount,
  };
}

// Node.js/Jest: CommonJS exports
if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    // Config
    CONFIG,
    EXPECTED_CHAIN_ID,
    COINGECKO_ID_MAP,

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
    getCachedPrice,
    getTokenPrice,
    calculateMarketDeviation,

    // Token search
    searchTokens,

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
    decodeContractError,
    parseContractError,

    // Config validation
    validateConfig,
  };
}
