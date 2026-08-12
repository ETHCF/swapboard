/**
 * @fileoverview Swapboard Frontend Application
 * @description Client-side application for interacting with the Swapboard smart contract.
 *              Handles wallet connection, order display, and transaction submission.
 * @author Zak Cole (numbergroup.xyz) for Ethereum Community Foundation
 * @license AGPL-3.0-only
 *
 * Dependencies:
 * - ethers.js v6 (loaded dynamically from CDN)
 * - The Graph subgraph for order indexing
 *
 * Configuration:
 * - Update CONFIG.CONTRACT_ADDRESS and CONFIG.SUBGRAPH_URL before deployment
 * - Local development skips config validation (localhost/file://)
 */

(function () {
  "use strict";

  // Import shared utilities from lib.js (loaded before app.js)
  const {
    escapeHtml,
    isValidAddress,
    truncateAddress,
    formatUsd,
    formatAmount,
    COINGECKO_ID_MAP,
    // Protocol version
    VERSION_STORAGE_KEY,
    SUPPORTED_VERSIONS,
    resolveVersion,
    capsFor,
    orderQueryFields,
    normalizeOrder,
    offersEthDirectly,
    // V2 helpers
    NATIVE_ETH,
    isNativeEth,
    chunkArray,
    resolveSelectionMode,
    canSelectOrder,
    getShiftRangeIds,
    computeFillFromReceive,
    summarizeFillBatch,
  } = window.SwapboardLib || {};

  // ============================================================================
  // Configuration
  // ============================================================================

  /**
   * Application configuration. Update these values before deployment.
   * @constant {Object}
   */
  const CONFIG = {
    // Contract address on Ethereum mainnet
    CONTRACT_ADDRESS: "0x000000fF3D7A2d373615141d7489Ca66683DbecF",
    // Goldsky subgraph endpoint (Mainnet)
    SUBGRAPH_URL:
      "https://api.goldsky.com/api/public/project_cmmkvehnce9da01u17d657vdt/subgraphs/Swapboard/1.0.0/gn",
    // Number of orders per page
    PAGE_SIZE: 200,
    // Request timeout in milliseconds
    REQUEST_TIMEOUT: 30000,
    // Debounce delay for token info fetch
    DEBOUNCE_DELAY: 500,
    // Show market deviation percentage (vs CoinGecko prices)
    SHOW_MARKET_DEVIATION: false,
    // v2 batch limits: the most orders that fit in a single transaction.
    // Seeded conservatively; retune once real gas numbers land.
    MAX_BATCH_FILL: 15,
    MAX_BATCH_CANCEL: 25,
    MAX_BATCH_CREATE: 10,
  };

  const EXPECTED_CHAIN_ID = 1;
  const EXPECTED_CHAIN = {
    chainId: "0x1",
    chainName: "Ethereum",
    nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
    rpcUrls: ["https://eth-mainnet.g.alchemy.com/v2/WLD-4NTd9zxSax2e5Oh2q"],
    blockExplorerUrls: ["https://etherscan.io"],
  };

  // ============================================================================
  // Protocol Version
  // ============================================================================

  /**
   * Reads the persisted version preference.
   * @returns {string|null} Stored value, or null when storage is unavailable
   */
  function readStoredVersion() {
    try {
      return localStorage.getItem(VERSION_STORAGE_KEY);
    } catch {
      return null;
    }
  }

  const initialVersion = resolveVersion({
    search: window.location.search,
    stored: readStoredVersion(),
  });

  /**
   * Protocol version the app is currently speaking.
   * @type {number}
   */
  const ACTIVE_VERSION = initialVersion.version;

  /**
   * Capabilities of ACTIVE_VERSION. Every version-dependent branch in the app
   * reads a named flag off this object rather than comparing version numbers,
   * so what a branch is actually about stays legible at the call site.
   * @type {Object}
   */
  const CAPS = capsFor(ACTIVE_VERSION);

  /**
   * Switches protocol version.
   *
   * A reload is the honest way to do this. The version decides the subgraph
   * query shape, the connector, the table columns, and the shape of the sell
   * form; rebuilding all of that in place would mean unwinding wallet state,
   * in-flight requests, and the current selection, and any missed corner
   * leaves the two versions' state mixed together. Reloading cannot.
   *
   * @param {number} version - Version to switch to
   */
  function setVersion(version) {
    if (!SUPPORTED_VERSIONS.includes(version) || version === ACTIVE_VERSION) return;

    try {
      localStorage.setItem(VERSION_STORAGE_KEY, String(version));
    } catch {
      // Storage unavailable (private mode); the URL below still carries it.
    }

    // Keep ?v= in step with the choice, so the reload lands on the new version
    // even if storage was refused, and so the URL stays shareable.
    const url = new URL(window.location.href);
    url.searchParams.set("v", String(version));
    // The order hash addresses an order in the version being left behind.
    url.hash = "";
    window.location.href = url.toString();
  }

  /** Headline text and blurb for each version. */
  const VERSION_COPY = {
    1: {
      title: "Welcome to SWAPBOARD v1",
      note: "V1: no partial fills. Live on mainnet.",
      hint: "Swapboard v1 — deployed and live on mainnet",
    },
    2: {
      title: "Welcome to SWAPBOARD v2",
      note: "V2: partial fills, batch fill/cancel/create, and native ETH. Preview — contracts are not deployed, so transactions are simulated.",
      hint: "Swapboard v2 — preview, contracts not yet deployed",
    },
  };

  /**
   * Number of columns in the order table, which the select column changes.
   * Used for the full-width "Loading" / "No orders" rows.
   * @returns {number}
   */
  function orderColumnCount() {
    return CAPS.batch ? 10 : 9;
  }

  /**
   * Applies everything about the page that depends on the protocol version:
   * the body attribute driving the CSS gates, the copy, and the switcher's
   * pressed state.
   *
   * Feature chrome is hidden in CSS off `body[data-version]` rather than by
   * toggling each node here, so a control added later is gated by matching a
   * selector instead of by remembering to update this function.
   */
  function applyVersionUi() {
    const copy = VERSION_COPY[ACTIVE_VERSION] || VERSION_COPY[1];

    document.body.dataset.version = String(ACTIVE_VERSION);

    const title = $("#app-title");
    if (title) title.textContent = copy.title;

    const note = $("#version-note-text");
    if (note) note.textContent = copy.note;

    document.querySelectorAll("#version-switch .version-option").forEach((btn) => {
      const version = Number(btn.dataset.version);
      const active = version === ACTIVE_VERSION;
      btn.setAttribute("aria-pressed", String(active));
      btn.classList.toggle("active", active);
      btn.title = (VERSION_COPY[version] || {}).hint || "";
    });
  }

  // ============================================================================
  // Theme (Dark Mode)
  // ============================================================================

  function updateThemeIcons(isDark) {
    const sunIcon = $("#theme-icon-sun");
    const moonIcon = $("#theme-icon-moon");
    if (isDark) {
      sunIcon.classList.add("hidden");
      moonIcon.classList.remove("hidden");
    } else {
      sunIcon.classList.remove("hidden");
      moonIcon.classList.add("hidden");
    }
  }

  function initTheme() {
    const stored = localStorage.getItem("swapboard-theme");
    if (stored === "dark") {
      document.body.classList.add("dark-mode");
      updateThemeIcons(true);
    } else if (stored === "light") {
      document.body.classList.remove("dark-mode");
      updateThemeIcons(false);
    } else {
      // No preference stored, check system preference
      if (window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches) {
        document.body.classList.add("dark-mode");
        updateThemeIcons(true);
      }
    }
  }

  function toggleTheme() {
    const isDark = document.body.classList.toggle("dark-mode");
    localStorage.setItem("swapboard-theme", isDark ? "dark" : "light");
    updateThemeIcons(isDark);
  }

  function updateNotifyText() {
    $("#wallet-notifications").textContent = notificationsEnabled
      ? "Disable Notifications"
      : "Enable Notifications";
  }

  // Validate configuration - fail fast on placeholder values
  // Skips validation on localhost/file:// for development/testing
  function validateConfig() {
    const isLocal =
      window.location.hostname === "localhost" ||
      window.location.hostname === "127.0.0.1" ||
      window.location.protocol === "file:";

    if (isLocal) {
      console.warn("Development mode: skipping config validation");
      return;
    }

    const errors = [];
    if (CONFIG.CONTRACT_ADDRESS === "0x0000000000000000000000000000000000000000") {
      errors.push("CONTRACT_ADDRESS is not configured");
    }
    if (CONFIG.SUBGRAPH_URL.includes("YOUR_ID")) {
      errors.push("SUBGRAPH_URL is not configured");
    }
    if (errors.length > 0) {
      const msg =
        "Configuration error: " +
        errors.join(", ") +
        ". Update CONFIG in app.js before deployment.";
      console.error(msg);
      document.body.innerHTML =
        '<div style="color:red;padding:20px;font-family:monospace;">' + msg + "</div>";
      throw new Error(msg);
    }
  }

  const CONTRACT_ABI = [
    "function createOrder(address tokenA, uint256 amountA, address tokenB, uint256 amountB) external returns (uint256 orderId)",
    "function createOrderWithEth(address tokenB, uint256 amountB) external payable returns (uint256 orderId)",
    "function fillOrder(uint256 orderId, uint256 deadline) external",
    "function fillOrderWithEth(uint256 orderId, uint256 deadline) external payable",
    "function fillOrderUnwrap(uint256 orderId, uint256 deadline) external",
    "function cancelOrder(uint256 orderId) external",
    "function cancelOrderUnwrap(uint256 orderId) external",
    "function getOrder(uint256 orderId) external view returns (tuple(address maker, address tokenA, uint256 amountA, address tokenB, uint256 amountB, bool active))",
    "function getOrders(uint256[] orderIds) external view returns (tuple(address maker, address tokenA, uint256 amountA, address tokenB, uint256 amountB, bool active)[])",
    "function canFill(uint256 orderId) external view returns (bool)",
    "function nextOrderId() external view returns (uint256)",
    "function weth() external view returns (address)",
    "event OrderCreated(uint256 indexed orderId, address indexed maker, address tokenA, uint256 amountA, address tokenB, uint256 amountB)",
    "event OrderFilled(uint256 indexed orderId, address indexed taker)",
    "event OrderCanceled(uint256 indexed orderId)",
    "error ZeroAddress()",
    "error ZeroAmount()",
    "error ZeroETH()",
    "error SameToken()",
    "error NotAContract(address token)",
    "error NotWETH(address expected, address actual)",
    "error ETHAmountMismatch(uint256 required, uint256 sent)",
    "error ETHTransferFailed(address recipient)",
    "error BalanceMismatch(uint256 expected, uint256 received)",
    "error OrderNotFound(uint256 orderId)",
    "error OrderNotActive(uint256 orderId)",
    "error NotMaker(uint256 orderId, address caller, address maker)",
  ];

  const ERC20_ABI = [
    "function name() view returns (string)",
    "function symbol() view returns (string)",
    "function decimals() view returns (uint8)",
    "function balanceOf(address) view returns (uint256)",
    "function allowance(address owner, address spender) view returns (uint256)",
    "function approve(address spender, uint256 amount) returns (bool)",
  ];

  let provider = null;
  let signer = null;
  let userAddress = null;
  let contract = null;
  let cachedWethAddress = null;

  function isWeth(addr) {
    if (!cachedWethAddress || !addr) return false;
    return addr.toLowerCase() === cachedWethAddress;
  }

  /**
   * Order IDs currently ticked in the order table.
   * Deliberately in-memory: unlike the watchlist, a selection is a transient
   * intent to act, not a preference worth surviving a reload.
   * @type {Set<string>}
   */
  const selectedOrderIds = new Set();

  /** Order ID of the last plain (non-shift) checkbox click, for shift ranges. */
  let selectionAnchorId = null;

  const tokenCache = new Map();
  const ensCache = new Map();
  let currentPage = 1;
  let currentFilters = { selling: "", wanting: "", status: "open", myOrders: false };
  let currentSort = { column: "orderId", direction: "desc" };
  let cachedOrders = [];
  /** True when the last order query errored, as opposed to returning nothing. */
  let ordersQueryFailed = false;
  let highlightedOrderId = null;
  let notificationsEnabled = false;
  const RECENT_TOKENS_KEY = "swapboard_recent_tokens";
  const MAX_RECENT_TOKENS = 5;
  const FILTERS_KEY = "swapboard_filters";
  const SORT_KEY = "swapboard_sort";
  const WATCHED_ORDERS_KEY = "swapboard_watched_orders";
  const UNISWAP_TOKEN_LIST_URL = "https://tokens.uniswap.org";
  let uniswapTokens = [];
  let autoRefreshInterval = null;
  const AUTO_REFRESH_MS = 30000;

  // ============================================================================
  // EIP-6963 Multi-Wallet Discovery
  // ============================================================================

  /**
   * Discovered EIP-6963 wallet providers.
   * @type {Map<string, {info: Object, provider: Object}>}
   */
  const discoveredProviders = new Map();

  /**
   * The currently selected EIP-1193 provider (from wallet selection).
   * @type {Object|null}
   */
  let selectedProvider = null;

  /**
   * Sets up EIP-6963 provider discovery.
   * Listens for wallet announcements and requests providers to announce themselves.
   */
  function setupEIP6963Discovery() {
    window.addEventListener("eip6963:announceProvider", (event) => {
      const { info, provider } = event.detail;
      if (info?.uuid && provider) {
        discoveredProviders.set(info.uuid, { info, provider });
      }
    });
    window.dispatchEvent(new Event("eip6963:requestProvider"));
  }

  // ============================================================================
  // Price Service (CoinGecko)
  // ============================================================================

  // COINGECKO_ID_MAP comes from lib.js. It used to be duplicated here, and the
  // copy silently fell behind when lib.js gained the native-ETH sentinel — the
  // local one shadowed it, so every v2 ETH order priced as "N/A" while the
  // identical WETH order priced fine. One definition, no drift.

  const STABLE_ADDRESSES = new Set([
    "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", // USDC
    "0xdac17f958d2ee523a2206206994597c13d831ec7", // USDT
    "0x6b175474e89094c44da98b954eedeac495271d0f", // DAI
  ]);

  function isStable(addr) {
    return !!addr && STABLE_ADDRESSES.has(addr.toLowerCase());
  }

  // Picks which token should be the quote (numerator) in the Price column.
  // Returns "A", "B", or null to fall back to the existing tokenB/tokenA default.
  function preferredQuoteSide(tokenAAddr, tokenBAddr) {
    const aStable = isStable(tokenAAddr);
    const bStable = isStable(tokenBAddr);
    if (aStable && !bStable) return "A";
    if (bStable && !aStable) return "B";
    if (aStable && bStable) return null;
    const aEth = isWeth(tokenAAddr);
    const bEth = isWeth(tokenBAddr);
    if (aEth && !bEth) return "A";
    if (bEth && !aEth) return "B";
    return null;
  }

  /**
   * Price cache with TTL tracking.
   * @type {Map<string, {usd: number, fetchedAt: number}>}
   */
  const priceCache = new Map();
  const PRICE_CACHE_TTL_MS = 60000;
  let priceFetchInProgress = null;

  /**
   * Returns cached price if valid, null otherwise.
   * @param {string} coinGeckoId - CoinGecko coin ID
   * @returns {{usd: number, fetchedAt: number}|null}
   */
  function getCachedPrice(coinGeckoId) {
    const cached = priceCache.get(coinGeckoId);
    if (!cached) return null;
    if (Date.now() - cached.fetchedAt > PRICE_CACHE_TTL_MS) return null;
    return cached;
  }

  /**
   * Fetches prices for multiple CoinGecko IDs in a single request.
   * Implements rate limiting via request coalescing.
   * @param {string[]} coinGeckoIds - Array of CoinGecko coin IDs
   * @returns {Promise<void>}
   */
  async function fetchPrices(coinGeckoIds) {
    const idsToFetch = coinGeckoIds.filter((id) => !getCachedPrice(id));
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
            priceCache.set(id, { usd: data[id].usd, fetchedAt: now });
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
   * Gets USD price for a token address.
   * @param {string} tokenAddress - Ethereum token address
   * @returns {number|null} USD price or null if unavailable
   */
  function getTokenPrice(tokenAddress) {
    const id = COINGECKO_ID_MAP[tokenAddress.toLowerCase()];
    if (!id) return null;
    const cached = getCachedPrice(id);
    return cached ? cached.usd : null;
  }

  /**
   * Calculates the market rate deviation for an order.
   * @param {Object} order - Order with tokenA/tokenB and amounts
   * @returns {{deviation: number, label: string}|null} Deviation percentage and label, or null if unavailable
   */
  function calculateMarketDeviation(order) {
    const priceA = getTokenPrice(order.tokenA.address);
    const priceB = getTokenPrice(order.tokenB.address);

    if (priceA === null || priceB === null) return null;
    if (priceA === 0 || priceB === 0) return null;

    const amountA = BigInt(order.amountA);
    const amountB = BigInt(order.amountB);

    if (amountA === 0n || amountB === 0n) return null;

    // Market rate: how many tokenB per tokenA at market prices
    const marketRate = priceA / priceB;

    // Order rate: how many tokenB per tokenA this order offers
    const humanAmountA = Number(amountA) / Math.pow(10, order.tokenA.decimals);
    const humanAmountB = Number(amountB) / Math.pow(10, order.tokenB.decimals);
    const orderRate = humanAmountB / humanAmountA;

    // Deviation: positive = seller asking more (bad for buyer), negative = discount (good for buyer)
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
  // Utility Functions
  // ============================================================================

  /** @param {string} sel - CSS selector */
  const $ = (sel) => document.querySelector(sel);

  /**
   * Resolves an address to its ENS name if available.
   * Results are cached to avoid redundant lookups.
   * @param {string} address - Ethereum address
   * @returns {Promise<string|null>} ENS name or null if not found
   */
  async function resolveEns(address) {
    if (!address || !provider) return null;
    const lowerAddr = address.toLowerCase();

    if (ensCache.has(lowerAddr)) {
      return ensCache.get(lowerAddr);
    }

    try {
      const name = await provider.lookupAddress(address);
      ensCache.set(lowerAddr, name);
      return name;
    } catch (e) {
      ensCache.set(lowerAddr, null);
      return null;
    }
  }

  /**
   * Batch resolves ENS names for multiple addresses.
   * @param {string[]} addresses - Array of Ethereum addresses
   * @returns {Promise<void>}
   */
  async function batchResolveEns(addresses) {
    if (!provider) return;

    const uncached = addresses.filter((addr) => !ensCache.has(addr.toLowerCase()));
    if (uncached.length === 0) return;

    // Resolve in parallel, limit to 10 concurrent lookups
    const batchSize = 10;
    for (let i = 0; i < uncached.length; i += batchSize) {
      const batch = uncached.slice(i, i + batchSize);
      await Promise.all(batch.map((addr) => resolveEns(addr)));
    }
  }

  /**
   * Gets cached ENS name for an address.
   * @param {string} address - Ethereum address
   * @returns {string|null} Cached ENS name or null
   */
  function getCachedEns(address) {
    return ensCache.get(address.toLowerCase()) || null;
  }

  /**
   * Gets order ID from URL hash if present.
   * Supports formats: #order-123, #order=123, #123
   * @returns {string|null} Order ID or null
   */
  function getOrderIdFromHash() {
    const hash = window.location.hash;
    if (!hash) return null;

    // Format: #order-123 (new format)
    const dashMatch = hash.match(/^#order-(\d+)$/);
    if (dashMatch) return dashMatch[1];

    // Format: #order=123
    const orderMatch = hash.match(/^#order=(\d+)$/);
    if (orderMatch) return orderMatch[1];

    // Format: #123
    const simpleMatch = hash.match(/^#(\d+)$/);
    if (simpleMatch) return simpleMatch[1];

    return null;
  }

  /**
   * Creates a shareable URL for an order.
   * @param {string} orderId - Order ID
   * @returns {string} Full URL with hash
   */
  function getOrderShareUrl(orderId) {
    const url = new URL(window.location.href);
    url.hash = "order-" + orderId;
    return url.toString();
  }

  /**
   * Creates a share button for an order.
   * @param {string} orderId - Order ID
   * @returns {HTMLElement} Share button element
   */
  /**
   * Requests notification permission from the user.
   * @returns {Promise<boolean>} True if permission granted
   */
  async function requestNotificationPermission() {
    if (!("Notification" in window)) {
      showToast("Browser does not support notifications", "error");
      return false;
    }

    if (Notification.permission === "granted") {
      return true;
    }

    if (Notification.permission === "denied") {
      showToast("Notifications blocked. Enable in browser settings.", "error");
      return false;
    }

    const permission = await Notification.requestPermission();
    return permission === "granted";
  }

  /**
   * Shows a browser notification.
   * @param {string} title - Notification title
   * @param {string} body - Notification body
   * @param {string} [tag] - Notification tag for grouping
   */
  function showNotification(title, body, tag) {
    if (!notificationsEnabled) {
      return;
    }
    if (Notification.permission !== "granted") {
      return;
    }

    try {
      const notification = new Notification(title, {
        body: body,
        tag: tag,
      });

      notification.onclick = () => {
        window.focus();
        notification.close();
      };

      setTimeout(() => notification.close(), 10000);
    } catch (e) {
      console.error("Notification error:", e);
    }
  }

  /**
   * Estimates what a transaction will cost, in gas, ETH, and USD.
   *
   * Only reachable in v1 mode (CAPS.gasEstimate) — estimating requires a
   * deployed contract to encode against and simulate the call on.
   *
   * @param {Object} txParams - {from, to, data, value?}
   * @returns {Promise<Object|null>} {gas, eth, usd}, or null if unavailable
   */
  async function estimateGasCost(txParams) {
    if (!provider) return null;

    try {
      const [gasEstimate, feeData] = await Promise.all([
        provider.estimateGas(txParams),
        provider.getFeeData(),
      ]);

      const gasPrice = feeData.gasPrice || feeData.maxFeePerGas;
      if (!gasPrice) return null;

      const gasCostWei = gasEstimate * gasPrice;
      const gasCostEth = Number(gasCostWei) / 1e18;

      const ethPrice = getTokenPrice("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2");
      const gasCostUsd = ethPrice ? gasCostEth * ethPrice : null;

      return {
        gas: gasEstimate.toString(),
        eth: gasCostEth < 0.0001 ? gasCostEth.toExponential(2) : gasCostEth.toFixed(6),
        usd: gasCostUsd ? formatUsd(gasCostUsd) : "$--",
      };
    } catch (e) {
      console.error("Gas estimation error:", e);
      return null;
    }
  }

  /**
   * Toggles notifications on/off.
   */
  async function toggleNotifications() {
    if (notificationsEnabled) {
      notificationsEnabled = false;
      localStorage.setItem("swapboard_notifications", "false");
      showToast("Notifications disabled");
      return;
    }

    const granted = await requestNotificationPermission();
    if (granted) {
      notificationsEnabled = true;
      localStorage.setItem("swapboard_notifications", "true");
      showToast("Notifications enabled", "success");
    }
  }

  /**
   * Fetches and caches the Uniswap token list.
   * Filters to Ethereum mainnet tokens only.
   */
  async function fetchUniswapTokenList() {
    if (uniswapTokens.length > 0) return;

    try {
      const res = await fetch(UNISWAP_TOKEN_LIST_URL);
      if (!res.ok) return;

      const data = await res.json();
      // Filter to Ethereum mainnet (chainId: 1)
      uniswapTokens = (data.tokens || [])
        .filter((t) => t.chainId === 1)
        .map((t) => ({
          address: t.address.toLowerCase(),
          symbol: t.symbol,
          name: t.name,
          decimals: t.decimals,
          logoURI: t.logoURI,
        }));
    } catch (e) {
      console.error("Failed to fetch Uniswap token list:", e);
    }
  }

  /**
   * The "ETH" entry offered by the token autocomplete, or null when there
   * isn't one to offer yet.
   *
   * The address depends on the version: v2 has a NATIVE_ETH sentinel and the
   * create path recognizes it, but v1 has no sentinel and reaches ETH by
   * wrapping into WETH. Handing v1 the sentinel makes `offersEthDirectly`
   * false, so the order takes the ERC20 path and builds a contract on an
   * address with no code. Before WETH is known, v1 has no address to offer.
   *
   * @returns {{address: string, symbol: string, name: string,
   *   decimals: number, logoURI: null}|null} Token entry, or null
   */
  function getEthToken() {
    const address = CAPS.nativeEth ? NATIVE_ETH : cachedWethAddress;
    if (!address) return null;
    return {
      address,
      symbol: "ETH",
      name: "Ether",
      decimals: 18,
      logoURI: null,
    };
  }

  /**
   * Searches tokens by symbol or name.
   * @param {string} query - Search query
   * @param {number} limit - Max results
   * @returns {Array} Matching tokens
   */

  function searchTokens(query, limit = 10) {
    if (!query || query.length < 1) return [];

    const q = query.toLowerCase();
    const results = [];

    // Inject native ETH when query matches
    const eth = getEthToken();
    if (eth && "eth".startsWith(q)) {
      results.push(eth);
    }

    // Exact symbol matches first
    for (const t of uniswapTokens) {
      if (t.symbol.toLowerCase() === q) {
        results.push(t);
      }
    }

    // Symbol starts with query
    for (const t of uniswapTokens) {
      if (t.symbol.toLowerCase().startsWith(q) && !results.includes(t)) {
        results.push(t);
        if (results.length >= limit) return results;
      }
    }

    // Symbol or name contains query
    for (const t of uniswapTokens) {
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

  /**
   * Creates a token selector dropdown for a token input.
   * @param {HTMLInputElement} input - Token input element
   */
  function createTokenSelector(input) {
    const wrapper = document.createElement("div");
    wrapper.className = "token-selector-wrapper";

    input.parentNode.insertBefore(wrapper, input);
    wrapper.appendChild(input);

    const dropdown = document.createElement("div");
    dropdown.className = "token-selector-dropdown hidden";
    dropdown.addEventListener("click", (e) => e.stopPropagation());
    wrapper.appendChild(dropdown);

    let selectedIndex = -1;

    function renderDropdown(tokens, recentTokens = []) {
      dropdown.textContent = "";
      selectedIndex = -1;

      if (recentTokens.length > 0) {
        const recentTitle = document.createElement("div");
        recentTitle.className = "token-selector-title";
        recentTitle.textContent = "Recent";
        dropdown.appendChild(recentTitle);

        recentTokens.forEach((t, idx) => {
          const item = createTokenItem(t, idx);
          dropdown.appendChild(item);
        });
      }

      if (tokens.length > 0) {
        const title = document.createElement("div");
        title.className = "token-selector-title";
        title.textContent = recentTokens.length > 0 ? "Search Results" : "Tokens";
        dropdown.appendChild(title);

        tokens.forEach((t, idx) => {
          const item = createTokenItem(t, recentTokens.length + idx);
          dropdown.appendChild(item);
        });
      }

      if (tokens.length === 0 && recentTokens.length === 0) {
        const empty = document.createElement("div");
        empty.className = "token-selector-empty";
        empty.textContent = "Type to search tokens...";
        dropdown.appendChild(empty);
      }

      dropdown.classList.remove("hidden");
    }

    function createTokenItem(token, index) {
      const item = document.createElement("div");
      item.className = "token-selector-item";
      item.dataset.index = index;

      if (token.logoURI) {
        const img = document.createElement("img");
        img.src = token.logoURI;
        img.className = "token-logo";
        img.onerror = () => {
          img.style.display = "none";
        };
        item.appendChild(img);
      }

      const info = document.createElement("div");
      info.className = "token-info";

      const symbol = document.createElement("span");
      symbol.className = "token-symbol";
      symbol.textContent = token.symbol;
      info.appendChild(symbol);

      const name = document.createElement("span");
      name.className = "token-name";
      name.textContent = token.name;
      info.appendChild(name);

      item.appendChild(info);

      item.addEventListener("click", (e) => {
        e.stopPropagation();
        input.value = token.address;
        input.dispatchEvent(new Event("input"));
        dropdown.classList.add("hidden");
      });

      item.addEventListener("mouseenter", () => {
        updateSelection(index);
      });

      return item;
    }

    function updateSelection(index) {
      const items = dropdown.querySelectorAll(".token-selector-item");
      items.forEach((item, i) => {
        item.classList.toggle("selected", parseInt(item.dataset.index) === index);
      });
      selectedIndex = index;
    }

    function getItemCount() {
      return dropdown.querySelectorAll(".token-selector-item").length;
    }

    input.addEventListener("focus", () => {
      const query = input.value.trim();
      if (query.length >= 2 && !query.startsWith("0x")) {
        const results = searchTokens(query);
        renderDropdown(results, []);
      } else {
        const recent = getRecentTokens();
        const eth = getEthToken();
        if (eth && !recent.some((t) => t.address === eth.address)) {
          recent.unshift(eth);
        }
        renderDropdown([], recent);
      }
    });

    input.addEventListener("input", () => {
      const query = input.value.trim();

      // If it looks like an address, don't show token selector
      if (query.startsWith("0x")) {
        dropdown.classList.add("hidden");
        return;
      }

      if (query.length >= 1) {
        const results = searchTokens(query);
        renderDropdown(results, []);
      } else {
        const recent = getRecentTokens();
        const eth = getEthToken();
        if (eth && !recent.some((t) => t.address === eth.address)) {
          recent.unshift(eth);
        }
        renderDropdown([], recent);
      }
    });

    input.addEventListener("keydown", (e) => {
      if (dropdown.classList.contains("hidden")) return;

      const itemCount = getItemCount();
      if (itemCount === 0) return;

      if (e.key === "ArrowDown") {
        e.preventDefault();
        updateSelection(selectedIndex < itemCount - 1 ? selectedIndex + 1 : 0);
      } else if (e.key === "ArrowUp") {
        e.preventDefault();
        updateSelection(selectedIndex > 0 ? selectedIndex - 1 : itemCount - 1);
      } else if (e.key === "Enter" && selectedIndex >= 0) {
        e.preventDefault();
        const items = dropdown.querySelectorAll(".token-selector-item");
        const selected = Array.from(items).find(
          (item) => parseInt(item.dataset.index) === selectedIndex
        );
        if (selected) selected.click();
      } else if (e.key === "Escape") {
        dropdown.classList.add("hidden");
      }
    });

    input.addEventListener("blur", () => {
      // Delay to allow click on dropdown item
      setTimeout(() => {
        dropdown.classList.add("hidden");
      }, 200);
    });
  }

  /**
   * Gets recent tokens from localStorage.
   * @returns {Array<{address: string, symbol: string}>} Recent tokens array
   */
  function getRecentTokens() {
    try {
      const stored = localStorage.getItem(RECENT_TOKENS_KEY);
      return stored ? JSON.parse(stored) : [];
    } catch (e) {
      return [];
    }
  }

  /**
   * Adds a token to recent tokens list.
   * @param {string} address - Token address
   * @param {string} symbol - Token symbol
   */
  function addRecentToken(address, symbol) {
    if (!address || !symbol) return;

    const recent = getRecentTokens();
    const lowerAddr = address.toLowerCase();

    // Remove if already exists
    const filtered = recent.filter((t) => t.address.toLowerCase() !== lowerAddr);

    // Add to front
    filtered.unshift({ address, symbol });

    // Limit to max
    const trimmed = filtered.slice(0, MAX_RECENT_TOKENS);

    try {
      localStorage.setItem(RECENT_TOKENS_KEY, JSON.stringify(trimmed));
    } catch (e) {
      console.error("Failed to save recent tokens:", e);
    }
  }

  /**
   * Saves current filter preferences to localStorage.
   */
  function saveFilterPreferences() {
    try {
      localStorage.setItem(FILTERS_KEY, JSON.stringify(currentFilters));
    } catch (e) {
      console.error("Failed to save filter preferences:", e);
    }
  }

  /**
   * Saves current sort preferences to localStorage.
   */
  function saveSortPreferences() {
    try {
      localStorage.setItem(SORT_KEY, JSON.stringify(currentSort));
    } catch (e) {
      console.error("Failed to save sort preferences:", e);
    }
  }

  /**
   * Loads filter preferences from localStorage.
   */
  function loadFilterPreferences() {
    try {
      const stored = localStorage.getItem(FILTERS_KEY);
      if (stored) {
        const parsed = JSON.parse(stored);
        if (parsed.status) currentFilters.status = parsed.status;
        if (parsed.selling) currentFilters.selling = parsed.selling;
        if (parsed.wanting) currentFilters.wanting = parsed.wanting;
      }
    } catch (e) {
      console.error("Failed to load filter preferences:", e);
    }
  }

  /**
   * Loads sort preferences from localStorage.
   */
  function loadSortPreferences() {
    try {
      const stored = localStorage.getItem(SORT_KEY);
      if (stored) {
        const parsed = JSON.parse(stored);
        if (parsed.column) currentSort.column = parsed.column;
        if (parsed.direction) currentSort.direction = parsed.direction;
      }
    } catch (e) {
      console.error("Failed to load sort preferences:", e);
    }
  }

  /**
   * Gets watched orders from localStorage.
   * Format: { orderId: { status: "Open"|"Filled"|"Cancelled", symbol: "WETH/USDC" } }
   * @returns {Object}
   */
  function getWatchedOrders() {
    try {
      const stored = localStorage.getItem(WATCHED_ORDERS_KEY);
      return stored ? JSON.parse(stored) : {};
    } catch (e) {
      return {};
    }
  }

  /**
   * Adds an order to the watch list.
   * @param {Object} order - Order object
   */
  function watchOrder(order) {
    const watched = getWatchedOrders();
    const status = order.active ? "Open" : order.taker ? "Filled" : "Cancelled";
    watched[order.orderId] = {
      status: status,
      symbol: order.tokenA.symbol + "/" + order.tokenB.symbol,
    };
    try {
      localStorage.setItem(WATCHED_ORDERS_KEY, JSON.stringify(watched));
    } catch (e) {
      console.error("Failed to save watched order:", e);
    }
  }

  /**
   * Removes an order from the watch list.
   * @param {string} orderId - Order ID
   */
  function unwatchOrder(orderId) {
    const watched = getWatchedOrders();
    delete watched[orderId];
    try {
      localStorage.setItem(WATCHED_ORDERS_KEY, JSON.stringify(watched));
    } catch (e) {
      console.error("Failed to remove watched order:", e);
    }
  }

  /**
   * Checks if an order is being watched.
   * @param {string} orderId - Order ID
   * @returns {boolean}
   */
  function isOrderWatched(orderId) {
    const watched = getWatchedOrders();
    return orderId in watched;
  }

  /**
   * Checks watched orders for status changes and sends notifications.
   * @param {Array} orders - Current orders from API
   */
  function checkWatchedOrders(orders) {
    const watched = getWatchedOrders();
    if (Object.keys(watched).length === 0) return;

    for (const order of orders) {
      const savedInfo = watched[order.orderId];
      if (!savedInfo) continue;

      const currentStatus = order.active ? "Open" : order.taker ? "Filled" : "Cancelled";
      if (savedInfo.status !== currentStatus) {
        // Status changed, send notification
        if (currentStatus === "Filled") {
          showNotification(
            "Order Filled",
            `Order #${order.orderId} (${savedInfo.symbol}) has been filled!`,
            "order-" + order.orderId
          );
        } else if (currentStatus === "Cancelled") {
          showNotification(
            "Order Cancelled",
            `Order #${order.orderId} (${savedInfo.symbol}) has been cancelled.`,
            "order-" + order.orderId
          );
        }

        // Update stored status
        watched[order.orderId].status = currentStatus;
        try {
          localStorage.setItem(WATCHED_ORDERS_KEY, JSON.stringify(watched));
        } catch (e) {
          // Ignore
        }
      }
    }
  }

  /**
   * Creates a recent tokens dropdown for a token input field.
   * @param {HTMLInputElement} input - Token input element
   * @param {string} infoId - Info element selector
   */
  function createRecentTokensDropdown(input, infoId) {
    const wrapper = document.createElement("div");
    wrapper.className = "recent-tokens-wrapper";
    wrapper.style.position = "relative";

    input.parentNode.insertBefore(wrapper, input);
    wrapper.appendChild(input);

    const dropdown = document.createElement("div");
    dropdown.className = "recent-tokens-dropdown hidden";
    wrapper.appendChild(dropdown);

    function showDropdown() {
      const recent = getRecentTokens();
      if (recent.length === 0) return;

      dropdown.textContent = "";
      const title = document.createElement("div");
      title.className = "recent-tokens-title";
      title.textContent = "Recent:";
      dropdown.appendChild(title);

      recent.forEach((token) => {
        const item = document.createElement("div");
        item.className = "recent-token-item";
        item.textContent = token.symbol;
        item.title = token.address;
        item.addEventListener("click", () => {
          input.value = token.address;
          input.dispatchEvent(new Event("input"));
          dropdown.classList.add("hidden");
        });
        dropdown.appendChild(item);
      });

      dropdown.classList.remove("hidden");
    }

    function hideDropdown() {
      setTimeout(() => {
        dropdown.classList.add("hidden");
      }, 200);
    }

    input.addEventListener("focus", showDropdown);
    input.addEventListener("blur", hideDropdown);
  }

  /**
   * Creates a copy button that copies text to clipboard.
   * @param {string} text - Text to copy
   * @returns {HTMLElement} Copy button element
   */
  function createCopyButton(text) {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.textContent = "\u29C9";
    btn.classList.add("copy-btn");
    btn.title = "Copy to clipboard";
    btn.addEventListener("click", async (e) => {
      e.stopPropagation();
      try {
        await navigator.clipboard.writeText(text);
        btn.textContent = "\u2713";
        setTimeout(() => {
          btn.textContent = "\u29C9";
        }, 1000);
      } catch (err) {
        console.error("Copy failed:", err);
      }
    });
    return btn;
  }

  function formatNumber(num) {
    return String(num).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  }

  /**
   * Formats a timestamp as relative time (e.g., "2h ago", "3d ago").
   * @param {number|string} timestamp - Unix timestamp in seconds
   * @returns {string} Relative time string
   */
  function formatTimeAgo(timestamp) {
    if (!timestamp) return "";

    const now = Math.floor(Date.now() / 1000);
    const ts = typeof timestamp === "string" ? parseInt(timestamp) : timestamp;
    const diff = now - ts;

    if (diff < 0) return "just now";
    if (diff < 60) return diff + "s ago";
    if (diff < 3600) return Math.floor(diff / 60) + "m ago";
    if (diff < 86400) return Math.floor(diff / 3600) + "h ago";
    if (diff < 604800) return Math.floor(diff / 86400) + "d ago";
    if (diff < 2592000) return Math.floor(diff / 604800) + "w ago";
    return Math.floor(diff / 2592000) + "mo ago";
  }

  function formatRatio(num) {
    if (num >= 1000) {
      return num.toFixed(0).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
    } else if (num >= 1) {
      return num.toFixed(2);
    } else if (num >= 0.0001) {
      return num.toFixed(6);
    } else {
      return num.toExponential(2);
    }
  }

  /**
   * Parses a human-readable amount string to base units.
   * @param {string} str - Amount string (e.g., "100.5")
   * @param {number} decimals - Token decimals
   * @returns {bigint} Amount in base units
   * @throws {Error} If format is invalid
   */
  function parseAmount(str, decimals) {
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

  /**
   * `parseAmount` that reports a rejection instead of throwing.
   *
   * parseAmount rejects malformed input, and dust that would round to zero at
   * the token's precision, by throwing — the messages are worth keeping, but
   * every caller is an input listener or a form collector where an escaped
   * throw means a dead control rather than a visible error. (lib.js exports a
   * null-returning parseAmount, but this local one shadows it; callers written
   * against lib's null contract silently got the throwing version.)
   *
   * @param {string} str - User-entered amount
   * @param {number} decimals - Token decimals
   * @returns {{amount: bigint|null, error: string|null}} Parsed amount, or the
   *   rejection message with a null amount
   */
  function tryParseAmount(str, decimals) {
    try {
      return { amount: parseAmount(str, decimals), error: null };
    } catch (e) {
      return { amount: null, error: e.message };
    }
  }

  let toastTimeout = null;
  function setTextWithDots(el, text) {
    el.textContent = "";
    el.appendChild(document.createTextNode(text));
    const dots = document.createElement("span");
    dots.className = "loading-dots";
    el.appendChild(dots);
  }

  function showToast(msg, type = "info", persistent = false) {
    const toast = $("#toast");
    toast.textContent = "";
    if (msg.endsWith("...")) {
      toast.appendChild(document.createTextNode(msg.slice(0, -3)));
      const dots = document.createElement("span");
      dots.className = "loading-dots";
      toast.appendChild(dots);
    } else {
      toast.textContent = msg;
    }
    toast.className = "toast " + type;
    if (toastTimeout) {
      clearTimeout(toastTimeout);
      toastTimeout = null;
    }
    if (!persistent) {
      toastTimeout = setTimeout(() => {
        toast.className = "toast hidden";
      }, 5000);
    }
  }

  function hideToast() {
    const toast = $("#toast");
    toast.className = "toast hidden";
    if (toastTimeout) {
      clearTimeout(toastTimeout);
      toastTimeout = null;
    }
  }

  function decodeContractError(data) {
    if (!data || data === "0x") return null;
    try {
      const iface = new ethers.Interface(CONTRACT_ABI);
      const decoded = iface.parseError(data);
      if (!decoded) return null;
      switch (decoded.name) {
        case "OrderNotActive":
          return `Order #${decoded.args[0]} is no longer active`;
        case "OrderNotFound":
          return `Order #${decoded.args[0]} not found`;
        case "NotMaker":
          return "You are not the maker of this order";
        case "ZeroAddress":
          return "Invalid token address";
        case "ZeroAmount":
          return "Amount too small (check decimal places)";
        case "SameToken":
          return "Offered and wanted tokens must be different";
        case "NotAContract":
          return "Token address is not a contract";
        case "BalanceMismatch":
          return "Token balance mismatch during transfer";
        case "ZeroETH":
          return "ETH amount cannot be zero";
        case "NotWETH":
          return "Token is not WETH";
        case "ETHAmountMismatch":
          return "ETH amount does not match required amount";
        case "ETHTransferFailed":
          return "ETH transfer to recipient failed";
        default:
          return "Transaction rejected by contract";
      }
    } catch {
      return null;
    }
  }

  function parseContractError(e) {
    // Try to decode custom contract errors from error data
    // ethers v6 puts data in different places depending on error type
    const errorData = e.data || e.error?.data || e.info?.error?.data;
    const decoded = decodeContractError(errorData);
    if (decoded) return decoded;

    // Check for data in error message (ethers v6 format)
    const msgMatch = (e.message || "").match(/data="(0x[a-fA-F0-9]+)"/);
    if (msgMatch) {
      const decoded2 = decodeContractError(msgMatch[1]);
      if (decoded2) return decoded2;
    }

    const msg = (e.reason || e.message || "").toLowerCase();
    if (msg.includes("user rejected") || msg.includes("user denied")) {
      return "Transaction cancelled";
    }
    if (
      msg.includes("insufficient") ||
      msg.includes("exceeds balance") ||
      msg.includes("transfer amount exceeds") ||
      msg.includes("erc20: transfer amount")
    ) {
      return "Insufficient token balance";
    }
    if (msg.includes("allowance") || msg.includes("erc20: insufficient allowance")) {
      return "Token approval failed";
    }
    if (msg.includes("nonce")) {
      return "Transaction conflict, try again";
    }
    if (msg.includes("could not decode result data") || msg.includes("bad_data")) {
      return "Token contract not found on this network";
    }
    if (msg.includes("missing revert data")) {
      return "Transaction failed. Order may already be filled or cancelled.";
    }
    if (msg.includes("gas") && msg.includes("estimation")) {
      return "Transaction would fail. Check order status and try again.";
    }
    if (msg.includes("network") || msg.includes("disconnected")) {
      return "Network error. Check your connection.";
    }
    if (msg.includes("timeout")) {
      return "Request timed out. Please try again.";
    }
    if (msg.includes("replacement") && msg.includes("underpriced")) {
      return "Gas price too low. Try again with higher gas.";
    }
    if (msg.includes("execution reverted")) {
      return "Transaction failed. The order may no longer be available.";
    }
    // Avoid showing raw technical messages - use short message if available
    if (e.shortMessage && e.shortMessage.length < 100) {
      return e.shortMessage;
    }
    return "Transaction failed. Please try again.";
  }

  /**
   * Sorts orders array based on current sort state.
   * @param {Array} orders - Orders array from subgraph
   * @returns {Array} Sorted orders array
   */
  function sortOrders(orders) {
    const col = currentSort.column;
    const dir = currentSort.direction === "asc" ? 1 : -1;

    return [...orders].sort((a, b) => {
      let valA, valB;

      switch (col) {
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
          valA = Number(BigInt(a.amountA)) / Math.pow(10, a.tokenA.decimals);
          valB = Number(BigInt(b.amountA)) / Math.pow(10, b.tokenA.decimals);
          break;
        case "tokenB":
          valA = (a.tokenB.symbol || "").toLowerCase();
          valB = (b.tokenB.symbol || "").toLowerCase();
          break;
        case "amountB":
          valA = Number(BigInt(a.amountB)) / Math.pow(10, a.tokenB.decimals);
          valB = Number(BigInt(b.amountB)) / Math.pow(10, b.tokenB.decimals);
          break;
        case "usdVal":
          const priceA = getTokenPrice(a.tokenA.address);
          const priceB = getTokenPrice(b.tokenA.address);
          const humanA = Number(BigInt(a.amountA)) / Math.pow(10, a.tokenA.decimals);
          const humanB = Number(BigInt(b.amountA)) / Math.pow(10, b.tokenA.decimals);
          valA = priceA !== null ? humanA * priceA : -1;
          valB = priceB !== null ? humanB * priceB : -1;
          break;
        case "price":
          const amtA1 = BigInt(a.amountA);
          const amtB1 = BigInt(a.amountB);
          const amtA2 = BigInt(b.amountA);
          const amtB2 = BigInt(b.amountB);
          const qsA = preferredQuoteSide(a.tokenA.address, a.tokenB.address);
          if (qsA === "A") {
            valA =
              amtB1 > 0n
                ? (Number(amtA1) / Number(amtB1)) *
                  Math.pow(10, a.tokenB.decimals - a.tokenA.decimals)
                : 0;
          } else {
            valA =
              amtA1 > 0n
                ? (Number(amtB1) / Number(amtA1)) *
                  Math.pow(10, a.tokenA.decimals - a.tokenB.decimals)
                : 0;
          }
          const qsB = preferredQuoteSide(b.tokenA.address, b.tokenB.address);
          if (qsB === "A") {
            valB =
              amtB2 > 0n
                ? (Number(amtA2) / Number(amtB2)) *
                  Math.pow(10, b.tokenB.decimals - b.tokenA.decimals)
                : 0;
          } else {
            valB =
              amtA2 > 0n
                ? (Number(amtB2) / Number(amtA2)) *
                  Math.pow(10, b.tokenA.decimals - b.tokenB.decimals)
                : 0;
          }
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

  /**
   * Handles column header click for sorting.
   * @param {string} column - Column identifier
   */
  function handleSort(column) {
    if (currentSort.column === column) {
      currentSort.direction = currentSort.direction === "asc" ? "desc" : "asc";
    } else {
      currentSort.column = column;
      currentSort.direction = "desc";
    }
    saveSortPreferences();
    renderOrders();
    updateSortIndicators();
  }

  /**
   * Updates sort indicators in table headers.
   */
  function updateSortIndicators() {
    document.querySelectorAll("thead th[data-sort]").forEach((th) => {
      const col = th.dataset.sort;
      const indicator = th.querySelector(".sort-indicator");
      if (indicator) {
        if (col === currentSort.column) {
          indicator.textContent = currentSort.direction === "asc" ? " \u25B2" : " \u25BC";
        } else {
          indicator.textContent = "";
        }
      }
    });
  }

  /**
   * Renders skeleton loading rows in the order table.
   * @param {number} count - Number of skeleton rows to render
   */
  function renderSkeletonRows(count = 10) {
    const tbody = $("#order-table");
    tbody.textContent = "";

    for (let i = 0; i < count; i++) {
      const tr = document.createElement("tr");

      // Column 0: Select (empty). Absent when the table has no select column.
      if (CAPS.batch) {
        const tdSelect = document.createElement("td");
        tdSelect.className = "select-col";
        tdSelect.dataset.label = "";
        tr.appendChild(tdSelect);
      }

      // Column 1: Action (empty)
      const tdAction = document.createElement("td");
      tdAction.dataset.label = "";
      tr.appendChild(tdAction);

      // Column 2: Trade ID
      const tdId = document.createElement("td");
      tdId.dataset.label = "Trade ID";
      const skelId = document.createElement("span");
      skelId.className = "skeleton skeleton-short";
      tdId.appendChild(skelId);
      tr.appendChild(tdId);

      // Column 2: Maker
      const tdMaker = document.createElement("td");
      tdMaker.dataset.label = "Maker";
      const skelMaker = document.createElement("span");
      skelMaker.className = "skeleton skeleton-text";
      tdMaker.appendChild(skelMaker);
      tr.appendChild(tdMaker);

      // Column 3: Offered Token
      const tdTokenA = document.createElement("td");
      tdTokenA.dataset.label = "Offered";
      const skelTokenA = document.createElement("span");
      skelTokenA.className = "skeleton skeleton-short";
      tdTokenA.appendChild(skelTokenA);
      tr.appendChild(tdTokenA);

      // Column 4: Offered Size
      const tdAmtA = document.createElement("td");
      tdAmtA.dataset.label = "Offered Size";
      const skelAmtA = document.createElement("span");
      skelAmtA.className = "skeleton skeleton-number";
      tdAmtA.appendChild(skelAmtA);
      tr.appendChild(tdAmtA);

      // Column 5: Wanted Token
      const tdTokenB = document.createElement("td");
      tdTokenB.dataset.label = "Wanted";
      const skelTokenB = document.createElement("span");
      skelTokenB.className = "skeleton skeleton-short";
      tdTokenB.appendChild(skelTokenB);
      tr.appendChild(tdTokenB);

      // Column 6: Wanted Size
      const tdAmtB = document.createElement("td");
      tdAmtB.dataset.label = "Wanted Size";
      const skelAmtB = document.createElement("span");
      skelAmtB.className = "skeleton skeleton-number";
      tdAmtB.appendChild(skelAmtB);
      tr.appendChild(tdAmtB);

      // Column 7: USD Val
      const tdUsd = document.createElement("td");
      tdUsd.dataset.label = "USD Val";
      const skelUsd = document.createElement("span");
      skelUsd.className = "skeleton skeleton-short";
      tdUsd.appendChild(skelUsd);
      tr.appendChild(tdUsd);

      // Column 8: Price
      const tdPrice = document.createElement("td");
      tdPrice.dataset.label = "Price";
      const skelPrice = document.createElement("span");
      skelPrice.className = "skeleton skeleton-text";
      tdPrice.appendChild(skelPrice);
      tr.appendChild(tdPrice);

      tbody.appendChild(tr);
    }
  }

  function showModal(title, body, onConfirm, gasEstimate) {
    const modal = $("#modal");
    $("#modal-title").textContent = title;

    // Body may be a plain string or a built-up DOM node (batch summaries and
    // the partial-fill controls need structure, not just text).
    const bodyEl = $("#modal-body");
    bodyEl.textContent = "";
    if (body instanceof Node) {
      bodyEl.appendChild(body);
    } else {
      bodyEl.textContent = body;
    }

    // Add gas estimate if available
    if (gasEstimate) {
      const gasDiv = document.createElement("div");
      gasDiv.className = "gas-estimate";
      gasDiv.appendChild(document.createElement("br"));
      gasDiv.appendChild(
        document.createTextNode(
          "Estimated gas: " +
            gasEstimate.gas +
            " (~" +
            gasEstimate.eth +
            " ETH / " +
            gasEstimate.usd +
            ")"
        )
      );
      bodyEl.appendChild(gasDiv);
    }

    modal.classList.remove("hidden");

    const confirmHandler = () => {
      modal.classList.add("hidden");
      $("#modal-confirm").removeEventListener("click", confirmHandler);
      $("#modal-cancel").removeEventListener("click", cancelHandler);
      onConfirm();
    };

    const cancelHandler = () => {
      modal.classList.add("hidden");
      $("#modal-confirm").removeEventListener("click", confirmHandler);
      $("#modal-cancel").removeEventListener("click", cancelHandler);
    };

    $("#modal-confirm").addEventListener("click", confirmHandler);
    $("#modal-cancel").addEventListener("click", cancelHandler);
  }

  /**
   * Renders "<amount> <symbol>" into an order-modal row.
   *
   * Links to CoinGecko and offers the contract address where there is one;
   * native ETH gets neither. When the order is partly filled, the original
   * amount is appended so the remaining figure has context.
   *
   * @param {HTMLElement} el - Row value element to populate
   * @param {Object} token - Token with {address, symbol, decimals}
   * @param {bigint} amount - Remaining amount in base units
   * @param {string|undefined} original - Original amount in base units
   */
  function fillOrderModalAmount(el, token, amount, original) {
    el.textContent = "";
    const decimals = token.decimals || 18;
    const text = formatAmount(amount, decimals) + " " + token.symbol;

    if (isNativeEth(token.address)) {
      el.textContent = text;
    } else {
      const coinGeckoId = COINGECKO_ID_MAP[token.address.toLowerCase()];
      if (coinGeckoId) {
        const link = document.createElement("a");
        link.href = "https://www.coingecko.com/en/coins/" + coinGeckoId;
        link.target = "_blank";
        link.textContent = text;
        el.appendChild(link);
      } else {
        el.textContent = text;
      }
      el.appendChild(createCopyButton(token.address));
    }

    if (original !== null && original !== undefined && BigInt(original) > amount) {
      const hint = document.createElement("span");
      hint.className = "partial-progress";
      hint.textContent = "of " + formatAmount(original, decimals) + " left";
      el.appendChild(hint);
    }
  }

  /**
   * Opens the order detail modal for a specific order.
   * @param {Object} order - Order object with all metadata
   */
  function openOrderModal(order) {
    const modal = $("#order-modal");

    // Trade ID
    $("#order-modal-id").textContent = order.orderId;

    // Status
    const statusEl = $("#order-modal-status");
    statusEl.textContent = "";
    const statusSpan = document.createElement("span");
    statusSpan.className = "order-modal-status";
    if (order.active) {
      statusSpan.textContent = "Open";
      statusSpan.classList.add("status-open");
    } else if (order.taker) {
      statusSpan.textContent = "Filled";
      statusSpan.classList.add("status-filled");
    } else {
      statusSpan.textContent = "Cancelled";
      statusSpan.classList.add("status-cancelled");
    }
    statusEl.appendChild(statusSpan);

    // Created date
    const dateEl = $("#order-modal-date");
    if (order.createdAt) {
      const date = new Date(parseInt(order.createdAt) * 1000);
      dateEl.textContent = date.toLocaleString() + " (" + formatTimeAgo(order.createdAt) + ")";
    } else {
      dateEl.textContent = "--";
    }

    // Maker
    const makerEl = $("#order-modal-maker");
    makerEl.textContent = "";
    const makerLink = document.createElement("a");
    makerLink.href = "https://etherscan.io/address/" + order.maker;
    makerLink.target = "_blank";
    makerLink.rel = "noopener noreferrer";
    const ensName = getCachedEns(order.maker);
    makerLink.textContent = ensName || truncateAddress(order.maker);
    makerLink.title = order.maker;
    makerEl.appendChild(makerLink);
    makerEl.appendChild(createCopyButton(order.maker));

    // Offered
    const offeredEl = $("#order-modal-offered");
    const tokenADecimals = order.tokenA.decimals || 18;
    const amountA = BigInt(order.amountA);
    fillOrderModalAmount(offeredEl, order.tokenA, amountA, order.originalAmountA);

    // Wanted
    const wantedEl = $("#order-modal-wanted");
    const tokenBDecimals = order.tokenB.decimals || 18;
    const amountB = BigInt(order.amountB);
    fillOrderModalAmount(wantedEl, order.tokenB, amountB, order.originalAmountB);

    // USD Value
    const usdEl = $("#order-modal-usd");
    const tokenAPrice = getTokenPrice(order.tokenA.address);
    if (tokenAPrice !== null && amountA > 0n) {
      const humanAmountA = Number(amountA) / Math.pow(10, tokenADecimals);
      usdEl.textContent = formatUsd(humanAmountA * tokenAPrice);
    } else {
      usdEl.textContent = "$ --";
    }

    // Price (both directions)
    const priceEl = $("#order-modal-price");
    if (amountA > 0n && amountB > 0n) {
      const humanA = Number(amountA) / Math.pow(10, tokenADecimals);
      const humanB = Number(amountB) / Math.pow(10, tokenBDecimals);
      const priceAPerB = humanA / humanB;
      const priceBPerA = humanB / humanA;
      priceEl.textContent = "";
      priceEl.appendChild(
        document.createTextNode(
          "1 " + order.tokenB.symbol + " = " + priceAPerB.toFixed(6) + " " + order.tokenA.symbol
        )
      );
      priceEl.appendChild(document.createElement("br"));
      priceEl.appendChild(
        document.createTextNode(
          "1 " + order.tokenA.symbol + " = " + priceBPerA.toFixed(6) + " " + order.tokenB.symbol
        )
      );
    } else {
      priceEl.textContent = "--";
    }

    // Market rate comparison
    const marketRow = $("#order-modal-market-row");
    const marketEl = $("#order-modal-market");
    if (CONFIG.SHOW_MARKET_DEVIATION) {
      const marketDev = calculateMarketDeviation(order);
      if (marketDev) {
        marketRow.style.display = "flex";
        marketEl.textContent = "";
        const devSpan = document.createElement("span");
        devSpan.className = "market-deviation";
        if (marketDev.deviation < -1) {
          devSpan.classList.add("good-deal");
        } else if (marketDev.deviation > 5) {
          devSpan.classList.add("bad-deal");
        }
        devSpan.textContent = marketDev.label;
        marketEl.appendChild(devSpan);
      } else {
        marketRow.style.display = "none";
      }
    } else {
      marketRow.style.display = "none";
    }

    // Taker (only if filled)
    const takerRow = $("#order-modal-taker-row");
    const takerEl = $("#order-modal-taker");
    if (order.taker) {
      takerRow.style.display = "flex";
      takerEl.textContent = "";
      const takerLink = document.createElement("a");
      takerLink.href = "https://etherscan.io/address/" + order.taker;
      takerLink.target = "_blank";
      takerLink.rel = "noopener noreferrer";
      const takerEns = getCachedEns(order.taker);
      takerLink.textContent = takerEns || truncateAddress(order.taker);
      takerLink.title = order.taker;
      takerEl.appendChild(takerLink);
      takerEl.appendChild(createCopyButton(order.taker));
    } else {
      takerRow.style.display = "none";
    }

    // Share link
    const linkEl = $("#order-modal-link");
    linkEl.textContent = "";
    const linkInput = document.createElement("input");
    linkInput.type = "text";
    linkInput.className = "order-modal-link-input";
    linkInput.value = getOrderShareUrl(order.orderId);
    linkInput.readOnly = true;
    linkInput.addEventListener("click", () => linkInput.select());
    linkEl.appendChild(linkInput);
    linkEl.appendChild(createCopyButton(getOrderShareUrl(order.orderId)));

    // Actions
    const actionsEl = $("#order-modal-actions");
    actionsEl.textContent = "";

    if (order.active) {
      const isOwnOrder = userAddress && order.maker.toLowerCase() === userAddress.toLowerCase();
      if (isOwnOrder) {
        const cancelBtn = document.createElement("button");
        cancelBtn.textContent = "Cancel Order";
        cancelBtn.style.background = "#c00";
        cancelBtn.addEventListener("click", async () => {
          modal.classList.add("hidden");
          handleCancelOrder(order);
        });
        actionsEl.appendChild(cancelBtn);
      } else {
        const fillBtn = document.createElement("button");
        fillBtn.textContent = "Fill Order";
        fillBtn.addEventListener("click", async () => {
          modal.classList.add("hidden");
          if (!userAddress) {
            await connectWallet();
          }
          if (userAddress) {
            handleFillOrder(order);
          }
        });
        actionsEl.appendChild(fillBtn);
      }
    }

    // Watch/Unwatch button
    const watchBtn = document.createElement("button");
    const isWatched = isOrderWatched(order.orderId);
    watchBtn.textContent = isWatched ? "Unwatch" : "Watch";
    watchBtn.title = isWatched
      ? "Stop watching this order"
      : "Get notified when this order is filled or cancelled";
    watchBtn.style.background = isWatched ? "#666" : "#333";
    watchBtn.addEventListener("click", () => {
      if (isOrderWatched(order.orderId)) {
        unwatchOrder(order.orderId);
        watchBtn.textContent = "Watch";
        watchBtn.style.background = "#333";
        watchBtn.title = "Get notified when this order is filled or cancelled";
        showToast("Stopped watching order #" + order.orderId, "success");
      } else {
        watchOrder(order);
        watchBtn.textContent = "Unwatch";
        watchBtn.style.background = "#666";
        watchBtn.title = "Stop watching this order";
        showToast("Watching order #" + order.orderId, "success");
      }
    });
    actionsEl.appendChild(watchBtn);

    const closeBtn = document.createElement("button");
    closeBtn.textContent = "Close";
    closeBtn.style.background = "#fff";
    closeBtn.style.color = "#000";
    closeBtn.style.border = "1px solid #000";
    closeBtn.addEventListener("click", () => {
      modal.classList.add("hidden");
      // Clear hash when closing manually
      if (window.location.hash) {
        history.pushState("", document.title, window.location.pathname + window.location.search);
      }
    });
    actionsEl.appendChild(closeBtn);

    // Update URL hash
    window.location.hash = "order-" + order.orderId;

    modal.classList.remove("hidden");
  }

  // ============================================================================
  // Token Information
  // ============================================================================

  async function retryRpc(fn, attempts = 3, baseDelayMs = 200) {
    let lastErr;
    for (let i = 0; i < attempts; i++) {
      try {
        return await fn();
      } catch (e) {
        lastErr = e;
        if (i < attempts - 1) {
          await new Promise((r) => setTimeout(r, baseDelayMs * (i + 1)));
        }
      }
    }
    throw lastErr;
  }

  /**
   * Fetches ERC20 token metadata from the blockchain.
   * Successful results are cached to avoid redundant RPC calls.
   * Returns `decimals: null` when the on-chain value cannot be determined;
   * callers must treat that as a hard failure rather than substituting a default.
   * @param {string} address - Token contract address
   * @returns {Promise<{address: string, symbol: string, name: string, decimals: number|null}>}
   */
  async function fetchTokenInfo(address) {
    // Native ETH has no contract to read from.
    if (isNativeEth(address)) {
      return { address: NATIVE_ETH, symbol: "ETH", name: "Ether", decimals: 18 };
    }

    const lowerAddr = address.toLowerCase();
    if (tokenCache.has(lowerAddr)) {
      return tokenCache.get(lowerAddr);
    }
    try {
      const tokenContract = new ethers.Contract(address, ERC20_ABI, provider);
      const [symbol, name, decimals] = await Promise.all([
        retryRpc(() => tokenContract.symbol()).catch(() => "???"),
        retryRpc(() => tokenContract.name()).catch(() => "Unknown"),
        retryRpc(() => tokenContract.decimals()),
      ]);
      const safeSymbol = String(symbol).slice(0, 20);
      const safeName = String(name).slice(0, 100);
      const decimalsNum = Number(decimals);
      const safeDecimals =
        Number.isInteger(decimalsNum) && decimalsNum >= 0 && decimalsNum <= 77 ? decimalsNum : null;
      const info = { address, symbol: safeSymbol, name: safeName, decimals: safeDecimals };
      if (safeDecimals !== null) {
        tokenCache.set(lowerAddr, info);
      }
      return info;
    } catch (e) {
      return { address, symbol: "???", name: "Unknown", decimals: null };
    }
  }

  // ============================================================================
  // Subgraph Queries
  // ============================================================================

  /**
   * Executes a GraphQL query against The Graph subgraph.
   * @param {string} query - GraphQL query string
   * @param {Object} variables - Query variables
   * @returns {Promise<Object|null>} Query data or null on error
   */
  async function querySubgraph(query, variables = {}, silent = false) {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), CONFIG.REQUEST_TIMEOUT);
    try {
      const res = await fetch(CONFIG.SUBGRAPH_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ query, variables }),
        signal: controller.signal,
      });
      clearTimeout(timeoutId);
      if (!res.ok) {
        console.error("Subgraph HTTP error:", res.status);
        if (!silent) showToast("Failed to fetch data. Please try again.", "error");
        return null;
      }
      const json = await res.json();
      if (json.errors) {
        console.error("Subgraph error:", json.errors);
        if (!silent) showToast("Error loading data.", "error");
        return null;
      }
      return json.data;
    } catch (e) {
      clearTimeout(timeoutId);
      if (e.name === "AbortError") {
        if (!silent) showToast("Request timed out. Please try again.", "error");
      } else {
        console.error("Subgraph fetch error:", e);
        if (!silent) showToast("Network error. Check your connection.", "error");
      }
      return null;
    }
  }

  /**
   * Polls the subgraph until an order reaches an expected state.
   *
   * Indexing lags the chain by a few seconds, so reloading straight after a
   * confirmed transaction would show the pre-transaction row. Only reachable
   * in v1 mode (CAPS.subgraphPolling); nothing indexes v2 yet.
   *
   * @param {string} orderId - Order to watch
   * @param {boolean} expectedActive - Active flag to wait for
   * @param {number} [maxAttempts=10] - Polls before giving up
   * @param {number} [interval=1500] - Milliseconds between polls
   * @returns {Promise<boolean>} True if the state was observed
   */
  async function waitForOrderUpdate(orderId, expectedActive, maxAttempts = 10, interval = 1500) {
    for (let i = 0; i < maxAttempts; i++) {
      // Silent: transient errors while polling are expected and must not
      // raise a toast on every attempt.
      const data = await querySubgraph(
        `
        query {
          order(id: "${orderId}") {
            active
          }
        }
      `,
        {},
        true
      );
      if (data && data.order && data.order.active === expectedActive) {
        return true;
      }
      await new Promise((resolve) => setTimeout(resolve, interval));
    }
    return false;
  }

  async function loadStats() {
    const [statsData, tokenData] = await Promise.all([
      querySubgraph(`
        query {
          globalStats(id: "global") {
            totalOrders
            activeOrders
            filledOrders
            cancelledOrders
          }
        }
      `),
      querySubgraph(`
        query {
          tokens(first: 100) {
            address
            decimals
            volumeSold
          }
        }
      `),
    ]);

    if (statsData && statsData.globalStats) {
      const s = statsData.globalStats;
      $("#stat-total").textContent = formatNumber(s.totalOrders || "0");
      $("#stat-active").textContent = formatNumber(s.activeOrders || "0");
      $("#stat-filled").textContent = formatNumber(s.filledOrders || "0");
      $("#stat-cancelled").textContent = formatNumber(s.cancelledOrders || "0");
    }

    if (tokenData && tokenData.tokens && tokenData.tokens.length > 0) {
      const addresses = tokenData.tokens
        .map((t) => t.address.toLowerCase())
        .filter((addr) => COINGECKO_ID_MAP[addr]);
      const coinGeckoIds = addresses.map((addr) => COINGECKO_ID_MAP[addr]);
      if (coinGeckoIds.length > 0) {
        await fetchPrices(coinGeckoIds);
      }

      let totalUsd = 0;
      let hasPrice = false;
      for (const token of tokenData.tokens) {
        const price = getTokenPrice(token.address);
        if (price === null) continue;
        hasPrice = true;
        const volume = Number(BigInt(token.volumeSold)) / Math.pow(10, token.decimals);
        totalUsd += volume * price;
      }

      $("#stat-volume").textContent = hasPrice ? "$" + formatNumber(Math.round(totalUsd)) : "N/A";
    } else {
      $("#stat-volume").textContent = "N/A";
    }
  }

  async function loadPopularPairs() {
    const data = await querySubgraph(`
      query {
        pairStats_collection(first: 10, orderBy: tradeCount, orderDirection: desc) {
          tokenA {
            address
            symbol
          }
          tokenB {
            address
            symbol
          }
        }
      }
    `);

    const pairsList = $("#pairs-list");
    if (data && data.pairStats_collection && data.pairStats_collection.length > 0) {
      pairsList.textContent = "";
      data.pairStats_collection.forEach((p, i) => {
        if (i > 0) pairsList.appendChild(document.createTextNode(" "));
        const link = document.createElement("a");
        link.href = "#";
        link.className = "pair-link";
        link.dataset.tokenA = p.tokenA.address;
        link.dataset.tokenB = p.tokenB.address;
        link.textContent = "[" + p.tokenA.symbol + "/" + p.tokenB.symbol + "]";
        pairsList.appendChild(link);
      });

      // Attach click handlers to pair links
      pairsList.querySelectorAll(".pair-link").forEach((link) => {
        link.addEventListener("click", (e) => {
          e.preventDefault();
          const tokenA = link.dataset.tokenA;
          const tokenB = link.dataset.tokenB;
          $("#filter-selling").value = tokenA;
          $("#filter-wanting").value = tokenB;
          currentFilters.selling = tokenA;
          currentFilters.wanting = tokenB;
          currentPage = 1;
          loadOrders();
        });
      });
    } else {
      pairsList.textContent = "No popular pairs yet";
    }
  }

  async function loadTokenFilters() {
    const data = await querySubgraph(`
      query {
        tokens(first: 50, orderBy: volumeSold, orderDirection: desc) {
          address
          symbol
        }
      }
    `);

    if (data && data.tokens) {
      const sellingSelect = $("#filter-selling");
      const wantingSelect = $("#filter-wanting");

      // Clear existing options except "All"
      sellingSelect.textContent = "";
      const sellingDefault = document.createElement("option");
      sellingDefault.value = "";
      sellingDefault.textContent = "All";
      sellingSelect.appendChild(sellingDefault);
      wantingSelect.textContent = "";
      const wantingDefault = document.createElement("option");
      wantingDefault.value = "";
      wantingDefault.textContent = "All";
      wantingSelect.appendChild(wantingDefault);

      data.tokens.forEach((token) => {
        const option1 = document.createElement("option");
        option1.value = token.address;
        option1.textContent = token.symbol;
        sellingSelect.appendChild(option1);

        const option2 = document.createElement("option");
        option2.value = token.address;
        option2.textContent = token.symbol;
        wantingSelect.appendChild(option2);
      });

      // Restore saved filter selections
      if (currentFilters.selling) {
        sellingSelect.value = currentFilters.selling;
      }
      if (currentFilters.wanting) {
        wantingSelect.value = currentFilters.wanting;
      }
    }
  }

  async function loadOrders(silent = false) {
    // Show skeleton loading state (skip for silent auto-refresh)
    if (!silent) {
      renderSkeletonRows(CONFIG.PAGE_SIZE);
    }

    const skip = (currentPage - 1) * CONFIG.PAGE_SIZE;
    const conditions = [];

    if (currentFilters.status === "open") {
      conditions.push("active: true");
    } else if (currentFilters.status === "filled") {
      conditions.push("active: false, taker_not: null");
    } else if (currentFilters.status === "cancelled") {
      conditions.push("active: false, taker: null");
    }
    // "watched" and "all" have no status condition - handled client-side

    if (currentFilters.selling && isValidAddress(currentFilters.selling)) {
      conditions.push(`tokenA_: { address: "${currentFilters.selling.toLowerCase()}" }`);
    }
    if (currentFilters.wanting && isValidAddress(currentFilters.wanting)) {
      conditions.push(`tokenB_: { address: "${currentFilters.wanting.toLowerCase()}" }`);
    }
    if (currentFilters.myOrders && userAddress) {
      conditions.push(`maker: "${userAddress.toLowerCase()}"`);
    }

    const where = conditions.length > 0 ? `where: { ${conditions.join(", ")} }` : "";

    // The v1 subgraph has no partialFill/originalAmount fields, and GraphQL
    // rejects the whole query on a single unknown field — asking for the v2
    // shape in v1 mode returns nothing at all, not a partial result.
    const orderFields = orderQueryFields(ACTIVE_VERSION).join("\n          ");

    const data = await querySubgraph(`
      query {
        orders(first: ${CONFIG.PAGE_SIZE}, skip: ${skip}, orderBy: orderId, orderDirection: desc, ${where}) {
          ${orderFields}
          tokenA {
            address
            symbol
            decimals
          }
          tokenB {
            address
            symbol
            decimals
          }
        }
      }
    `);

    if (!data || !data.orders) {
      cachedOrders = [];
      // "No orders found" would be a lie when the query never came back —
      // and in v2 against the live subgraph it never can, because no deployed
      // subgraph indexes v2 yet. renderOrders says which of the two it is.
      ordersQueryFailed = true;
    } else {
      ordersQueryFailed = false;
      cachedOrders = data.orders;
      for (const o of cachedOrders) {
        // Display WETH as ETH. Native-ETH orders already carry the ETH symbol;
        // they keep no address, which is how the two stay distinguishable.
        if (isWeth(o.tokenA.address)) o.tokenA.symbol = "ETH";
        if (isWeth(o.tokenB.address)) o.tokenB.symbol = "ETH";
        // Backfills the fields the v1 subgraph never returns, so rendering and
        // fill math stay on one code path in both versions.
        normalizeOrder(o, ACTIVE_VERSION);
      }
    }

    // A background auto-refresh keeps the selection (only stale IDs are
    // dropped); any deliberate reload — filter, page, wallet, post-transaction
    // — resets it, since the user is looking at a different set of orders.
    if (silent) {
      pruneSelection();
    } else {
      clearSelection(false);
    }

    // Check watched orders for status changes
    checkWatchedOrders(cachedOrders);

    // Filter to only watched orders if that filter is active
    if (currentFilters.status === "watched") {
      const watched = getWatchedOrders();
      cachedOrders = cachedOrders.filter((o) => o.orderId in watched);
    }

    // Batch fetch prices for all tokenA and tokenB addresses
    if (cachedOrders.length > 0) {
      const tokenAddressesA = cachedOrders.map((o) => o.tokenA.address.toLowerCase());
      const tokenAddressesB = cachedOrders.map((o) => o.tokenB.address.toLowerCase());
      const allTokenAddresses = [...new Set([...tokenAddressesA, ...tokenAddressesB])];
      const coinGeckoIds = allTokenAddresses.map((addr) => COINGECKO_ID_MAP[addr]).filter(Boolean);

      if (coinGeckoIds.length > 0) {
        await fetchPrices(coinGeckoIds);
      }

      // Batch resolve ENS names for all maker addresses
      const makerAddresses = [...new Set(cachedOrders.map((o) => o.maker))];
      batchResolveEns(makerAddresses).then(() => {
        // Re-render to show ENS names once resolved
        renderOrders();
      });
    }

    renderOrders();
    updateSortIndicators();

    // Open modal if there's a highlighted order ID from URL hash
    if (highlightedOrderId) {
      const order = findOrderById(highlightedOrderId);
      if (order) {
        openOrderModal(order);
      }
      highlightedOrderId = null; // Clear after opening
    }
  }

  /**
   * Finds an order by ID from cached orders.
   * @param {string} orderId - Order ID to find
   * @returns {Object|null} Order object or null
   */
  function findOrderById(orderId) {
    return cachedOrders.find((o) => o.orderId === orderId) || null;
  }

  // ============================================================================
  // Selection (multi-select)
  // ============================================================================

  /**
   * Returns the selected orders, in display order.
   * @returns {Object[]}
   */
  function getSelectedOrders() {
    return sortOrders(cachedOrders).filter((o) => selectedOrderIds.has(o.orderId));
  }

  /**
   * The order that anchors the selection rules — the first one still selected,
   * in display order. Every other order must be compatible with it.
   * @returns {Object|null}
   */
  function getSelectionAnchor() {
    return getSelectedOrders()[0] || null;
  }

  /**
   * Empties the selection and refreshes the table.
   * @param {boolean} [rerender=true] - Whether to re-render rows
   */
  function clearSelection(rerender = true) {
    if (selectedOrderIds.size === 0 && !selectionAnchorId) return;
    selectedOrderIds.clear();
    selectionAnchorId = null;
    if (rerender) renderOrders();
  }

  /**
   * Drops selected IDs that are no longer on screen (page change, refresh,
   * filter change) so the selection never references invisible orders.
   */
  function pruneSelection() {
    const visible = new Set(cachedOrders.map((o) => o.orderId));
    for (const id of [...selectedOrderIds]) {
      if (!visible.has(id)) selectedOrderIds.delete(id);
    }
    if (selectionAnchorId && !visible.has(selectionAnchorId)) {
      selectionAnchorId = null;
    }
  }

  /**
   * Handles a checkbox click, including shift-click range selection.
   * @param {Object} order - Order whose row was clicked
   * @param {boolean} shiftKey - Whether shift was held
   */
  function toggleOrderSelection(order, shiftKey) {
    const sorted = sortOrders(cachedOrders);

    if (shiftKey && selectionAnchorId && selectionAnchorId !== order.orderId) {
      const ids = getShiftRangeIds(
        sorted,
        selectionAnchorId,
        order.orderId,
        getSelectionAnchor(),
        userAddress
      );
      for (const id of ids) selectedOrderIds.add(id);
    } else if (selectedOrderIds.has(order.orderId)) {
      selectedOrderIds.delete(order.orderId);
      if (selectionAnchorId === order.orderId) selectionAnchorId = null;
    } else {
      selectedOrderIds.add(order.orderId);
      selectionAnchorId = order.orderId;
    }

    renderOrders();
  }

  /**
   * Selects every open order the connected wallet made on this page,
   * surfacing [Cancel All]. Only reachable from the My Orders filter.
   */
  function selectAllOwnOrders() {
    if (!userAddress) return;

    selectedOrderIds.clear();
    for (const order of sortOrders(cachedOrders)) {
      if (order.active && resolveSelectionMode(order, userAddress) === "own") {
        selectedOrderIds.add(order.orderId);
      }
    }
    selectionAnchorId = null;
    renderOrders();
  }

  /**
   * Syncs the selection bar to the current selection.
   *
   * Shown from one order onward rather than two: ticking a single box and
   * seeing nothing appear reads as broken, and both batch actions work fine
   * with a single order.
   */
  function renderSelectionBar() {
    const bar = $("#selection-bar");

    // Without batch entry points there is nothing to select for, so the bar
    // stays down regardless of what is in selectedOrderIds.
    if (!CAPS.batch) {
      bar.classList.add("hidden");
      return;
    }

    const selectAllBtn = $("#select-all-orders");
    const fillBtn = $("#batch-fill-btn");
    const cancelBtn = $("#batch-cancel-btn");

    // [Select All] belongs to the My Orders view, where Cancel All is the point.
    selectAllBtn.classList.toggle("hidden", !(currentFilters.myOrders && userAddress));

    const count = selectedOrderIds.size;
    if (count === 0) {
      bar.classList.toggle("hidden", !(currentFilters.myOrders && userAddress));
      $("#selection-count").textContent = "0 selected";
      fillBtn.classList.add("hidden");
      cancelBtn.classList.add("hidden");
      return;
    }

    bar.classList.remove("hidden");
    $("#selection-count").textContent = count + (count === 1 ? " order" : " orders") + " selected";

    const isOwn = resolveSelectionMode(getSelectionAnchor(), userAddress) === "own";
    fillBtn.classList.toggle("hidden", isOwn);
    cancelBtn.classList.toggle("hidden", !isOwn);
  }

  /**
   * Builds a token cell for the order table.
   *
   * Native ETH has no contract, so it renders as bare text with no CoinGecko
   * link, copy button, or address tooltip. That absence is also what tells a
   * native-ETH order apart from a WETH order, which still shows its address.
   *
   * @param {Object} token - Token with {address, symbol}
   * @param {string} label - Mobile card label
   * @returns {HTMLTableCellElement}
   */
  function buildTokenCell(token, label) {
    const td = document.createElement("td");
    td.dataset.label = label;

    if (isNativeEth(token.address)) {
      const span = document.createElement("span");
      span.textContent = token.symbol;
      span.title = "Native ETH";
      td.appendChild(span);
      return td;
    }

    const wrap = document.createElement("span");
    wrap.style.whiteSpace = "nowrap";

    const coinGeckoId = COINGECKO_ID_MAP[token.address.toLowerCase()];
    if (coinGeckoId) {
      const link = document.createElement("a");
      link.href = "https://www.coingecko.com/en/coins/" + coinGeckoId;
      link.target = "_blank";
      link.rel = "noopener noreferrer";
      link.textContent = token.symbol;
      wrap.appendChild(link);
    } else {
      const span = document.createElement("span");
      span.textContent = token.symbol;
      wrap.appendChild(span);
    }

    wrap.appendChild(createCopyButton(token.address));
    td.appendChild(wrap);
    td.title = token.address;
    return td;
  }

  /**
   * Builds an amount cell for the order table.
   *
   * v2 amounts are what is *left* to fill, so a partially filled order also
   * shows what it started at.
   *
   * @param {string} remaining - Remaining amount in base units
   * @param {string|undefined} original - Original amount in base units
   * @param {number} decimals - Token decimals
   * @param {string} label - Mobile card label
   * @returns {HTMLTableCellElement}
   */
  function buildAmountCell(remaining, original, decimals, label) {
    const td = document.createElement("td");
    td.dataset.label = label;
    td.appendChild(document.createTextNode(formatAmount(remaining, decimals)));

    if (original !== null && original !== undefined && BigInt(original) > BigInt(remaining)) {
      const hint = document.createElement("span");
      hint.className = "partial-progress";
      hint.textContent = "of " + formatAmount(original, decimals) + " left";
      hint.title = "Partially filled";
      td.appendChild(hint);
    }

    return td;
  }

  function renderOrders() {
    const tbody = $("#order-table");
    tbody.textContent = "";

    if (cachedOrders.length === 0) {
      const tr = document.createElement("tr");
      const td = document.createElement("td");
      td.colSpan = orderColumnCount();
      if (!ordersQueryFailed) {
        td.textContent = "No orders found";
      } else if (!CAPS.live) {
        // The usual reason a v2 query fails: it asks for fields no deployed
        // subgraph has. Say so, rather than implying the board is empty.
        td.textContent =
          "Swapboard v2 is not deployed yet, so there are no orders to index. " +
          "Switch to v1 for live orders, or add ?mock=true to preview v2 with simulated data.";
      } else {
        td.textContent = "Could not load orders. Check your connection and try again.";
      }
      tr.appendChild(td);
      tbody.appendChild(tr);
      updatePagination(0);
      renderSelectionBar();
      return;
    }

    const sortedOrders = sortOrders(cachedOrders);
    const selectionAnchor = getSelectionAnchor();

    for (const order of sortedOrders) {
      const tr = document.createElement("tr");
      const isMaker = userAddress && order.maker.toLowerCase() === userAddress.toLowerCase();

      if (isMaker) {
        tr.classList.add("own-order");
      }

      const tokenADecimals = order.tokenA.decimals;
      const tokenBDecimals = order.tokenB.decimals;
      const amountA = BigInt(order.amountA);
      const amountB = BigInt(order.amountB);

      // Price: calculate both directions for toggle.
      // priceNormal is the side shown by default; priceInverted is shown after click.
      // Default to tokenB/tokenA, but flip when one side is a stable or ETH so the
      // quote currency follows trading conventions ($ for stables, ETH for non-stable
      // ERC20s paired with ETH).
      let priceNormal = "N/A";
      let priceInverted = "N/A";
      if (amountA > 0n && amountB > 0n) {
        const priceBPerA =
          (Number(amountB) / Number(amountA)) * Math.pow(10, tokenADecimals - tokenBDecimals);
        const priceAPerB =
          (Number(amountA) / Number(amountB)) * Math.pow(10, tokenBDecimals - tokenADecimals);
        const bQuoted = isStable(order.tokenB.address)
          ? formatUsd(priceBPerA) + " / " + escapeHtml(order.tokenA.symbol)
          : formatRatio(priceBPerA) +
            " " +
            escapeHtml(order.tokenB.symbol) +
            "/" +
            escapeHtml(order.tokenA.symbol);
        const aQuoted = isStable(order.tokenA.address)
          ? formatUsd(priceAPerB) + " / " + escapeHtml(order.tokenB.symbol)
          : formatRatio(priceAPerB) +
            " " +
            escapeHtml(order.tokenA.symbol) +
            "/" +
            escapeHtml(order.tokenB.symbol);
        const quoteSide = preferredQuoteSide(order.tokenA.address, order.tokenB.address);
        if (quoteSide === "A") {
          priceNormal = aQuoted;
          priceInverted = bQuoted;
        } else {
          priceNormal = bQuoted;
          priceInverted = aQuoted;
        }
      }

      // Calculate USD value of sell side
      const tokenAPrice = getTokenPrice(order.tokenA.address);
      let usdVal = "$ --";
      if (tokenAPrice !== null && amountA > 0n) {
        const humanAmountA = Number(amountA) / Math.pow(10, tokenADecimals);
        usdVal = formatUsd(humanAmountA * tokenAPrice);
      }

      // Build row with links
      // Column 0: Selection checkbox. Disabled when the order can't join the
      // current selection (closed, or it would mix own/other orders or pairs).
      // Omitted entirely without batch entry points to select orders *for*.
      if (CAPS.batch) {
        const tdSelect = document.createElement("td");
        tdSelect.className = "select-col";
        tdSelect.dataset.label = "";
        const selectBox = document.createElement("input");
        selectBox.type = "checkbox";
        selectBox.checked = selectedOrderIds.has(order.orderId);
        selectBox.disabled =
          !selectBox.checked && !canSelectOrder(order, selectionAnchor, userAddress);
        selectBox.title = selectBox.disabled
          ? "Can't mix your own orders with other makers' orders, or different pairs when filling"
          : "Select order #" + order.orderId;
        // Suppress the browser's shift-click text selection across rows.
        selectBox.addEventListener("mousedown", (e) => {
          if (e.shiftKey) e.preventDefault();
        });
        selectBox.addEventListener("click", (e) => {
          e.stopPropagation();
          toggleOrderSelection(order, e.shiftKey);
        });
        tdSelect.appendChild(selectBox);
        tr.appendChild(tdSelect);
      }

      // Column 1: Action button (Fill for others, Cancel for own) or status
      const tdAction = document.createElement("td");
      tdAction.dataset.label = "";
      if (order.active) {
        if (isMaker) {
          const cancelBtn = document.createElement("a");
          cancelBtn.href = "#";
          cancelBtn.textContent = "[Cancel]";
          cancelBtn.classList.add("cancel-btn");
          cancelBtn.addEventListener("click", async (e) => {
            e.preventDefault();
            e.stopPropagation();
            handleCancelOrder(order);
          });
          tdAction.appendChild(cancelBtn);
        } else {
          const fillBtn = document.createElement("a");
          fillBtn.href = "#";
          fillBtn.textContent = "[Fill]";
          fillBtn.classList.add("buy-btn");
          fillBtn.addEventListener("click", async (e) => {
            e.preventDefault();
            e.stopPropagation();
            if (!userAddress) {
              await connectWallet();
            }
            if (userAddress) {
              handleFillOrder(order);
            }
          });
          tdAction.appendChild(fillBtn);
        }
      } else {
        const statusSpan = document.createElement("span");
        if (order.taker) {
          statusSpan.textContent = "[FILLED]";
          statusSpan.classList.add("status-filled-label");
        } else {
          statusSpan.textContent = "[CANCELED]";
          statusSpan.classList.add("status-canceled-label");
        }
        tdAction.appendChild(statusSpan);
        if (order.taker && order.filledAt) {
          const filledDateSpan = document.createElement("span");
          filledDateSpan.className = "order-age";
          filledDateSpan.textContent = formatTimeAgo(parseInt(order.filledAt));
          filledDateSpan.title = new Date(parseInt(order.filledAt) * 1000).toLocaleString();
          tdAction.appendChild(filledDateSpan);
        }
      }
      tr.appendChild(tdAction);

      // Column 2: Trade ID (clickable to open detail modal)
      const tdId = document.createElement("td");
      tdId.dataset.label = "Trade ID";
      const idLink = document.createElement("a");
      idLink.href = "#order-" + order.orderId;
      idLink.textContent = order.orderId;
      idLink.classList.add("trade-id-link");
      idLink.addEventListener("click", (e) => {
        e.preventDefault();
        openOrderModal(order);
      });
      tdId.appendChild(idLink);
      tr.appendChild(tdId);

      // Highlight if this is the linked order
      if (highlightedOrderId === order.orderId) {
        tr.classList.add("highlighted-order");
        tr.id = "order-" + order.orderId;
      }

      // Column 3: Maker (link to Etherscan + copy, show ENS if available)
      const tdSeller = document.createElement("td");
      tdSeller.dataset.label = "Maker";
      const sellerWrap = document.createElement("span");
      sellerWrap.style.whiteSpace = "nowrap";
      const sellerLink = document.createElement("a");
      sellerLink.href = "https://etherscan.io/address/" + order.maker;
      sellerLink.target = "_blank";
      sellerLink.rel = "noopener noreferrer";
      const ensName = getCachedEns(order.maker);
      sellerLink.textContent = ensName || truncateAddress(order.maker);
      sellerLink.title = order.maker;
      sellerWrap.appendChild(sellerLink);
      sellerWrap.appendChild(createCopyButton(order.maker));
      tdSeller.appendChild(sellerWrap);
      tr.appendChild(tdSeller);

      // Column 4: Offered Token (link to CoinGecko + copy; bare text for ETH)
      tr.appendChild(buildTokenCell(order.tokenA, "Offered"));

      // Column 5: Offered Size (remaining, for v2 partial fills)
      tr.appendChild(
        buildAmountCell(order.amountA, order.originalAmountA, tokenADecimals, "Offered Size")
      );

      // Column 6: Wanted Token (link to CoinGecko + copy; bare text for ETH)
      tr.appendChild(buildTokenCell(order.tokenB, "Wanted"));

      // Column 7: Wanted Size (remaining, for v2 partial fills)
      tr.appendChild(
        buildAmountCell(order.amountB, order.originalAmountB, tokenBDecimals, "Wanted Size")
      );

      // Column 8: USD Val (nowrap to keep $ and value on same line)
      const tdUsd = document.createElement("td");
      tdUsd.dataset.label = "USD Val";
      tdUsd.textContent = usdVal;
      tdUsd.style.whiteSpace = "nowrap";
      tr.appendChild(tdUsd);

      // Column 9: Price (clickable to invert ratio) + market deviation
      const tdPrice = document.createElement("td");
      tdPrice.dataset.label = "Price";
      const priceSpan = document.createElement("span");
      priceSpan.textContent = priceNormal;
      tdPrice.appendChild(priceSpan);

      // Add market deviation indicator
      if (CONFIG.SHOW_MARKET_DEVIATION) {
        const marketDev = calculateMarketDeviation(order);
        if (marketDev) {
          const devSpan = document.createElement("span");
          devSpan.className = "market-deviation";
          if (marketDev.deviation < -1) {
            devSpan.classList.add("good-deal");
          } else if (marketDev.deviation > 5) {
            devSpan.classList.add("bad-deal");
          }
          devSpan.textContent = " " + marketDev.label;
          devSpan.title = "Compared to market rate";
          tdPrice.appendChild(devSpan);
        }
      }

      if (priceNormal !== "N/A") {
        tdPrice.dataset.priceNormal = priceNormal;
        tdPrice.dataset.priceInverted = priceInverted;
        tdPrice.dataset.showingNormal = "true";
        tdPrice.classList.add("price-cell");
        tdPrice.title = "Click to invert ratio";
        tdPrice.addEventListener("click", function (e) {
          e.stopPropagation();
          const isNormal = this.dataset.showingNormal === "true";
          priceSpan.textContent = isNormal ? this.dataset.priceInverted : this.dataset.priceNormal;
          this.dataset.showingNormal = isNormal ? "false" : "true";
        });
      }
      tr.appendChild(tdPrice);

      tbody.appendChild(tr);
    }
    updatePagination(sortedOrders.length);
    renderSelectionBar();

    // Scroll to highlighted order if present
    if (highlightedOrderId) {
      const highlightedRow = document.getElementById("order-" + highlightedOrderId);
      if (highlightedRow) {
        setTimeout(() => {
          highlightedRow.scrollIntoView({ behavior: "smooth", block: "center" });
        }, 100);
      }
    }
  }

  function updatePagination(count) {
    $("#page-info").textContent = "Page " + currentPage;
    $("#prev-page").disabled = currentPage === 1;
    $("#next-page").disabled = count < CONFIG.PAGE_SIZE;
  }

  // ============================================================================
  // V2 CONNECTOR — DUMMY IMPLEMENTATION
  // ============================================================================
  //
  // !!! NONE OF THIS TALKS TO A CHAIN. !!!
  //
  // The Swapboard v2 contracts are not deployed. The v2 interface lives in the
  // unmerged PR #4 (ETHCF/swapboard, branch `z0r0z:partial`), which adds:
  //
  //   struct CreateOrderParams { address tokenA; uint256 amountA;
  //                              address tokenB; uint256 amountB; bool partialFill; }
  //
  //   createOrder(tokenA, amountA, tokenB, amountB, partialFill) -> uint256
  //   createOrders(CreateOrderParams[])                          -> uint256[]
  //   fillOrder(orderId, deadline, fillAmountB)
  //   fillOrders(orderIds[], deadline, fillAmountsB[])
  //   tryFillOrders(orderIds[], deadline, fillAmountsB[])        -> bool[]
  //   cancelOrders(orderIds[])
  //   cancelOrdersUnwrap(orderIds[])
  //
  // Every method below mirrors one of those signatures exactly, logs the
  // arguments it *would* submit, waits a beat, and resolves as if it succeeded.
  // Swapping in real `contract.<method>(...)` calls should therefore require no
  // changes above this layer.
  //
  // Because the stubs are inert, order rows do NOT change state after a
  // simulated fill or cancel — loadOrders() re-reads unchanged data.
  //
  // --- Native ETH ---------------------------------------------------------
  //
  // Native ETH is never routed through the ERC20 path. Anywhere the user
  // *sends* ETH, msg.value has to carry it, so v2 gets a dedicated payable
  // entry point and this connector calls it directly:
  //
  //   createOrderWithEth(tokenB, amountB, partialFill)            payable
  //   createOrdersWithEth(CreateOrderParams[])                    payable
  //   fillOrderWithEth(orderId, deadline)                         payable
  //   tryFillOrdersWithEth(orderIds[], deadline, fillAmountsB[])  payable -> bool[]
  //
  // Anywhere the user only *receives* ETH — filling or cancelling an order
  // that offers native ETH — no special call is needed: the contract already
  // escrows ETH and pays it straight out, so the plain method is correct.
  //
  // WETH is unrelated to any of this and keeps its own v1 wrap/unwrap
  // variants (fillOrderUnwrap, cancelOrderUnwrap).
  //
  // Two things went away with the v1 call sites and come back with the real
  // contracts, rather than being faked here:
  //   * gas estimates in the confirmation modal — these need a real ABI to
  //     encode against, and an invented number is worse than none.
  //   * waitForOrderUpdate() subgraph polling after a transaction — with inert
  //     stubs it would only ever time out.
  // ============================================================================

  /** Simulated per-transaction confirmation delay, in milliseconds. */
  const V2_SIM_DELAY_MS = 700;

  let v2TxCounter = 0;

  /**
   * Logs a stubbed contract call with its decoded arguments.
   * @param {string} method - Contract method name
   * @param {Object} args - Arguments that would be encoded
   */
  function logV2Call(method, args) {
    console.info("[V2-DUMMY] " + method, args);
  }

  /**
   * Produces a deterministic-looking fake transaction hash.
   * @returns {string} 0x-prefixed 64-character hex string
   */
  function fakeTxHash() {
    v2TxCounter += 1;
    return "0x" + v2TxCounter.toString(16).padStart(64, "0");
  }

  /**
   * Resolves a stubbed transaction after a simulated confirmation delay.
   * Shaped like an ethers TransactionResponse so call sites read normally.
   * @param {string} method - Contract method name (for logging)
   * @param {Object} args - Arguments that would be encoded
   * @param {*} [result] - Value to attach to the receipt
   * @returns {Promise<{hash: string, wait: function(): Promise<Object>}>}
   */
  async function v2Send(method, args, result) {
    logV2Call(method, args);
    const hash = fakeTxHash();
    return {
      hash,
      result,
      wait: async () => {
        await new Promise((resolve) => setTimeout(resolve, V2_SIM_DELAY_MS));
        logV2Call(method + " -> confirmed", { hash, result });
        return { hash, status: 1, logs: [], result };
      },
    };
  }

  /** Encodes a CreateOrderParams struct for logging. */
  function toCreateParams(p) {
    return {
      tokenA: p.tokenA,
      amountA: p.amountA.toString(),
      tokenB: p.tokenB,
      amountB: p.amountB.toString(),
      partialFill: p.partialFill,
    };
  }

  const V2 = {
    /** @see ISwapboard.createOrder — offered token is an ERC20 */
    createOrder(tokenA, amountA, tokenB, amountB, partialFill) {
      return v2Send("createOrder", {
        tokenA,
        amountA: amountA.toString(),
        tokenB,
        amountB: amountB.toString(),
        partialFill,
      });
    },

    /**
     * @see ISwapboard.createOrderWithEth
     * Offers native ETH: the offered amount rides in msg.value, so tokenA is
     * implicit and never passed.
     */
    createOrderWithEth(tokenB, amountB, partialFill, value) {
      return v2Send("createOrderWithEth", {
        tokenB,
        amountB: amountB.toString(),
        partialFill,
        value: value.toString(),
      });
    },

    /** @see ISwapboard.createOrders — every offered token is an ERC20 */
    createOrders(params) {
      return v2Send("createOrders", { params: params.map(toCreateParams) });
    },

    /**
     * @see ISwapboard.createOrdersWithEth
     * Every order in the batch offers native ETH; msg.value is their total.
     */
    createOrdersWithEth(params, value) {
      return v2Send("createOrdersWithEth", {
        params: params.map(toCreateParams),
        value: value.toString(),
      });
    },

    /** @see ISwapboard.fillOrder — fillAmountB of 0 means "fill the remainder" */
    fillOrder(orderId, deadline, fillAmountB) {
      return v2Send("fillOrder", {
        orderId,
        deadline,
        fillAmountB: fillAmountB.toString(),
      });
    },

    /**
     * @see ISwapboard.fillOrderWithEth
     * Pays with native ETH. msg.value *is* the fill amount, so there is no
     * separate fillAmountB argument.
     */
    fillOrderWithEth(orderId, deadline, value) {
      return v2Send("fillOrderWithEth", { orderId, deadline, value: value.toString() });
    },

    /** @see ISwapboard.fillOrderUnwrap — taker receives native ETH */
    fillOrderUnwrap(orderId, deadline, fillAmountB) {
      return v2Send("fillOrderUnwrap", {
        orderId,
        deadline,
        fillAmountB: fillAmountB.toString(),
      });
    },

    /** @see ISwapboard.cancelOrder */
    cancelOrder(orderId) {
      return v2Send("cancelOrder", { orderId });
    },

    /** @see ISwapboard.cancelOrderUnwrap — maker receives native ETH */
    cancelOrderUnwrap(orderId) {
      return v2Send("cancelOrderUnwrap", { orderId });
    },

    /** @see ISwapboard.fillOrders */
    fillOrders(orderIds, deadline, fillAmountsB) {
      return v2Send("fillOrders", {
        orderIds,
        deadline,
        fillAmountsB: fillAmountsB.map(String),
      });
    },

    /**
     * @see ISwapboard.tryFillOrders
     * Skips orders that are no longer fillable instead of reverting the batch.
     * The stub reports every order as filled.
     */
    tryFillOrders(orderIds, deadline, fillAmountsB) {
      const filled = orderIds.map(() => true);
      return v2Send(
        "tryFillOrders",
        { orderIds, deadline, fillAmountsB: fillAmountsB.map(String) },
        filled
      );
    },

    /**
     * @see ISwapboard.tryFillOrdersWithEth
     * Batch equivalent of fillOrderWithEth: msg.value covers the whole batch,
     * and the contract refunds whatever the skipped orders did not consume.
     */
    tryFillOrdersWithEth(orderIds, deadline, fillAmountsB, value) {
      const filled = orderIds.map(() => true);
      return v2Send(
        "tryFillOrdersWithEth",
        {
          orderIds,
          deadline,
          fillAmountsB: fillAmountsB.map(String),
          value: value.toString(),
        },
        filled
      );
    },

    /** @see ISwapboard.cancelOrders */
    cancelOrders(orderIds) {
      return v2Send("cancelOrders", { orderIds });
    },

    /** @see ISwapboard.cancelOrdersUnwrap */
    cancelOrdersUnwrap(orderIds) {
      return v2Send("cancelOrdersUnwrap", { orderIds });
    },

    /**
     * Ensures the Swapboard contract can move `total` of `tokenAddress`.
     * Batched: one approval covers every order in the batch using that token.
     * @param {string} tokenAddress - ERC20 address (native ETH needs no approval)
     * @param {bigint} total - Total amount the batch will move
     * @returns {Promise<boolean>} True if an approval transaction was sent
     */
    async ensureAllowance(tokenAddress, total) {
      if (isNativeEth(tokenAddress)) return false;
      logV2Call("ERC20.allowance", { token: tokenAddress, owner: userAddress });
      const tx = await v2Send("ERC20.approve", {
        token: tokenAddress,
        spender: CONFIG.CONTRACT_ADDRESS,
        amount: total.toString(),
      });
      await tx.wait();
      return true;
    },

    /**
     * No gas estimate in v2: there is no deployed ABI to encode against, and
     * an invented number is worse than none.
     * @returns {Promise<null>}
     */
    async estimateFor() {
      return null;
    },

    /** No subgraph indexes v2 yet, so there is nothing to poll for. */
    async syncAfter() {},
  };

  // ============================================================================
  // V1 CONNECTOR — LIVE CONTRACTS
  // ============================================================================
  //
  // Swapboard v1 at CONFIG.CONTRACT_ADDRESS is deployed, immutable, and holds
  // real funds. Every method here submits a real transaction.
  //
  // The surface deliberately matches the V2 connector above so the call sites
  // above this layer never branch on version — they call SB.<method> and the
  // adapter decides what that means. Where v2 takes an argument v1 has no
  // concept of (fillAmountB, partialFill), the v1 method accepts and ignores
  // it; the UI never produces a meaningful value for it anyway, because
  // CAPS.partialFill gates those controls off.
  //
  // The batch entry points (fillOrders / cancelOrders / createOrders and the
  // tryFill variants) do not exist on v1 at all. They are present here only to
  // throw a clear error: CAPS.batch keeps the selection UI hidden in v1, so
  // reaching one of these means a gate was missed, and failing loudly beats
  // silently sending one transaction where the user asked for twenty.
  // ============================================================================

  /** Rejects a v2-only batch call that leaked past a capability gate. */
  function v1Unsupported(method) {
    return Promise.reject(
      new Error(`${method} is a v2 entry point and does not exist on Swapboard v1`)
    );
  }

  const V1 = {
    /** @see Swapboard.createOrder — partialFill has no v1 equivalent */
    createOrder(tokenA, amountA, tokenB, amountB) {
      return contract.createOrder(tokenA, amountA, tokenB, amountB);
    },

    /**
     * @see Swapboard.createOrderWithEth
     * v1 reaches ETH by wrapping: the offered side is WETH and the ETH rides
     * in msg.value.
     */
    createOrderWithEth(tokenB, amountB, partialFill, value) {
      return contract.createOrderWithEth(tokenB, amountB, { value });
    },

    createOrders: () => v1Unsupported("createOrders"),
    createOrdersWithEth: () => v1Unsupported("createOrdersWithEth"),

    /** @see Swapboard.fillOrder — v1 orders are all-or-nothing */
    fillOrder(orderId, deadline) {
      return contract.fillOrder(orderId, deadline);
    },

    /** @see Swapboard.fillOrderWithEth — msg.value is the full wanted amount */
    fillOrderWithEth(orderId, deadline, value) {
      return contract.fillOrderWithEth(orderId, deadline, { value });
    },

    /** @see Swapboard.fillOrderUnwrap — taker receives native ETH */
    fillOrderUnwrap(orderId, deadline) {
      return contract.fillOrderUnwrap(orderId, deadline);
    },

    /** @see Swapboard.cancelOrder */
    cancelOrder(orderId) {
      return contract.cancelOrder(orderId);
    },

    /** @see Swapboard.cancelOrderUnwrap — maker receives native ETH */
    cancelOrderUnwrap(orderId) {
      return contract.cancelOrderUnwrap(orderId);
    },

    fillOrders: () => v1Unsupported("fillOrders"),
    tryFillOrders: () => v1Unsupported("tryFillOrders"),
    tryFillOrdersWithEth: () => v1Unsupported("tryFillOrdersWithEth"),
    cancelOrders: () => v1Unsupported("cancelOrders"),
    cancelOrdersUnwrap: () => v1Unsupported("cancelOrdersUnwrap"),

    /**
     * Approves the Swapboard contract for `total` of `tokenAddress` when the
     * existing allowance falls short.
     * @param {string} tokenAddress - ERC20 address
     * @param {bigint} total - Amount the transaction will move
     * @returns {Promise<boolean>} True if an approval transaction was sent
     */
    async ensureAllowance(tokenAddress, total) {
      const tokenContract = new ethers.Contract(tokenAddress, ERC20_ABI, signer);
      const allowance = await tokenContract.allowance(userAddress, CONFIG.CONTRACT_ADDRESS);
      if (allowance >= BigInt(total)) return false;

      showToast("Approve tokens in wallet...", "info", true);
      const approveTx = await tokenContract.approve(CONFIG.CONTRACT_ADDRESS, total);
      showToast("Waiting for approval tx...", "info", true);
      await approveTx.wait();
      showToast("Approval confirmed");
      return true;
    },

    /**
     * Estimates the gas cost of a call before showing the confirmation modal.
     * Returns null on any failure — a missing estimate is not worth blocking a
     * transaction over.
     *
     * @param {string} method - Contract method name
     * @param {Array} args - Arguments to encode
     * @param {bigint} [value] - msg.value for payable calls
     * @returns {Promise<Object|null>} {gas, eth, usd} or null
     */
    async estimateFor(method, args, value) {
      if (!provider || !contract) return null;
      try {
        const txParams = {
          from: userAddress,
          to: CONFIG.CONTRACT_ADDRESS,
          data: contract.interface.encodeFunctionData(method, args),
        };
        if (value !== undefined && value !== null) txParams.value = BigInt(value);
        return await estimateGasCost(txParams);
      } catch (e) {
        console.error("Gas estimation failed:", e);
        return null;
      }
    },

    /**
     * Waits for the subgraph to catch up with a transaction before reloading,
     * so the table does not flash the pre-transaction state.
     * @param {string} orderId - Order that changed
     * @param {boolean} expectedActive - Active flag to wait for
     */
    async syncAfter(orderId, expectedActive) {
      // Mock orders are generated, not indexed — their state never changes, so
      // polling would only burn the full timeout before giving up.
      if (window.SWAPBOARD_MOCK) return;
      await waitForOrderUpdate(orderId, expectedActive);
    },
  };

  /**
   * The connector for the active protocol version. Fixed for the life of the
   * page — setVersion() reloads rather than swapping this out.
   * @type {Object}
   */
  const SB = ACTIVE_VERSION === 1 ? V1 : V2;

  // ============================================================================
  // Order Actions
  // ============================================================================

  /**
   * Handles the fill order flow: confirms with user, approves tokens, fills.
   * @param {Object} order - Order object from subgraph
   */
  /**
   * Builds the partial-fill controls for the fill confirmation.
   *
   * The user types how much of the offered token they want to receive; the
   * amount they pay is derived from it. Presets are percentages of what is
   * *left* on the order, so they stay meaningful on a partly filled order.
   *
   * @param {Object} order - Order being filled
   * @param {function(bigint): void} onChange - Called with the new fillAmountB
   * @returns {HTMLElement}
   */
  function buildPartialFillControls(order, onChange) {
    const remainingA = BigInt(order.amountA);
    const wrap = document.createElement("div");
    wrap.className = "partial-fill-controls";

    const label = document.createElement("label");
    label.textContent = "Receive (" + order.tokenA.symbol + "):";
    wrap.appendChild(label);

    const inputRow = document.createElement("div");
    inputRow.className = "partial-fill-input-row";
    const input = document.createElement("input");
    input.type = "text";
    input.value = formatAmount(remainingA, order.tokenA.decimals);
    inputRow.appendChild(input);
    wrap.appendChild(inputRow);

    const presets = document.createElement("div");
    presets.className = "partial-fill-presets";
    wrap.appendChild(presets);

    const send = document.createElement("div");
    send.className = "partial-fill-send";
    wrap.appendChild(send);

    /**
     * Recomputes the payment for a desired receive amount and reports it.
     * @param {bigint} receive - Desired amount of the offered token
     * @param {boolean} writeBack - Whether to rewrite the input box
     */
    function update(receive, writeBack) {
      const { fillAmountB, actualAmountA } = computeFillFromReceive(order, receive);

      input.classList.toggle("input-error", fillAmountB === 0n);
      if (writeBack) {
        input.value = formatAmount(actualAmountA, order.tokenA.decimals);
      }

      send.textContent =
        "You send: " + formatAmount(fillAmountB, order.tokenB.decimals) + " " + order.tokenB.symbol;

      onChange(fillAmountB);
    }

    for (const percent of [25, 50, 75, 100]) {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "quick-amt-btn";
      btn.textContent = percent + "%";
      btn.addEventListener("click", () => {
        for (const other of presets.children) other.classList.remove("active");
        btn.classList.add("active");
        update((remainingA * BigInt(percent)) / 100n, true);
      });
      presets.appendChild(btn);
    }
    presets.lastChild.classList.add("active");

    input.addEventListener("input", () => {
      for (const other of presets.children) other.classList.remove("active");
      const { amount } = tryParseAmount(input.value, order.tokenA.decimals);
      update(amount === null ? 0n : amount, false);
    });

    update(remainingA, false);
    return wrap;
  }

  /**
   * Fills a single order, optionally in part.
   *
   * Routing follows how each side has to settle:
   *   - wanted token is native ETH -> fillOrderWithEth (payable, no approval)
   *   - wanted token is WETH       -> fillOrderWithEth, so the taker can pay
   *                                   in ETH rather than wrapping first
   *   - offered token is WETH      -> fillOrderUnwrap, so the taker is paid
   *                                   in ETH rather than WETH
   *   - otherwise                  -> approve + fillOrder
   *
   * An order offering *native* ETH needs no special call: the contract already
   * escrows ETH and pays it straight out, so plain fillOrder is correct.
   *
   * A fillAmountB equal to the full remainder is submitted as 0, which the
   * contract reads as "fill the entire remaining order".
   *
   * @param {Object} order - Order to fill
   */
  async function handleFillOrder(order) {
    if (!signer) {
      showToast("Connect wallet first", "error");
      return;
    }

    const payWithEth = isNativeEth(order.tokenB.address) || isWeth(order.tokenB.address);
    const unwrapToEth = isWeth(order.tokenA.address);
    const remainingB = BigInt(order.amountB);

    const body = document.createElement("div");
    const summary = document.createElement("div");
    summary.textContent =
      `You will send ${formatAmount(order.amountB, order.tokenB.decimals)} ${order.tokenB.symbol} ` +
      `and receive ${formatAmount(order.amountA, order.tokenA.decimals)} ${order.tokenA.symbol} in return.`;
    body.appendChild(summary);

    // Orders that opted out of partial fill are all-or-nothing, so there is
    // nothing to choose and the controls stay off. So is every v1 order.
    let fillAmountB = remainingB;
    if (CAPS.partialFill && order.partialFill) {
      body.appendChild(
        buildPartialFillControls(order, (amount) => {
          fillAmountB = amount;
        })
      );
    }

    // Estimated against the full-remainder fill, which is what the modal opens
    // on. A partial fill costs about the same, so re-estimating on every
    // keystroke would buy precision nobody acts on.
    const estimateDeadline = Math.floor(Date.now() / 1000) + 300;
    let gasEstimate = null;
    if (CAPS.gasEstimate) {
      showToast("Estimating gas...");
      gasEstimate = payWithEth
        ? await SB.estimateFor("fillOrderWithEth", [order.orderId, estimateDeadline], remainingB)
        : await SB.estimateFor(unwrapToEth ? "fillOrderUnwrap" : "fillOrder", [
            order.orderId,
            estimateDeadline,
          ]);
    }

    showModal(
      "Fill Order #" + order.orderId,
      body,
      async () => {
        try {
          if (fillAmountB <= 0n) {
            showToast("Enter an amount to fill", "error");
            return;
          }

          const deadline = Math.floor(Date.now() / 1000) + 300;
          // 0 means "fill the remainder" on-chain; send it when the user hasn't
          // scaled the order down, so a race that partially fills it first
          // doesn't turn into a revert.
          const fillArg = fillAmountB >= remainingB ? 0n : fillAmountB;

          let tx;
          if (payWithEth) {
            // Paying in ETH: the amount rides in msg.value, so nothing to approve.
            showToast("Confirm fill in wallet...", "info", true);
            tx = await SB.fillOrderWithEth(order.orderId, deadline, fillAmountB);
          } else {
            showToast("Checking allowance...", "info", true);
            await SB.ensureAllowance(order.tokenB.address, fillAmountB);

            showToast("Confirm fill in wallet...", "info", true);
            tx = unwrapToEth
              ? await SB.fillOrderUnwrap(order.orderId, deadline, fillArg)
              : await SB.fillOrder(order.orderId, deadline, fillArg);
          }

          showToast("Waiting for tx confirmation...", "info", true);
          await tx.wait();
          showToast("Order filled! Syncing...", "success", true);
          // A fully filled order goes inactive; a partial fill leaves it active
          // with a smaller remainder, which this poll cannot distinguish, so
          // only wait when the whole order was taken.
          await SB.syncAfter(order.orderId, fillAmountB < remainingB);
          loadOrders();
          loadStats();
          showToast("Order filled!", "success");
        } catch (e) {
          console.error("Fill error:", e);
          showToast("Fill failed: " + parseContractError(e), "error");
        }
      },
      gasEstimate
    );
  }

  /**
   * Cancels a single order, returning the remaining offered amount to the maker.
   *
   * Orders offering WETH unwrap so the maker gets native ETH back. Orders
   * offering native ETH need no special call — the escrow is already ETH.
   *
   * @param {Object} order - Order to cancel
   */
  async function handleCancelOrder(order) {
    if (!signer) {
      showToast("Connect wallet first", "error");
      return;
    }

    const unwrap = isWeth(order.tokenA.address);
    const amountAStr = formatAmount(order.amountA, order.tokenA.decimals);

    let gasEstimate = null;
    if (CAPS.gasEstimate) {
      showToast("Estimating gas...");
      gasEstimate = await SB.estimateFor(unwrap ? "cancelOrderUnwrap" : "cancelOrder", [
        order.orderId,
      ]);
    }

    showModal(
      "Cancel Order #" + order.orderId,
      `Your ${amountAStr} ${order.tokenA.symbol} will be returned to your wallet.`,
      async () => {
        try {
          showToast("Cancelling order...", "info", true);
          const tx = unwrap
            ? await SB.cancelOrderUnwrap(order.orderId)
            : await SB.cancelOrder(order.orderId);
          await tx.wait();
          showToast("Order cancelled! Updating...", "success", true);
          await SB.syncAfter(order.orderId, false);
          loadOrders();
          loadStats();
          showToast("Order cancelled!", "success");
        } catch (e) {
          console.error("Cancel error:", e);
          showToast("Cancel failed: " + parseContractError(e), "error");
        }
      },
      gasEstimate
    );
  }

  // ============================================================================
  // Batch Order Actions (Fill All / Cancel All)
  // ============================================================================

  /**
   * Builds one line of a batch confirmation list.
   * @param {string} id - Order ID
   * @param {string} text - Description of the swap or refund
   * @returns {HTMLElement}
   */
  function buildBatchItem(id, text) {
    const item = document.createElement("div");
    item.className = "batch-summary-item";

    const idSpan = document.createElement("span");
    idSpan.className = "batch-summary-id";
    idSpan.textContent = "#" + id;
    item.appendChild(idSpan);

    const textSpan = document.createElement("span");
    textSpan.textContent = text;
    item.appendChild(textSpan);

    return item;
  }

  /**
   * Adds a labelled total row to a batch summary.
   * @param {HTMLElement} parent - Totals container
   * @param {string} label - Row label
   * @param {string} value - Row value
   * @param {boolean} [emphasis=false] - Render as the headline figure
   */
  function appendTotalRow(parent, label, value, emphasis = false) {
    const row = document.createElement("div");
    if (emphasis) row.className = "batch-summary-emphasis";

    const labelSpan = document.createElement("span");
    labelSpan.textContent = label;
    row.appendChild(labelSpan);

    const valueSpan = document.createElement("span");
    valueSpan.textContent = value;
    row.appendChild(valueSpan);

    parent.appendChild(row);
  }

  /**
   * Adds a note explaining how many transactions a batch will take.
   * @param {HTMLElement} parent - Container to append to
   * @param {number} count - Number of orders
   * @param {number} perTx - Maximum orders per transaction
   */
  function appendBatchTxNote(parent, count, perTx) {
    const txCount = Math.ceil(count / perTx);
    if (txCount <= 1) return;

    const note = document.createElement("div");
    note.className = "batch-summary-note";
    note.textContent = `Too many orders for one transaction — this will be split into ${txCount} transactions of up to ${perTx} orders each.`;
    parent.appendChild(note);
  }

  /**
   * Runs a batch across as many transactions as it takes, reporting progress.
   *
   * @param {Array[]} chunks - Orders/IDs grouped one group per transaction
   * @param {string} verb - Present participle for the progress toast ("Filling")
   * @param {function(Array, number): Promise<*>} send - Submits one chunk
   * @returns {Promise<number>} Number of orders processed
   */
  async function runBatchTransactions(chunks, verb, send) {
    let processed = 0;

    for (let i = 0; i < chunks.length; i++) {
      const chunk = chunks[i];
      const remaining = chunks.length - i - 1;
      const progress =
        chunks.length > 1
          ? ` (transaction ${i + 1} of ${chunks.length}, ${remaining} remaining)`
          : "";

      showToast(`${verb} ${chunk.length} orders${progress}...`, "info", true);
      const tx = await send(chunk, i);
      await tx.wait();
      processed += chunk.length;
    }

    return processed;
  }

  /**
   * Fills every selected order.
   *
   * Selection rules guarantee a single token pair, so one approval covers the
   * whole batch and the totals in the confirmation are meaningful. Orders are
   * filled to their full remaining amount (fillAmountB of 0); partial fill is
   * intentionally not offered for batches.
   */
  async function fillSelectedOrders() {
    const orders = getSelectedOrders();
    if (orders.length === 0) return;

    if (!signer) {
      showToast("Connect wallet first", "error");
      return;
    }

    const { tokenA, tokenB } = orders[0];
    const totals = summarizeFillBatch(orders);
    const sendStr = formatAmount(totals.totalSend, tokenB.decimals);
    const receiveStr = formatAmount(totals.totalReceive, tokenA.decimals);
    // Same routing as a single fill: pay in ETH for a native-ETH or WETH
    // wanted token, otherwise approve the ERC20.
    const payWithEth = isNativeEth(tokenB.address) || isWeth(tokenB.address);

    const body = document.createElement("div");
    body.className = "batch-summary";

    const list = document.createElement("div");
    list.className = "batch-summary-list";
    for (const order of orders) {
      list.appendChild(
        buildBatchItem(
          order.orderId,
          `${formatAmount(order.amountB, tokenB.decimals)} ${tokenB.symbol} → ` +
            `${formatAmount(order.amountA, tokenA.decimals)} ${tokenA.symbol}`
        )
      );
    }
    body.appendChild(list);

    const totalsEl = document.createElement("div");
    totalsEl.className = "batch-summary-totals";
    appendTotalRow(totalsEl, "Orders", String(totals.count));
    appendTotalRow(
      totalsEl,
      "Average price",
      totals.avgPrice === null
        ? "N/A"
        : `${formatRatio(totals.avgPrice)} ${tokenB.symbol}/${tokenA.symbol}`
    );
    appendTotalRow(totalsEl, "You send", `${sendStr} ${tokenB.symbol}`, true);
    appendTotalRow(totalsEl, "You receive", `${receiveStr} ${tokenA.symbol}`, true);
    body.appendChild(totalsEl);

    if (payWithEth) {
      const note = document.createElement("div");
      note.className = "batch-summary-note";
      note.textContent =
        "Paid in ETH, so no token approval is needed. Anything the skipped orders don't use is refunded.";
      body.appendChild(note);
    }

    const skipNote = document.createElement("div");
    skipNote.className = "batch-summary-note";
    skipNote.textContent =
      "Orders that are no longer fillable when the transaction lands are skipped; the rest still fill.";
    body.appendChild(skipNote);

    appendBatchTxNote(body, orders.length, CONFIG.MAX_BATCH_FILL);

    showModal(`Fill ${orders.length} Orders`, body, async () => {
      try {
        if (!payWithEth) {
          showToast("Checking allowance...", "info", true);
          await SB.ensureAllowance(tokenB.address, totals.totalSend);
        }

        const deadline = Math.floor(Date.now() / 1000) + 300;
        const chunks = chunkArray(orders, CONFIG.MAX_BATCH_FILL);

        const filled = await runBatchTransactions(chunks, "Filling", (chunk) => {
          const ids = chunk.map((o) => o.orderId);
          // fillAmountB of 0 means "fill the entire remaining amount", which
          // is also what finishes off already partially filled orders.
          const amounts = chunk.map(() => 0n);

          if (!payWithEth) return SB.tryFillOrders(ids, deadline, amounts);

          // Paying in ETH: msg.value covers this chunk, and the contract
          // refunds whatever any skipped orders leave unspent.
          const chunkValue = chunk.reduce((sum, o) => sum + BigInt(o.amountB), 0n);
          return SB.tryFillOrdersWithEth(ids, deadline, amounts, chunkValue);
        });

        clearSelection(false);
        showToast(`Filled ${filled} orders! Syncing...`, "success", true);
        loadOrders();
        loadStats();
        showToast(`Filled ${filled} orders!`, "success");
      } catch (e) {
        console.error("Batch fill error:", e);
        showToast("Fill failed: " + parseContractError(e), "error");
      }
    });
  }

  /**
   * Cancels every selected order.
   *
   * Own orders may span different pairs, so totals are grouped per offered
   * token. Orders offering WETH are routed to cancelOrdersUnwrap so the maker
   * gets native ETH back, matching the single-order behaviour.
   */
  async function cancelSelectedOrders() {
    const orders = getSelectedOrders();
    if (orders.length === 0) return;

    if (!signer) {
      showToast("Connect wallet first", "error");
      return;
    }

    const body = document.createElement("div");
    body.className = "batch-summary";

    const list = document.createElement("div");
    list.className = "batch-summary-list";
    const refunds = new Map();
    for (const order of orders) {
      const { symbol, decimals } = order.tokenA;
      list.appendChild(
        buildBatchItem(order.orderId, `${formatAmount(order.amountA, decimals)} ${symbol} returned`)
      );

      const existing = refunds.get(symbol);
      refunds.set(symbol, {
        decimals,
        total: (existing ? existing.total : 0n) + BigInt(order.amountA),
      });
    }
    body.appendChild(list);

    const totalsEl = document.createElement("div");
    totalsEl.className = "batch-summary-totals";
    appendTotalRow(totalsEl, "Orders", String(orders.length));
    for (const [symbol, { decimals, total }] of refunds) {
      appendTotalRow(totalsEl, "Returned", `${formatAmount(total, decimals)} ${symbol}`, true);
    }
    body.appendChild(totalsEl);

    appendBatchTxNote(body, orders.length, CONFIG.MAX_BATCH_CANCEL);

    showModal(`Cancel ${orders.length} Orders`, body, async () => {
      try {
        // Split by settlement type first so each transaction is homogeneous,
        // then by batch size.
        // Only WETH needs unwrapping; a native-ETH order already escrows ETH.
        const needsUnwrap = (o) => isWeth(o.tokenA.address);
        const unwrap = orders.filter(needsUnwrap);
        const plain = orders.filter((o) => !needsUnwrap(o));

        let cancelled = 0;
        cancelled += await runBatchTransactions(
          chunkArray(plain, CONFIG.MAX_BATCH_CANCEL),
          "Cancelling",
          (chunk) => SB.cancelOrders(chunk.map((o) => o.orderId))
        );
        cancelled += await runBatchTransactions(
          chunkArray(unwrap, CONFIG.MAX_BATCH_CANCEL),
          "Cancelling",
          (chunk) => SB.cancelOrdersUnwrap(chunk.map((o) => o.orderId))
        );

        clearSelection(false);
        showToast(`Cancelled ${cancelled} orders! Updating...`, "success", true);
        loadOrders();
        loadStats();
        showToast(`Cancelled ${cancelled} orders!`, "success");
      } catch (e) {
        console.error("Batch cancel error:", e);
        showToast("Cancel failed: " + parseContractError(e), "error");
      }
    });
  }

  // ============================================================================
  // Sell Tokens form (batch create)
  // ============================================================================
  //
  // The form is a list of order rows cloned from #create-row-template. Fields
  // are addressed by [data-field] scoped to their row rather than by global id,
  // so several orders can go out in one createOrders() transaction.

  /**
   * Finds a field inside a create-order row.
   * @param {HTMLElement} row - A .create-row element
   * @param {string} name - data-field value
   * @returns {HTMLElement}
   */
  function rowField(row, name) {
    return row.querySelector('[data-field="' + name + '"]');
  }

  /**
   * Returns every create-order row, in form order.
   * @returns {HTMLElement[]}
   */
  function getCreateRows() {
    return Array.from(document.querySelectorAll("#create-rows .create-row"));
  }

  /**
   * Per-row token metadata and balances, keyed by the row element so removing
   * a row disposes of its state automatically.
   * @type {WeakMap<HTMLElement, {tokenA: Object, tokenB: Object}>}
   */
  const rowStates = new WeakMap();

  /**
   * Returns (creating if needed) the validation state for a row.
   * @param {HTMLElement} row - A .create-row element
   * @returns {{tokenA: {info: ?Object, balance: ?bigint}, tokenB: {info: ?Object, balance: ?bigint}}}
   */
  function getRowState(row) {
    if (!rowStates.has(row)) {
      rowStates.set(row, {
        tokenA: { info: null, balance: null },
        tokenB: { info: null, balance: null },
      });
    }
    return rowStates.get(row);
  }

  /**
   * Validates an amount field against the row's token metadata and balance.
   * @param {HTMLElement} row - A .create-row element
   * @param {"tokenA"|"tokenB"} side - Which side of the order
   * @returns {boolean} True when the amount is usable
   */
  function validateRowAmount(row, side) {
    const input = rowField(row, side === "tokenA" ? "amountA" : "amountB");
    const state = getRowState(row)[side];

    let errorSpan = input.parentNode.querySelector(".amount-error");
    if (!errorSpan) {
      errorSpan = document.createElement("span");
      errorSpan.className = "amount-error";
      input.parentNode.appendChild(errorSpan);
    }

    const value = input.value.trim();
    if (!value || !state.info) {
      input.classList.remove("input-error");
      errorSpan.textContent = "";
      return true;
    }

    const { amount, error } = tryParseAmount(value, state.info.decimals);
    if (amount === null) {
      input.classList.add("input-error");
      errorSpan.textContent = error;
      return false;
    }

    // Only the offered side is spent, so only it can exceed a balance.
    if (side === "tokenA" && state.balance !== null && amount > state.balance) {
      input.classList.add("input-error");
      errorSpan.textContent = "Exceeds balance";
      return false;
    }

    if (amount === 0n && value !== "0") {
      input.classList.add("input-error");
      errorSpan.textContent = "Amount too small";
      return false;
    }

    input.classList.remove("input-error");
    errorSpan.textContent = "";
    return true;
  }

  /**
   * Shows the implied price for a row once both amounts are filled in.
   * @param {HTMLElement} row - A .create-row element
   */
  function updateRowPriceDisplay(row) {
    const priceInfo = rowField(row, "price-info");
    const state = getRowState(row);
    const amountA = parseFloat(rowField(row, "amountA").value.trim());
    const amountB = parseFloat(rowField(row, "amountB").value.trim());

    priceInfo.textContent = "";
    if (isNaN(amountA) || isNaN(amountB) || amountA <= 0 || amountB <= 0) return;

    const symbolA = state.tokenA.info ? state.tokenA.info.symbol : "Token A";
    const symbolB = state.tokenB.info ? state.tokenB.info.symbol : "Token B";
    const trim = (n) => n.toFixed(6).replace(/\.?0+$/, "");

    priceInfo.appendChild(
      document.createTextNode("1 " + symbolB + " = " + trim(amountA / amountB) + " " + symbolA)
    );
    priceInfo.appendChild(document.createElement("br"));
    priceInfo.appendChild(
      document.createTextNode("1 " + symbolA + " = " + trim(amountB / amountA) + " " + symbolB)
    );
  }

  /**
   * Renders quick-amount buttons (25/50/75/100% of balance) for a row side.
   * @param {HTMLElement} row - A .create-row element
   * @param {"tokenA"|"tokenB"} side - Which side of the order
   * @param {bigint} balance - Available balance in base units
   * @param {number} decimals - Token decimals
   */
  function renderRowQuickAmounts(row, side, balance, decimals) {
    const container = rowField(row, "quick-amounts-A");
    if (!container || side !== "tokenA") return;

    container.textContent = "";
    if (balance <= 0n) return;

    const amountInput = rowField(row, "amountA");
    for (const percent of [25, 50, 75, 100]) {
      const btn = document.createElement("button");
      btn.type = "button";
      btn.className = "quick-amt-btn";
      btn.textContent = percent + "%";
      btn.addEventListener("click", () => {
        amountInput.value = formatAmount(((balance * BigInt(percent)) / 100n).toString(), decimals);
        amountInput.dispatchEvent(new Event("input"));
      });
      container.appendChild(btn);
    }
  }

  /**
   * Renders the resolved token metadata line under a token input.
   * @param {HTMLElement} infoEl - The [data-field="tokenX-info"] element
   * @param {Object} info - Token info from fetchTokenInfo
   */
  function renderTokenInfoLine(infoEl, info) {
    infoEl.textContent = "";

    if (isNativeEth(info.address)) {
      infoEl.appendChild(document.createTextNode("ETH (18 decimals) — native, no contract"));
      return;
    }

    const coinGeckoId = COINGECKO_ID_MAP[info.address.toLowerCase()];
    if (coinGeckoId) {
      const link = document.createElement("a");
      link.href = "https://www.coingecko.com/en/coins/" + coinGeckoId;
      link.target = "_blank";
      link.rel = "noopener noreferrer";
      link.textContent = info.symbol;
      link.title = "Verify on CoinGecko";
      infoEl.appendChild(link);
      infoEl.appendChild(document.createTextNode(" (" + info.decimals + " decimals) "));

      const verifyLink = document.createElement("a");
      verifyLink.href = "https://www.coingecko.com/en/coins/" + coinGeckoId;
      verifyLink.target = "_blank";
      verifyLink.rel = "noopener noreferrer";
      verifyLink.textContent = "[verify]";
      verifyLink.className = "verify-link";
      infoEl.appendChild(verifyLink);
      return;
    }

    infoEl.appendChild(document.createTextNode(info.symbol + " (" + info.decimals + " decimals) "));
    const warnSpan = document.createElement("span");
    warnSpan.className = "token-warning";
    warnSpan.textContent = "[unknown token]";
    warnSpan.title = "This token is not in our verified list. Double-check the address.";
    infoEl.appendChild(warnSpan);
  }

  /**
   * Loads and displays the connected wallet's balance for a row side.
   *
   * The balance shown has to be the one the order will actually spend. An
   * offered side that settles as ETH spends the account balance even when the
   * field holds a token address: v1 has no native sentinel and routes an
   * offered WETH through createOrderWithEth, paying in ETH via msg.value. So
   * the test is "does this side settle as ETH", not "is this address native" —
   * the latter is never true in v1 and would show a v1 seller their WETH
   * balance (typically 0) for an order paid out of their ETH.
   *
   * Only the offered side is spent, so only tokenA gets this treatment.
   *
   * @param {HTMLElement} row - A .create-row element
   * @param {"tokenA"|"tokenB"} side - Which side of the order
   * @param {Object} info - Token info from fetchTokenInfo
   */
  async function loadRowBalance(row, side, info) {
    const balanceEl = rowField(row, side + "-balance");
    if (!userAddress || !provider) return;

    const spendsEth =
      side === "tokenA"
        ? offersEthDirectly(info.address, ACTIVE_VERSION, isWeth)
        : isNativeEth(info.address);

    try {
      const balance = spendsEth
        ? await provider.getBalance(userAddress)
        : await new ethers.Contract(info.address, ERC20_ABI, provider).balanceOf(userAddress);

      getRowState(row)[side].balance = balance;
      balanceEl.textContent = "Balance: " + formatAmount(balance.toString(), info.decimals);

      validateRowAmount(row, side);
      renderRowQuickAmounts(row, side, balance, info.decimals);
    } catch (e) {
      console.error("Balance fetch error:", e);
    }
  }

  /**
   * Wires a row's token address field: debounced metadata lookup, balance
   * fetch, and state bookkeeping.
   * @param {HTMLElement} row - A .create-row element
   * @param {"tokenA"|"tokenB"} side - Which side of the order
   */
  function setupRowTokenField(row, side) {
    const input = rowField(row, side);
    const infoEl = rowField(row, side + "-info");
    const balanceEl = rowField(row, side + "-balance");
    let timeout = null;

    input.addEventListener("input", () => {
      clearTimeout(timeout);
      rowField(row, "price-info").textContent = "";

      const addr = input.value.trim();
      const state = getRowState(row)[side];

      // Keep [ETH] lit when ETH arrives via the autocomplete rather than the
      // button, so the two entry points agree.
      row
        .querySelector('[data-eth-for="' + side + '"]')
        .classList.toggle("active", isNativeEth(addr));

      if (!isValidAddress(addr)) {
        infoEl.textContent = addr ? "Invalid address" : "";
        balanceEl.textContent = "";
        renderRowQuickAmounts(row, side, 0n, 18);
        state.info = null;
        state.balance = null;
        return;
      }

      timeout = setTimeout(async () => {
        infoEl.textContent = "Loading...";
        balanceEl.textContent = "";

        const info = await fetchTokenInfo(addr);
        if (info.decimals == null) {
          infoEl.textContent = "";
          const warnSpan = document.createElement("span");
          warnSpan.className = "token-warning";
          warnSpan.textContent = "Could not read token decimals — cannot use this token";
          infoEl.appendChild(warnSpan);
          state.info = null;
          state.balance = null;
          return;
        }

        if (isWeth(addr)) {
          info.symbol = "ETH";
          info.name = "Ether";
        }

        state.info = info;
        state.balance = null;
        renderTokenInfoLine(infoEl, info);
        await loadRowBalance(row, side, info);
      }, CONFIG.DEBOUNCE_DELAY);
    });
  }

  /**
   * Toggles a row side between native ETH and a pasted contract address.
   *
   * Native ETH has no contract, so selecting it pins the field to the sentinel
   * and locks it; clicking again hands the field back to the user.
   *
   * @param {HTMLElement} row - A .create-row element
   * @param {"tokenA"|"tokenB"} side - Which side of the order
   */
  function toggleRowNativeEth(row, side) {
    const input = rowField(row, side);
    const btn = row.querySelector('[data-eth-for="' + side + '"]');
    const enabling = !isNativeEth(input.value.trim());

    input.value = enabling ? NATIVE_ETH : "";
    input.readOnly = enabling;
    input.classList.toggle("input-native-eth", enabling);
    btn.classList.toggle("active", enabling);

    input.dispatchEvent(new Event("input"));
  }

  /**
   * Renumbers rows and syncs the [Add Sell] button to the batch limit.
   */
  function refreshCreateRows() {
    const rows = getCreateRows();

    rows.forEach((row, i) => {
      row.querySelector(".create-row-label").textContent =
        rows.length > 1 ? "Order " + (i + 1) + " of " + rows.length : "";
    });

    // One order per transaction without a batch create entry point.
    const rowLimit = CAPS.multiCreate ? CONFIG.MAX_BATCH_CREATE : 1;
    const atLimit = rows.length >= rowLimit;
    $("#add-sell-btn").disabled = atLimit;
    $("#create-limit-note").textContent =
      atLimit && CAPS.multiCreate
        ? "Limit reached — " + CONFIG.MAX_BATCH_CREATE + " orders per transaction"
        : "";
    $("#create-btn").textContent =
      rows.length > 1 ? "Create " + rows.length + " Orders" : "Create Order";
  }

  /**
   * Appends a fresh order row to the Sell Tokens form.
   * @returns {HTMLElement|null} The new row, or null at the batch limit
   */
  function addCreateRow() {
    const rowLimit = CAPS.multiCreate ? CONFIG.MAX_BATCH_CREATE : 1;
    if (getCreateRows().length >= rowLimit) return null;

    const row = $("#create-row-template").content.firstElementChild.cloneNode(true);

    for (const side of ["tokenA", "tokenB"]) {
      setupRowTokenField(row, side);
      // The [ETH] shortcut fills in the native-ETH sentinel, which only v2
      // understands; v1 reaches ETH by naming WETH like any other token.
      if (CAPS.nativeEth) {
        row.querySelector('[data-eth-for="' + side + '"]').addEventListener("click", () => {
          toggleRowNativeEth(row, side);
        });
      }
    }

    rowField(row, "amountA").addEventListener("input", () => {
      updateRowPriceDisplay(row);
      validateRowAmount(row, "tokenA");
    });
    rowField(row, "amountB").addEventListener("input", () => {
      updateRowPriceDisplay(row);
      validateRowAmount(row, "tokenB");
    });

    row.querySelector(".create-row-remove").addEventListener("click", () => {
      if (getCreateRows().length <= 1) return;
      row.remove();
      refreshCreateRows();
    });

    $("#create-rows").appendChild(row);

    // Safe to attach before the Uniswap list has loaded: the selector reads it
    // lazily, on input.
    createTokenSelector(rowField(row, "tokenA"));
    createTokenSelector(rowField(row, "tokenB"));

    refreshCreateRows();
    return row;
  }

  /**
   * Clears the Sell Tokens form back to a single empty row.
   */
  function resetCreateForm() {
    $("#create-rows").textContent = "";
    addCreateRow();
  }

  /**
   * Reads and validates every row into contract-ready CreateOrderParams.
   * @returns {Promise<Object[]|null>} Params array, or null if anything is invalid
   */
  async function collectCreateParams() {
    const rows = getCreateRows();
    const params = [];

    for (let i = 0; i < rows.length; i++) {
      const row = rows[i];
      const label = rows.length > 1 ? "Order " + (i + 1) + ": " : "";

      const tokenAAddr = rowField(row, "tokenA").value.trim();
      const tokenBAddr = rowField(row, "tokenB").value.trim();
      const amountAStr = rowField(row, "amountA").value.trim();
      const amountBStr = rowField(row, "amountB").value.trim();

      if (!tokenAAddr || !tokenBAddr || !amountAStr || !amountBStr) {
        showToast(label + "Fill in all fields", "error");
        return null;
      }
      if (!isValidAddress(tokenAAddr) || !isValidAddress(tokenBAddr)) {
        showToast(label + "Invalid token address format", "error");
        return null;
      }
      if (tokenAAddr.toLowerCase() === tokenBAddr.toLowerCase()) {
        showToast(label + "Offered and wanted token must differ", "error");
        return null;
      }

      const tokenA = await fetchTokenInfo(tokenAAddr);
      const tokenB = await fetchTokenInfo(tokenBAddr);
      if (isWeth(tokenAAddr)) tokenA.symbol = "ETH";
      if (isWeth(tokenBAddr)) tokenB.symbol = "ETH";

      if (tokenA.decimals == null || tokenB.decimals == null) {
        showToast(
          label + "Could not read decimals — check that both token addresses are correct",
          "error"
        );
        return null;
      }

      const parsedA = tryParseAmount(amountAStr, tokenA.decimals);
      const parsedB = tryParseAmount(amountBStr, tokenB.decimals);
      if (parsedA.error || parsedB.error) {
        showToast(label + (parsedA.error || parsedB.error), "error");
        return null;
      }
      const amountA = parsedA.amount;
      const amountB = parsedB.amount;
      if (amountA === 0n || amountB === 0n) {
        showToast(label + "Amounts must be greater than 0", "error");
        return null;
      }

      const state = getRowState(row);
      if (state.tokenA.balance !== null && amountA > state.tokenA.balance) {
        showToast(label + "Insufficient balance for offered token", "error");
        return null;
      }

      params.push({
        tokenA: tokenAAddr,
        amountA,
        tokenB: tokenBAddr,
        amountB,
        // The checkbox is the opt-out, so partial fills are the default —
        // except on v1, where every order is all-or-nothing regardless.
        partialFill: CAPS.partialFill && !rowField(row, "no-partial").checked,
        tokenAInfo: tokenA,
        tokenBInfo: tokenB,
        amountAStr,
        amountBStr,
      });
    }

    return params;
  }

  /**
   * Creates every order in the Sell Tokens form.
   *
   * Approvals are grouped by offered token, so a batch selling the same token
   * across several rows approves once for the combined amount.
   */
  async function handleCreateOrder() {
    if (!signer) {
      showToast("Connect wallet first", "error");
      return;
    }

    // collectCreateParams reports its own validation failures and returns null.
    // This catch is for the rest: fetchTokenInfo hits the network, so an RPC
    // failure lands here too, and an escaped throw would leave the Create
    // button looking simply dead — no toast, no modal, no state change.
    let params;
    try {
      params = await collectCreateParams();
    } catch (e) {
      console.error("Create validation error:", e);
      showToast(e.message || "Could not read the order details", "error");
      return;
    }
    if (!params) return;

    const body = document.createElement("div");
    body.className = "batch-summary";

    const list = document.createElement("div");
    list.className = "batch-summary-list";
    params.forEach((p, i) => {
      list.appendChild(
        buildBatchItem(
          String(i + 1),
          `Sell ${p.amountAStr} ${p.tokenAInfo.symbol} for ${p.amountBStr} ${p.tokenBInfo.symbol}` +
            // On v1 nothing partially fills, so saying so would be noise.
            (!CAPS.partialFill || p.partialFill ? "" : " (no partial fills)")
        )
      );
    });
    body.appendChild(list);

    // Orders offering ETH go out through the payable entry point, so they are
    // submitted separately from the ERC20 ones. What counts as "offering ETH"
    // is version-dependent: v2 means the native-ETH sentinel, v1 means WETH.
    const offersEth = (p) => offersEthDirectly(p.tokenA, ACTIVE_VERSION, isWeth);
    const ethParams = params.filter(offersEth);
    const erc20Params = params.filter((p) => !offersEth(p));

    // Without batch entry points every order is its own transaction.
    const createChunkSize = CAPS.batch ? CONFIG.MAX_BATCH_CREATE : 1;

    if (ethParams.length > 0 && erc20Params.length > 0) {
      const note = document.createElement("div");
      note.className = "batch-summary-note";
      note.textContent =
        `${ethParams.length} of these offer ETH and settle through a separate ` +
        "call, so this takes one more transaction than a token-only batch.";
      body.appendChild(note);
    }

    appendBatchTxNote(body, erc20Params.length, createChunkSize);
    appendBatchTxNote(body, ethParams.length, createChunkSize);

    showModal(
      params.length > 1 ? `Create ${params.length} Orders` : "Create Order",
      body,
      async () => {
        const createBtn = $("#create-btn");
        const originalText = createBtn.textContent;
        createBtn.disabled = true;
        setTextWithDots(createBtn, "Processing");

        try {
          // One approval per distinct offered token, covering every row using
          // it. Orders paying through msg.value have nothing to approve.
          const totals = new Map();
          for (const p of params) {
            if (offersEth(p)) continue;
            totals.set(p.tokenA, (totals.get(p.tokenA) || 0n) + p.amountA);
          }

          for (const [token, total] of totals) {
            setTextWithDots(createBtn, "Approving");
            showToast("Checking allowance...", "info", true);
            await SB.ensureAllowance(token, total);
          }

          setTextWithDots(createBtn, "Creating");

          await runBatchTransactions(
            chunkArray(erc20Params, createChunkSize),
            "Creating",
            (chunk) =>
              chunk.length === 1
                ? SB.createOrder(
                    chunk[0].tokenA,
                    chunk[0].amountA,
                    chunk[0].tokenB,
                    chunk[0].amountB,
                    chunk[0].partialFill
                  )
                : SB.createOrders(chunk)
          );

          // Offering ETH means the amount rides in msg.value, so these go
          // through the payable variant with no tokenA argument.
          await runBatchTransactions(
            chunkArray(ethParams, createChunkSize),
            "Creating",
            (chunk) => {
              const value = chunk.reduce((sum, p) => sum + p.amountA, 0n);
              return chunk.length === 1
                ? SB.createOrderWithEth(
                    chunk[0].tokenB,
                    chunk[0].amountB,
                    chunk[0].partialFill,
                    value
                  )
                : SB.createOrdersWithEth(chunk, value);
            }
          );

          showToast("Orders created! Updating...", "success", true);
          for (const p of params) {
            addRecentToken(p.tokenA, p.tokenAInfo.symbol);
            addRecentToken(p.tokenB, p.tokenBInfo.symbol);
          }

          resetCreateForm();
          $("#sell-modal").classList.add("hidden");
          loadOrders();
          loadStats();
          showToast(
            params.length > 1 ? `Created ${params.length} orders!` : "Order created!",
            "success"
          );
        } catch (e) {
          console.error("Create error:", e);
          showToast("Create failed: " + parseContractError(e), "error");
        } finally {
          createBtn.disabled = false;
          createBtn.textContent = originalText;
        }
      }
    );
  }

  // ============================================================================
  // Wallet Connection
  // ============================================================================

  const NETWORK_NAMES = {
    1: "Mainnet",
    11155111: "Sepolia",
    5: "Goerli",
    137: "Polygon",
    42161: "Arbitrum",
    10: "Optimism",
  };

  function updateNetworkIndicator(chainId) {
    const name = NETWORK_NAMES[chainId] || "Chain " + chainId;
    const indicator = document.getElementById("network-indicator");
    if (indicator) {
      indicator.textContent = "[" + name + "]";
      indicator.classList.remove("hidden");
    }
  }

  async function switchToExpectedNetwork() {
    try {
      await window.ethereum.request({
        method: "wallet_switchEthereumChain",
        params: [{ chainId: EXPECTED_CHAIN.chainId }],
      });
      return true;
    } catch (switchError) {
      if (switchError.code === 4902) {
        try {
          await window.ethereum.request({
            method: "wallet_addEthereumChain",
            params: [EXPECTED_CHAIN],
          });
          return true;
        } catch (addError) {
          return false;
        }
      }
      return false;
    }
  }

  async function validateNetwork() {
    const network = await provider.getNetwork();
    const chainId = Number(network.chainId);

    if (chainId !== EXPECTED_CHAIN_ID) {
      const networkName = NETWORK_NAMES[chainId] || "Chain " + chainId;
      showToast(`Wrong network: ${networkName}. Switching to Ethereum mainnet...`, "error", true);

      const switched = await switchToExpectedNetwork();
      if (!switched) {
        showToast("Please switch to Ethereum mainnet", "error");
        return false;
      }
      return false;
    }
    return true;
  }

  /**
   * Initiates wallet connection flow.
   * Shows wallet selection modal if multiple wallets available.
   */
  async function connectWallet() {
    showWalletModal();
  }

  /**
   * Shows the wallet selection modal with all discovered wallets.
   * If only one wallet is found, connects directly without showing modal.
   */
  function showWalletModal() {
    const walletList = $("#wallet-list");
    walletList.innerHTML = "";

    const providers = Array.from(discoveredProviders.values());

    // No EIP-6963 wallets found - check for legacy window.ethereum
    if (providers.length === 0) {
      if (typeof window.ethereum !== "undefined") {
        // Single legacy wallet - connect directly
        connectWithProvider(window.ethereum, "Browser Wallet");
        return;
      }
      // No wallets at all
      showToast("No wallet found. Install MetaMask or another wallet.", "error");
      return;
    }

    // If only one EIP-6963 wallet, connect directly
    if (providers.length === 1) {
      const { info, provider: walletProvider } = providers[0];
      connectWithProvider(walletProvider, info.name);
      return;
    }

    // Multiple wallets - show selection modal
    providers.forEach(({ info, provider: walletProvider }) => {
      const btn = document.createElement("a");
      btn.href = "#";
      btn.className = "wallet-option";
      btn.textContent = `[${info.name}]`;

      btn.addEventListener("click", (e) => {
        e.preventDefault();
        $("#wallet-modal").classList.add("hidden");
        connectWithProvider(walletProvider, info.name);
      });

      walletList.appendChild(btn);
    });

    $("#wallet-modal").classList.remove("hidden");
  }

  /**
   * Connects to wallet using a specific EIP-1193 provider.
   * @param {Object} walletProvider - The EIP-1193 provider object
   * @param {string} walletName - Display name of the wallet (for toasts)
   */
  async function connectWithProvider(walletProvider, walletName) {
    try {
      selectedProvider = walletProvider;
      provider = new ethers.BrowserProvider(walletProvider);
      await provider.send("eth_requestAccounts", []);
      signer = await provider.getSigner();
      userAddress = await signer.getAddress();

      const validNetwork = await validateNetwork();
      if (!validNetwork) return;

      const network = await provider.getNetwork();
      updateNetworkIndicator(Number(network.chainId));

      contract = new ethers.Contract(CONFIG.CONTRACT_ADDRESS, CONTRACT_ABI, signer);

      if (!cachedWethAddress) {
        try {
          cachedWethAddress = (await contract.weth()).toLowerCase();
        } catch (e) {
          cachedWethAddress = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";
        }
      }

      $("#connect-btn").textContent = "[" + truncateAddress(userAddress) + "]";
      $("#sell-btn").classList.remove("hidden");
      $("#my-orders-label").classList.remove("hidden");
      updateWalletMenu();
      updateNotifyText();

      // Subscribe to contract events for real-time updates
      contract.on("OrderFilled", (orderId, taker) => {
        if (taker.toLowerCase() !== userAddress.toLowerCase()) {
          showNotification(
            "Order Filled",
            `Your order #${orderId} has been filled!`,
            "order-" + orderId
          );
        }
        loadOrders();
        loadStats();
      });

      contract.on("OrderCanceled", (orderId) => {
        showToast(`Order #${orderId} canceled`, "info");
        loadOrders();
        loadStats();
      });

      contract.on("OrderCreated", (orderId, maker, tokenA, amountA, tokenB, amountB) => {
        loadOrders();
        loadStats();
      });

      // Set up provider event listeners for the selected wallet
      setupProviderListeners(walletProvider);

      showToast(`Connected to ${walletName}`, "success");
      loadOrders();
    } catch (e) {
      console.error("Connect error:", e);
      if (e.code === 4001 || e.code === "ACTION_REJECTED") {
        showToast("Wallet connection cancelled", "info");
        return;
      }
      const msg = (e.message || "").toLowerCase();
      if (
        msg.includes("not connected") ||
        (e.error && e.error.message && e.error.message.toLowerCase().includes("not connected"))
      ) {
        showToast("Wallet not connected. Please unlock your wallet and try again.", "error");
        return;
      }
      if (msg.includes("user rejected") || msg.includes("user denied")) {
        showToast("Wallet connection cancelled", "info");
        return;
      }
      showToast("Connection failed. Please try again.", "error");
    }
  }

  /**
   * Sets up event listeners for the selected wallet provider.
   * @param {Object} walletProvider - The EIP-1193 provider object
   */
  function setupProviderListeners(walletProvider) {
    walletProvider.on("accountsChanged", (accounts) => {
      if (accounts.length === 0) {
        disconnectWallet();
        $("#sell-modal").classList.add("hidden");
      } else {
        connectWithProvider(walletProvider, "Wallet");
      }
    });

    walletProvider.on("chainChanged", (chainIdHex) => {
      const chainId = parseInt(chainIdHex, 16);
      if (chainId !== EXPECTED_CHAIN_ID) {
        showToast("Please switch to Ethereum mainnet", "error");
        disconnectWallet();
      } else {
        window.location.reload();
      }
    });
  }

  function disconnectWallet() {
    userAddress = null;
    signer = null;
    contract = null;
    selectedProvider = null;
    $("#connect-btn").textContent = "[Connect Wallet]";
    $("#sell-btn").classList.add("hidden");
    $("#network-indicator").classList.add("hidden");
    $("#my-orders-label").classList.add("hidden");
    $("#filter-my-orders").checked = false;
    currentFilters.myOrders = false;
    loadOrders();
  }

  function updateWalletMenu() {
    if (!userAddress) return;
    const etherscanBase = EXPECTED_CHAIN.blockExplorerUrls[0];
    $("#wallet-etherscan").href = etherscanBase + "/address/" + userAddress;
    provider
      .getBalance(userAddress)
      .then((bal) => {
        const eth = ethers.formatEther(bal);
        $("#wallet-balance").textContent = parseFloat(eth).toFixed(4) + " ETH";
      })
      .catch(() => {});
  }

  function applyWalletFilter(status) {
    document.querySelector(`input[name="status"][value="${status}"]`).checked = true;
    currentFilters.status = status;
    $("#filter-my-orders").checked = true;
    currentFilters.myOrders = true;
    currentPage = 1;
    loadOrders();
    $("#wallet-menu").classList.add("hidden");
  }

  function setRevokeStatus(el, className, text) {
    el.textContent = "";
    const div = document.createElement("div");
    div.className = className;
    div.textContent = text;
    el.appendChild(div);
  }

  async function loadUserApprovals() {
    const revokeList = $("#revoke-list");
    setRevokeStatus(revokeList, "revoke-loading", "Checking approvals...");

    const query = `{
      orders(
        where: { maker: "${userAddress.toLowerCase()}" }
        first: 1000
      ) {
        tokenA { address symbol decimals }
        tokenB { address symbol decimals }
      }
    }`;
    const data = await querySubgraph(query, {}, true);
    if (!data || !data.orders) {
      setRevokeStatus(revokeList, "revoke-empty", "Failed to load orders");
      return;
    }

    const tokenMap = new Map();
    for (const order of data.orders) {
      if (!tokenMap.has(order.tokenA.address)) {
        tokenMap.set(order.tokenA.address, order.tokenA);
      }
      if (!tokenMap.has(order.tokenB.address)) {
        tokenMap.set(order.tokenB.address, order.tokenB);
      }
    }

    const approvals = [];
    for (const [address, token] of tokenMap) {
      try {
        const tokenContract = new ethers.Contract(address, ERC20_ABI, provider);
        const allowance = await tokenContract.allowance(userAddress, CONFIG.CONTRACT_ADDRESS);
        if (allowance > 0n) {
          approvals.push({ address, symbol: token.symbol, decimals: token.decimals, allowance });
        }
      } catch (err) {
        console.error("Failed to check allowance for", address, err);
      }
    }

    if (approvals.length === 0) {
      setRevokeStatus(revokeList, "revoke-empty", "No active approvals");
      return;
    }

    revokeList.textContent = "";
    approvals.forEach((t) => {
      const amt =
        t.allowance === ethers.MaxUint256 ? "Unlimited" : formatAmount(t.allowance, t.decimals);
      const row = document.createElement("div");
      row.className = "revoke-row";
      row.dataset.address = t.address;
      const info = document.createElement("div");
      const symbolSpan = document.createElement("span");
      symbolSpan.className = "revoke-token";
      symbolSpan.textContent = t.symbol;
      const allowanceSpan = document.createElement("span");
      allowanceSpan.className = "revoke-allowance";
      allowanceSpan.textContent = amt;
      info.appendChild(symbolSpan);
      info.appendChild(allowanceSpan);
      const btn = document.createElement("button");
      btn.className = "revoke-btn";
      btn.dataset.address = t.address;
      btn.dataset.symbol = t.symbol;
      btn.textContent = "Revoke";
      row.appendChild(info);
      row.appendChild(btn);
      revokeList.appendChild(row);
    });
  }

  async function revokeApproval(tokenAddress, tokenSymbol) {
    try {
      showToast("Revoking approval for " + tokenSymbol + "...", "info", true);
      const tokenContract = new ethers.Contract(tokenAddress, ERC20_ABI, signer);
      const tx = await tokenContract.approve(CONFIG.CONTRACT_ADDRESS, 0);
      showToast("Waiting for confirmation...", "info", true);
      await tx.wait();
      showToast("Revoked approval for " + tokenSymbol, "success");
      const row = $(`.revoke-row[data-address="${tokenAddress}"]`);
      if (row) row.remove();
      const remaining = $$(".revoke-row").length;
      if (remaining === 0) {
        setRevokeStatus($("#revoke-list"), "revoke-empty", "No active approvals");
      }
    } catch (err) {
      console.error("Revoke failed:", err);
      if (err.code === 4001 || err.code === "ACTION_REJECTED") {
        showToast("Revoke cancelled", "error");
      } else {
        showToast("Failed to revoke approval", "error");
      }
    }
  }

  async function exportMyOrders() {
    const query = `{
      orders(
        where: { maker: "${userAddress.toLowerCase()}" }
        orderBy: orderId
        orderDirection: desc
        first: 1000
      ) {
        orderId
        maker
        amountA
        amountB
        active
        taker
        createdAt
        tokenA { address symbol decimals }
        tokenB { address symbol decimals }
      }
    }`;
    const data = await querySubgraph(query, {}, true);
    if (!data || !data.orders) {
      showToast("Failed to export orders", "error");
      return;
    }
    const headers = [
      "Trade ID",
      "Status",
      "Offered Token",
      "Offered Amount",
      "Wanted Token",
      "Wanted Amount",
      "Created",
      "Taker",
    ];
    const rows = data.orders.map((o) => {
      const status = o.active ? "Open" : o.taker ? "Filled" : "Cancelled";
      const amtA = o.tokenA.decimals
        ? (parseFloat(o.amountA) / Math.pow(10, o.tokenA.decimals)).toString()
        : o.amountA;
      const amtB = o.tokenB.decimals
        ? (parseFloat(o.amountB) / Math.pow(10, o.tokenB.decimals)).toString()
        : o.amountB;
      return [
        o.orderId,
        status,
        o.tokenA.symbol,
        amtA,
        o.tokenB.symbol,
        amtB,
        o.createdAt,
        o.taker || "",
      ];
    });
    const csvContent = [headers.join(","), ...rows.map((r) => r.join(","))].join("\n");
    const blob = new Blob([csvContent], { type: "text/csv;charset=utf-8;" });
    const link = document.createElement("a");
    link.href = URL.createObjectURL(blob);
    link.download = `swapboard-my-orders-${userAddress.slice(0, 8)}.csv`;
    link.click();
    URL.revokeObjectURL(link.href);
    showToast("Exported " + data.orders.length + " orders", "success");
  }

  async function switchWallet() {
    // Clear local state
    userAddress = null;
    signer = null;
    contract = null;
    selectedProvider = null;

    // Show wallet selection modal
    showWalletModal();
  }

  async function resolveBuildInfo() {
    const REPO = "https://github.com/ETHCF/swapboard";
    const API = "https://api.github.com/repos/ETHCF/swapboard";

    const buildLink = document.querySelector('footer a[title="View commit on GitHub"]');
    const hashEls = document.querySelectorAll(".verify-hash");

    const needsCommit = buildLink && buildLink.href.includes("__COMMIT_FULL__");
    const needsHashes = hashEls.length > 0 && hashEls[0].textContent.includes("__");

    if (!needsCommit && !needsHashes) return;

    if (needsCommit) {
      try {
        const res = await fetch(API + "/commits/main");
        if (res.ok) {
          const data = await res.json();
          const full = data.sha;
          const short = full.slice(0, 7);
          buildLink.href = REPO + "/commit/" + full;
          buildLink.textContent = "[Build: " + short + "]";
        }
      } catch (_) {}
    }

    if (needsHashes) {
      const fileMap = {
        __HASH_HTML__: "index.html",
        __HASH_APPJS__: "app.js",
        __HASH_LIBJS__: "lib.js",
        __HASH_CSS__: "style.css",
        __HASH_MOCK__: "mock.js",
      };
      for (const el of hashEls) {
        const placeholder = el.textContent.trim();
        const filename = fileMap[placeholder];
        if (!filename) continue;
        try {
          const res = await fetch(filename);
          if (!res.ok) continue;
          const buf = await res.arrayBuffer();
          const digest = await crypto.subtle.digest("SHA-256", buf);
          const hex = Array.from(new Uint8Array(digest))
            .map((b) => b.toString(16).padStart(2, "0"))
            .join("");
          el.textContent = hex.slice(0, 16) + "...";
        } catch (_) {}
      }
    }
  }

  function init() {
    if (typeof ethers === "undefined") {
      const script = document.createElement("script");
      script.src = "https://cdnjs.cloudflare.com/ajax/libs/ethers/6.15.0/ethers.umd.min.js";
      script.integrity =
        "sha512-UXYETj+vXKSURF1UlgVRLzWRS9ZiQTv3lcL4rbeLyqTXCPNZC6PTLF/Ik3uxm2Zo+E109cUpJPZfLxJsCgKSng==";
      script.crossOrigin = "anonymous";
      script.onload = initApp;
      script.onerror = () =>
        showToast("Failed to load ethers.js - integrity check may have failed", "error");
      document.head.appendChild(script);
    } else {
      initApp();
    }
  }

  function initApp() {
    // Initialize wallet discovery immediately (EIP-6963)
    setupEIP6963Discovery();

    validateConfig();

    // Before anything renders: the version decides the table's columns and
    // which controls exist at all.
    applyVersionUi();

    // Initialize dark mode from localStorage or system preference
    initTheme();

    // Populate contract link
    $("#contract-link").href =
      EXPECTED_CHAIN.blockExplorerUrls[0] + "/address/" + CONFIG.CONTRACT_ADDRESS;

    // Resolve build info if deploy.sh placeholders are unreplaced
    resolveBuildInfo();

    // Load saved preferences
    loadFilterPreferences();
    loadSortPreferences();

    // Apply loaded filter preferences to UI
    if (currentFilters.status) {
      const radio = $(`input[name="status"][value="${currentFilters.status}"]`);
      if (radio) radio.checked = true;
    }
    if (currentFilters.selling) {
      $("#filter-selling").value = currentFilters.selling;
    }
    if (currentFilters.wanting) {
      $("#filter-wanting").value = currentFilters.wanting;
    }

    // Check for order link in URL hash (overrides saved status filter)
    const linkedOrderId = getOrderIdFromHash();
    if (linkedOrderId) {
      highlightedOrderId = linkedOrderId;
      // Switch to "all" filter to find the order regardless of status
      currentFilters.status = "all";
      $('input[name="status"][value="all"]').checked = true;
    }

    // Keyboard shortcuts
    document.addEventListener("keydown", (e) => {
      // Ignore when typing in inputs
      if (e.target.tagName === "INPUT" || e.target.tagName === "TEXTAREA") {
        // Only handle Escape in inputs
        if (e.key === "Escape") {
          e.target.blur();
        }
        return;
      }

      // Ignore if modifier keys are pressed (except for ?)
      if (e.ctrlKey || e.altKey || e.metaKey) {
        return;
      }

      switch (e.key) {
        case "c":
          // Connect wallet
          if (!userAddress) {
            e.preventDefault();
            connectWallet();
          }
          break;

        case "s":
          // Open sell modal (when connected)
          if (userAddress && $("#sell-modal").classList.contains("hidden")) {
            e.preventDefault();
            $("#sell-modal").classList.remove("hidden");
          }
          break;

        case "Escape":
          // Close modals
          e.preventDefault();
          $("#modal").classList.add("hidden");
          $("#sell-modal").classList.add("hidden");
          $("#order-modal").classList.add("hidden");
          $("#wallet-modal").classList.add("hidden");
          // Clear hash when closing via escape
          if (window.location.hash) {
            history.pushState(
              "",
              document.title,
              window.location.pathname + window.location.search
            );
          }
          break;

        case "r":
          // Refresh orders
          e.preventDefault();
          loadOrders();
          loadStats();
          showToast("Refreshing...");
          break;

        case "?":
          // Show shortcuts help
          e.preventDefault();
          showModal(
            "Keyboard Shortcuts",
            "c - Connect wallet\ns - Sell tokens\nr - Refresh orders\nEsc - Close modals\n? - Show this help",
            () => {}
          );
          break;
      }
    });

    // Handle hash changes
    window.addEventListener("hashchange", () => {
      const newOrderId = getOrderIdFromHash();
      if (newOrderId) {
        // Try to find order in cache first
        const order = findOrderById(newOrderId);
        if (order) {
          openOrderModal(order);
        } else {
          // Order not in cache, switch to "all" filter and reload
          highlightedOrderId = newOrderId;
          currentFilters.status = "all";
          $('input[name="status"][value="all"]').checked = true;
          loadOrders();
        }
      } else {
        // Hash cleared, close order modal
        $("#order-modal").classList.add("hidden");
      }
    });

    // Load notification preference from localStorage
    if (
      localStorage.getItem("swapboard_notifications") === "true" &&
      Notification.permission === "granted"
    ) {
      notificationsEnabled = true;
    }

    $("#theme-btn").addEventListener("click", (e) => {
      e.preventDefault();
      toggleTheme();
    });

    $("#hash-toggle").addEventListener("click", (e) => {
      e.preventDefault();
      $("#verify-modal").classList.remove("hidden");
    });

    $("#verify-modal-close").addEventListener("click", () => {
      $("#verify-modal").classList.add("hidden");
    });

    $("#verify-modal").addEventListener("click", (e) => {
      if (e.target === $("#verify-modal")) {
        $("#verify-modal").classList.add("hidden");
      }
    });

    $("#connect-btn").addEventListener("click", (e) => {
      e.preventDefault();
      e.stopPropagation();
      if (userAddress) {
        $("#wallet-menu").classList.toggle("hidden");
      } else {
        connectWallet();
      }
    });

    document.addEventListener("click", (e) => {
      if (!e.target.closest(".wallet-dropdown")) {
        $("#wallet-menu").classList.add("hidden");
      }
    });

    $("#wallet-copy").addEventListener("click", (e) => {
      e.preventDefault();
      e.stopPropagation();
      navigator.clipboard.writeText(userAddress).then(() => {
        showToast("Address copied", "success");
      });
      $("#wallet-menu").classList.add("hidden");
    });

    $("#wallet-disconnect").addEventListener("click", (e) => {
      e.preventDefault();
      e.stopPropagation();
      disconnectWallet();
      $("#wallet-menu").classList.add("hidden");
    });

    $("#wallet-open-orders").addEventListener("click", (e) => {
      e.preventDefault();
      e.stopPropagation();
      applyWalletFilter("open");
    });

    $("#wallet-filled-orders").addEventListener("click", (e) => {
      e.preventDefault();
      e.stopPropagation();
      applyWalletFilter("filled");
    });

    $("#wallet-cancelled-orders").addEventListener("click", (e) => {
      e.preventDefault();
      e.stopPropagation();
      applyWalletFilter("cancelled");
    });

    $("#wallet-export").addEventListener("click", (e) => {
      e.preventDefault();
      e.stopPropagation();
      exportMyOrders();
      $("#wallet-menu").classList.add("hidden");
    });

    $("#wallet-revoke").addEventListener("click", (e) => {
      e.preventDefault();
      e.stopPropagation();
      $("#wallet-menu").classList.add("hidden");
      $("#revoke-modal").classList.remove("hidden");
      loadUserApprovals();
    });

    $("#revoke-modal-close").addEventListener("click", () => {
      $("#revoke-modal").classList.add("hidden");
    });

    $("#revoke-modal").addEventListener("click", (e) => {
      if (e.target === $("#revoke-modal")) {
        $("#revoke-modal").classList.add("hidden");
      }
    });

    $("#wallet-modal-cancel").addEventListener("click", (e) => {
      e.preventDefault();
      $("#wallet-modal").classList.add("hidden");
    });

    $("#wallet-modal").addEventListener("click", (e) => {
      if (e.target === $("#wallet-modal")) {
        $("#wallet-modal").classList.add("hidden");
      }
    });

    $("#revoke-list").addEventListener("click", (e) => {
      if (e.target.classList.contains("revoke-btn")) {
        const address = e.target.dataset.address;
        const symbol = e.target.dataset.symbol;
        e.target.disabled = true;
        e.target.textContent = "...";
        revokeApproval(address, symbol);
      }
    });

    $("#wallet-switch").addEventListener("click", (e) => {
      e.preventDefault();
      e.stopPropagation();
      $("#wallet-menu").classList.add("hidden");
      switchWallet();
    });

    $("#wallet-etherscan").addEventListener("click", (e) => {
      e.stopPropagation();
      $("#wallet-menu").classList.add("hidden");
    });

    $("#wallet-notifications").addEventListener("click", async (e) => {
      e.preventDefault();
      await toggleNotifications();
      updateNotifyText();
      $("#wallet-menu").classList.add("hidden");
    });

    $("#sell-btn").addEventListener("click", (e) => {
      e.preventDefault();
      $("#sell-modal").classList.remove("hidden");
    });

    $("#sell-modal-cancel").addEventListener("click", () => {
      $("#sell-modal").classList.add("hidden");
    });

    // Click outside to close modals
    $("#order-modal").addEventListener("click", (e) => {
      if (e.target === $("#order-modal")) {
        $("#order-modal").classList.add("hidden");
        if (window.location.hash) {
          history.pushState("", document.title, window.location.pathname + window.location.search);
        }
      }
    });

    $("#sell-modal").addEventListener("click", (e) => {
      if (e.target === $("#sell-modal")) {
        $("#sell-modal").classList.add("hidden");
      }
    });

    // Filter change handlers
    $("#filter-selling").addEventListener("change", () => {
      currentFilters.selling = $("#filter-selling").value;
      currentPage = 1;
      saveFilterPreferences();
      loadOrders();
    });

    $("#filter-wanting").addEventListener("change", () => {
      currentFilters.wanting = $("#filter-wanting").value;
      currentPage = 1;
      saveFilterPreferences();
      loadOrders();
    });

    // Radio button status filters
    document.querySelectorAll('input[name="status"]').forEach((radio) => {
      radio.addEventListener("change", () => {
        currentFilters.status = radio.value;
        currentPage = 1;
        saveFilterPreferences();
        loadOrders();
      });
    });

    // My Orders filter
    $("#filter-my-orders").addEventListener("change", () => {
      currentFilters.myOrders = $("#filter-my-orders").checked;
      currentPage = 1;
      loadOrders();
    });

    // Selection bar. Left unwired without batch entry points — the bar and its
    // checkboxes are hidden in that case, so there is nothing to listen to.
    if (CAPS.batch) {
      $("#select-all-orders").addEventListener("click", (e) => {
        e.preventDefault();
        selectAllOwnOrders();
      });

      $("#selection-clear").addEventListener("click", (e) => {
        e.preventDefault();
        clearSelection();
      });

      $("#batch-fill-btn").addEventListener("click", async (e) => {
        e.preventDefault();
        if (!userAddress) await connectWallet();
        if (userAddress) fillSelectedOrders();
      });

      $("#batch-cancel-btn").addEventListener("click", (e) => {
        e.preventDefault();
        cancelSelectedOrders();
      });
    }

    // Protocol version switcher
    document.querySelectorAll("#version-switch .version-option").forEach((btn) => {
      btn.addEventListener("click", () => setVersion(Number(btn.dataset.version)));
    });

    $("#prev-page").addEventListener("click", () => {
      if (currentPage > 1) {
        currentPage--;
        loadOrders();
      }
    });

    $("#next-page").addEventListener("click", () => {
      currentPage++;
      loadOrders();
    });

    // CSV Export
    $("#export-csv").addEventListener("click", () => {
      if (!cachedOrders || cachedOrders.length === 0) {
        showToast("No orders to export", "error");
        return;
      }

      // Build CSV content
      const headers = [
        "Trade ID",
        "Status",
        "Maker",
        "Offered Token",
        "Offered Symbol",
        "Offered Amount",
        "Wanted Token",
        "Wanted Symbol",
        "Wanted Amount",
        "Created At",
      ];
      const rows = cachedOrders.map((order) => {
        const tokenADecimals = parseInt(order.tokenA.decimals) || 18;
        const tokenBDecimals = parseInt(order.tokenB.decimals) || 18;
        const amountA = formatAmount(order.amountA, tokenADecimals);
        const amountB = formatAmount(order.amountB, tokenBDecimals);
        let status = "Open";
        if (!order.active) {
          status = order.taker ? "Filled" : "Cancelled";
        }
        const createdDate = new Date(parseInt(order.createdAt) * 1000).toISOString();

        return [
          order.orderId,
          status,
          order.maker,
          order.tokenA.address,
          order.tokenA.symbol,
          amountA,
          order.tokenB.address,
          order.tokenB.symbol,
          amountB,
          createdDate,
        ]
          .map((val) => {
            // Escape quotes and wrap in quotes if contains comma
            const str = String(val);
            if (str.includes(",") || str.includes('"') || str.includes("\n")) {
              return '"' + str.replace(/"/g, '""') + '"';
            }
            return str;
          })
          .join(",");
      });

      const csvContent = [headers.join(","), ...rows].join("\n");
      const blob = new Blob([csvContent], { type: "text/csv;charset=utf-8;" });
      const link = document.createElement("a");
      link.href = URL.createObjectURL(blob);
      link.download = "swapboard-orders-" + new Date().toISOString().split("T")[0] + ".csv";
      link.click();
      URL.revokeObjectURL(link.href);
      showToast("Exported " + cachedOrders.length + " orders", "success");
    });

    $("#create-btn").addEventListener("click", handleCreateOrder);

    $("#add-sell-btn").addEventListener("click", addCreateRow);

    // Start the Sell Tokens form with one empty order row
    resetCreateForm();

    // Rows attach their own autocomplete in addCreateRow(); this just warms
    // the token list they search against.
    fetchUniswapTokenList();

    // Sortable column headers
    document.querySelectorAll("thead th.sortable").forEach((th) => {
      th.addEventListener("click", (e) => {
        // Don't sort if clicking the swap icon
        if (e.target.classList.contains("swap-icon")) return;
        const col = th.dataset.sort;
        if (col) {
          handleSort(col);
        }
      });
    });

    if (window.ethereum) {
      provider = new ethers.BrowserProvider(window.ethereum);

      // Check for existing connection
      provider
        .send("eth_accounts", [])
        .then(async (accounts) => {
          if (accounts && accounts.length > 0) {
            signer = await provider.getSigner();
            userAddress = await signer.getAddress();

            const validNetwork = await validateNetwork();
            if (!validNetwork) return;

            const network = await provider.getNetwork();
            updateNetworkIndicator(Number(network.chainId));
            contract = new ethers.Contract(CONFIG.CONTRACT_ADDRESS, CONTRACT_ABI, signer);

            if (!cachedWethAddress) {
              try {
                cachedWethAddress = (await contract.weth()).toLowerCase();
              } catch (e) {
                cachedWethAddress = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";
              }
            }

            $("#connect-btn").textContent = "[" + truncateAddress(userAddress) + "]";
            $("#sell-btn").classList.remove("hidden");
            $("#my-orders-label").classList.remove("hidden");
            updateNotifyText();

            // Subscribe to contract events for real-time updates
            contract.on("OrderFilled", (orderId, taker) => {
              if (taker.toLowerCase() !== userAddress.toLowerCase()) {
                showNotification(
                  "Order Filled",
                  `Your order #${orderId} has been filled!`,
                  "order-" + orderId
                );
              }
              loadOrders();
              loadStats();
            });

            contract.on("OrderCanceled", (orderId) => {
              showToast(`Order #${orderId} canceled`, "info");
              loadOrders();
              loadStats();
            });

            contract.on("OrderCreated", (orderId, maker, tokenA, amountA, tokenB, amountB) => {
              loadOrders();
              loadStats();
            });

            loadOrders();
          }
        })
        .catch(() => {});
    }

    loadStats();
    loadPopularPairs();
    loadTokenFilters();
    loadOrders();

    // Start auto-refresh
    startAutoRefresh();
  }

  /**
   * Starts the auto-refresh interval for orders.
   */
  function startAutoRefresh() {
    if (autoRefreshInterval) {
      clearInterval(autoRefreshInterval);
    }
    autoRefreshInterval = setInterval(async () => {
      await loadOrders(true);
      await loadStats();
    }, AUTO_REFRESH_MS);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }

  // Register service worker for PWA support
  if ("serviceWorker" in navigator) {
    window.addEventListener("load", () => {
      navigator.serviceWorker.register("/sw.js").catch(() => {});
    });
  }
})();
