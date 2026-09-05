/**
 * @fileoverview Swapboard Development Mock Data
 * @description Stands in for the subgraph and the chain so the app can be run
 *              and tested with no deployment behind it. Intercepts subgraph
 *              fetches and installs a wallet provider.
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
 * What this file is for
 * ---------------------
 * Swapboard v2 has no deployed contract and no deployed subgraph, so the mock
 * is the only thing the v2 UI can be exercised against. That makes fidelity the
 * whole point, and it is enforced two ways:
 *
 *   1. The store is built by *replaying* order lifecycles through create/fill/
 *      cancel functions that mirror `subgraph/v2/src/mapping.ts`. Every counter,
 *      remaining amount and status is arrived at the same way the real indexer
 *      arrives at it, rather than being computed independently and hoped to match.
 *   2. Queries are parsed and validated against a schema descriptor transcribed
 *      from `subgraph/v2/schema.graphql`. An unknown field is an error, exactly
 *      as graph-node treats it — which is the failure this mock used to hide,
 *      by pattern-matching queries with `String.includes` and answering whatever
 *      it felt like.
 *
 * Both schemas are described, so `?v=1` still gets v1 shapes and v1 spellings.
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

  // Lets app.js tell simulated data from real. v1 uses it to skip polling the
  // subgraph after a transaction: mock orders are generated rather than
  // indexed, so their state never changes and the poll would only ever run out
  // its full timeout.
  window.SWAPBOARD_MOCK = true;

  // ============================================================================
  // Protocol Version
  // ============================================================================
  //
  // Resolved through lib.js, which index.html loads first, so the mock and the
  // app cannot disagree about which version is active — and therefore cannot
  // disagree about which schema a query should be validated against.
  // ============================================================================

  const Lib = window.SwapboardLib || {};

  /**
   * Protocol version being mocked.
   * Falls back to 1 when lib.js is absent, matching its own DEFAULT_VERSION.
   * @constant {number}
   */
  const MOCK_VERSION = (() => {
    if (typeof Lib.resolveVersion !== "function") return 1;
    let stored = null;
    try {
      stored = localStorage.getItem(Lib.VERSION_STORAGE_KEY);
    } catch (e) {
      stored = null;
    }
    return Lib.resolveVersion({ search: window.location.search, stored: stored }).version;
  })();

  /** True when mocking v2: partial fills, native ETH, the Fill entity. */
  const IS_V2 = MOCK_VERSION === 2;

  // Show mock mode banner.
  //
  // Pinned to the bottom: at the top it sat over the header, hiding the title
  // and clipping the version switcher and wallet button behind it.
  //
  // z-index 900 puts it above the page (the sticky table header and the token
  // dropdown top out at 100) but below modals and the wallet menu at 1000 and
  // toasts at 1001. It has to lose to those: a modal is fixed-position too, so
  // the paddingBottom below does nothing to move it clear, and a banner that
  // won on z-index would swallow clicks on any control in the bottom ~40px of
  // an open modal.
  document.addEventListener("DOMContentLoaded", function () {
    const banner = document.createElement("div");
    banner.id = "mock-banner";
    banner.style.cssText =
      "position:fixed;bottom:0;left:0;right:0;background:#ff6600;color:#fff;padding:8px 15px;font-size:13px;font-weight:bold;z-index:900;display:flex;justify-content:space-between;align-items:center;font-family:monospace;";
    banner.innerHTML =
      'MOCK MODE ACTIVE - Data is simulated <button id="mock-disable" style="background:#fff;color:#ff6600;border:none;padding:4px 10px;cursor:pointer;font-weight:bold;font-family:inherit;">Disable</button>';
    document.body.appendChild(banner);

    // A fixed banner is out of flow, so the end of the page would otherwise
    // scroll underneath it and stay unreachable. Measured rather than assumed,
    // since the height moves with font size and wrapping.
    document.body.style.paddingBottom = banner.offsetHeight + "px";

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

    /**
     * Address the mock wallet connects as, and the maker on every cancel-cohort
     * order. Shared so the two cannot drift apart — if they did, "My Orders"
     * would come up empty and the cancel cohort would be unreachable.
     */
    walletAddress: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",

    /**
     * Orders sharing one token pair, added on top of the generated set.
     *
     * Fill All batches a single pair — canSelectOrder() rejects anything whose
     * pair differs from the anchor — and the seeded generator picks pairs at
     * random, which in practice leaves every open order on a pair of its own.
     * Without a cohort like this there is nothing to multi-select.
     *
     * Above MAX_BATCH_FILL (15) so the batch splits across transactions.
     */
    fillCohortSize: 18,

    /**
     * Orders made by walletAddress, so the connected wallet owns something to
     * cancel. Nothing in the seeded set is ever owned by the mock wallet.
     *
     * Sized to clear MAX_BATCH_CANCEL (25) so the batch splits across
     * transactions.
     */
    cancelCohortSize: 30,
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
   * Native ETH, as it appears in v2 orders: a sentinel address with no contract
   * behind it. Kept out of TOKEN_REGISTRY so it cannot change how the seeded
   * generator picks token pairs.
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

  /** Largest amount the contract can hold, since v2 amounts are uint128. */
  const MAX_UINT128 = (1n << 128n) - 1n;

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

  /** Deterministic 32-byte hash from a numeric nonce, for tx hashes. */
  function generateTxHash(nonce) {
    return "0x" + nonce.toString(16).padStart(64, "0");
  }

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
    // v2 escrows amounts as uint128; anything larger could not exist on chain.
    return (baseUnits > MAX_UINT128 ? MAX_UINT128 : baseUnits).toString();
  }

  // ============================================================================
  // Entity Store
  // ============================================================================
  //
  // One record per entity in subgraph/v2/schema.graphql. Relations are held as
  // ids and joined on read, the way graph-node stores them, so a query asking
  // for `maker { id }` exercises the same shape the real subgraph would.
  //
  // Nothing here is computed twice: the store is populated by replaying order
  // lifecycles through applyCreate/applyFill/applyCancel below, which mirror the
  // three handlers in subgraph/v2/src/mapping.ts. Every counter and remaining
  // amount is therefore derived exactly the way the indexer derives it.
  // ============================================================================

  const STORE = {
    orders: new Map(),
    fills: [],
    tokens: new Map(),
    pairs: new Map(),
    accounts: new Map(),
    globalStats: {
      id: "global",
      totalOrders: "0",
      openOrders: "0",
      partiallyFilledOrders: "0",
      filledOrders: "0",
      canceledOrders: "0",
      totalFills: "0",
      totalTokens: "0",
      totalPairs: "0",
      totalAccounts: "0",
      updatedAt: "0",
    },
  };

  /** Order lifecycle states, spelled as the schema's OrderStatus enum. */
  const STATUS = {
    OPEN: "OPEN",
    PARTIALLY_FILLED: "PARTIALLY_FILLED",
    FILLED: "FILLED",
    CANCELED: "CANCELED",
  };

  /** Adds `delta` to a BigInt-valued counter held as a decimal string. */
  function bump(entity, field, delta) {
    entity[field] = (BigInt(entity[field]) + BigInt(delta)).toString();
  }

  /**
   * Human-unit price of one tokenA in tokenB, as a decimal string.
   * Mirrors `priceOf` in subgraph/v2/src/helpers.ts, zero included.
   */
  function priceOf(amountA, decimalsA, amountB, decimalsB) {
    const a = Number(BigInt(amountA)) / Math.pow(10, decimalsA);
    const b = Number(BigInt(amountB)) / Math.pow(10, decimalsB);
    if (a === 0) return "0";
    return String(b / a);
  }

  /** Registers a token on first sight, mirroring helpers.getOrCreateToken. */
  function getOrCreateToken(token, timestamp) {
    const id = token.address.toLowerCase();
    let entity = STORE.tokens.get(id);
    if (entity) return entity;

    entity = {
      id: id,
      address: id,
      symbol: token.symbol,
      name: token.name,
      decimals: token.decimals,
      isNative: id === NATIVE_ETH_TOKEN.address.toLowerCase(),
      volumeSold: "0",
      volumeBought: "0",
      ordersSelling: "0",
      ordersBuying: "0",
      openOrdersSelling: "0",
      openOrdersBuying: "0",
      fillCount: "0",
      firstSeenAt: String(timestamp),
    };
    STORE.tokens.set(id, entity);
    bump(STORE.globalStats, "totalTokens", 1);
    return entity;
  }

  /** Registers an account on first sight. */
  function getOrCreateAccount(address, timestamp) {
    const id = address.toLowerCase();
    let entity = STORE.accounts.get(id);
    if (entity) {
      entity.lastActiveAt = String(timestamp);
      return entity;
    }

    entity = {
      id: id,
      address: id,
      ordersCreated: "0",
      ordersOpen: "0",
      ordersFilled: "0",
      ordersCanceled: "0",
      fillsTakenCount: "0",
      fillsReceivedCount: "0",
      firstSeenAt: String(timestamp),
      lastActiveAt: String(timestamp),
    };
    STORE.accounts.set(id, entity);
    bump(STORE.globalStats, "totalAccounts", 1);
    return entity;
  }

  /** Registers a directional pair on first sight. Pairs are tokenA -> tokenB. */
  function getOrCreatePair(tokenAId, tokenBId) {
    const id = tokenAId + "-" + tokenBId;
    let entity = STORE.pairs.get(id);
    if (entity) return entity;

    entity = {
      id: id,
      tokenA: tokenAId,
      tokenB: tokenBId,
      orderCount: "0",
      openOrderCount: "0",
      filledOrderCount: "0",
      canceledOrderCount: "0",
      fillCount: "0",
      volumeA: "0",
      volumeB: "0",
      lastTradeAt: null,
    };
    STORE.pairs.set(id, entity);
    bump(STORE.globalStats, "totalPairs", 1);
    return entity;
  }

  /**
   * Mirrors handleOrderCreated.
   * @param {Object} spec - {orderId, maker, tokenA, tokenB, amountA, amountB,
   *   partialFillAllowed, timestamp, block}
   * @returns {Object} The stored Order entity
   */
  function applyCreate(spec) {
    const ts = String(spec.timestamp);
    const tokenA = getOrCreateToken(spec.tokenA, spec.timestamp);
    const tokenB = getOrCreateToken(spec.tokenB, spec.timestamp);
    const pair = getOrCreatePair(tokenA.id, tokenB.id);
    const maker = getOrCreateAccount(spec.maker, spec.timestamp);

    const order = {
      id: String(spec.orderId),
      orderId: String(spec.orderId),
      maker: maker.id,
      tokenA: tokenA.id,
      tokenB: tokenB.id,
      pair: pair.id,
      amountA: spec.amountA,
      amountB: spec.amountB,
      availableA: spec.amountA,
      availableB: spec.amountB,
      filledA: "0",
      filledB: "0",
      filledFraction: "0",
      partialFillAllowed: spec.partialFillAllowed,
      status: STATUS.OPEN,
      active: true,
      priceBPerA: priceOf(spec.amountA, tokenA.decimals, spec.amountB, tokenB.decimals),
      priceAPerB: priceOf(spec.amountB, tokenB.decimals, spec.amountA, tokenA.decimals),
      fillCount: 0,
      createdAt: ts,
      createdBlock: String(spec.block),
      createdTx: generateTxHash(spec.orderId * 1000),
      updatedAt: ts,
      filledAt: null,
      filledTx: null,
      canceledAt: null,
      canceledTx: null,
    };
    STORE.orders.set(order.id, order);

    bump(tokenA, "ordersSelling", 1);
    bump(tokenA, "openOrdersSelling", 1);
    bump(tokenB, "ordersBuying", 1);
    bump(tokenB, "openOrdersBuying", 1);
    bump(pair, "orderCount", 1);
    bump(pair, "openOrderCount", 1);
    bump(maker, "ordersCreated", 1);
    bump(maker, "ordersOpen", 1);
    bump(STORE.globalStats, "totalOrders", 1);
    bump(STORE.globalStats, "openOrders", 1);
    STORE.globalStats.updatedAt = ts;

    return order;
  }

  /**
   * The tokenB owed for taking `amountA`, ceiled — `Swapboard._quoteFill`.
   *
   * Kept here rather than imported from lib.js so the mock's chain state is
   * derived from the contract's own rule, not from the UI's copy of it. If the
   * two ever drift, that is a bug the mock should surface, not paper over.
   */
  function quoteFill(order, amountA) {
    const availableA = BigInt(order.availableA);
    const availableB = BigInt(order.availableB);
    const want = BigInt(amountA);
    if (want >= availableA) return availableB;
    return (want * availableB + availableA - 1n) / availableA;
  }

  /**
   * Mirrors handleOrderFilled, including the Fill entity it emits.
   * @param {string} orderId - Order being filled
   * @param {Object} spec - {taker, amountA, timestamp, block, txNonce, logIndex}
   */
  function applyFill(orderId, spec) {
    const order = STORE.orders.get(String(orderId));
    const tokenA = STORE.tokens.get(order.tokenA);
    const tokenB = STORE.tokens.get(order.tokenB);
    const pair = STORE.pairs.get(order.pair);
    const maker = STORE.accounts.get(order.maker);
    const taker = getOrCreateAccount(spec.taker, spec.timestamp);
    const ts = String(spec.timestamp);

    const amountA = BigInt(spec.amountA);
    const amountB = quoteFill(order, amountA);
    const wasPartiallyFilled = order.status === STATUS.PARTIALLY_FILLED;

    order.availableA = (BigInt(order.availableA) - amountA).toString();
    order.availableB = (BigInt(order.availableB) - amountB).toString();
    order.filledA = (BigInt(order.amountA) - BigInt(order.availableA)).toString();
    order.filledB = (BigInt(order.amountB) - BigInt(order.availableB)).toString();
    order.filledFraction =
      BigInt(order.amountA) === 0n
        ? "0"
        : String(Number(BigInt(order.filledA)) / Number(BigInt(order.amountA)));
    order.fillCount += 1;
    order.updatedAt = ts;

    const txHash = generateTxHash(spec.txNonce);
    // An order closes when either side is exhausted; ceil rounding on tokenB
    // means tokenA dust can be left stranded, which is exactly the contract's
    // behaviour and not something to tidy up here.
    const closed = BigInt(order.availableA) === 0n || BigInt(order.availableB) === 0n;
    if (closed) {
      order.status = STATUS.FILLED;
      order.active = false;
      order.filledAt = ts;
      order.filledTx = txHash;
    } else {
      order.status = STATUS.PARTIALLY_FILLED;
    }

    STORE.fills.push({
      id: txHash + "-" + spec.logIndex,
      order: order.id,
      orderId: order.orderId,
      taker: taker.id,
      maker: maker.id,
      tokenA: tokenA.id,
      tokenB: tokenB.id,
      pair: pair.id,
      amountA: amountA.toString(),
      amountB: amountB.toString(),
      priceBPerA: priceOf(amountA.toString(), tokenA.decimals, amountB.toString(), tokenB.decimals),
      remainingA: order.availableA,
      remainingB: order.availableB,
      closedOrder: closed,
      timestamp: ts,
      blockNumber: String(spec.block),
      transactionHash: txHash,
      logIndex: String(spec.logIndex),
    });

    bump(tokenA, "volumeSold", amountA);
    bump(tokenA, "fillCount", 1);
    bump(tokenB, "volumeBought", amountB);
    bump(tokenB, "fillCount", 1);
    bump(pair, "fillCount", 1);
    bump(pair, "volumeA", amountA);
    bump(pair, "volumeB", amountB);
    pair.lastTradeAt = ts;
    bump(taker, "fillsTakenCount", 1);
    bump(maker, "fillsReceivedCount", 1);
    maker.lastActiveAt = ts;
    bump(STORE.globalStats, "totalFills", 1);

    if (closed) {
      bump(tokenA, "openOrdersSelling", -1);
      bump(tokenB, "openOrdersBuying", -1);
      bump(pair, "openOrderCount", -1);
      bump(pair, "filledOrderCount", 1);
      bump(maker, "ordersOpen", -1);
      bump(maker, "ordersFilled", 1);
      bump(STORE.globalStats, "openOrders", -1);
      bump(STORE.globalStats, "filledOrders", 1);
      if (wasPartiallyFilled) bump(STORE.globalStats, "partiallyFilledOrders", -1);
    } else if (!wasPartiallyFilled) {
      bump(STORE.globalStats, "partiallyFilledOrders", 1);
    }
    STORE.globalStats.updatedAt = ts;
  }

  /**
   * Mirrors handleOrderCanceled. `availableA` is left as it stands: after a
   * cancel it is the amount refunded to the maker.
   * @param {string} orderId - Order being cancelled
   * @param {Object} spec - {timestamp, txNonce}
   */
  function applyCancel(orderId, spec) {
    const order = STORE.orders.get(String(orderId));
    const tokenA = STORE.tokens.get(order.tokenA);
    const tokenB = STORE.tokens.get(order.tokenB);
    const pair = STORE.pairs.get(order.pair);
    const maker = STORE.accounts.get(order.maker);
    const ts = String(spec.timestamp);
    const wasPartiallyFilled = order.status === STATUS.PARTIALLY_FILLED;

    order.status = STATUS.CANCELED;
    order.active = false;
    order.canceledAt = ts;
    order.canceledTx = generateTxHash(spec.txNonce);
    order.updatedAt = ts;

    bump(tokenA, "openOrdersSelling", -1);
    bump(tokenB, "openOrdersBuying", -1);
    bump(pair, "openOrderCount", -1);
    bump(pair, "canceledOrderCount", 1);
    bump(maker, "ordersOpen", -1);
    bump(maker, "ordersCanceled", 1);
    maker.lastActiveAt = ts;
    bump(STORE.globalStats, "openOrders", -1);
    bump(STORE.globalStats, "canceledOrders", 1);
    if (wasPartiallyFilled) bump(STORE.globalStats, "partiallyFilledOrders", -1);
    STORE.globalStats.updatedAt = ts;
  }

  // ============================================================================
  // Order Generation
  // ============================================================================
  //
  // Every order is generated as a lifecycle — created, then optionally filled or
  // cancelled — and replayed through the handlers above. The PRNG is consumed in
  // exactly the order the previous generator consumed it, so the seeded
  // open/filled/cancelled split that test.js asserts on is unchanged.
  //
  // Native ETH legs and partial fills exist only under v2. That is not a
  // projection detail: v1 has no ETH sentinel and no partial fills, so an order
  // book containing either could not have come from a v1 contract.
  // ============================================================================

  /** Block number standing in for a timestamp, at ~12s per block. */
  function blockAt(timestamp) {
    return Math.floor(timestamp / 12);
  }

  /**
   * Generates the seeded order set.
   * @param {number} now - Current unix timestamp
   */
  function generateSeededOrders(now) {
    for (let i = 0; i < MOCK_CONFIG.orderCount; i++) {
      // Pick two different tokens
      const tokenAIndex = randInt(0, TOKEN_REGISTRY.length - 1);
      let tokenBIndex = randInt(0, TOKEN_REGISTRY.length - 1);
      while (tokenBIndex === tokenAIndex) {
        tokenBIndex = randInt(0, TOKEN_REGISTRY.length - 1);
      }

      let tokenA = TOKEN_REGISTRY[tokenAIndex];
      let tokenB = TOKEN_REGISTRY[tokenBIndex];

      // Determine order outcome
      const isActive = randPercent(MOCK_CONFIG.activePercent);
      const isFilled = !isActive && randPercent(MOCK_CONFIG.filledPercent);

      // Generate timestamps (spread over past 30 days)
      const createdAt = now - randInt(60, 30 * 24 * 60 * 60);
      const closedAt = createdAt + randInt(300, 7 * 24 * 60 * 60);

      // Some WETH legs become native ETH. Both are 18 decimals, so the
      // generated amounts stay valid, and having both around is what lets you
      // see the UI distinguish them (ETH renders with no contract address).
      if (IS_V2) {
        if (tokenA.symbol === "WETH" && i % 3 === 0) tokenA = NATIVE_ETH_TOKEN;
        if (tokenB.symbol === "WETH" && i % 4 === 1) tokenB = NATIVE_ETH_TOKEN;
      }

      // Every fifth order opts out of partial fills. v1 orders are all
      // all-or-nothing, so the flag is only meaningful under v2.
      const partialFillAllowed = IS_V2 && i % 5 !== 0;

      const amountA = generateAmount(tokenA);
      const amountB = generateAmount(tokenB);
      const maker = randChoice(MAKER_ADDRESSES);
      const taker = isFilled ? generateAddress(0x3000 + randInt(0, 20)) : null;

      applyCreate({
        orderId: i,
        maker: maker,
        tokenA: tokenA,
        tokenB: tokenB,
        amountA: amountA,
        amountB: amountB,
        partialFillAllowed: partialFillAllowed,
        timestamp: createdAt,
        block: blockAt(createdAt),
      });

      if (isFilled) {
        applyFill(i, {
          taker: taker,
          amountA: amountA,
          timestamp: closedAt,
          block: blockAt(closedAt),
          txNonce: i * 1000 + 1,
          logIndex: 0,
        });
      } else if (!isActive) {
        applyCancel(i, { timestamp: closedAt, txNonce: i * 1000 + 2 });
      } else if (partialFillAllowed && i % 7 === 3) {
        // A few open orders are already part-filled, so the remaining-amount
        // display and the fill math have something to work on.
        applyFill(i, {
          taker: generateAddress(0x3000 + (i % 20)),
          amountA: ((BigInt(amountA) * 60n) / 100n).toString(),
          timestamp: createdAt + 600,
          block: blockAt(createdAt + 600),
          txNonce: i * 1000 + 3,
          logIndex: 0,
        });
      }
    }
  }

  // ============================================================================
  // Multi-Select Cohorts
  // ============================================================================
  //
  // The seeded generator picks each order's pair and maker at random, which
  // leaves the open orders spread across as many distinct pairs as there are
  // orders, and none of them owned by the connected wallet. Both batch actions
  // are unreachable in that data:
  //
  //   Fill All   — canSelectOrder() only lets orders join a fill selection if
  //                their pair matches the anchor's exactly, so with no pair
  //                repeated a selection can never exceed one order.
  //   Cancel All — only ever offered on your own orders, and the wallet owns
  //                none.
  //
  // These two cohorts are appended after the seeded loop and built entirely
  // from their index — no rng() calls — so the seeded stream, and with it the
  // active/filled/cancelled split test.js asserts on, is untouched. They take
  // the highest order IDs, which puts them at the top of the default sort.
  // ============================================================================

  /**
   * Creates one cohort order, optionally leaving it part-filled.
   *
   * An order that opted out of partial fills cannot be part-filled on chain, so
   * `partFilled` is ignored for those rather than producing a state the contract
   * could never reach.
   */
  function buildCohortOrder(spec) {
    const createdAt = spec.now - 3600 - spec.orderId * 60;
    applyCreate({
      orderId: spec.orderId,
      maker: spec.maker,
      tokenA: spec.tokenA,
      tokenB: spec.tokenB,
      amountA: spec.amountA,
      amountB: spec.amountB,
      partialFillAllowed: spec.partialFillAllowed,
      timestamp: createdAt,
      block: blockAt(createdAt),
    });

    if (spec.partFilled && spec.partialFillAllowed) {
      applyFill(spec.orderId, {
        taker: MAKER_ADDRESSES[spec.orderId % MAKER_ADDRESSES.length],
        amountA: ((BigInt(spec.amountA) * 65n) / 100n).toString(),
        timestamp: createdAt + 300,
        block: blockAt(createdAt + 300),
        txNonce: spec.orderId * 1000 + 4,
        logIndex: 0,
      });
    }
  }

  /**
   * Open orders on a single pair, from makers other than the wallet.
   *
   * Every order shares WETH -> USDC so the whole run is selectable together.
   * Sizes climb across the cohort, which spreads the implied prices out so the
   * batch summary has a real average to report rather than one repeated number.
   *
   * @param {number} startId - First order ID to use
   * @param {number} now - Current unix timestamp
   */
  function generateFillCohort(startId, now) {
    const WETH = TOKEN_REGISTRY.find((t) => t.symbol === "WETH");
    const USDC = TOKEN_REGISTRY.find((t) => t.symbol === "USDC");

    for (let i = 0; i < MOCK_CONFIG.fillCohortSize; i++) {
      // 0.5 -> 9.0 WETH, priced at 2,000 + 25*i USDC each.
      const weth = 5n + BigInt(i) * 5n; // tenths of a WETH
      const amountA = (weth * 10n ** 17n).toString();
      const pricePerWeth = 2000n + BigInt(i) * 25n;
      const amountB = ((weth * pricePerWeth * 10n ** 6n) / 10n).toString();

      buildCohortOrder({
        orderId: startId + i,
        now: now,
        // Spread across makers so the cohort looks like a real order book,
        // and never the wallet — an own order would flip the selection into
        // cancel mode and hide Fill All.
        maker: MAKER_ADDRESSES[i % MAKER_ADDRESSES.length],
        tokenA: WETH,
        tokenB: USDC,
        amountA: amountA,
        amountB: amountB,
        // Every fourth order is all-or-nothing, so a batch spanning the
        // cohort mixes both kinds.
        partialFillAllowed: IS_V2 && i % 4 !== 3,
        // Every fifth is already part-filled.
        partFilled: i % 5 === 2,
      });
    }
  }

  /**
   * Open orders owned by the connected wallet.
   *
   * Deliberately spread across pairs: Cancel All is pair-agnostic, and mixing
   * pairs is what demonstrates that. Under v2 native ETH appears among the
   * offered tokens, so cancelling an ETH-denominated escrow is reachable.
   *
   * @param {number} startId - First order ID to use
   * @param {number} now - Current unix timestamp
   */
  function generateCancelCohort(startId, now) {
    const WETH = TOKEN_REGISTRY.find((t) => t.symbol === "WETH");
    const offered = IS_V2
      ? [WETH, NATIVE_ETH_TOKEN, ...TOKEN_REGISTRY.filter((t) => t.symbol !== "WETH")]
      : TOKEN_REGISTRY.slice();
    const wanted = TOKEN_REGISTRY.filter((t) => t.symbol === "USDC" || t.symbol === "DAI");

    for (let i = 0; i < MOCK_CONFIG.cancelCohortSize; i++) {
      const tokenA = offered[i % offered.length];
      let tokenB = wanted[i % wanted.length];
      // An order cannot offer and want the same token.
      if (tokenB.address === tokenA.address) tokenB = wanted[(i + 1) % wanted.length];

      const units = 10n ** BigInt(tokenA.decimals);
      const amountA = (units * BigInt(i + 1)).toString();
      const amountB = (10n ** BigInt(tokenB.decimals) * BigInt(100 * (i + 1))).toString();

      buildCohortOrder({
        orderId: startId + i,
        now: now,
        maker: MOCK_CONFIG.walletAddress,
        tokenA: tokenA,
        tokenB: tokenB,
        amountA: amountA,
        amountB: amountB,
        partialFillAllowed: IS_V2 && i % 3 !== 0,
        partFilled: i % 6 === 4,
      });
    }
  }

  (function populateStore() {
    const now = Math.floor(Date.now() / 1000);
    generateSeededOrders(now);
    generateCancelCohort(MOCK_CONFIG.orderCount, now);
    // Fill cohort last so it takes the highest IDs and lands at the top of the
    // default newest-first sort — it is the one you need visible to shift-select.
    generateFillCohort(MOCK_CONFIG.orderCount + MOCK_CONFIG.cancelCohortSize, now);
  })();

  /** Fills indexed by id, so relation lookups do not scan the array. */
  const FILLS_BY_ID = new Map(STORE.fills.map((f) => [f.id, f]));

  /**
   * The taker of the fill that closed an order, or null while it is still open.
   *
   * v1 records this on the order itself. v2 does not — a partially filled order
   * has many takers and no one of them owns it — so it is recovered from the
   * closing Fill, which is the only fill that corresponds to v1's `taker`.
   *
   * @param {Object} order - Order entity
   * @returns {string|null} Taker address, lowercase
   */
  function closingTaker(order) {
    if (order.status !== STATUS.FILLED) return null;
    for (let i = STORE.fills.length - 1; i >= 0; i--) {
      if (STORE.fills[i].order === order.id && STORE.fills[i].closedOrder) {
        return STORE.fills[i].taker;
      }
    }
    return null;
  }

  // ============================================================================
  // Schema Descriptors
  // ============================================================================
  //
  // Transcribed from subgraph/v2/schema.graphql and subgraph/v1/schema.graphql.
  // Each field is either a scalar (`type: null`) or a relation naming the type
  // it resolves against, plus a getter reading it off the stored entity.
  //
  // These exist to make unknown fields an *error*. graph-node rejects an entire
  // query on one unknown field, so a query the mock happily answers but the real
  // subgraph would reject is worse than useless — it is what let the v2 UI look
  // healthy while being unable to load a single order.
  // ============================================================================

  /** Scalar field: reads a property straight off the entity. */
  function scalar(key) {
    return { type: null, get: (e) => e[key] };
  }

  /** Relation to a single entity, held as an id. */
  function ref(type, key) {
    return { type: type, get: (e) => e[key] };
  }

  /** Derived list of entities, resolved by scanning. */
  function derived(type, get) {
    return { type: type, list: true, get: get };
  }

  const ORDER_FILL_IDS = (order) =>
    STORE.fills.filter((f) => f.order === order.id).map((f) => f.id);

  const SCHEMA_V2 = {
    Order: {
      id: scalar("id"),
      orderId: scalar("orderId"),
      maker: ref("Account", "maker"),
      tokenA: ref("Token", "tokenA"),
      tokenB: ref("Token", "tokenB"),
      pair: ref("Pair", "pair"),
      amountA: scalar("amountA"),
      amountB: scalar("amountB"),
      availableA: scalar("availableA"),
      availableB: scalar("availableB"),
      filledA: scalar("filledA"),
      filledB: scalar("filledB"),
      filledFraction: scalar("filledFraction"),
      partialFillAllowed: scalar("partialFillAllowed"),
      status: scalar("status"),
      active: scalar("active"),
      priceBPerA: scalar("priceBPerA"),
      priceAPerB: scalar("priceAPerB"),
      fillCount: scalar("fillCount"),
      fills: derived("Fill", ORDER_FILL_IDS),
      createdAt: scalar("createdAt"),
      createdBlock: scalar("createdBlock"),
      createdTx: scalar("createdTx"),
      updatedAt: scalar("updatedAt"),
      filledAt: scalar("filledAt"),
      filledTx: scalar("filledTx"),
      canceledAt: scalar("canceledAt"),
      canceledTx: scalar("canceledTx"),
    },
    Fill: {
      id: scalar("id"),
      order: ref("Order", "order"),
      orderId: scalar("orderId"),
      taker: ref("Account", "taker"),
      maker: ref("Account", "maker"),
      tokenA: ref("Token", "tokenA"),
      tokenB: ref("Token", "tokenB"),
      pair: ref("Pair", "pair"),
      amountA: scalar("amountA"),
      amountB: scalar("amountB"),
      priceBPerA: scalar("priceBPerA"),
      remainingA: scalar("remainingA"),
      remainingB: scalar("remainingB"),
      closedOrder: scalar("closedOrder"),
      timestamp: scalar("timestamp"),
      blockNumber: scalar("blockNumber"),
      transactionHash: scalar("transactionHash"),
      logIndex: scalar("logIndex"),
    },
    Token: {
      id: scalar("id"),
      address: scalar("address"),
      symbol: scalar("symbol"),
      name: scalar("name"),
      decimals: scalar("decimals"),
      isNative: scalar("isNative"),
      volumeSold: scalar("volumeSold"),
      volumeBought: scalar("volumeBought"),
      ordersSelling: scalar("ordersSelling"),
      ordersBuying: scalar("ordersBuying"),
      openOrdersSelling: scalar("openOrdersSelling"),
      openOrdersBuying: scalar("openOrdersBuying"),
      fillCount: scalar("fillCount"),
      firstSeenAt: scalar("firstSeenAt"),
      sellOrders: derived("Order", (t) => idsWhere(STORE.orders, (o) => o.tokenA === t.id)),
      buyOrders: derived("Order", (t) => idsWhere(STORE.orders, (o) => o.tokenB === t.id)),
    },
    Pair: {
      id: scalar("id"),
      tokenA: ref("Token", "tokenA"),
      tokenB: ref("Token", "tokenB"),
      orderCount: scalar("orderCount"),
      openOrderCount: scalar("openOrderCount"),
      filledOrderCount: scalar("filledOrderCount"),
      canceledOrderCount: scalar("canceledOrderCount"),
      fillCount: scalar("fillCount"),
      volumeA: scalar("volumeA"),
      volumeB: scalar("volumeB"),
      lastTradeAt: scalar("lastTradeAt"),
      orders: derived("Order", (p) => idsWhere(STORE.orders, (o) => o.pair === p.id)),
      fills: derived("Fill", (p) => STORE.fills.filter((f) => f.pair === p.id).map((f) => f.id)),
    },
    Account: {
      id: scalar("id"),
      address: scalar("address"),
      ordersCreated: scalar("ordersCreated"),
      ordersOpen: scalar("ordersOpen"),
      ordersFilled: scalar("ordersFilled"),
      ordersCanceled: scalar("ordersCanceled"),
      fillsTakenCount: scalar("fillsTakenCount"),
      fillsReceivedCount: scalar("fillsReceivedCount"),
      firstSeenAt: scalar("firstSeenAt"),
      lastActiveAt: scalar("lastActiveAt"),
      orders: derived("Order", (a) => idsWhere(STORE.orders, (o) => o.maker === a.id)),
      fillsTaken: derived("Fill", (a) =>
        STORE.fills.filter((f) => f.taker === a.id).map((f) => f.id)
      ),
      fillsReceived: derived("Fill", (a) =>
        STORE.fills.filter((f) => f.maker === a.id).map((f) => f.id)
      ),
    },
    GlobalStats: {
      id: scalar("id"),
      totalOrders: scalar("totalOrders"),
      openOrders: scalar("openOrders"),
      partiallyFilledOrders: scalar("partiallyFilledOrders"),
      filledOrders: scalar("filledOrders"),
      canceledOrders: scalar("canceledOrders"),
      totalFills: scalar("totalFills"),
      totalTokens: scalar("totalTokens"),
      totalPairs: scalar("totalPairs"),
      totalAccounts: scalar("totalAccounts"),
      updatedAt: scalar("updatedAt"),
    },
  };

  // v1 reads the same store through a narrower, differently spelled surface:
  // maker and taker are plain addresses, amounts are the whole order, and the
  // cancel fields carry two `l`s. Under `?v=1` the generator never produces a
  // partial fill or an ETH sentinel, so nothing here has to hide one.
  const SCHEMA_V1 = {
    Order: {
      id: scalar("id"),
      orderId: scalar("orderId"),
      maker: scalar("maker"),
      taker: { type: null, get: closingTaker },
      tokenA: ref("Token", "tokenA"),
      tokenB: ref("Token", "tokenB"),
      amountA: scalar("amountA"),
      amountB: scalar("amountB"),
      active: scalar("active"),
      createdAt: scalar("createdAt"),
      createdTx: scalar("createdTx"),
      filledAt: scalar("filledAt"),
      filledTx: scalar("filledTx"),
      cancelledAt: scalar("canceledAt"),
      cancelledTx: scalar("canceledTx"),
    },
    Token: {
      id: scalar("id"),
      address: scalar("address"),
      symbol: scalar("symbol"),
      name: scalar("name"),
      decimals: scalar("decimals"),
      volumeSold: scalar("volumeSold"),
      volumeBought: scalar("volumeBought"),
      ordersSelling: scalar("ordersSelling"),
      ordersBuying: scalar("ordersBuying"),
      sellOrders: derived("Order", (t) => idsWhere(STORE.orders, (o) => o.tokenA === t.id)),
      buyOrders: derived("Order", (t) => idsWhere(STORE.orders, (o) => o.tokenB === t.id)),
    },
    PairStats: {
      id: scalar("id"),
      tokenA: ref("Token", "tokenA"),
      tokenB: ref("Token", "tokenB"),
      orderCount: scalar("orderCount"),
      tradeCount: scalar("fillCount"),
    },
    GlobalStats: {
      id: scalar("id"),
      totalOrders: scalar("totalOrders"),
      activeOrders: scalar("openOrders"),
      filledOrders: scalar("filledOrders"),
      cancelledOrders: scalar("canceledOrders"),
    },
  };

  /** Ids of the entities in a Map satisfying a predicate. */
  function idsWhere(map, predicate) {
    const out = [];
    for (const entity of map.values()) {
      if (predicate(entity)) out.push(entity.id);
    }
    return out;
  }

  const SCHEMA = IS_V2 ? SCHEMA_V2 : SCHEMA_V1;

  /** Where each type's entities are found, by id. */
  const LOOKUP = {
    Order: (id) => STORE.orders.get(id),
    Fill: (id) => FILLS_BY_ID.get(id),
    Token: (id) => STORE.tokens.get(id),
    Pair: (id) => STORE.pairs.get(id),
    Account: (id) => STORE.accounts.get(id),
    GlobalStats: () => STORE.globalStats,
  };

  /** Root query fields, per version. */
  const ROOTS = IS_V2
    ? {
        orders: { type: "Order", many: true, all: () => [...STORE.orders.values()] },
        order: { type: "Order", many: false },
        fills: { type: "Fill", many: true, all: () => STORE.fills.slice() },
        tokens: { type: "Token", many: true, all: () => [...STORE.tokens.values()] },
        pairs: { type: "Pair", many: true, all: () => [...STORE.pairs.values()] },
        accounts: { type: "Account", many: true, all: () => [...STORE.accounts.values()] },
        globalStats: { type: "GlobalStats", many: false },
      }
    : {
        orders: { type: "Order", many: true, all: () => [...STORE.orders.values()] },
        order: { type: "Order", many: false },
        tokens: { type: "Token", many: true, all: () => [...STORE.tokens.values()] },
        // graph-node pluralises PairStats as pairStats_collection.
        pairStats_collection: {
          type: "PairStats",
          many: true,
          all: () => [...STORE.pairs.values()],
        },
        globalStats: { type: "GlobalStats", many: false },
      };

  // ============================================================================
  // GraphQL Reader
  // ============================================================================
  //
  // Enough of a parser to read the queries this app sends: a selection set,
  // nested selections, and field arguments including a `where` object. Not a
  // GraphQL engine — no fragments, variables, aliases or directives, none of
  // which app.js uses.
  // ============================================================================

  /** Raised for anything graph-node would reject outright. */
  function QueryError(message) {
    return { __queryError: message };
  }

  /**
   * Parses a GraphQL document into a selection tree.
   * @param {string} src - Query text
   * @returns {Array<{name: string, args: Object, selections: Array}>} Root fields
   */
  function parseQuery(src) {
    let i = 0;

    const skipWs = () => {
      while (i < src.length && /[\s,]/.test(src[i])) i++;
    };

    const readName = () => {
      const start = i;
      while (i < src.length && /[A-Za-z0-9_]/.test(src[i])) i++;
      return src.slice(start, i);
    };

    function readValue() {
      skipWs();
      const c = src[i];

      if (c === '"') {
        i++;
        let out = "";
        while (i < src.length && src[i] !== '"') {
          if (src[i] === "\\") i++;
          out += src[i++];
        }
        i++;
        return out;
      }

      if (c === "[") {
        i++;
        const items = [];
        skipWs();
        while (i < src.length && src[i] !== "]") {
          items.push(readValue());
          skipWs();
        }
        i++;
        return items;
      }

      if (c === "{") {
        i++;
        const obj = {};
        skipWs();
        while (i < src.length && src[i] !== "}") {
          const key = readName();
          skipWs();
          if (src[i] === ":") i++;
          obj[key] = readValue();
          skipWs();
        }
        i++;
        return obj;
      }

      // Number, boolean, null, or a bare enum value such as FILLED.
      const start = i;
      while (i < src.length && !/[\s,)}\]]/.test(src[i])) i++;
      const raw = src.slice(start, i);
      if (raw === "true") return true;
      if (raw === "false") return false;
      if (raw === "null") return null;
      if (/^-?\d+(\.\d+)?$/.test(raw)) return Number(raw);
      return raw;
    }

    function readArgs() {
      skipWs();
      if (src[i] !== "(") return {};
      i++;
      const args = {};
      skipWs();
      while (i < src.length && src[i] !== ")") {
        const key = readName();
        skipWs();
        if (src[i] === ":") i++;
        args[key] = readValue();
        skipWs();
      }
      i++;
      return args;
    }

    function readSelections() {
      skipWs();
      if (src[i] !== "{") return null;
      i++;
      const fields = [];
      skipWs();
      while (i < src.length && src[i] !== "}") {
        const name = readName();
        if (!name) {
          i++;
          skipWs();
          continue;
        }
        const args = readArgs();
        const selections = readSelections();
        fields.push({ name: name, args: args, selections: selections });
        skipWs();
      }
      i++;
      return fields;
    }

    skipWs();
    // Optional `query` / `query Name` prefix before the root selection set.
    if (src.slice(i, i + 5) === "query") {
      i += 5;
      skipWs();
      readName();
    }
    return readSelections() || [];
  }

  // ============================================================================
  // Query Execution
  // ============================================================================

  /**
   * Reads a field off an entity through its schema descriptor.
   * @throws {Object} A QueryError when the field is not in the schema
   */
  function readField(typeName, entity, fieldName) {
    const fields = SCHEMA[typeName];
    const descriptor = fields ? fields[fieldName] : null;
    if (!descriptor) {
      throw QueryError(
        `Type \`${typeName}\` has no field \`${fieldName}\`` +
          (IS_V2 ? "" : " (mocking v1 — did you mean to run ?v=2 ?)")
      );
    }
    return descriptor.get(entity);
  }

  /** Compares two resolved values, numerically when both are numeric. */
  function compareValues(a, b) {
    if (a === null || a === undefined) return b === null || b === undefined ? 0 : -1;
    if (b === null || b === undefined) return 1;
    const na = Number(a);
    const nb = Number(b);
    if (!Number.isNaN(na) && !Number.isNaN(nb) && typeof a !== "boolean") {
      return na < nb ? -1 : na > nb ? 1 : 0;
    }
    return String(a) < String(b) ? -1 : String(a) > String(b) ? 1 : 0;
  }

  /** Case-insensitive equality, so address comparisons behave like the indexer's. */
  function valuesEqual(actual, expected) {
    if (actual === null || actual === undefined) return expected === null;
    if (typeof actual === "boolean" || typeof expected === "boolean") return actual === expected;
    return String(actual).toLowerCase() === String(expected).toLowerCase();
  }

  /**
   * Applies one `where` entry to an entity.
   *
   * Supports the operator suffixes graph-node exposes that this app actually
   * uses — plain equality, `_not`, `_in`, and the `_` relation filter — and
   * treats anything else as an unknown field rather than silently ignoring it.
   */
  function matchesCondition(typeName, entity, key, expected) {
    if (key.endsWith("_")) {
      // Relation filter: `tokenA_: { address: "0x..." }`
      const fieldName = key.slice(0, -1);
      const descriptor = (SCHEMA[typeName] || {})[fieldName];
      if (!descriptor || !descriptor.type) {
        throw QueryError(`Type \`${typeName}\` has no relation \`${fieldName}\``);
      }
      const related = LOOKUP[descriptor.type](descriptor.get(entity));
      if (!related) return false;
      return Object.keys(expected).every((k) =>
        matchesCondition(descriptor.type, related, k, expected[k])
      );
    }

    for (const suffix of ["_not_in", "_not", "_in", "_gte", "_lte", "_gt", "_lt"]) {
      if (!key.endsWith(suffix)) continue;
      const value = readField(typeName, entity, key.slice(0, -suffix.length));
      switch (suffix) {
        case "_not":
          return !valuesEqual(value, expected);
        case "_in":
          return expected.some((e) => valuesEqual(value, e));
        case "_not_in":
          return !expected.some((e) => valuesEqual(value, e));
        case "_gt":
          return compareValues(value, expected) > 0;
        case "_lt":
          return compareValues(value, expected) < 0;
        case "_gte":
          return compareValues(value, expected) >= 0;
        default:
          return compareValues(value, expected) <= 0;
      }
    }

    return valuesEqual(readField(typeName, entity, key), expected);
  }

  /** Filters, orders and paginates a collection the way graph-node would. */
  function applyCollectionArgs(typeName, entities, args) {
    let out = entities;

    if (args.where) {
      const keys = Object.keys(args.where);
      out = out.filter((e) => keys.every((k) => matchesCondition(typeName, e, k, args.where[k])));
    }

    if (args.orderBy) {
      const direction = args.orderDirection === "desc" ? -1 : 1;
      out = out.slice().sort((a, b) => {
        return (
          compareValues(
            readField(typeName, a, args.orderBy),
            readField(typeName, b, args.orderBy)
          ) * direction
        );
      });
    }

    const skip = typeof args.skip === "number" ? args.skip : 0;
    const first = typeof args.first === "number" ? args.first : 100;
    return out.slice(skip, skip + first);
  }

  /**
   * Projects an entity down to exactly the fields that were asked for,
   * recursing into relations.
   */
  function project(typeName, entity, selections) {
    if (!entity) return null;
    if (!selections || selections.length === 0) {
      throw QueryError(`Field of type \`${typeName}\` must have a selection of subfields`);
    }

    const out = {};
    for (const field of selections) {
      const descriptor = (SCHEMA[typeName] || {})[field.name];
      if (!descriptor) {
        throw QueryError(`Type \`${typeName}\` has no field \`${field.name}\``);
      }

      if (!descriptor.type) {
        if (field.selections) {
          throw QueryError(`Field \`${typeName}.${field.name}\` does not have subfields`);
        }
        out[field.name] = descriptor.get(entity);
        continue;
      }

      const lookup = LOOKUP[descriptor.type];
      if (descriptor.list) {
        const ids = descriptor.get(entity);
        const related = ids.map(lookup).filter(Boolean);
        out[field.name] = applyCollectionArgs(descriptor.type, related, field.args).map((e) =>
          project(descriptor.type, e, field.selections)
        );
      } else {
        out[field.name] = project(
          descriptor.type,
          lookup(descriptor.get(entity)),
          field.selections
        );
      }
    }
    return out;
  }

  /**
   * Runs a parsed query against the store.
   * @param {string} query - GraphQL query text
   * @returns {{data: Object}|{errors: Array}} graph-node-shaped response
   */
  function executeQuery(query) {
    let roots;
    try {
      roots = parseQuery(query);
    } catch (e) {
      return { errors: [{ message: "Could not parse query: " + e.message }] };
    }

    const data = {};
    try {
      for (const field of roots) {
        const root = ROOTS[field.name];
        if (!root) {
          throw QueryError(`Type \`Query\` has no field \`${field.name}\``);
        }

        if (root.many) {
          const all = root.all();
          data[field.name] = applyCollectionArgs(root.type, all, field.args).map((e) =>
            project(root.type, e, field.selections)
          );
        } else {
          const entity = LOOKUP[root.type](field.args.id);
          data[field.name] = entity ? project(root.type, entity, field.selections) : null;
        }
      }
    } catch (e) {
      if (e && e.__queryError) {
        console.error("[Mock] Rejected query:", e.__queryError);
        return { errors: [{ message: e.__queryError }] };
      }
      throw e;
    }

    return { data: data };
  }

  // ============================================================================
  // Mock Price Data
  // ============================================================================

  /**
   * Static mock prices for development (approximate real prices).
   * Keys are CoinGecko coin IDs matching COINGECKO_ID_MAP in app.js.
   * @constant {Object.<string, number>}
   */
  const MOCK_PRICES = {
    // Native ETH and WETH are the same asset, so they have to price alike —
    // otherwise a v2 ETH order and its WETH twin show different USD values.
    ethereum: 3500,
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

    const result = executeQuery(query);
    if (result.errors) {
      // Answered the way graph-node answers it: HTTP 200 with an errors array
      // and no data. querySubgraph() treats that as a failure, which is the
      // point — a query the real subgraph would reject must not appear to work.
      return { ok: true, status: 200, json: async () => result };
    }

    console.log("[Mock] " + Object.keys(result.data).join(", ") + " query handled");
    return { ok: true, status: 200, json: async () => result };
  };

  // ============================================================================
  // ABI Encoding
  // ============================================================================
  //
  // Just enough to answer the view calls app.js makes. Hand-rolled because the
  // mock has to be able to answer before ethers finishes loading from the CDN,
  // and because every return here is static-typed except `version()`.
  // ============================================================================

  /** One 32-byte word. */
  function word(value) {
    return BigInt(value).toString(16).padStart(64, "0");
  }

  /** An address, left-padded into a word. */
  function encAddress(address) {
    return address.toLowerCase().replace(/^0x/, "").padStart(64, "0");
  }

  /** A dynamic string: head offset, length, then padded UTF-8 bytes. */
  function encString(text) {
    let hex = "";
    for (let i = 0; i < text.length; i++) {
      hex += text.charCodeAt(i).toString(16).padStart(2, "0");
    }
    const padded = hex.padEnd(Math.ceil(hex.length / 64) * 64, "0");
    return "0x" + word(32) + word(text.length) + padded;
  }

  /** Reads the nth 32-byte argument word out of calldata. */
  function argWord(data, index) {
    const body = data.slice(10);
    return BigInt("0x" + body.slice(index * 64, (index + 1) * 64));
  }

  /**
   * The Order tuple as ISwapboard declares it. Field order is load-bearing:
   * maker, active and partialFillAllowed come first, then both tokens, then
   * all four amounts.
   */
  function encOrderTuple(order) {
    if (!order) {
      // getOrder on an unknown id returns a zeroed struct rather than
      // reverting, exactly as the contract does.
      return word(0).repeat(9);
    }
    return (
      encAddress(order.maker) +
      word(order.active ? 1 : 0) +
      word(order.partialFillAllowed ? 1 : 0) +
      encAddress(order.tokenA) +
      encAddress(order.tokenB) +
      word(order.amountA) +
      word(order.amountB) +
      word(order.availableA) +
      word(order.availableB)
    );
  }

  /** An array of static tuples: head offset, length, then the tuples inline. */
  function encOrderTupleArray(orders) {
    return "0x" + word(32) + word(orders.length) + orders.map((o) => encOrderTuple(o)).join("");
  }

  /**
   * v2 view calls, answered from the same store the subgraph mock serves.
   *
   * Serving both from one store is what makes a fill quote testable: the UI
   * prices a fill off the indexed order and submits the result as `minAmountB`,
   * and on chain that has to agree with what `getOrder` reports to the wei.
   */
  const V2_CALLS = {
    // getEth()
    "0xcb05b93e": () => "0x" + encAddress(NATIVE_ETH_TOKEN.address),
    // getNextOrderId()
    "0x8158900b": () => "0x" + word(STORE.orders.size),
    // version()
    "0x54fd4d50": () => encString("2.0.0"),
    // canFill(uint256)
    "0xfb4ca3b6": (data) => {
      const order = STORE.orders.get(String(argWord(data, 0)));
      return "0x" + word(order && order.active ? 1 : 0);
    },
    // getOrder(uint256)
    "0xd09ef241": (data) => "0x" + encOrderTuple(STORE.orders.get(String(argWord(data, 0)))),
    // getOrders(uint256[])
    "0x03652027": (data) => {
      // One dynamic argument: word 0 is its offset, word 1 the length, and the
      // ids follow from word 2.
      const length = Number(argWord(data, 1));
      const orders = [];
      for (let i = 0; i < length; i++) {
        orders.push(STORE.orders.get(String(argWord(data, 2 + i))));
      }
      return encOrderTupleArray(orders);
    },
  };

  const V1_CALLS = {
    // getWeth(). app.js caches this on connect and every isWeth() check
    // compares against it, so without an answer here the catch-all below —
    // which decodes as address 0x…01 — would silently mean "nothing is WETH":
    // WETH legs would render as WETH instead of ETH, and the unwrap-on-fill
    // and unwrap-on-cancel paths would never run.
    "0x107c279f": () => "0x" + encAddress(TOKEN_REGISTRY[0].address),
  };

  const CONTRACT_CALLS = IS_V2 ? V2_CALLS : V1_CALLS;

  /** ERC20 reads, which both versions make against token contracts. */
  const ERC20_CALLS = {
    // balanceOf(address) — a large balance, so nothing is blocked on funds
    "0x70a08231": () => "0x" + word(1000000000000000000000n),
    // allowance(address,address) — max uint256
    "0xdd62ed3e": () => "0x" + "f".repeat(64),
    // approve(address,uint256)
    "0x095ea7b3": () => "0x" + word(1),
    // symbol()
    "0x95d89b41": () => encString("MOCK"),
    // name()
    "0x06fdde03": () => encString("Mock Token"),
    // decimals() — 18, padded to a full 32-byte word. ethers cannot decode a
    // bare "0x12", and decimals() is the one metadata call fetchTokenInfo does
    // not swallow errors from, so a short value makes every order-creation
    // attempt fail in mock mode.
    "0x313ce567": () => "0x" + word(18),
  };

  /**
   * Answers an eth_call from the selector table.
   *
   * A token metadata read and a Swapboard read are told apart by the selector
   * alone, since no ERC20 selector collides with a Swapboard one.
   *
   * @param {Array} params - eth_call params, whose first entry carries `data`
   * @returns {string} ABI-encoded return value
   */
  function handleCall(params) {
    const data = (params && params[0] && params[0].data) || "";
    const selector = data.slice(0, 10).toLowerCase();

    const handler = CONTRACT_CALLS[selector] || ERC20_CALLS[selector];
    if (handler) return handler(data);

    console.warn("[Mock Wallet] Unhandled eth_call selector:", selector);
    return "0x" + word(1);
  }

  // ============================================================================
  // Mock Wallet Provider
  // ============================================================================

  if (MOCK_CONFIG.enableMockWallet) {
    console.log("[Mock] Creating mock wallet provider (overriding any existing wallet)");

    // Same address the cancel cohort is made by, so connecting the mock wallet
    // actually owns those orders.
    const mockAddress = MOCK_CONFIG.walletAddress;
    let connected = false;

    const mockProvider = {
      isMetaMask: true,
      chainId: "0x1", // Ethereum mainnet — see note above
      selectedAddress: null,

      request: async function ({ method, params }) {
        console.log("[Mock Wallet]", method);

        switch (method) {
          case "eth_requestAccounts":
            connected = true;
            // Named, not `this`: ethers hands the provider's request method
            // around detached, so `this` is not reliably the provider.
            mockProvider.selectedAddress = mockAddress;
            return [mockAddress];

          case "eth_accounts":
            return connected ? [mockAddress] : [];

          case "eth_chainId":
            return "0x1"; // Ethereum mainnet

          case "wallet_switchEthereumChain":
            return null;

          case "eth_sendTransaction": {
            // Writes are acknowledged but change nothing: the store is an index
            // of a chain that does not exist, and inventing state transitions
            // here would let the UI look correct against behaviour no contract
            // has been asked to produce.
            await new Promise((r) => setTimeout(r, 2000));
            const txHash = "0x" + Date.now().toString(16).padStart(64, "0");
            console.log("[Mock Wallet] Transaction:", txHash);
            return txHash;
          }

          case "eth_call":
            return handleCall(params);

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

          case "eth_getLogs":
            // Must be an array, not the null the default branch would give.
            // app.js subscribes to OrderFilled/OrderCreated on connect, and
            // ethers maps over whatever comes back on every poll — null there
            // throws "Cannot read properties of null (reading 'map')" on a
            // timer, several times a minute, for the whole session.
            return [];

          case "net_version":
            return "1"; // Ethereum mainnet

          default:
            console.warn("[Mock Wallet] Unhandled:", method);
            return null;
        }
      },

      on: function (event, callback) {
        // Store callbacks for potential use
        mockProvider._callbacks = mockProvider._callbacks || {};
        mockProvider._callbacks[event] = callback;
      },

      removeListener: function () {},

      removeAllListeners: function () {},
    };
    // ------------------------------------------------------------------------
    // Installing over window.ethereum
    // ------------------------------------------------------------------------
    //
    // This used to be a bare `window.ethereum = {...}`, which throws
    // "Cannot set property ethereum of #<Window> which has only a getter"
    // on any browser where an extension has already defined the property as
    // accessor-only — Rabby and Keplr both do, and MetaMask logs its own
    // "encountered an error setting the global Ethereum provider" when it
    // loses that race. The throw escaped the top-level IIFE, so every line of
    // mock.js below this point — including the EIP-6963 wiring — silently
    // never ran, and mock mode fell back to whatever real wallets were
    // installed. Nothing about the mock is worth taking the page down for:
    // try the strongest install, fall back, and carry on either way.
    // Always reachable under a name no extension competes for. app.js's
    // eager-reconnect path reads a provider off the window directly, and when
    // the override below loses, this is the only handle it has on the mock.
    window.SWAPBOARD_MOCK_PROVIDER = mockProvider;

    try {
      Object.defineProperty(window, "ethereum", {
        value: mockProvider,
        writable: true,
        configurable: true,
      });
    } catch (e) {
      try {
        window.ethereum = mockProvider;
      } catch (e2) {
        console.warn(
          "[Mock] Could not override window.ethereum (locked by a wallet extension). " +
            "Mock mode still works via EIP-6963."
        );
      }
    }

    // ------------------------------------------------------------------------
    // EIP-6963 announcement
    // ------------------------------------------------------------------------
    //
    // Overriding window.ethereum is not enough. app.js discovers wallets via
    // EIP-6963 and only falls back to window.ethereum when nothing announced
    // itself, so on any browser with a real wallet extension installed the
    // mock provider above was never reached: mock mode would open the real
    // MetaMask/Rabby popup, and the header kept saying "[Connect Wallet]"
    // whenever that popup was dismissed or the real wallet was on a chain
    // other than mainnet. Announce the mock as a 6963 provider, and suppress
    // the real ones, so mock mode overrides the wallet the way it claims to.
    const MOCK_PROVIDER_UUID = "5c0mock00-0000-4000-8000-5w4pb0ard000";
    const mockProviderInfo = {
      uuid: MOCK_PROVIDER_UUID,
      name: "Mock Wallet",
      rdns: "xyz.swapboard.mock",
      icon:
        "data:image/svg+xml;base64," +
        btoa(
          '<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96">' +
            '<rect width="96" height="96" fill="#ff6600"/>' +
            '<text x="48" y="62" font-family="monospace" font-size="40" ' +
            'font-weight="bold" fill="#fff" text-anchor="middle">M</text></svg>'
        ),
    };

    const announceMockProvider = () => {
      window.dispatchEvent(
        new CustomEvent("eip6963:announceProvider", {
          // mockProvider, never window.ethereum: the install above may have
          // been refused, and extensions re-assign the global late, so reading
          // it here can hand the app a real wallet labelled "Mock Wallet".
          detail: Object.freeze({ info: mockProviderInfo, provider: mockProvider }),
        })
      );
    };

    // Registered before app.js loads (index.html orders mock.js first), so this
    // runs ahead of app.js's own listener and can cut off announcements from
    // real extensions before the app ever sees them. Without this, a browser
    // with one real wallet would show a two-wallet picker in mock mode.
    window.addEventListener("eip6963:announceProvider", function (event) {
      if (event.detail?.info?.uuid === MOCK_PROVIDER_UUID) return;
      console.log("[Mock] Suppressing real wallet:", event.detail?.info?.name || "unknown");
      event.stopImmediatePropagation();
    });

    window.addEventListener("eip6963:requestProvider", announceMockProvider);

    // Also announce unprompted, for any listener that registered before its
    // own request went out.
    announceMockProvider();
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
  console.log("Protocol version:", "v" + MOCK_VERSION);
  console.log(
    "To disable: add ?mock=false to URL or localStorage.setItem('swapboard_mock', 'false')"
  );
  console.log("Configuration:", MOCK_CONFIG);
  console.log("Orders generated:", STORE.orders.size);
  console.log("Fills generated:", STORE.fills.length);
  console.log("Stats:", STORE.globalStats);
  console.log("Tokens:", [...STORE.tokens.values()].map((t) => t.symbol).join(", "));
  console.log("To change data, modify MOCK_CONFIG.seed and refresh");
})();
