/**
 * Mock Data Script for Swapboard Frontend Testing
 *
 * Usage:
 *   1. Include this script AFTER app.js in index.html:
 *      <script src="mock.js"></script>
 *
 *   2. Open index.html in a browser
 *
 *   3. Mock data will automatically populate the UI
 *
 * To disable: Remove the script tag from index.html
 */

(function() {
  "use strict";

  // Mock token data
  const MOCK_TOKENS = [
    { address: "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2", symbol: "WETH", decimals: 18 },
    { address: "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599", symbol: "WBTC", decimals: 8 },
    { address: "0xdac17f958d2ee523a2206206994597c13d831ec7", symbol: "USDT", decimals: 6 },
    { address: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", symbol: "USDC", decimals: 6 },
    { address: "0x6b175474e89094c44da98b954eedeac495271d0f", symbol: "DAI", decimals: 18 },
    { address: "0x514910771af9ca656af840dff83e8264ecf986ca", symbol: "LINK", decimals: 18 },
    { address: "0xae7ab96520de3a18e5e111b5eaab095312d7fe84", symbol: "stETH", decimals: 18 },
    { address: "0xb8c77482e45f1f44de1745f52c74426c631bdd52", symbol: "BNB", decimals: 18 },
    { address: "0x95ad61b0a150d79219dcf64e1e6cc01f0b64c4ce", symbol: "SHIB", decimals: 18 },
    { address: "0x6982508145454ce325ddbe47a25d4ec3d2311933", symbol: "PEPE", decimals: 18 },
  ];

  // Mock orders data
  const MOCK_ORDERS = [
    { orderId: "8", maker: "0x59Cd5F9199248b50d40a6291c9E329eA13a82d31", tokenAIdx: 2, tokenBIdx: 0, amountA: "1234567230000", amountB: "411522410000000000000", active: true, taker: null },
    { orderId: "7", maker: "0x59Cd5F9199248b50d40a6291c9E329eA13a82d31", tokenAIdx: 1, tokenBIdx: 2, amountA: "136271625", amountB: "115830881250000", active: true, taker: null },
    { orderId: "6", maker: "0x59Cd5F9199248b50d40a6291c9E329eA13a82d31", tokenAIdx: 7, tokenBIdx: 5, amountA: "100236172391823000000", amountB: "6930910723670000000000", active: true, taker: null },
    { orderId: "5", maker: "0x59Cd5F9199248b50d40a6291c9E329eA13a82d31", tokenAIdx: 0, tokenBIdx: 2, amountA: "100000000000000000000", amountB: "425124000000", active: true, taker: null },
    { orderId: "4", maker: "0x6291c9E329eA13a82d3159Cd5F9199248b50d40a", tokenAIdx: 4, tokenBIdx: 0, amountA: "50000000000000000000000", amountB: "15000000000000000000", active: true, taker: null },
    { orderId: "3", maker: "0x6291c9E329eA13a82d3159Cd5F9199248b50d40a", tokenAIdx: 5, tokenBIdx: 3, amountA: "1000000000000000000000", amountB: "15000000000", active: false, taker: "0x1234567890123456789012345678901234567890" },
    { orderId: "2", maker: "0x6291c9E329eA13a82d3159Cd5F9199248b50d40a", tokenAIdx: 8, tokenBIdx: 0, amountA: "100000000000000000000000000", amountB: "500000000000000000", active: false, taker: null },
    { orderId: "1", maker: "0x6291c9E329eA13a82d3159Cd5F9199248b50d40a", tokenAIdx: 0, tokenBIdx: 2, amountA: "10000000000000000000", amountB: "35000000000", active: true, taker: null },
    { orderId: "0", maker: "0x6291c9E329eA13a82d3159Cd5F9199248b50d40a", tokenAIdx: 4, tokenBIdx: 3, amountA: "25000000000000000000000", amountB: "25000000000", active: true, taker: null },
  ];

  // Mock global stats
  const MOCK_GLOBAL_STATS = {
    totalOrders: "156172",
    activeOrders: "54091",
    filledOrders: "89234",
    cancelledOrders: "12847"
  };

  // Mock pair stats for popular pairs
  const MOCK_PAIR_STATS = [
    { tokenA: { address: "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2", symbol: "WETH" }, tokenB: { address: "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599", symbol: "WBTC" } },
    { tokenA: { address: "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2", symbol: "WETH" }, tokenB: { address: "0xdac17f958d2ee523a2206206994597c13d831ec7", symbol: "USDT" } },
    { tokenA: { address: "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2", symbol: "WETH" }, tokenB: { address: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", symbol: "USDC" } },
    { tokenA: { address: "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2", symbol: "WETH" }, tokenB: { address: "0x6b175474e89094c44da98b954eedeac495271d0f", symbol: "DAI" } },
    { tokenA: { address: "0xae7ab96520de3a18e5e111b5eaab095312d7fe84", symbol: "stETH" }, tokenB: { address: "0xdac17f958d2ee523a2206206994597c13d831ec7", symbol: "USDT" } },
    { tokenA: { address: "0xae7ab96520de3a18e5e111b5eaab095312d7fe84", symbol: "stETH" }, tokenB: { address: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", symbol: "USDC" } },
    { tokenA: { address: "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599", symbol: "WBTC" }, tokenB: { address: "0xdac17f958d2ee523a2206206994597c13d831ec7", symbol: "USDT" } },
    { tokenA: { address: "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599", symbol: "WBTC" }, tokenB: { address: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", symbol: "USDC" } },
    { tokenA: { address: "0xb8c77482e45f1f44de1745f52c74426c631bdd52", symbol: "BNB" }, tokenB: { address: "0xdac17f958d2ee523a2206206994597c13d831ec7", symbol: "USDT" } },
    { tokenA: { address: "0x6982508145454ce325ddbe47a25d4ec3d2311933", symbol: "PEPE" }, tokenB: { address: "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2", symbol: "WETH" } },
  ];

  // Build full order objects with token data
  function buildMockOrders() {
    return MOCK_ORDERS.map(o => ({
      orderId: o.orderId,
      maker: o.maker,
      amountA: o.amountA,
      amountB: o.amountB,
      active: o.active,
      taker: o.taker,
      tokenA: MOCK_TOKENS[o.tokenAIdx],
      tokenB: MOCK_TOKENS[o.tokenBIdx]
    }));
  }

  // Filter orders based on query conditions
  function filterOrders(orders, status, sellingAddr, wantingAddr) {
    return orders.filter(o => {
      if (status === "open" && !o.active) return false;
      if (status === "filled" && (o.active || !o.taker)) return false;
      if (status === "cancelled" && (o.active || o.taker)) return false;
      if (sellingAddr && o.tokenA.address.toLowerCase() !== sellingAddr.toLowerCase()) return false;
      if (wantingAddr && o.tokenB.address.toLowerCase() !== wantingAddr.toLowerCase()) return false;
      return true;
    });
  }

  // Parse GraphQL query to extract parameters
  function parseQuery(query) {
    const result = { type: null, status: null, selling: null, wanting: null };

    if (query.includes("globalStats")) result.type = "stats";
    else if (query.includes("pairStatses")) result.type = "pairs";
    else if (query.includes("tokens(")) result.type = "tokens";
    else if (query.includes("orders(")) result.type = "orders";

    if (query.includes("active: true")) result.status = "open";
    else if (query.includes("taker_not: null")) result.status = "filled";
    else if (query.includes("taker: null") && query.includes("active: false")) result.status = "cancelled";

    const sellingMatch = query.match(/tokenA_:\s*\{\s*address:\s*"([^"]+)"/);
    if (sellingMatch) result.selling = sellingMatch[1];

    const wantingMatch = query.match(/tokenB_:\s*\{\s*address:\s*"([^"]+)"/);
    if (wantingMatch) result.wanting = wantingMatch[1];

    return result;
  }

  // Mock subgraph response handler
  function mockQuerySubgraph(query) {
    const parsed = parseQuery(query);

    switch (parsed.type) {
      case "stats":
        return Promise.resolve({ globalStats: MOCK_GLOBAL_STATS });

      case "pairs":
        return Promise.resolve({ pairStatses: MOCK_PAIR_STATS });

      case "tokens":
        return Promise.resolve({ tokens: MOCK_TOKENS });

      case "orders":
        const allOrders = buildMockOrders();
        const filtered = filterOrders(allOrders, parsed.status, parsed.selling, parsed.wanting);
        return Promise.resolve({ orders: filtered });

      default:
        return Promise.resolve({});
    }
  }

  // Override fetch to intercept subgraph calls
  const originalFetch = window.fetch;
  window.fetch = function(url, options) {
    if (typeof url === "string" && url.includes("thegraph.com")) {
      const body = JSON.parse(options.body);
      console.log("[MOCK] Intercepted subgraph query:", body.query.slice(0, 100) + "...");
      return mockQuerySubgraph(body.query).then(data => ({
        ok: true,
        json: () => Promise.resolve({ data })
      }));
    }
    return originalFetch.apply(this, arguments);
  };

  console.log("[MOCK] Mock data script loaded. Subgraph queries will return mock data.");
})();
