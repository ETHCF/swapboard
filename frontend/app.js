(function () {
  "use strict";

  // Configuration - Update these before deployment
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

  const $ = (sel) => document.querySelector(sel);

  function escapeHtml(str) {
    if (str === null || str === undefined) return "";
    const div = document.createElement("div");
    div.textContent = String(str);
    return div.innerHTML;
  }

  function isValidAddress(addr) {
    if (typeof addr !== "string") return false;
    return /^0x[a-fA-F0-9]{40}$/.test(addr);
  }

  function truncateAddress(addr) {
    if (!addr || !isValidAddress(addr)) return "";
    return addr.slice(0, 6) + "..." + addr.slice(-4);
  }

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

      // USD Val placeholder (would need price oracle in production)
      const usdVal = "$ --";

      // Build row - full address shown, no truncation
      const cells = [
        escapeHtml(order.orderId),
        order.maker,
        escapeHtml(order.tokenA.symbol),
        formatAmount(order.amountA, tokenADecimals),
        escapeHtml(order.tokenB.symbol),
        formatAmount(order.amountB, tokenBDecimals),
        usdVal,
        price
      ];

      cells.forEach((content, index) => {
        const td = document.createElement("td");
        td.textContent = content;
        if (index === 2) td.title = order.tokenA.address;
        if (index === 4) td.title = order.tokenB.address;
        tr.appendChild(td);
      });

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
