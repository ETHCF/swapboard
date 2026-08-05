/**
 * @fileoverview Swapboard Development Mock Data
 * @description Provides mock data for local development without requiring a live
 *              subgraph or blockchain connection. Intercepts fetch calls to the
 *              subgraph URL and returns generated mock data.
 *
 * @author Zak Cole (numbergroup.xyz) for Ethereum Community Foundation
 * @license AGPL-3.0-only
 *
 * Activation:
 *   Mock mode activates automatically based on the following precedence:
 *
 *   1. URL parameter (highest priority):
 *      - ?mock=true   - Force enable mock mode
 *      - ?mock=false  - Force disable mock mode
 *
 *   2. localStorage (persisted preference):
 *      - localStorage.setItem('swapboard_mock', 'true')
 *      - localStorage.setItem('swapboard_mock', 'false')
 *
 *   3. Hostname detection (default):
 *      - Enabled on: localhost, 127.0.0.1, file:// protocol
 *      - Disabled on: all other hosts (production)
 *
 * Configuration:
 *   - Modify MOCK_CONFIG below to adjust data generation
 *   - Change seed for different deterministic data sets
 *   - All data is generated programmatically for reproducibility
 */

(function () {
  "use strict";

  // ============================================================================
  // Activation Check
  // ============================================================================

  const STORAGE_KEY = "swapboard_mock";

  /**
   * Determines if mock mode should be enabled.
   * Checks URL params, localStorage, and hostname in that order.
   * @returns {boolean}
   */
  function shouldEnableMock() {
    // 1. Check URL parameter (highest priority)
    const urlParams = new URLSearchParams(window.location.search);
    const mockParam = urlParams.get("mock");
    if (mockParam !== null) {
      const enabled = mockParam === "true" || mockParam === "1";
      // Persist the choice
      try {
        localStorage.setItem(STORAGE_KEY, String(enabled));
      } catch (e) {
        // localStorage may be unavailable
      }
      return enabled;
    }

    // 2. Check localStorage (persisted preference)
    try {
      const stored = localStorage.getItem(STORAGE_KEY);
      if (stored !== null) {
        return stored === "true";
      }
    } catch (e) {
      // localStorage may be unavailable
    }

    // 3. Hostname detection (default behavior)
    const hostname = window.location.hostname;
    const protocol = window.location.protocol;
    const isDev =
      hostname === "localhost" ||
      hostname === "127.0.0.1" ||
      hostname === "" ||
      protocol === "file:";

    return isDev;
  }

  // Exit early if mock mode is disabled
  if (!shouldEnableMock()) {
    return;
  }

  // Show mock mode banner
  document.addEventListener("DOMContentLoaded", function () {
    const banner = document.createElement("div");
    banner.id = "mock-banner";
    banner.style.cssText =
      "position:fixed;top:0;left:0;right:0;background:#ff6600;color:#fff;padding:8px 15px;font-size:13px;font-weight:bold;z-index:9999;display:flex;justify-content:space-between;align-items:center;font-family:monospace;";
    banner.innerHTML =
      'MOCK MODE ACTIVE - Data is simulated <button id="mock-disable" style="background:#fff;color:#ff6600;border:none;padding:4px 10px;cursor:pointer;font-weight:bold;font-family:inherit;">Disable</button>';
    document.body.prepend(banner);
    document.getElementById("mock-disable").addEventListener("click", function () {
      localStorage.setItem(STORAGE_KEY, "false");
      window.location.reload();
    });
  });

  // ============================================================================
  // Configuration
  // ============================================================================

  /**
   * Mock data configuration. Adjust these values to change generated data.
   * @constant {Object}
   */
  const MOCK_CONFIG = {
    /** Total number of orders to generate */
    orderCount: 50,

    /** Percentage of orders that remain active/open (0-100) */
    activePercent: 40,

    /** Percentage of closed orders that are filled vs cancelled (0-100) */
    filledPercent: 70,

    /** Random seed for deterministic data generation */
    seed: 12345,

    /** Simulated network delay in milliseconds */
    networkDelay: 150,

    /** Number of unique maker addresses to generate */
    makerCount: 15,

    /** Enable mock wallet provider if no real wallet detected */
    enableMockWallet: true,
  };

  // ============================================================================
  // Seeded Random Number Generator
  // ============================================================================

  /**
   * Creates a seeded PRNG using the mulberry32 algorithm.
   * Ensures reproducible "random" sequences across runs.
   * @param {number} seed - Initial seed value
   * @returns {function(): number} Returns float between 0 and 1
   */
  function createSeededRng(seed) {
    return function () {
      let t = (seed += 0x6d2b79f5);
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  const rng = createSeededRng(MOCK_CONFIG.seed);

  /** Returns random integer in range [min, max] inclusive */
  function randInt(min, max) {
    return Math.floor(rng() * (max - min + 1)) + min;
  }

  /** Returns random element from array */
  function randChoice(arr) {
    return arr[Math.floor(rng() * arr.length)];
  }

  /** Returns true with given probability (0-100) */
  function randPercent(percent) {
    return rng() * 100 < percent;
  }

  // ============================================================================
  // Token Definitions
  // ============================================================================

  /**
   * Real mainnet token addresses and metadata.
   * Using actual addresses makes the mock data feel authentic.
   */
  /**
   * Native ETH, as it appears in v2 orders: a sentinel address with no
   * contract behind it. Kept out of TOKEN_REGISTRY so it can't change how the
   * seeded generator picks token pairs.
   * @constant {Object}
   */
  const NATIVE_ETH_TOKEN = {
    address: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
    symbol: "ETH",
    name: "Ether",
    decimals: 18,
  };

  const TOKEN_REGISTRY = [
    {
      address: "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
      symbol: "WETH",
      name: "Wrapped Ether",
      decimals: 18,
    },
    {
      address: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
      symbol: "USDC",
      name: "USD Coin",
      decimals: 6,
    },
    {
      address: "0xdac17f958d2ee523a2206206994597c13d831ec7",
      symbol: "USDT",
      name: "Tether USD",
      decimals: 6,
    },
    {
      address: "0x6b175474e89094c44da98b954eedeac495271d0f",
      symbol: "DAI",
      name: "Dai Stablecoin",
      decimals: 18,
    },
    {
      address: "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599",
      symbol: "WBTC",
      name: "Wrapped BTC",
      decimals: 8,
    },
    {
      address: "0x514910771af9ca656af840dff83e8264ecf986ca",
      symbol: "LINK",
      name: "Chainlink",
      decimals: 18,
    },
    {
      address: "0x7fc66500c84a76ad7e9c93437bfc5ac33e2ddae9",
      symbol: "AAVE",
      name: "Aave Token",
      decimals: 18,
    },
    {
      address: "0x1f9840a85d5af5bf1d1762f925bdaddc4201f984",
      symbol: "UNI",
      name: "Uniswap",
      decimals: 18,
    },
    {
      address: "0xae7ab96520de3a18e5e111b5eaab095312d7fe84",
      symbol: "stETH",
      name: "Lido Staked ETH",
      decimals: 18,
    },
    {
      address: "0x7d1afa7b718fb893db30a3abc0cfc608aacfebb0",
      symbol: "MATIC",
      name: "Polygon",
      decimals: 18,
    },
    {
      address: "0x6982508145454ce325ddbe47a25d4ec3d2311933",
      symbol: "PEPE",
      name: "Pepe",
      decimals: 18,
    },
    {
      address: "0x95ad61b0a150d79219dcf64e1e6cc01f0b64c4ce",
      symbol: "SHIB",
      name: "Shiba Inu",
      decimals: 18,
    },
  ];

  // ============================================================================
  // Address Generation
  // ============================================================================

  /**
   * Generates a deterministic Ethereum address from an index.
   * @param {number} index - Numeric index
   * @returns {string} Checksummed-style address
   */
  function generateAddress(index) {
    const base = index.toString(16).padStart(8, "0");
    return "0x" + base.repeat(5).slice(0, 40);
  }

  /**
   * Pre-generate maker addresses for consistent distribution.
   */
  const MAKER_ADDRESSES = Array.from({ length: MOCK_CONFIG.makerCount }, (_, i) =>
    generateAddress(0x1000 + i)
  );

  // ============================================================================
  // Amount Generation
  // ============================================================================

  /**
   * Generates a realistic token amount based on the token type.
   * Stablecoins get larger amounts, ETH/BTC get smaller amounts.
   * @param {Object} token - Token object with decimals
   * @returns {string} Amount in base units as string
   */
  function generateAmount(token) {
    let minHuman, maxHuman;

    // Set realistic ranges based on token type
    if (token.symbol === "USDC" || token.symbol === "USDT" || token.symbol === "DAI") {
      minHuman = 100;
      maxHuman = 250000;
    } else if (token.symbol === "WBTC") {
      minHuman = 0.01;
      maxHuman = 5;
    } else if (token.symbol === "WETH" || token.symbol === "ETH" || token.symbol === "stETH") {
      minHuman = 0.1;
      maxHuman = 100;
    } else if (token.symbol === "PEPE" || token.symbol === "SHIB") {
      minHuman = 1000000;
      maxHuman = 10000000000;
    } else {
      minHuman = 10;
      maxHuman = 10000;
    }

    const humanAmount = minHuman + rng() * (maxHuman - minHuman);
    const baseUnits = BigInt(Math.floor(humanAmount * Math.pow(10, token.decimals)));
    return baseUnits.toString();
  }

  // ============================================================================
  // Order Generation
  // ============================================================================

  /**
   * Generates all mock orders based on configuration.
   * @returns {Array<Object>} Array of order objects matching subgraph schema
   */
  function generateOrders() {
    const orders = [];
    const now = Math.floor(Date.now() / 1000);

    for (let i = 0; i < MOCK_CONFIG.orderCount; i++) {
      // Pick two different tokens
      const tokenAIndex = randInt(0, TOKEN_REGISTRY.length - 1);
      let tokenBIndex = randInt(0, TOKEN_REGISTRY.length - 1);
      while (tokenBIndex === tokenAIndex) {
        tokenBIndex = randInt(0, TOKEN_REGISTRY.length - 1);
      }

      let tokenA = TOKEN_REGISTRY[tokenAIndex];
      let tokenB = TOKEN_REGISTRY[tokenBIndex];

      // Determine order status
      const isActive = randPercent(MOCK_CONFIG.activePercent);
      const isFilled = !isActive && randPercent(MOCK_CONFIG.filledPercent);
      const isCancelled = !isActive && !isFilled;

      // Generate timestamps (spread over past 30 days)
      const createdAt = now - randInt(60, 30 * 24 * 60 * 60);
      const closedAt = createdAt + randInt(300, 7 * 24 * 60 * 60);

      // ---- v2 fields ----
      // All of these are derived from the loop index rather than the PRNG, so
      // the seeded stream — and with it the active/filled/cancelled split that
      // test.js asserts on — stays exactly as it was.

      // Some WETH legs become native ETH. Both are 18 decimals, so the
      // generated amounts stay valid, and having both around is what lets you
      // see the UI distinguish them (ETH renders with no contract address).
      if (tokenA.symbol === "WETH" && i % 3 === 0) tokenA = NATIVE_ETH_TOKEN;
      if (tokenB.symbol === "WETH" && i % 4 === 1) tokenB = NATIVE_ETH_TOKEN;

      // Every fifth order opts out of partial fills.
      const partialFill = i % 5 !== 0;

      let amountA = generateAmount(tokenA);
      let amountB = generateAmount(tokenB);
      let originalAmountA = null;
      let originalAmountB = null;

      // A few open, partial-fill-enabled orders are already part-filled, so
      // the remaining-amount display has something to show.
      if (isActive && partialFill && i % 7 === 3) {
        originalAmountA = amountA;
        originalAmountB = amountB;
        amountA = ((BigInt(amountA) * 40n) / 100n).toString();
        amountB = ((BigInt(amountB) * 40n) / 100n).toString();
      }

      orders.push({
        orderId: String(i),
        maker: randChoice(MAKER_ADDRESSES),
        amountA,
        amountB,
        originalAmountA,
        originalAmountB,
        partialFill,
        active: isActive,
        taker: isFilled ? generateAddress(0x3000 + randInt(0, 20)) : null,
        createdAt: String(createdAt),
        createdTx: "0x" + (i * 1000).toString(16).padStart(64, "0"),
        filledAt: isFilled ? String(closedAt) : null,
        filledTx: isFilled ? "0x" + (i * 1000 + 1).toString(16).padStart(64, "0") : null,
        cancelledAt: isCancelled ? String(closedAt) : null,
        cancelledTx: isCancelled ? "0x" + (i * 1000 + 2).toString(16).padStart(64, "0") : null,
        tokenA: {
          address: tokenA.address,
          symbol: tokenA.symbol,
          decimals: tokenA.decimals,
        },
        tokenB: {
          address: tokenB.address,
          symbol: tokenB.symbol,
          decimals: tokenB.decimals,
        },
      });
    }

    // Sort by orderId descending (newest first)
    return orders.sort((a, b) => parseInt(b.orderId) - parseInt(a.orderId));
  }

  const MOCK_ORDERS = generateOrders();

  // ============================================================================
  // Statistics Generation
  // ============================================================================

  /**
   * Calculates global stats from generated orders.
   * @returns {Object} Stats matching GlobalStats schema
   */
  function calculateGlobalStats() {
    const stats = { total: 0, active: 0, filled: 0, cancelled: 0 };

    for (const order of MOCK_ORDERS) {
      stats.total++;
      if (order.active) stats.active++;
      else if (order.taker) stats.filled++;
      else stats.cancelled++;
    }

    return {
      totalOrders: String(stats.total),
      activeOrders: String(stats.active),
      filledOrders: String(stats.filled),
      cancelledOrders: String(stats.cancelled),
      totalVolumeUsd: "2543876.42",
    };
  }

  /**
   * Calculates pair statistics from generated orders.
   * @returns {Array<Object>} Sorted by trade count descending
   */
  function calculatePairStats() {
    const pairMap = new Map();

    for (const order of MOCK_ORDERS) {
      const key = `${order.tokenA.address}-${order.tokenB.address}`;
      if (!pairMap.has(key)) {
        pairMap.set(key, {
          tokenA: order.tokenA,
          tokenB: order.tokenB,
          orderCount: 0,
          tradeCount: 0,
        });
      }
      const pair = pairMap.get(key);
      pair.orderCount++;
      if (order.taker) pair.tradeCount++;
    }

    return Array.from(pairMap.values())
      .sort((a, b) => b.tradeCount - a.tradeCount)
      .slice(0, 10);
  }

  const MOCK_STATS = calculateGlobalStats();
  const MOCK_PAIRS = calculatePairStats();

  // ============================================================================
  // Mock Price Data
  // ============================================================================

  /**
   * Static mock prices for development (approximate real prices).
   * Keys are CoinGecko coin IDs matching COINGECKO_ID_MAP in app.js.
   * @constant {Object.<string, number>}
   */
  const MOCK_PRICES = {
    weth: 3500,
    "usd-coin": 1.0,
    tether: 1.0,
    dai: 1.0,
    "wrapped-bitcoin": 95000,
    chainlink: 22,
    aave: 180,
    uniswap: 12,
    "staked-ether": 3480,
    "matic-network": 0.45,
    pepe: 0.000018,
    "shiba-inu": 0.000022,
  };

  // ============================================================================
  // Query Handler
  // ============================================================================

  /**
   * Filters orders based on GraphQL where clause.
   * @param {string} whereClause - Where clause content
   * @returns {Array} Filtered orders
   */
  function filterOrders(whereClause) {
    if (!whereClause) return MOCK_ORDERS;

    return MOCK_ORDERS.filter((order) => {
      // Status filters
      if (whereClause.includes("active: true") && !order.active) return false;
      if (whereClause.includes("active: false") && order.active) return false;
      if (whereClause.includes("taker_not: null") && !order.taker) return false;
      if (whereClause.includes("taker: null") && order.taker) return false;

      // Token filters
      const tokenAMatch = whereClause.match(/tokenA_:\s*\{\s*address:\s*"([^"]+)"/i);
      if (tokenAMatch && order.tokenA.address.toLowerCase() !== tokenAMatch[1].toLowerCase()) {
        return false;
      }

      const tokenBMatch = whereClause.match(/tokenB_:\s*\{\s*address:\s*"([^"]+)"/i);
      if (tokenBMatch && order.tokenB.address.toLowerCase() !== tokenBMatch[1].toLowerCase()) {
        return false;
      }

      return true;
    });
  }

  /**
   * Handles GraphQL query and returns mock response.
   * @param {string} query - GraphQL query string
   * @returns {Object} Response data
   */
  function handleQuery(query) {
    // Global stats
    if (query.includes("globalStats")) {
      return { globalStats: MOCK_STATS };
    }

    // Pair stats
    if (query.includes("pairStats")) {
      return { pairStatses: MOCK_PAIRS };
    }

    // Token list
    if (query.includes("tokens(")) {
      return {
        tokens: TOKEN_REGISTRY.map((t) => ({
          address: t.address,
          symbol: t.symbol,
        })),
      };
    }

    // Orders query
    if (query.includes("orders(")) {
      // Extract pagination
      const firstMatch = query.match(/first:\s*(\d+)/);
      const skipMatch = query.match(/skip:\s*(\d+)/);
      const first = firstMatch ? parseInt(firstMatch[1]) : 20;
      const skip = skipMatch ? parseInt(skipMatch[1]) : 0;

      // Extract where clause with proper brace matching
      let whereClause = "";
      const whereStart = query.indexOf("where:");
      if (whereStart !== -1) {
        const braceStart = query.indexOf("{", whereStart);
        if (braceStart !== -1) {
          let depth = 0;
          let end = braceStart;
          for (let i = braceStart; i < query.length; i++) {
            if (query[i] === "{") depth++;
            else if (query[i] === "}") depth--;
            if (depth === 0) {
              end = i;
              break;
            }
          }
          whereClause = query.substring(braceStart + 1, end);
        }
      }

      // Filter and paginate
      const filtered = filterOrders(whereClause);
      const paginated = filtered.slice(skip, skip + first);

      return { orders: paginated };
    }

    console.warn("[Mock] Unhandled query type");
    return {};
  }

  // ============================================================================
  // Fetch Interceptor
  // ============================================================================

  const originalFetch = window.fetch;

  window.fetch = async function (url, options) {
    const urlStr = typeof url === "string" ? url : url.toString();

    // Intercept CoinGecko price requests
    if (urlStr.includes("api.coingecko.com/api/v3/simple/price")) {
      await new Promise((r) => setTimeout(r, MOCK_CONFIG.networkDelay));

      // Parse requested IDs from URL
      const urlObj = new URL(urlStr);
      const idsParam = urlObj.searchParams.get("ids") || "";
      const requestedIds = idsParam.split(",").filter(Boolean);

      const data = {};
      for (const id of requestedIds) {
        if (MOCK_PRICES[id] !== undefined) {
          data[id] = { usd: MOCK_PRICES[id] };
        }
      }

      console.log("[Mock] CoinGecko price query:", requestedIds.join(", "));

      return {
        ok: true,
        status: 200,
        json: async () => data,
      };
    }

    // Intercept subgraph requests
    const isSubgraph =
      urlStr.includes("thegraph.com") ||
      urlStr.includes("subgraph") ||
      urlStr.includes("localhost:8");

    if (!isSubgraph) {
      return originalFetch.apply(this, arguments);
    }

    // Parse query from request body
    let query = "";
    try {
      const body = JSON.parse(options?.body || "{}");
      query = body.query || "";
    } catch (e) {
      console.warn("[Mock] Failed to parse request body");
    }

    // Simulate network delay
    await new Promise((r) => setTimeout(r, MOCK_CONFIG.networkDelay));

    // Generate response
    const data = handleQuery(query);
    const responseType = Object.keys(data)[0] || "unknown";
    console.log(`[Mock] ${responseType} query handled`);

    return {
      ok: true,
      status: 200,
      json: async () => ({ data }),
    };
  };

  // ============================================================================
  // Mock Wallet Provider
  // ============================================================================

  if (MOCK_CONFIG.enableMockWallet) {
    console.log("[Mock] Creating mock wallet provider (overriding any existing wallet)");

    const mockAddress = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";
    let connected = false;

    window.ethereum = {
      isMetaMask: true,
      chainId: "0xaa36a7", // Sepolia
      selectedAddress: null,

      request: async function ({ method, params }) {
        console.log("[Mock Wallet]", method);

        switch (method) {
          case "eth_requestAccounts":
            connected = true;
            this.selectedAddress = mockAddress;
            return [mockAddress];

          case "eth_accounts":
            return connected ? [mockAddress] : [];

          case "eth_chainId":
            return "0xaa36a7"; // Sepolia

          case "wallet_switchEthereumChain":
            return null;

          case "eth_sendTransaction":
            await new Promise((r) => setTimeout(r, 2000));
            const txHash = "0x" + Date.now().toString(16).padStart(64, "0");
            console.log("[Mock Wallet] Transaction:", txHash);
            return txHash;

          case "eth_call":
            // Return mock data for common calls
            if (params?.[0]?.data?.startsWith("0x70a08231")) {
              // balanceOf - return large balance
              return "0x" + BigInt(1000000000000000000000n).toString(16).padStart(64, "0");
            }
            if (params?.[0]?.data?.startsWith("0xdd62ed3e")) {
              // allowance - return max uint256
              return "0x" + "f".repeat(64);
            }
            if (params?.[0]?.data?.startsWith("0x095ea7b3")) {
              // approve - return true
              return "0x0000000000000000000000000000000000000000000000000000000000000001";
            }
            if (params?.[0]?.data?.startsWith("0x95d89b41")) {
              // symbol() - encode "MOCK" as hex without Buffer (browser-compatible)
              const symbolHex = "MOCK"
                .split("")
                .map((c) => c.charCodeAt(0).toString(16).padStart(2, "0"))
                .join("");
              return "0x" + symbolHex.padEnd(64, "0");
            }
            if (params?.[0]?.data?.startsWith("0x313ce567")) {
              // decimals() - 18, padded to a full 32-byte word. ethers cannot
              // decode a bare "0x12", and decimals() is the one metadata call
              // fetchTokenInfo does not swallow errors from, so a short value
              // makes every order-creation attempt fail in mock mode.
              return "0x" + (18).toString(16).padStart(64, "0");
            }
            return "0x0000000000000000000000000000000000000000000000000000000000000001";

          case "eth_estimateGas":
            return "0x30000";

          case "eth_gasPrice":
            return "0x3b9aca00";

          case "eth_getBalance":
            // Return 1 ETH
            return "0x" + BigInt(1000000000000000000n).toString(16).padStart(64, "0");

          case "eth_getTransactionReceipt":
            return {
              status: "0x1",
              blockNumber: "0x100",
              transactionHash: params[0],
              logs: [],
            };

          case "eth_blockNumber":
            return "0x" + Math.floor(Date.now() / 12000).toString(16);

          case "net_version":
            return "11155111"; // Sepolia

          default:
            console.warn("[Mock Wallet] Unhandled:", method);
            return null;
        }
      },

      on: function (event, callback) {
        // Store callbacks for potential use
        this._callbacks = this._callbacks || {};
        this._callbacks[event] = callback;
      },

      removeListener: function () {},

      removeAllListeners: function () {},
    };
  }

  // ============================================================================
  // Initialization
  // ============================================================================

  /**
   * Determines why mock mode was activated for logging purposes.
   * @returns {string}
   */
  function getActivationReason() {
    const urlParams = new URLSearchParams(window.location.search);
    if (urlParams.get("mock") !== null) {
      return "URL parameter (?mock=true)";
    }
    try {
      if (localStorage.getItem(STORAGE_KEY) !== null) {
        return "localStorage preference";
      }
    } catch (e) {
      // localStorage unavailable
    }
    const hostname = window.location.hostname;
    if (hostname === "localhost" || hostname === "127.0.0.1") {
      return "localhost detected";
    }
    if (window.location.protocol === "file:") {
      return "file:// protocol detected";
    }
    return "development environment";
  }

  const style = "color: #00ff00; font-weight: bold; font-size: 14px;";
  console.log("%c[Swapboard Mock Mode Enabled]", style);
  console.log("Reason:", getActivationReason());
  console.log(
    "To disable: add ?mock=false to URL or localStorage.setItem('swapboard_mock', 'false')"
  );
  console.log("Configuration:", MOCK_CONFIG);
  console.log("Orders generated:", MOCK_ORDERS.length);
  console.log("Stats:", MOCK_STATS);
  console.log("Tokens:", TOKEN_REGISTRY.map((t) => t.symbol).join(", "));
  console.log("To change data, modify MOCK_CONFIG.seed and refresh");
})();
