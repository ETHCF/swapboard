#!/usr/bin/env node
/**
 * E2E Functional Tests for Swapboard Frontend
 *
 * Tests actual user interactions and verifies correct behavior.
 * Uses mock data with known values to verify filtering, rendering, and validation.
 *
 * Mock data summary:
 * - 9 total orders
 * - 7 open (active: true): IDs 8,7,6,5,4,1,0
 * - 1 filled (active: false, taker set): ID 3
 * - 1 cancelled (active: false, taker null): ID 2
 *
 * Usage:
 *   node test.js [url]
 */

const path = require("path");
const fs = require("fs");

const EXPECTED = {
  stats: {
    total: "156,172",
    active: "54,091",
    filled: "89,234",
    cancelled: "12,847"
  },
  orders: {
    open: ["8", "7", "6", "5", "4", "1", "0"],
    filled: ["3"],
    cancelled: ["2"],
    all: ["8", "7", "6", "5", "4", "3", "2", "1", "0"]
  },
  tokens: {
    weth: "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
    usdt: "0xdac17f958d2ee523a2206206994597c13d831ec7"
  }
};

async function runTests() {
  let puppeteer;
  try {
    puppeteer = require("puppeteer");
  } catch (e) {
    console.error("Puppeteer required. Run: npm install puppeteer");
    process.exit(1);
  }

  const url = process.argv[2] || "file://" + path.resolve(__dirname, "index.html");
  console.log("Testing:", url);
  console.log("");

  const browser = await puppeteer.launch({ headless: "new" });
  const page = await browser.newPage();

  const errors = [];
  page.on("pageerror", err => errors.push(err.message));

  let passed = 0;
  let failed = 0;
  const failures = [];

  function test(name, condition, details) {
    if (condition) {
      console.log(`  PASS: ${name}`);
      passed++;
    } else {
      console.log(`  FAIL: ${name}`);
      if (details) console.log(`        ${details}`);
      failed++;
      failures.push({ name, details });
    }
  }

  async function getOrderIds() {
    return page.$$eval("#order-table tr", rows => {
      return rows.map(row => {
        const firstCell = row.querySelector("td:first-child");
        return firstCell ? firstCell.textContent.trim() : null;
      }).filter(id => id !== null && id !== "No orders found");
    });
  }

  async function getRowCount() {
    const ids = await getOrderIds();
    return ids.length;
  }

  async function clickRadio(value) {
    await page.click(`input[name="status"][value="${value}"]`);
    await page.waitForFunction(
      () => !document.querySelector("#order-table tr td")?.textContent.includes("Loading"),
      { timeout: 3000 }
    );
    await new Promise(r => setTimeout(r, 100));
  }

  async function selectToken(selectId, tokenAddress) {
    await page.select(selectId, tokenAddress);
    await page.waitForFunction(
      () => !document.querySelector("#order-table tr td")?.textContent.includes("Loading"),
      { timeout: 3000 }
    );
    await new Promise(r => setTimeout(r, 100));
  }

  try {
    // Inject mock before page loads
    const mockScript = fs.readFileSync(path.resolve(__dirname, "mock.js"), "utf8");
    await page.evaluateOnNewDocument(mockScript);

    await page.goto(url, { waitUntil: "networkidle0", timeout: 10000 });

    // Wait for initial data load
    await page.waitForFunction(
      () => document.getElementById("stat-total")?.textContent !== "--",
      { timeout: 5000 }
    );

    // ==================== STATS TESTS ====================
    console.log("--- Stats Rendering ---");

    const statTotal = await page.$eval("#stat-total", el => el.textContent);
    test(
      "Total orders matches mock data",
      statTotal === EXPECTED.stats.total,
      `Expected "${EXPECTED.stats.total}", got "${statTotal}"`
    );

    const statActive = await page.$eval("#stat-active", el => el.textContent);
    test(
      "Active orders matches mock data",
      statActive === EXPECTED.stats.active,
      `Expected "${EXPECTED.stats.active}", got "${statActive}"`
    );

    const statFilled = await page.$eval("#stat-filled", el => el.textContent);
    test(
      "Filled orders matches mock data",
      statFilled === EXPECTED.stats.filled,
      `Expected "${EXPECTED.stats.filled}", got "${statFilled}"`
    );

    const statCancelled = await page.$eval("#stat-cancelled", el => el.textContent);
    test(
      "Cancelled orders matches mock data",
      statCancelled === EXPECTED.stats.cancelled,
      `Expected "${EXPECTED.stats.cancelled}", got "${statCancelled}"`
    );

    // ==================== STATUS FILTER TESTS ====================
    console.log("\n--- Status Filter Behavior ---");

    // Default should be "open" with 7 orders
    let orderIds = await getOrderIds();
    test(
      "Default filter shows open orders only",
      orderIds.length === EXPECTED.orders.open.length,
      `Expected ${EXPECTED.orders.open.length} orders, got ${orderIds.length}`
    );

    test(
      "Open orders have correct IDs",
      JSON.stringify(orderIds.sort()) === JSON.stringify(EXPECTED.orders.open.sort()),
      `Expected IDs ${EXPECTED.orders.open.join(",")}, got ${orderIds.join(",")}`
    );

    // Switch to "all" filter
    await clickRadio("all");
    orderIds = await getOrderIds();
    test(
      "All filter shows all 9 orders",
      orderIds.length === EXPECTED.orders.all.length,
      `Expected ${EXPECTED.orders.all.length} orders, got ${orderIds.length}`
    );

    // Switch to "filled" filter
    await clickRadio("filled");
    orderIds = await getOrderIds();
    test(
      "Filled filter shows 1 order",
      orderIds.length === EXPECTED.orders.filled.length,
      `Expected ${EXPECTED.orders.filled.length} order, got ${orderIds.length}`
    );

    test(
      "Filled order has correct ID",
      orderIds[0] === EXPECTED.orders.filled[0],
      `Expected ID "${EXPECTED.orders.filled[0]}", got "${orderIds[0]}"`
    );

    // Switch to "cancelled" filter
    await clickRadio("cancelled");
    orderIds = await getOrderIds();
    test(
      "Cancelled filter shows 1 order",
      orderIds.length === EXPECTED.orders.cancelled.length,
      `Expected ${EXPECTED.orders.cancelled.length} order, got ${orderIds.length}`
    );

    test(
      "Cancelled order has correct ID",
      orderIds[0] === EXPECTED.orders.cancelled[0],
      `Expected ID "${EXPECTED.orders.cancelled[0]}", got "${orderIds[0]}"`
    );

    // Reset to open
    await clickRadio("open");

    // ==================== TOKEN FILTER TESTS ====================
    console.log("\n--- Token Filter Behavior ---");

    // Verify token dropdowns are populated
    const sellingOptions = await page.$$eval("#filter-selling option", opts =>
      opts.map(o => o.textContent)
    );
    test(
      "Selling filter has token options",
      sellingOptions.length > 1,
      `Expected multiple options, got ${sellingOptions.length}`
    );

    test(
      "Selling filter includes WETH",
      sellingOptions.includes("WETH"),
      `Options: ${sellingOptions.join(", ")}`
    );

    // Filter by WETH as selling token (open orders: 5, 1)
    await selectToken("#filter-selling", EXPECTED.tokens.weth);
    orderIds = await getOrderIds();
    test(
      "WETH selling filter shows correct orders",
      orderIds.length === 2 && orderIds.includes("5") && orderIds.includes("1"),
      `Expected IDs 5,1; got ${orderIds.join(",")}`
    );

    // Reset selling filter
    await selectToken("#filter-selling", "");

    // Filter by USDT as wanting token (open orders: 7, 5, 1)
    await selectToken("#filter-wanting", EXPECTED.tokens.usdt);
    orderIds = await getOrderIds();
    test(
      "USDT wanting filter shows correct orders",
      orderIds.length === 3 && orderIds.includes("7") && orderIds.includes("5") && orderIds.includes("1"),
      `Expected IDs 7,5,1; got ${orderIds.join(",")}`
    );

    // Combined filter: WETH selling + USDT wanting (orders 5, 1)
    await selectToken("#filter-selling", EXPECTED.tokens.weth);
    orderIds = await getOrderIds();
    test(
      "Combined WETH+USDT filter shows correct orders",
      orderIds.length === 2 && orderIds.includes("5") && orderIds.includes("1"),
      `Expected IDs 5,1; got ${orderIds.join(",")}`
    );

    // Reset filters
    await selectToken("#filter-selling", "");
    await selectToken("#filter-wanting", "");

    // ==================== ORDER DATA ACCURACY ====================
    console.log("\n--- Order Data Accuracy ---");

    // Verify order 8 data (first open order): USDT -> WETH
    // amountA: 1234567230000 (USDT, 6 decimals) = 1,234,567.23
    // amountB: 411522410000000000000 (WETH, 18 decimals) = 411.52241
    const firstRow = await page.$$eval("#order-table tr:first-child td", cells =>
      cells.map(c => c.textContent.trim())
    );

    test(
      "First order ID is 8",
      firstRow[0] === "8",
      `Expected "8", got "${firstRow[0]}"`
    );

    test(
      "First order selling token is USDT",
      firstRow[2] === "USDT",
      `Expected "USDT", got "${firstRow[2]}"`
    );

    test(
      "First order wanting token is WETH",
      firstRow[4] === "WETH",
      `Expected "WETH", got "${firstRow[4]}"`
    );

    // Verify amount formatting (1234567230000 with 6 decimals = 1,234,567.23)
    test(
      "First order sell amount formatted correctly",
      firstRow[3] === "1,234,567.23",
      `Expected "1,234,567.23", got "${firstRow[3]}"`
    );

    // ==================== TOKEN INPUT VALIDATION ====================
    console.log("\n--- Token Input Validation ---");

    // Enter invalid address
    await page.type("#create-tokenA", "0xinvalid");
    await new Promise(r => setTimeout(r, 600)); // Wait for debounce

    const tokenAInfo = await page.$eval("#tokenA-info", el => el.textContent);
    test(
      "Invalid address shows error",
      tokenAInfo === "Invalid address",
      `Expected "Invalid address", got "${tokenAInfo}"`
    );

    // Clear and enter valid format (won't fetch real data but validates format)
    await page.$eval("#create-tokenA", el => el.value = "");
    await page.type("#create-tokenA", "0x1234567890123456789012345678901234567890");
    await new Promise(r => setTimeout(r, 600));

    const tokenAInfoValid = await page.$eval("#tokenA-info", el => el.textContent);
    test(
      "Valid address format shows loading/result",
      tokenAInfoValid !== "Invalid address" && tokenAInfoValid !== "",
      `Got "${tokenAInfoValid}"`
    );

    // ==================== TABLE STRUCTURE ====================
    console.log("\n--- Table Structure ---");

    const columnCount = await page.$$eval(
      "#order-table tr:first-child td",
      cells => cells.length
    );
    test(
      "Order table has 8 columns",
      columnCount === 8,
      `Expected 8 columns, got ${columnCount}`
    );

    const headers = await page.$$eval("thead th", ths => ths.map(t => t.textContent.trim()));
    const expectedHeaders = ["Trade ID", "Account", "Selling Token", "Sell Size", "Wanted Token", "Wanted Size", "USD Val", "Price"];
    test(
      "Table headers are correct",
      headers.length === 8 && headers[0].includes("Trade ID") && headers[2].includes("Selling"),
      `Got headers: ${headers.join(", ")}`
    );

    // ==================== ERROR CHECK ====================
    console.log("\n--- Console Errors ---");
    test(
      "No JavaScript errors on page",
      errors.length === 0,
      errors.length > 0 ? `Errors: ${errors.join("; ")}` : undefined
    );

  } catch (e) {
    console.error("\nTest execution error:", e.message);
    failed++;
    failures.push({ name: "Test execution", details: e.message });
  }

  await browser.close();

  // Summary
  console.log("\n========================================");
  console.log(`Results: ${passed} passed, ${failed} failed`);
  console.log("========================================");

  if (failures.length > 0) {
    console.log("\nFailure details:");
    failures.forEach((f, i) => {
      console.log(`  ${i + 1}. ${f.name}`);
      if (f.details) console.log(`     ${f.details}`);
    });
  }

  console.log("");
  process.exit(failed > 0 ? 1 : 0);
}

runTests();
