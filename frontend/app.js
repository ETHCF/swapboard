/**
 * @fileoverview Swapboard Frontend Application
 * @description Client-side application for interacting with the Swapboard smart contract.
 *              Handles wallet connection, order display, and transaction submission.
 * @author Swapboard Contributors
 * @license MIT
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

  // ============================================================================
  // Configuration
  // ============================================================================

  /**
   * Application configuration. Update these values before deployment.
   * @constant {Object}
   */
  const CONFIG = {
    // Contract address on Sepolia testnet
    CONTRACT_ADDRESS: "0xBe3D7A555aa633263110d10d37AB40Ef3a2b8BBa",
    // Goldsky subgraph endpoint (Sepolia)
    SUBGRAPH_URL: "https://api.goldsky.com/api/public/project_cmk2ptqkv97cw01xi85vph3la/subgraphs/swapboard-sepolia/1.0.0/gn",
    // Number of orders per page
    PAGE_SIZE: 20,
    // Request timeout in milliseconds
    REQUEST_TIMEOUT: 30000,
    // Debounce delay for token info fetch
    DEBOUNCE_DELAY: 500,
  };

  const EXPECTED_CHAIN_ID = 11155111;
  const EXPECTED_CHAIN = {
    chainId: "0xaa36a7",
    chainName: "Sepolia",
    nativeCurrency: { name: "Sepolia ETH", symbol: "ETH", decimals: 18 },
    rpcUrls: ["https://rpc.sepolia.org"],
    blockExplorerUrls: ["https://sepolia.etherscan.io"]
  };

  // Validate configuration - fail fast on placeholder values
  // Skips validation on localhost/file:// for development/testing
  function validateConfig() {
    const isLocal = window.location.hostname === "localhost"
      || window.location.hostname === "127.0.0.1"
      || window.location.protocol === "file:";

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
      const msg = "Configuration error: " + errors.join(", ") + ". Update CONFIG in app.js before deployment.";
      console.error(msg);
      document.body.innerHTML = '<div style="color:red;padding:20px;font-family:monospace;">' + msg + '</div>';
      throw new Error(msg);
    }
  }

  const CONTRACT_ABI = [
    "function createOrder(address tokenA, uint256 amountA, address tokenB, uint256 amountB) external returns (uint256 orderId)",
    "function fillOrder(uint256 orderId) external",
    "function cancelOrder(uint256 orderId) external",
    "function getOrder(uint256 orderId) external view returns (tuple(address maker, address tokenA, uint256 amountA, address tokenB, uint256 amountB, bool active))",
    "function getOrders(uint256[] orderIds) external view returns (tuple(address maker, address tokenA, uint256 amountA, address tokenB, uint256 amountB, bool active)[])",
    "function canFill(uint256 orderId) external view returns (bool)",
    "function nextOrderId() external view returns (uint256)",
    "event OrderCreated(uint256 indexed orderId, address indexed maker, address tokenA, uint256 amountA, address tokenB, uint256 amountB)",
    "event OrderFilled(uint256 indexed orderId, address indexed taker)",
    "event OrderCanceled(uint256 indexed orderId)",
    "error ZeroAddress()",
    "error ZeroAmount()",
    "error SameToken()",
    "error NotAContract(address token)",
    "error BalanceMismatch(uint256 expected, uint256 received)",
    "error OrderNotFound(uint256 orderId)",
    "error OrderNotActive(uint256 orderId)",
    "error NotMaker(uint256 orderId, address caller, address maker)"
  ];

  const ERC20_ABI = [
    "function name() view returns (string)",
    "function symbol() view returns (string)",
    "function decimals() view returns (uint8)",
    "function balanceOf(address) view returns (uint256)",
    "function allowance(address owner, address spender) view returns (uint256)",
    "function approve(address spender, uint256 amount) returns (bool)"
  ];

  let provider = null;
  let signer = null;
  let userAddress = null;
  let contract = null;

  // Create form state for validation
  const createFormState = {
    tokenA: { info: null, balance: null },
    tokenB: { info: null, balance: null }
  };

  const tokenCache = new Map();
  const ensCache = new Map();
  let currentPage = 1;
  let currentFilters = { selling: "", wanting: "", status: "open", myOrders: false };
  let currentSort = { column: "orderId", direction: "desc" };
  let cachedOrders = [];
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
  // Price Service (CoinGecko)
  // ============================================================================

  /**
   * Maps lowercase token addresses to CoinGecko coin IDs.
   * Only tokens in this registry can have USD prices displayed.
   * @constant {Object.<string, string>}
   */
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
        const url = "https://api.coingecko.com/api/v3/simple/price?ids=" +
          idsToFetch.join(",") + "&vs_currencies=usd";
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

  // ============================================================================
  // Utility Functions
  // ============================================================================

  /** @param {string} sel - CSS selector */
  const $ = (sel) => document.querySelector(sel);

  /**
   * Escapes HTML special characters to prevent XSS.
   * @param {string|null|undefined} str - String to escape
   * @returns {string} HTML-safe string
   */
  function escapeHtml(str) {
    if (str === null || str === undefined) return "";
    const div = document.createElement("div");
    div.textContent = String(str);
    return div.innerHTML;
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

    const uncached = addresses.filter(addr => !ensCache.has(addr.toLowerCase()));
    if (uncached.length === 0) return;

    // Resolve in parallel, limit to 10 concurrent lookups
    const batchSize = 10;
    for (let i = 0; i < uncached.length; i += batchSize) {
      const batch = uncached.slice(i, i + batchSize);
      await Promise.all(batch.map(addr => resolveEns(addr)));
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
    if (!notificationsEnabled || Notification.permission !== "granted") {
      return;
    }

    try {
      const notification = new Notification(title, {
        body: body,
        icon: "data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>S</text></svg>",
        tag: tag,
        requireInteraction: false
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
   * Estimates gas cost for a transaction and formats it for display.
   * @param {Object} txParams - Transaction parameters for estimation
   * @returns {Promise<{gas: string, eth: string, usd: string}|null>} Formatted gas costs or null on error
   */
  async function estimateGasCost(txParams) {
    if (!provider) return null;

    try {
      const [gasEstimate, feeData] = await Promise.all([
        provider.estimateGas(txParams),
        provider.getFeeData()
      ]);

      const gasPrice = feeData.gasPrice || feeData.maxFeePerGas;
      if (!gasPrice) return null;

      const gasCostWei = gasEstimate * gasPrice;
      const gasCostEth = Number(gasCostWei) / 1e18;

      // Get ETH price for USD estimate
      const ethPrice = getTokenPrice("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2");
      const gasCostUsd = ethPrice ? gasCostEth * ethPrice : null;

      return {
        gas: gasEstimate.toString(),
        eth: gasCostEth < 0.0001 ? gasCostEth.toExponential(2) : gasCostEth.toFixed(6),
        usd: gasCostUsd ? formatUsd(gasCostUsd) : "$ --"
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
        .filter(t => t.chainId === 1)
        .map(t => ({
          address: t.address.toLowerCase(),
          symbol: t.symbol,
          name: t.name,
          decimals: t.decimals,
          logoURI: t.logoURI
        }));

      console.log(`Loaded ${uniswapTokens.length} tokens from Uniswap list`);
    } catch (e) {
      console.error("Failed to fetch Uniswap token list:", e);
    }
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
      if ((t.symbol.toLowerCase().includes(q) || t.name.toLowerCase().includes(q)) && !results.includes(t)) {
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
      dropdown.innerHTML = "";
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
        img.onerror = () => { img.style.display = "none"; };
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
        const selected = Array.from(items).find(item => parseInt(item.dataset.index) === selectedIndex);
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
    const filtered = recent.filter(t => t.address.toLowerCase() !== lowerAddr);

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
    const status = order.active ? "Open" : (order.taker ? "Filled" : "Cancelled");
    watched[order.orderId] = {
      status: status,
      symbol: order.tokenA.symbol + "/" + order.tokenB.symbol
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

      const currentStatus = order.active ? "Open" : (order.taker ? "Filled" : "Cancelled");
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

      dropdown.innerHTML = "";
      const title = document.createElement("div");
      title.className = "recent-tokens-title";
      title.textContent = "Recent:";
      dropdown.appendChild(title);

      recent.forEach(token => {
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
    btn.innerHTML = "&#x29C9;";
    btn.classList.add("copy-btn");
    btn.title = "Copy to clipboard";
    btn.addEventListener("click", async (e) => {
      e.stopPropagation();
      try {
        await navigator.clipboard.writeText(text);
        btn.innerHTML = "&#x2713;";
        setTimeout(() => { btn.innerHTML = "&#x29C9;"; }, 1000);
      } catch (err) {
        console.error("Copy failed:", err);
      }
    });
    return btn;
  }

  /**
   * Formats a token amount for display with proper decimal handling.
   * @param {string|bigint} amount - Amount in base units
   * @param {number} decimals - Token decimals
   * @returns {string} Human-readable amount with thousands separators
   */
  function formatAmount(amount, decimals) {
    if (!amount) return "0";
    const str = amount.toString().padStart(decimals + 1, "0");
    const intPart = str.slice(0, -decimals) || "0";
    const decPart = str.slice(-decimals);
    const trimmed = decPart.replace(/0+$/, "");
    if (trimmed === "") return intPart.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
    return intPart.replace(/\B(?=(\d{3})+(?!\d))/g, ",") + "." + trimmed;
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

  let toastTimeout = null;
  function showToast(msg, type = "info", persistent = false) {
    const toast = $("#toast");
    if (msg.endsWith("...")) {
      toast.innerHTML = msg.slice(0, -3) + '<span class="loading-dots"></span>';
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
        default:
          return decoded.name;
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
    if (msg.includes("insufficient") || msg.includes("exceeds balance") ||
        msg.includes("transfer amount exceeds") || msg.includes("erc20: transfer amount")) {
      return "Insufficient token balance";
    }
    if (msg.includes("allowance") || msg.includes("erc20: insufficient allowance")) {
      return "Token approval failed";
    }
    if (msg.includes("nonce")) {
      return "Transaction conflict, try again";
    }
    if (msg.includes("missing revert data")) {
      return "Transaction failed. Order may already be filled or cancelled.";
    }
    if (msg.includes("gas") && msg.includes("estimation")) {
      return "Transaction would fail. Check order status and try again.";
    }
    return e.reason || e.shortMessage || e.message || "Unknown error";
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
          valA = amtA1 > 0n ? Number(amtB1) / Number(amtA1) * Math.pow(10, a.tokenA.decimals - a.tokenB.decimals) : 0;
          valB = amtA2 > 0n ? Number(amtB2) / Number(amtA2) * Math.pow(10, b.tokenA.decimals - b.tokenB.decimals) : 0;
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
    document.querySelectorAll("thead th[data-sort]").forEach(th => {
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
    tbody.innerHTML = "";

    for (let i = 0; i < count; i++) {
      const tr = document.createElement("tr");

      // Column 0: Action (empty)
      const tdAction = document.createElement("td");
      tdAction.dataset.label = "";
      tr.appendChild(tdAction);

      // Column 1: Trade ID
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

    const bodyEl = $("#modal-body");
    bodyEl.textContent = body;

    // Add gas estimate if available
    if (gasEstimate) {
      const gasDiv = document.createElement("div");
      gasDiv.className = "gas-estimate";
      gasDiv.innerHTML = "<br>Estimated gas: " + escapeHtml(gasEstimate.gas) +
        " (~" + escapeHtml(gasEstimate.eth) + " ETH / " + escapeHtml(gasEstimate.usd) + ")";
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
   * Opens the order detail modal for a specific order.
   * @param {Object} order - Order object with all metadata
   */
  function openOrderModal(order) {
    const modal = $("#order-modal");

    // Trade ID
    $("#order-modal-id").textContent = order.orderId;

    // Status
    const statusEl = $("#order-modal-status");
    statusEl.innerHTML = "";
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
    makerEl.innerHTML = "";
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
    offeredEl.innerHTML = "";
    const tokenADecimals = order.tokenA.decimals || 18;
    const amountA = BigInt(order.amountA);
    const formattedAmountA = formatAmount(amountA, tokenADecimals);
    const tokenAId = COINGECKO_ID_MAP[order.tokenA.address.toLowerCase()];
    if (tokenAId) {
      const tokenALink = document.createElement("a");
      tokenALink.href = "https://www.coingecko.com/en/coins/" + tokenAId;
      tokenALink.target = "_blank";
      tokenALink.textContent = formattedAmountA + " " + order.tokenA.symbol;
      offeredEl.appendChild(tokenALink);
    } else {
      offeredEl.textContent = formattedAmountA + " " + order.tokenA.symbol;
    }
    offeredEl.appendChild(createCopyButton(order.tokenA.address));

    // Wanted
    const wantedEl = $("#order-modal-wanted");
    wantedEl.innerHTML = "";
    const tokenBDecimals = order.tokenB.decimals || 18;
    const amountB = BigInt(order.amountB);
    const formattedAmountB = formatAmount(amountB, tokenBDecimals);
    const tokenBId = COINGECKO_ID_MAP[order.tokenB.address.toLowerCase()];
    if (tokenBId) {
      const tokenBLink = document.createElement("a");
      tokenBLink.href = "https://www.coingecko.com/en/coins/" + tokenBId;
      tokenBLink.target = "_blank";
      tokenBLink.textContent = formattedAmountB + " " + order.tokenB.symbol;
      wantedEl.appendChild(tokenBLink);
    } else {
      wantedEl.textContent = formattedAmountB + " " + order.tokenB.symbol;
    }
    wantedEl.appendChild(createCopyButton(order.tokenB.address));

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
      priceEl.innerHTML = "1 " + escapeHtml(order.tokenB.symbol) + " = " + priceAPerB.toFixed(6) + " " + escapeHtml(order.tokenA.symbol) + "<br>" +
                          "1 " + escapeHtml(order.tokenA.symbol) + " = " + priceBPerA.toFixed(6) + " " + escapeHtml(order.tokenB.symbol);
    } else {
      priceEl.textContent = "--";
    }

    // Market rate comparison
    const marketRow = $("#order-modal-market-row");
    const marketEl = $("#order-modal-market");
    const marketDev = calculateMarketDeviation(order);
    if (marketDev) {
      marketRow.style.display = "flex";
      marketEl.innerHTML = "";
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

    // Taker (only if filled)
    const takerRow = $("#order-modal-taker-row");
    const takerEl = $("#order-modal-taker");
    if (order.taker) {
      takerRow.style.display = "flex";
      takerEl.innerHTML = "";
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
    linkEl.innerHTML = "";
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
    actionsEl.innerHTML = "";

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
    watchBtn.title = isWatched ? "Stop watching this order" : "Get notified when this order is filled or cancelled";
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

  /**
   * Fetches ERC20 token metadata from the blockchain.
   * Results are cached to avoid redundant RPC calls.
   * @param {string} address - Token contract address
   * @returns {Promise<{address: string, symbol: string, name: string, decimals: number}>}
   */
  async function fetchTokenInfo(address) {
    const lowerAddr = address.toLowerCase();
    if (tokenCache.has(lowerAddr)) {
      return tokenCache.get(lowerAddr);
    }
    try {
      const tokenContract = new ethers.Contract(address, ERC20_ABI, provider);
      const [symbol, name, decimals] = await Promise.all([
        tokenContract.symbol().catch(() => "???"),
        tokenContract.name().catch(() => "Unknown"),
        tokenContract.decimals().catch(() => 18)
      ]);
      const safeSymbol = String(symbol).slice(0, 20);
      const safeName = String(name).slice(0, 100);
      const safeDecimals = Math.min(Math.max(Number(decimals) || 18, 0), 77);
      const info = { address, symbol: safeSymbol, name: safeName, decimals: safeDecimals };
      tokenCache.set(lowerAddr, info);
      return info;
    } catch (e) {
      const info = { address, symbol: "???", name: "Unknown", decimals: 18 };
      tokenCache.set(lowerAddr, info);
      return info;
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
  async function querySubgraph(query, variables = {}) {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), CONFIG.REQUEST_TIMEOUT);
    try {
      const res = await fetch(CONFIG.SUBGRAPH_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ query, variables }),
        signal: controller.signal
      });
      clearTimeout(timeoutId);
      if (!res.ok) {
        console.error("Subgraph HTTP error:", res.status);
        showToast("Failed to fetch data. Please try again.", "error");
        return null;
      }
      const json = await res.json();
      if (json.errors) {
        console.error("Subgraph error:", json.errors);
        showToast("Error loading data.", "error");
        return null;
      }
      return json.data;
    } catch (e) {
      clearTimeout(timeoutId);
      if (e.name === "AbortError") {
        showToast("Request timed out. Please try again.", "error");
      } else {
        console.error("Subgraph fetch error:", e);
        showToast("Network error. Check your connection.", "error");
      }
      return null;
    }
  }

  /**
   * Polls the subgraph until an order's active status changes.
   * Used after fill/cancel to wait for indexing before refreshing UI.
   * @param {string} orderId - The order ID to check
   * @param {boolean} expectedActive - The expected active status after the change
   * @param {number} maxAttempts - Maximum polling attempts (default 10)
   * @param {number} interval - Polling interval in ms (default 1500)
   */
  async function waitForOrderUpdate(orderId, expectedActive, maxAttempts = 10, interval = 1500) {
    for (let i = 0; i < maxAttempts; i++) {
      const data = await querySubgraph(`
        query {
          order(id: "${orderId}") {
            active
          }
        }
      `);
      if (data && data.order && data.order.active === expectedActive) {
        return true;
      }
      await new Promise(resolve => setTimeout(resolve, interval));
    }
    return false;
  }

  async function loadStats() {
    const data = await querySubgraph(`
      query {
        globalStats(id: "global") {
          totalOrders
          activeOrders
          filledOrders
          cancelledOrders
        }
      }
    `);

    if (data && data.globalStats) {
      const s = data.globalStats;
      $("#stat-total").textContent = formatNumber(s.totalOrders || "0");
      $("#stat-active").textContent = formatNumber(s.activeOrders || "0");
      $("#stat-filled").textContent = formatNumber(s.filledOrders || "0");
      $("#stat-cancelled").textContent = formatNumber(s.cancelledOrders || "0");
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
      pairsList.innerHTML = data.pairStats_collection
        .map(p => `<a href="#" class="pair-link" data-token-a="${escapeHtml(p.tokenA.address)}" data-token-b="${escapeHtml(p.tokenB.address)}">[${escapeHtml(p.tokenA.symbol)}/${escapeHtml(p.tokenB.symbol)}]</a>`)
        .join(" ");

      // Attach click handlers to pair links
      pairsList.querySelectorAll(".pair-link").forEach(link => {
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
      sellingSelect.innerHTML = '<option value="">All</option>';
      wantingSelect.innerHTML = '<option value="">All</option>';

      data.tokens.forEach(token => {
        const option1 = document.createElement("option");
        option1.value = token.address;
        option1.textContent = token.symbol;
        sellingSelect.appendChild(option1);

        const option2 = document.createElement("option");
        option2.value = token.address;
        option2.textContent = token.symbol;
        wantingSelect.appendChild(option2);
      });
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

    const data = await querySubgraph(`
      query {
        orders(first: ${CONFIG.PAGE_SIZE}, skip: ${skip}, orderBy: orderId, orderDirection: desc, ${where}) {
          orderId
          maker
          amountA
          amountB
          active
          taker
          createdAt
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
    } else {
      cachedOrders = data.orders;
    }

    // Check watched orders for status changes
    checkWatchedOrders(cachedOrders);

    // Filter to only watched orders if that filter is active
    if (currentFilters.status === "watched") {
      const watched = getWatchedOrders();
      cachedOrders = cachedOrders.filter(o => o.orderId in watched);
    }

    // Batch fetch prices for all tokenA and tokenB addresses
    if (cachedOrders.length > 0) {
      const tokenAddressesA = cachedOrders.map((o) => o.tokenA.address.toLowerCase());
      const tokenAddressesB = cachedOrders.map((o) => o.tokenB.address.toLowerCase());
      const allTokenAddresses = [...new Set([...tokenAddressesA, ...tokenAddressesB])];
      const coinGeckoIds = allTokenAddresses
        .map((addr) => COINGECKO_ID_MAP[addr])
        .filter(Boolean);

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

  function renderOrders() {
    const tbody = $("#order-table");
    tbody.innerHTML = "";

    if (cachedOrders.length === 0) {
      const tr = document.createElement("tr");
      const td = document.createElement("td");
      td.colSpan = 9;
      td.textContent = "No orders found";
      tr.appendChild(td);
      tbody.appendChild(tr);
      updatePagination(0);
      return;
    }

    const sortedOrders = sortOrders(cachedOrders);

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

      // Price: calculate both directions for toggle
      let priceNormal = "N/A";
      let priceInverted = "N/A";
      if (amountA > 0n && amountB > 0n) {
        const priceNum = Number(amountB) / Number(amountA) * Math.pow(10, tokenADecimals - tokenBDecimals);
        const priceNumInv = Number(amountA) / Number(amountB) * Math.pow(10, tokenBDecimals - tokenADecimals);
        priceNormal = formatRatio(priceNum) + " " + escapeHtml(order.tokenB.symbol) + "/" + escapeHtml(order.tokenA.symbol);
        priceInverted = formatRatio(priceNumInv) + " " + escapeHtml(order.tokenA.symbol) + "/" + escapeHtml(order.tokenB.symbol);
      }

      // Calculate USD value of sell side
      const tokenAPrice = getTokenPrice(order.tokenA.address);
      let usdVal = "$ --";
      if (tokenAPrice !== null && amountA > 0n) {
        const humanAmountA = Number(amountA) / Math.pow(10, tokenADecimals);
        usdVal = formatUsd(humanAmountA * tokenAPrice);
      }

      // Build row with links
      // Column 0: Action button (Fill for others, Cancel for own) or status
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
      }
      tr.appendChild(tdAction);

      // Column 1: Trade ID (clickable to open detail modal)
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

      // Column 2: Maker (link to Etherscan + copy, show ENS if available)
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

      // Column 3: Offered Token (link to CoinGecko + copy)
      const tdTokenA = document.createElement("td");
      tdTokenA.dataset.label = "Offered";
      const tokenAWrap = document.createElement("span");
      tokenAWrap.style.whiteSpace = "nowrap";
      const tokenAId = COINGECKO_ID_MAP[order.tokenA.address.toLowerCase()];
      if (tokenAId) {
        const tokenALink = document.createElement("a");
        tokenALink.href = "https://www.coingecko.com/en/coins/" + tokenAId;
        tokenALink.target = "_blank";
        tokenALink.rel = "noopener noreferrer";
        tokenALink.textContent = order.tokenA.symbol;
        tokenAWrap.appendChild(tokenALink);
      } else {
        const tokenASpan = document.createElement("span");
        tokenASpan.textContent = order.tokenA.symbol;
        tokenAWrap.appendChild(tokenASpan);
      }
      tokenAWrap.appendChild(createCopyButton(order.tokenA.address));
      tdTokenA.appendChild(tokenAWrap);
      tdTokenA.title = order.tokenA.address;
      tr.appendChild(tdTokenA);

      // Column 4: Sell Size
      const tdAmountA = document.createElement("td");
      tdAmountA.dataset.label = "Offered Size";
      tdAmountA.textContent = formatAmount(order.amountA, tokenADecimals);
      tr.appendChild(tdAmountA);

      // Column 5: Wanted Token (link to CoinGecko + copy)
      const tdTokenB = document.createElement("td");
      tdTokenB.dataset.label = "Wanted";
      const tokenBWrap = document.createElement("span");
      tokenBWrap.style.whiteSpace = "nowrap";
      const tokenBId = COINGECKO_ID_MAP[order.tokenB.address.toLowerCase()];
      if (tokenBId) {
        const tokenBLink = document.createElement("a");
        tokenBLink.href = "https://www.coingecko.com/en/coins/" + tokenBId;
        tokenBLink.target = "_blank";
        tokenBLink.rel = "noopener noreferrer";
        tokenBLink.textContent = order.tokenB.symbol;
        tokenBWrap.appendChild(tokenBLink);
      } else {
        const tokenBSpan = document.createElement("span");
        tokenBSpan.textContent = order.tokenB.symbol;
        tokenBWrap.appendChild(tokenBSpan);
      }
      tokenBWrap.appendChild(createCopyButton(order.tokenB.address));
      tdTokenB.appendChild(tokenBWrap);
      tdTokenB.title = order.tokenB.address;
      tr.appendChild(tdTokenB);

      // Column 6: Wanted Size
      const tdAmountB = document.createElement("td");
      tdAmountB.dataset.label = "Wanted Size";
      tdAmountB.textContent = formatAmount(order.amountB, tokenBDecimals);
      tr.appendChild(tdAmountB);

      // Column 7: USD Val (nowrap to keep $ and value on same line)
      const tdUsd = document.createElement("td");
      tdUsd.dataset.label = "USD Val";
      tdUsd.textContent = usdVal;
      tdUsd.style.whiteSpace = "nowrap";
      tr.appendChild(tdUsd);

      // Column 8: Price (clickable to invert ratio) + market deviation
      const tdPrice = document.createElement("td");
      tdPrice.dataset.label = "Price";
      const priceSpan = document.createElement("span");
      priceSpan.textContent = priceNormal;
      tdPrice.appendChild(priceSpan);

      // Add market deviation indicator
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

      if (priceNormal !== "N/A") {
        tdPrice.dataset.priceNormal = priceNormal;
        tdPrice.dataset.priceInverted = priceInverted;
        tdPrice.dataset.showingNormal = "true";
        tdPrice.classList.add("price-cell");
        tdPrice.title = "Click to invert ratio";
        tdPrice.addEventListener("click", function(e) {
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
  // Order Actions
  // ============================================================================

  /**
   * Handles the fill order flow: confirms with user, approves tokens, fills.
   * @param {Object} order - Order object from subgraph
   */
  async function handleFillOrder(order) {
    if (!signer) {
      showToast("Connect wallet first", "error");
      return;
    }

    const amountBStr = formatAmount(order.amountB, order.tokenB.decimals);
    const amountAStr = formatAmount(order.amountA, order.tokenA.decimals);

    // Estimate gas cost
    showToast("Estimating gas...");
    let gasEstimate = null;
    try {
      const txData = contract.interface.encodeFunctionData("fillOrder", [order.orderId]);
      gasEstimate = await estimateGasCost({
        from: userAddress,
        to: CONFIG.CONTRACT_ADDRESS,
        data: txData
      });
    } catch (e) {
      console.error("Gas estimation failed:", e);
    }

    showModal(
      "Fill Order #" + order.orderId,
      `You will send ${amountBStr} ${order.tokenB.symbol} and receive ${amountAStr} ${order.tokenA.symbol} in return.`,
      async () => {
        try {
          const isLocal = window.location.hostname === "localhost"
            || window.location.hostname === "127.0.0.1"
            || window.location.protocol === "file:";

          if (!isLocal) {
            showToast("Checking allowance...", "info", true);
            const tokenContract = new ethers.Contract(order.tokenB.address, ERC20_ABI, signer);
            const allowance = await tokenContract.allowance(userAddress, CONFIG.CONTRACT_ADDRESS);
            const amountB = BigInt(order.amountB);

            if (allowance < amountB) {
              showToast("Approve tokens in wallet...", "info", true);
              const approveTx = await tokenContract.approve(CONFIG.CONTRACT_ADDRESS, amountB);
              showToast("Waiting for approval tx...", "info", true);
              await approveTx.wait();
              showToast("Approval confirmed");
            }
          }

          showToast("Confirm fill in wallet...", "info", true);
          const tx = await contract.fillOrder(order.orderId);
          showToast("Waiting for tx confirmation...", "info", true);
          await tx.wait();
          showToast("Order filled! Updating...", "success", true);
          await waitForOrderUpdate(order.orderId, false);
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

  async function handleCancelOrder(order) {
    if (!signer) {
      showToast("Connect wallet first", "error");
      return;
    }

    const amountAStr = formatAmount(order.amountA, order.tokenA.decimals);

    // Estimate gas cost
    showToast("Estimating gas...");
    let gasEstimate = null;
    try {
      const txData = contract.interface.encodeFunctionData("cancelOrder", [order.orderId]);
      gasEstimate = await estimateGasCost({
        from: userAddress,
        to: CONFIG.CONTRACT_ADDRESS,
        data: txData
      });
    } catch (e) {
      console.error("Gas estimation failed:", e);
    }

    showModal(
      "Cancel Order #" + order.orderId,
      `Your ${amountAStr} ${order.tokenA.symbol} will be returned to your wallet.`,
      async () => {
        try {
          showToast("Cancelling order...");
          const tx = await contract.cancelOrder(order.orderId);
          await tx.wait();
          showToast("Order cancelled! Updating...", "success", true);
          await waitForOrderUpdate(order.orderId, false);
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

  async function handleCreateOrder() {
    if (!signer) {
      showToast("Connect wallet first", "error");
      return;
    }

    const tokenAAddr = $("#create-tokenA").value.trim();
    const tokenBAddr = $("#create-tokenB").value.trim();
    const amountAStr = $("#create-amountA").value.trim();
    const amountBStr = $("#create-amountB").value.trim();

    if (!tokenAAddr || !tokenBAddr || !amountAStr || !amountBStr) {
      showToast("Fill in all fields", "error");
      return;
    }

    if (!isValidAddress(tokenAAddr) || !isValidAddress(tokenBAddr)) {
      showToast("Invalid token address format", "error");
      return;
    }

    try {
      const tokenA = await fetchTokenInfo(tokenAAddr);
      const tokenB = await fetchTokenInfo(tokenBAddr);

      let amountA, amountB;
      try {
        amountA = parseAmount(amountAStr, tokenA.decimals);
        amountB = parseAmount(amountBStr, tokenB.decimals);
      } catch (e) {
        showToast(e.message, "error");
        return;
      }

      if (amountA === 0n || amountB === 0n) {
        showToast("Amounts must be greater than 0", "error");
        return;
      }

      // Check balance for offered token
      if (createFormState.tokenA.balance !== null && amountA > createFormState.tokenA.balance) {
        showToast("Insufficient balance for offered token", "error");
        return;
      }

      showModal(
        "Create Order",
        `Sell ${amountAStr} ${tokenA.symbol} for ${amountBStr} ${tokenB.symbol}`,
        async () => {
          const createBtn = $("#create-btn");
          const originalText = createBtn.textContent;
          createBtn.disabled = true;
          createBtn.innerHTML = 'Processing<span class="loading-dots"></span>';

          try {
            showToast("Checking allowance...", "info", true);
            const tokenContract = new ethers.Contract(tokenAAddr, ERC20_ABI, signer);
            const allowance = await tokenContract.allowance(userAddress, CONFIG.CONTRACT_ADDRESS);

            if (allowance < amountA) {
              createBtn.innerHTML = 'Approving<span class="loading-dots"></span>';
              showToast("Approve tokens in wallet...", "info", true);
              const approveTx = await tokenContract.approve(CONFIG.CONTRACT_ADDRESS, amountA);
              showToast("Waiting for approval tx...", "info", true);
              await approveTx.wait();
              showToast("Approval confirmed");
            }

            createBtn.innerHTML = 'Creating<span class="loading-dots"></span>';
            showToast("Confirm order in wallet...", "info", true);
            const tx = await contract.createOrder(tokenAAddr, amountA, tokenBAddr, amountB);
            showToast("Waiting for tx confirmation...", "info", true);
            const receipt = await tx.wait();
            showToast("Order created! Updating...", "success", true);

            // Save tokens to recent list
            addRecentToken(tokenAAddr, tokenA.symbol);
            addRecentToken(tokenBAddr, tokenB.symbol);

            $("#create-tokenA").value = "";
            $("#create-tokenB").value = "";
            $("#create-amountA").value = "";
            $("#create-amountB").value = "";
            $("#tokenA-info").textContent = "";
            $("#tokenB-info").textContent = "";
            $("#tokenA-balance").textContent = "";
            $("#tokenB-balance").textContent = "";
            $("#price-info").innerHTML = "";
            $("#sell-modal").classList.add("hidden");

            // Get order ID from event and wait for subgraph to index
            const orderCreatedEvent = receipt.logs
              .map(log => { try { return contract.interface.parseLog(log); } catch { return null; } })
              .find(parsed => parsed && parsed.name === "OrderCreated");
            if (orderCreatedEvent) {
              const newOrderId = orderCreatedEvent.args.orderId.toString();
              console.log("Order created with ID:", newOrderId);
              const indexed = await waitForOrderUpdate(newOrderId, true, 15, 2000);
              if (!indexed) {
                console.log("Subgraph indexing timeout for order", newOrderId);
              }
            } else {
              console.log("Could not parse OrderCreated event, waiting...");
              // Fallback: wait a bit for indexing
              await new Promise(resolve => setTimeout(resolve, 5000));
            }
            loadOrders();
            loadStats();
            showToast("Order created!", "success");
          } catch (e) {
            console.error("Create error:", e);
            showToast("Create failed: " + parseContractError(e), "error");
          } finally {
            createBtn.disabled = false;
            createBtn.textContent = originalText;
          }
        }
      );
    } catch (e) {
      console.error("Token info error:", e);
      showToast("Failed to load token info", "error");
    }
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
        params: [{ chainId: EXPECTED_CHAIN.chainId }]
      });
      return true;
    } catch (switchError) {
      if (switchError.code === 4902) {
        try {
          await window.ethereum.request({
            method: "wallet_addEthereumChain",
            params: [EXPECTED_CHAIN]
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
      showToast(`Wrong network: ${networkName}. Switching to Sepolia...`, "error", true);

      const switched = await switchToExpectedNetwork();
      if (!switched) {
        showToast("Please switch to Sepolia network in your wallet", "error");
        return false;
      }
      return false;
    }
    return true;
  }

  /**
   * Connects to the user's Ethereum wallet via window.ethereum (MetaMask, etc).
   * Sets up the ethers provider, signer, and contract instance.
   */
  async function connectWallet() {
    if (typeof window.ethereum === "undefined") {
      showToast("No wallet found. Install MetaMask.", "error");
      return;
    }
    try {
      provider = new ethers.BrowserProvider(window.ethereum);
      await provider.send("eth_requestAccounts", []);
      signer = await provider.getSigner();
      userAddress = await signer.getAddress();

      const validNetwork = await validateNetwork();
      if (!validNetwork) return;

      const network = await provider.getNetwork();
      updateNetworkIndicator(Number(network.chainId));

      contract = new ethers.Contract(CONFIG.CONTRACT_ADDRESS, CONTRACT_ABI, signer);

      $("#connect-btn").textContent = "[" + truncateAddress(userAddress) + "]";
      $("#sell-btn").classList.remove("hidden");
      $("#notify-btn").classList.remove("hidden");
      $("#my-orders-label").classList.remove("hidden");

      // Subscribe to contract events for real-time updates
      contract.on("OrderFilled", (orderId, taker) => {
        console.log(`Order ${orderId} filled by ${taker}`);
        // Notify if user's order was filled by someone else
        if (taker.toLowerCase() !== userAddress.toLowerCase()) {
          showNotification("Order Filled", `Your order #${orderId} has been filled!`, "order-" + orderId);
        }
        loadOrders();
        loadStats();
      });

      contract.on("OrderCanceled", (orderId) => {
        console.log(`Order ${orderId} canceled`);
        showToast(`Order #${orderId} canceled`, "info");
        loadOrders();
        loadStats();
      });

      contract.on("OrderCreated", (orderId, maker, tokenA, amountA, tokenB, amountB) => {
        console.log(`Order ${orderId} created by ${maker}`);
        loadOrders();
        loadStats();
      });

      showToast("Wallet connected", "success");
      loadOrders();
    } catch (e) {
      console.error("Connect error:", e);
      showToast("Connection failed: " + e.message, "error");
    }
  }

  function setupTokenInfoFetch(inputId, infoId, balanceId, quickAmountsId) {
    const input = $(inputId);
    let timeout = null;
    let currentTokenInfo = null;

    input.addEventListener("input", () => {
      clearTimeout(timeout);
      const addr = input.value.trim();

      if (!isValidAddress(addr)) {
        $(infoId).textContent = addr ? "Invalid address" : "";
        if (balanceId) $(balanceId).textContent = "";
        if (quickAmountsId) $(quickAmountsId).innerHTML = "";
        currentTokenInfo = null;
        return;
      }

      timeout = setTimeout(async () => {
        $(infoId).textContent = "Loading...";
        if (balanceId) $(balanceId).textContent = "";
        if (quickAmountsId) $(quickAmountsId).innerHTML = "";

        const info = await fetchTokenInfo(addr);
        currentTokenInfo = info;

        // Show token info with CoinGecko verification link if available
        const infoEl = $(infoId);
        infoEl.innerHTML = "";

        const coinGeckoId = COINGECKO_ID_MAP[addr.toLowerCase()];
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
        } else {
          // Unknown token - show warning
          const symbolSpan = document.createElement("span");
          symbolSpan.textContent = info.symbol;
          infoEl.appendChild(symbolSpan);
          infoEl.appendChild(document.createTextNode(" (" + info.decimals + " decimals) "));

          const warnSpan = document.createElement("span");
          warnSpan.className = "token-warning";
          warnSpan.textContent = "[unknown token]";
          warnSpan.title = "This token is not in our verified list. Double-check the address.";
          infoEl.appendChild(warnSpan);
        }

        // Store token info in form state
        const stateKey = inputId === "#create-tokenA" ? "tokenA" : "tokenB";
        createFormState[stateKey].info = info;
        createFormState[stateKey].balance = null;

        // Fetch balance if connected
        if (balanceId && userAddress && provider) {
          try {
            const tokenContract = new ethers.Contract(addr, ERC20_ABI, provider);
            const balance = await tokenContract.balanceOf(userAddress);
            createFormState[stateKey].balance = balance;
            const formatted = formatAmount(balance.toString(), info.decimals);
            $(balanceId).textContent = "Balance: " + formatted;

            // Validate amount if already entered
            const amountInputId = inputId === "#create-tokenA" ? "#create-amountA" : "#create-amountB";
            validateAmountInput(amountInputId, stateKey);

            // Add quick amount buttons
            if (quickAmountsId && balance > 0n) {
              $(quickAmountsId).innerHTML = "";
              [25, 50, 75, 100].forEach(pct => {
                const btn = document.createElement("button");
                btn.type = "button";
                btn.textContent = pct + "%";
                btn.classList.add("quick-amt-btn");
                btn.addEventListener("click", () => {
                  const amt = (balance * BigInt(pct)) / 100n;
                  $(amountInputId).value = formatAmount(amt.toString(), info.decimals);
                  $(amountInputId).dispatchEvent(new Event("input"));
                });
                $(quickAmountsId).appendChild(btn);
              });
            }
          } catch (e) {
            console.error("Balance fetch error:", e);
          }
        }
      }, CONFIG.DEBOUNCE_DELAY);
    });

    // Clear state when token address is cleared
    input.addEventListener("input", () => {
      if (!input.value.trim()) {
        const stateKey = inputId === "#create-tokenA" ? "tokenA" : "tokenB";
        createFormState[stateKey].info = null;
        createFormState[stateKey].balance = null;
      }
    });
  }

  function validateAmountInput(amountInputId, stateKey) {
    const input = $(amountInputId);
    const state = createFormState[stateKey];
    const errorSpanId = amountInputId + "-error";
    let errorSpan = document.getElementById(errorSpanId.slice(1));

    if (!errorSpan) {
      errorSpan = document.createElement("span");
      errorSpan.id = errorSpanId.slice(1);
      errorSpan.className = "amount-error";
      input.parentNode.appendChild(errorSpan);
    }

    const value = input.value.trim();
    if (!value || !state.info) {
      input.classList.remove("input-error");
      errorSpan.textContent = "";
      return true;
    }

    try {
      const amount = parseAmount(value, state.info.decimals);

      // Check if amount exceeds balance (only for tokenA - offered token)
      if (stateKey === "tokenA" && state.balance !== null && amount > state.balance) {
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
    } catch (e) {
      input.classList.add("input-error");
      errorSpan.textContent = e.message.includes("decimals") ? `Max ${state.info.decimals} decimals` : "Invalid amount";
      return false;
    }
  }

  function init() {
    if (typeof ethers === "undefined") {
      const script = document.createElement("script");
      script.src = "https://cdnjs.cloudflare.com/ajax/libs/ethers/6.15.0/ethers.umd.min.js";
      script.integrity = "sha512-UXYETj+vXKSURF1UlgVRLzWRS9ZiQTv3lcL4rbeLyqTXCPNZC6PTLF/Ik3uxm2Zo+E109cUpJPZfLxJsCgKSng==";
      script.crossOrigin = "anonymous";
      script.onload = initApp;
      script.onerror = () => showToast("Failed to load ethers.js - integrity check may have failed", "error");
      document.head.appendChild(script);
    } else {
      initApp();
    }
  }

  function initApp() {
    validateConfig();

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
          // Clear hash when closing via escape
          if (window.location.hash) {
            history.pushState("", document.title, window.location.pathname + window.location.search);
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
    if (localStorage.getItem("swapboard_notifications") === "true" && Notification.permission === "granted") {
      notificationsEnabled = true;
      $("#notify-btn").textContent = "[Notify: On]";
    }

    $("#connect-btn").addEventListener("click", (e) => {
      e.preventDefault();
      connectWallet();
    });

    $("#notify-btn").addEventListener("click", async (e) => {
      e.preventDefault();
      await toggleNotifications();
      $("#notify-btn").textContent = notificationsEnabled ? "[Notify: On]" : "[Notify: Off]";
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
      const headers = ["Trade ID", "Status", "Maker", "Offered Token", "Offered Symbol", "Offered Amount", "Wanted Token", "Wanted Symbol", "Wanted Amount", "Created At"];
      const rows = cachedOrders.map(order => {
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
          createdDate
        ].map(val => {
          // Escape quotes and wrap in quotes if contains comma
          const str = String(val);
          if (str.includes(",") || str.includes('"') || str.includes("\n")) {
            return '"' + str.replace(/"/g, '""') + '"';
          }
          return str;
        }).join(",");
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

    setupTokenInfoFetch("#create-tokenA", "#tokenA-info", "#tokenA-balance", "#quick-amounts-A");
    setupTokenInfoFetch("#create-tokenB", "#tokenB-info", "#tokenB-balance", null);

    // Add token selectors with Uniswap token list
    fetchUniswapTokenList().then(() => {
      createTokenSelector($("#create-tokenA"));
      createTokenSelector($("#create-tokenB"));
    });

    // Price calculator - show price based on amounts
    function updatePriceDisplay() {
      const amountAStr = $("#create-amountA").value.trim();
      const amountBStr = $("#create-amountB").value.trim();
      const tokenASymbol = $("#tokenA-info").textContent.split(" ")[0] || "Token A";
      const tokenBSymbol = $("#tokenB-info").textContent.split(" ")[0] || "Token B";

      const amountA = parseFloat(amountAStr);
      const amountB = parseFloat(amountBStr);

      if (!isNaN(amountA) && !isNaN(amountB) && amountA > 0 && amountB > 0) {
        const priceAPerB = amountA / amountB;
        const priceBPerA = amountB / amountA;
        $("#price-info").innerHTML =
          `1 ${tokenBSymbol} = ${priceAPerB.toFixed(6).replace(/\.?0+$/, "")} ${tokenASymbol}<br>` +
          `1 ${tokenASymbol} = ${priceBPerA.toFixed(6).replace(/\.?0+$/, "")} ${tokenBSymbol}`;
      } else {
        $("#price-info").innerHTML = "";
      }
    }

    $("#create-amountA").addEventListener("input", () => {
      updatePriceDisplay();
      validateAmountInput("#create-amountA", "tokenA");
    });
    $("#create-amountB").addEventListener("input", () => {
      updatePriceDisplay();
      validateAmountInput("#create-amountB", "tokenB");
    });

    // Clear price info when tokens change
    $("#create-tokenA").addEventListener("input", () => {
      $("#price-info").innerHTML = "";
    });
    $("#create-tokenB").addEventListener("input", () => {
      $("#price-info").innerHTML = "";
    });

    // Sortable column headers
    document.querySelectorAll("thead th.sortable").forEach(th => {
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
      provider.send("eth_accounts", []).then(async (accounts) => {
        if (accounts && accounts.length > 0) {
          signer = await provider.getSigner();
          userAddress = await signer.getAddress();

          const validNetwork = await validateNetwork();
          if (!validNetwork) return;

          const network = await provider.getNetwork();
          updateNetworkIndicator(Number(network.chainId));
          contract = new ethers.Contract(CONFIG.CONTRACT_ADDRESS, CONTRACT_ABI, signer);
          $("#connect-btn").textContent = "[" + truncateAddress(userAddress) + "]";
          $("#sell-btn").classList.remove("hidden");
          $("#notify-btn").classList.remove("hidden");
          $("#my-orders-label").classList.remove("hidden");

          // Subscribe to contract events for real-time updates
          contract.on("OrderFilled", (orderId, taker) => {
            console.log(`Order ${orderId} filled by ${taker}`);
            if (taker.toLowerCase() !== userAddress.toLowerCase()) {
              showNotification("Order Filled", `Your order #${orderId} has been filled!`, "order-" + orderId);
            }
            loadOrders();
            loadStats();
          });

          contract.on("OrderCanceled", (orderId) => {
            console.log(`Order ${orderId} canceled`);
            showToast(`Order #${orderId} canceled`, "info");
            loadOrders();
            loadStats();
          });

          contract.on("OrderCreated", (orderId, maker, tokenA, amountA, tokenB, amountB) => {
            console.log(`Order ${orderId} created by ${maker}`);
            loadOrders();
            loadStats();
          });

          loadOrders();
        }
      }).catch(() => {});

      window.ethereum.on("accountsChanged", (accounts) => {
        if (accounts.length === 0) {
          userAddress = null;
          signer = null;
          contract = null;
          $("#connect-btn").textContent = "[Connect Wallet]";
          $("#sell-btn").classList.add("hidden");
          $("#notify-btn").classList.add("hidden");
          $("#network-indicator").classList.add("hidden");
          $("#sell-modal").classList.add("hidden");
          $("#my-orders-label").classList.add("hidden");
          $("#filter-my-orders").checked = false;
          currentFilters.myOrders = false;
        } else {
          connectWallet();
        }
        loadOrders();
      });

      window.ethereum.on("chainChanged", (chainIdHex) => {
        const chainId = parseInt(chainIdHex, 16);
        if (chainId !== EXPECTED_CHAIN_ID) {
          showToast("Please switch to Sepolia network", "error");
          userAddress = null;
          signer = null;
          contract = null;
          $("#connect-btn").textContent = "[Connect Wallet]";
          $("#sell-btn").classList.add("hidden");
          $("#notify-btn").classList.add("hidden");
          document.getElementById("network-indicator").classList.add("hidden");
          $("#my-orders-label").classList.add("hidden");
          $("#filter-my-orders").checked = false;
          currentFilters.myOrders = false;
          loadOrders();
        } else {
          window.location.reload();
        }
      });
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
      navigator.serviceWorker.register("/sw.js").then(
        (registration) => {
          console.log("ServiceWorker registered:", registration.scope);
        },
        (error) => {
          console.log("ServiceWorker registration failed:", error);
        }
      );
    });
  }
})();
