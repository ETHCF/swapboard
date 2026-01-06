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
    // Contract address on Ethereum mainnet - MUST be updated after deployment
    CONTRACT_ADDRESS: "0x0000000000000000000000000000000000000000",
    // The Graph subgraph endpoint - MUST be updated after deployment
    SUBGRAPH_URL: "https://api.studio.thegraph.com/query/YOUR_ID/swapboard/version/latest",
    // Number of orders per page
    PAGE_SIZE: 20,
    // Request timeout in milliseconds
    REQUEST_TIMEOUT: 30000,
    // Debounce delay for token info fetch
    DEBOUNCE_DELAY: 500,
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
    "event OrderCanceled(uint256 indexed orderId)"
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

  const tokenCache = new Map();
  let currentPage = 1;
  let currentFilters = { selling: "", wanting: "", status: "open" };

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
   * Truncates an address for display (0x1234...5678).
   * @param {string} addr - Full Ethereum address
   * @returns {string} Truncated address or empty string if invalid
   */
  function truncateAddress(addr) {
    if (!addr || !isValidAddress(addr)) return "";
    return addr.slice(0, 6) + "..." + addr.slice(-4);
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
      decPart = decPart.slice(0, decimals);
    } else {
      decPart = decPart.padEnd(decimals, "0");
    }
    return BigInt(intPart + decPart);
  }

  function showToast(msg, type = "info") {
    const toast = $("#toast");
    toast.textContent = msg;
    toast.className = "toast " + type;
    setTimeout(() => {
      toast.className = "toast hidden";
    }, 5000);
  }

  function showModal(title, body, onConfirm) {
    const modal = $("#modal");
    $("#modal-title").textContent = title;
    $("#modal-body").textContent = body;
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
    }
  }

  async function loadPopularPairs() {
    const data = await querySubgraph(`
      query {
        pairStatses(first: 10, orderBy: tradeCount, orderDirection: desc) {
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
    if (data && data.pairStatses && data.pairStatses.length > 0) {
      pairsList.innerHTML = data.pairStatses
        .map(p => `<a href="#" class="pair-link" data-token-a="${escapeHtml(p.tokenA.address)}" data-token-b="${escapeHtml(p.tokenB.address)}">${escapeHtml(p.tokenA.symbol)}/${escapeHtml(p.tokenB.symbol)}</a>`)
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

  async function loadOrders() {
    const skip = (currentPage - 1) * CONFIG.PAGE_SIZE;
    const conditions = [];

    if (currentFilters.status === "open") {
      conditions.push("active: true");
    } else if (currentFilters.status === "filled") {
      conditions.push("active: false, taker_not: null");
    } else if (currentFilters.status === "cancelled") {
      conditions.push("active: false, taker: null");
    }

    if (currentFilters.selling && isValidAddress(currentFilters.selling)) {
      conditions.push(`tokenA_: { address: "${currentFilters.selling.toLowerCase()}" }`);
    }
    if (currentFilters.wanting && isValidAddress(currentFilters.wanting)) {
      conditions.push(`tokenB_: { address: "${currentFilters.wanting.toLowerCase()}" }`);
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

    const tbody = $("#order-table");
    tbody.innerHTML = "";

    if (!data || !data.orders || data.orders.length === 0) {
      const tr = document.createElement("tr");
      const td = document.createElement("td");
      td.colSpan = 8;
      td.textContent = "No orders found";
      tr.appendChild(td);
      tbody.appendChild(tr);
      return;
    }

    // Batch fetch prices for all tokenA addresses
    const tokenAddresses = [...new Set(data.orders.map((o) => o.tokenA.address.toLowerCase()))];
    const coinGeckoIds = tokenAddresses
      .map((addr) => COINGECKO_ID_MAP[addr])
      .filter(Boolean);

    if (coinGeckoIds.length > 0) {
      await fetchPrices(coinGeckoIds);
    }

    for (const order of data.orders) {
      const tr = document.createElement("tr");
      const isMaker = userAddress && order.maker.toLowerCase() === userAddress.toLowerCase();

      if (isMaker) {
        tr.classList.add("own-order");
      }

      const tokenADecimals = order.tokenA.decimals;
      const tokenBDecimals = order.tokenB.decimals;
      const amountA = BigInt(order.amountA);
      const amountB = BigInt(order.amountB);

      // Price: amountB/amountA (how much wanting per selling)
      let price = "N/A";
      if (amountA > 0n) {
        const priceNum = Number(amountB) / Number(amountA) * Math.pow(10, tokenADecimals - tokenBDecimals);
        price = formatRatio(priceNum) + " " + escapeHtml(order.tokenB.symbol) + "/" + escapeHtml(order.tokenA.symbol);
      }

      // Calculate USD value of sell side
      const tokenAPrice = getTokenPrice(order.tokenA.address);
      let usdVal = "$ --";
      if (tokenAPrice !== null && amountA > 0n) {
        const humanAmountA = Number(amountA) / Math.pow(10, tokenADecimals);
        usdVal = formatUsd(humanAmountA * tokenAPrice);
      }

      // Build row with links
      // Column 0: Trade ID
      const tdId = document.createElement("td");
      tdId.textContent = order.orderId;
      tr.appendChild(tdId);

      // Column 1: Seller (link to Etherscan)
      const tdSeller = document.createElement("td");
      const sellerLink = document.createElement("a");
      sellerLink.href = "https://etherscan.io/address/" + order.maker;
      sellerLink.target = "_blank";
      sellerLink.rel = "noopener noreferrer";
      sellerLink.textContent = truncateAddress(order.maker);
      sellerLink.title = order.maker;
      tdSeller.appendChild(sellerLink);
      tr.appendChild(tdSeller);

      // Column 2: Selling Token (link to CoinGecko)
      const tdTokenA = document.createElement("td");
      const tokenAId = COINGECKO_ID_MAP[order.tokenA.address.toLowerCase()];
      if (tokenAId) {
        const tokenALink = document.createElement("a");
        tokenALink.href = "https://www.coingecko.com/en/coins/" + tokenAId;
        tokenALink.target = "_blank";
        tokenALink.rel = "noopener noreferrer";
        tokenALink.textContent = order.tokenA.symbol;
        tdTokenA.appendChild(tokenALink);
      } else {
        tdTokenA.textContent = order.tokenA.symbol;
      }
      tdTokenA.title = order.tokenA.address;
      tr.appendChild(tdTokenA);

      // Column 3: Sell Size
      const tdAmountA = document.createElement("td");
      tdAmountA.textContent = formatAmount(order.amountA, tokenADecimals);
      tr.appendChild(tdAmountA);

      // Column 4: Wanted Token (link to CoinGecko)
      const tdTokenB = document.createElement("td");
      const tokenBId = COINGECKO_ID_MAP[order.tokenB.address.toLowerCase()];
      if (tokenBId) {
        const tokenBLink = document.createElement("a");
        tokenBLink.href = "https://www.coingecko.com/en/coins/" + tokenBId;
        tokenBLink.target = "_blank";
        tokenBLink.rel = "noopener noreferrer";
        tokenBLink.textContent = order.tokenB.symbol;
        tdTokenB.appendChild(tokenBLink);
      } else {
        tdTokenB.textContent = order.tokenB.symbol;
      }
      tdTokenB.title = order.tokenB.address;
      tr.appendChild(tdTokenB);

      // Column 5: Wanted Size
      const tdAmountB = document.createElement("td");
      tdAmountB.textContent = formatAmount(order.amountB, tokenBDecimals);
      tr.appendChild(tdAmountB);

      // Column 6: USD Val (nowrap to keep $ and value on same line)
      const tdUsd = document.createElement("td");
      tdUsd.textContent = usdVal;
      tdUsd.style.whiteSpace = "nowrap";
      tr.appendChild(tdUsd);

      // Column 7: Price
      const tdPrice = document.createElement("td");
      tdPrice.textContent = price;
      tr.appendChild(tdPrice);

      // Click handler for filling orders
      if (order.active && !isMaker && userAddress) {
        tr.classList.add("clickable");
        tr.dataset.orderId = order.orderId;
      }

      tbody.appendChild(tr);
    }

    attachOrderActions();
    updatePagination(data.orders.length);
  }

  function attachOrderActions() {
    // Row click for fill (non-makers only)
    document.querySelectorAll("#order-table tr.clickable").forEach((row) => {
      row.addEventListener("click", () => {
        if (row.dataset.orderId) {
          handleFillOrder(row.dataset.orderId);
        }
      });
    });
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
   * Handles the fill order flow: fetches order, confirms with user, approves tokens, fills.
   * @param {string} orderId - Order ID to fill
   */
  async function handleFillOrder(orderId) {
    if (!signer) {
      showToast("Connect wallet first", "error");
      return;
    }
    try {
      const order = await contract.getOrder(orderId);
      const tokenB = await fetchTokenInfo(order.tokenB);
      const amountStr = formatAmount(order.amountB.toString(), tokenB.decimals);

      showModal(
        "Fill Order #" + orderId,
        `You will send ${amountStr} ${tokenB.symbol} and receive tokens in return.`,
        async () => {
          try {
            showToast("Checking allowance...");
            const tokenContract = new ethers.Contract(order.tokenB, ERC20_ABI, signer);
            const allowance = await tokenContract.allowance(userAddress, CONFIG.CONTRACT_ADDRESS);

            if (allowance < order.amountB) {
              showToast("Approving tokens...");
              const approveTx = await tokenContract.approve(CONFIG.CONTRACT_ADDRESS, order.amountB);
              await approveTx.wait();
              showToast("Approval confirmed");
            }

            showToast("Filling order...");
            const tx = await contract.fillOrder(orderId);
            await tx.wait();
            showToast("Order filled!", "success");
            loadOrders();
            loadStats();
          } catch (e) {
            console.error("Fill error:", e);
            showToast("Fill failed: " + (e.reason || e.message), "error");
          }
        }
      );
    } catch (e) {
      console.error("Get order error:", e);
      showToast("Failed to load order", "error");
    }
  }

  async function handleCancelOrder(orderId) {
    if (!signer) {
      showToast("Connect wallet first", "error");
      return;
    }
    showModal(
      "Cancel Order #" + orderId,
      "Your deposited tokens will be returned to your wallet.",
      async () => {
        try {
          showToast("Cancelling order...");
          const tx = await contract.cancelOrder(orderId);
          await tx.wait();
          showToast("Order cancelled!", "success");
          loadOrders();
          loadStats();
        } catch (e) {
          console.error("Cancel error:", e);
          showToast("Cancel failed: " + (e.reason || e.message), "error");
        }
      }
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

      showModal(
        "Create Order",
        `Sell ${amountAStr} ${tokenA.symbol} for ${amountBStr} ${tokenB.symbol}`,
        async () => {
          try {
            showToast("Checking allowance...");
            const tokenContract = new ethers.Contract(tokenAAddr, ERC20_ABI, signer);
            const allowance = await tokenContract.allowance(userAddress, CONFIG.CONTRACT_ADDRESS);

            if (allowance < amountA) {
              showToast("Approving tokens...");
              const approveTx = await tokenContract.approve(CONFIG.CONTRACT_ADDRESS, amountA);
              await approveTx.wait();
              showToast("Approval confirmed");
            }

            showToast("Creating order...");
            const tx = await contract.createOrder(tokenAAddr, amountA, tokenBAddr, amountB);
            await tx.wait();
            showToast("Order created!", "success");

            $("#create-tokenA").value = "";
            $("#create-tokenB").value = "";
            $("#create-amountA").value = "";
            $("#create-amountB").value = "";
            $("#tokenA-info").textContent = "";
            $("#tokenB-info").textContent = "";

            loadOrders();
            loadStats();
          } catch (e) {
            console.error("Create error:", e);
            showToast("Create failed: " + (e.reason || e.message), "error");
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

      contract = new ethers.Contract(CONFIG.CONTRACT_ADDRESS, CONTRACT_ABI, signer);

      $("#connect-btn").textContent = "[" + truncateAddress(userAddress) + "]";
      $("#create-btn").textContent = "Create Order";
      $("#create-btn").disabled = false;

      showToast("Wallet connected", "success");
      loadOrders();
    } catch (e) {
      console.error("Connect error:", e);
      showToast("Connection failed: " + e.message, "error");
    }
  }

  function setupTokenInfoFetch(inputId, infoId) {
    const input = $(inputId);
    let timeout = null;

    input.addEventListener("input", () => {
      clearTimeout(timeout);
      const addr = input.value.trim();

      if (!isValidAddress(addr)) {
        $(infoId).textContent = addr ? "Invalid address" : "";
        return;
      }

      timeout = setTimeout(async () => {
        $(infoId).textContent = "Loading...";
        const info = await fetchTokenInfo(addr);
        $(infoId).textContent = info.symbol + " (" + info.decimals + " decimals)";
      }, CONFIG.DEBOUNCE_DELAY);
    });
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

    $("#connect-btn").addEventListener("click", (e) => {
      e.preventDefault();
      connectWallet();
    });

    // Filter change handlers
    $("#filter-selling").addEventListener("change", () => {
      currentFilters.selling = $("#filter-selling").value;
      currentPage = 1;
      loadOrders();
    });

    $("#filter-wanting").addEventListener("change", () => {
      currentFilters.wanting = $("#filter-wanting").value;
      currentPage = 1;
      loadOrders();
    });

    // Radio button status filters
    document.querySelectorAll('input[name="status"]').forEach((radio) => {
      radio.addEventListener("change", () => {
        currentFilters.status = radio.value;
        currentPage = 1;
        loadOrders();
      });
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

    $("#create-btn").addEventListener("click", handleCreateOrder);

    setupTokenInfoFetch("#create-tokenA", "#tokenA-info");
    setupTokenInfoFetch("#create-tokenB", "#tokenB-info");

    if (window.ethereum) {
      provider = new ethers.BrowserProvider(window.ethereum);

      window.ethereum.on("accountsChanged", (accounts) => {
        if (accounts.length === 0) {
          userAddress = null;
          signer = null;
          contract = null;
          $("#connect-btn").textContent = "[Connect Wallet]";
          $("#create-btn").textContent = "Connect Wallet to Create Order";
          $("#create-btn").disabled = true;
        } else {
          connectWallet();
        }
        loadOrders();
      });

      window.ethereum.on("chainChanged", () => {
        window.location.reload();
      });
    }

    loadStats();
    loadPopularPairs();
    loadTokenFilters();
    loadOrders();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
