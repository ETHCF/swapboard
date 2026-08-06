#!/usr/bin/env node
/**
 * Swapboard Full E2E Tests
 *
 * Tests the complete integrated flow:
 * 1. Execute transactions on contract
 * 2. Wait for subgraph to index
 * 3. Query subgraph to verify data
 * 4. Load frontend and verify rendering
 */

import { readFileSync, writeFileSync } from "fs";
import { dirname, join } from "path";
import { fileURLToPath } from "url";
import {
  createPublicClient,
  createWalletClient,
  http,
  parseEther,
  parseUnits,
  formatEther,
  formatUnits,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { foundry } from "viem/chains";

const __dirname = dirname(fileURLToPath(import.meta.url));

// Load config written by `pnpm setup` / `pnpm e2e`
function loadConfig() {
  const envPath = join(__dirname, ".env.e2e");
  let content;
  try {
    content = readFileSync(envPath, "utf-8");
  } catch (err) {
    if (err && err.code === "ENOENT") {
      console.error(
        "Missing e2e/.env.e2e. Run `pnpm setup` first, or use `pnpm e2e` to setup, test, and teardown."
      );
      process.exit(1);
    }
    throw err;
  }
  const config = {};
  for (const line of content.split("\n")) {
    const [key, value] = line.split("=");
    if (key && value) config[key.trim()] = value.trim();
  }
  return config;
}

const CONFIG = loadConfig();

// ABIs
const SWAPBOARD_ABI = [
  {
    type: "function",
    name: "createOrder",
    inputs: [
      { name: "tokenA", type: "address" },
      { name: "amountA", type: "uint256" },
      { name: "tokenB", type: "address" },
      { name: "amountB", type: "uint256" },
    ],
    outputs: [{ name: "orderId", type: "uint256" }],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "fillOrder",
    inputs: [
      { name: "orderId", type: "uint256" },
      { name: "deadline", type: "uint256" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "cancelOrder",
    inputs: [{ name: "orderId", type: "uint256" }],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "getNextOrderId",
    inputs: [],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
];

const ERC20_ABI = [
  {
    type: "function",
    name: "mint",
    inputs: [
      { name: "to", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "approve",
    inputs: [
      { name: "spender", type: "address" },
      { name: "amount", type: "uint256" },
    ],
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "nonpayable",
  },
  {
    type: "function",
    name: "balanceOf",
    inputs: [{ name: "account", type: "address" }],
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
  },
];

// Test accounts (Anvil defaults)
const ACCOUNTS = [
  {
    key: "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
    addr: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
  },
  {
    key: "0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d",
    addr: "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
  },
];

// Clients
const publicClient = createPublicClient({
  chain: foundry,
  transport: http(CONFIG.RPC_URL),
});

function getWalletClient(privateKey) {
  return createWalletClient({
    chain: foundry,
    transport: http(CONFIG.RPC_URL),
    account: privateKeyToAccount(privateKey),
  });
}

// Query subgraph
async function querySubgraph(query) {
  const res = await fetch(CONFIG.SUBGRAPH_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ query }),
  });
  const json = await res.json();
  if (json.errors) throw new Error(JSON.stringify(json.errors));
  return json.data;
}

// Wait for subgraph to index a block
async function waitForIndexing(targetBlock, maxWait = 30000) {
  const start = Date.now();
  while (Date.now() - start < maxWait) {
    try {
      const data = await querySubgraph(`{ _meta { block { number } } }`);
      if (data._meta.block.number >= targetBlock) return;
    } catch (e) {
      // Subgraph not ready yet
    }
    await new Promise((r) => setTimeout(r, 1000));
  }
  throw new Error(`Subgraph did not index block ${targetBlock} within ${maxWait}ms`);
}

// Test results
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

async function runTests() {
  console.log("=== E2E Tests ===\n");
  console.log("Config:");
  console.log(`  RPC: ${CONFIG.RPC_URL}`);
  console.log(`  Subgraph: ${CONFIG.SUBGRAPH_URL}`);
  console.log(`  Contract: ${CONFIG.CONTRACT_ADDR}`);
  console.log("");

  const alice = ACCOUNTS[0];
  const bob = ACCOUNTS[1];
  const aliceWallet = getWalletClient(alice.key);
  const bobWallet = getWalletClient(bob.key);

  // ========== Contract Transactions ==========
  console.log("--- Contract Transactions ---");

  // Mint tokens
  let hash = await aliceWallet.writeContract({
    address: CONFIG.TOKENA_ADDR,
    abi: ERC20_ABI,
    functionName: "mint",
    args: [alice.addr, parseEther("1000")],
  });
  await publicClient.waitForTransactionReceipt({ hash });

  hash = await bobWallet.writeContract({
    address: CONFIG.TOKENB_ADDR,
    abi: ERC20_ABI,
    functionName: "mint",
    args: [bob.addr, parseUnits("100000", 6)],
  });
  await publicClient.waitForTransactionReceipt({ hash });

  // Approve
  hash = await aliceWallet.writeContract({
    address: CONFIG.TOKENA_ADDR,
    abi: ERC20_ABI,
    functionName: "approve",
    args: [CONFIG.CONTRACT_ADDR, parseEther("1000")],
  });
  await publicClient.waitForTransactionReceipt({ hash });

  hash = await bobWallet.writeContract({
    address: CONFIG.TOKENB_ADDR,
    abi: ERC20_ABI,
    functionName: "approve",
    args: [CONFIG.CONTRACT_ADDR, parseUnits("100000", 6)],
  });
  await publicClient.waitForTransactionReceipt({ hash });

  // Create order
  hash = await aliceWallet.writeContract({
    address: CONFIG.CONTRACT_ADDR,
    abi: SWAPBOARD_ABI,
    functionName: "createOrder",
    args: [CONFIG.TOKENA_ADDR, parseEther("100"), CONFIG.TOKENB_ADDR, parseUnits("3000", 6)],
  });
  let receipt = await publicClient.waitForTransactionReceipt({ hash });
  const createBlock = receipt.blockNumber;
  console.log(`  Created order 0 at block ${createBlock}`);

  // Create second order
  hash = await aliceWallet.writeContract({
    address: CONFIG.CONTRACT_ADDR,
    abi: SWAPBOARD_ABI,
    functionName: "createOrder",
    args: [CONFIG.TOKENA_ADDR, parseEther("50"), CONFIG.TOKENB_ADDR, parseUnits("1500", 6)],
  });
  receipt = await publicClient.waitForTransactionReceipt({ hash });
  console.log(`  Created order 1 at block ${receipt.blockNumber}`);

  // Fill order 0 (deadline 0 = no expiry)
  hash = await bobWallet.writeContract({
    address: CONFIG.CONTRACT_ADDR,
    abi: SWAPBOARD_ABI,
    functionName: "fillOrder",
    args: [0n, 0n],
  });
  receipt = await publicClient.waitForTransactionReceipt({ hash });
  const fillBlock = receipt.blockNumber;
  console.log(`  Filled order 0 at block ${fillBlock}`);

  // Cancel order 1
  hash = await aliceWallet.writeContract({
    address: CONFIG.CONTRACT_ADDR,
    abi: SWAPBOARD_ABI,
    functionName: "cancelOrder",
    args: [1n],
  });
  receipt = await publicClient.waitForTransactionReceipt({ hash });
  const cancelBlock = receipt.blockNumber;
  console.log(`  Cancelled order 1 at block ${cancelBlock}`);

  // ========== Subgraph Verification ==========
  console.log("\n--- Subgraph Indexing ---");

  await waitForIndexing(Number(cancelBlock));
  console.log("  Subgraph synced to latest block");

  // Query orders
  const ordersData = await querySubgraph(`{
    orders(orderBy: orderId, orderDirection: asc) {
      orderId
      maker
      active
      taker
      tokenA { symbol }
      tokenB { symbol }
      amountA
      amountB
    }
  }`);

  console.log("\n--- Subgraph Data Verification ---");

  test(
    "Subgraph has 2 orders",
    ordersData.orders.length === 2,
    `Got ${ordersData.orders.length}`
  );

  const order0 = ordersData.orders.find((o) => o.orderId === "0");
  const order1 = ordersData.orders.find((o) => o.orderId === "1");

  test("Order 0 exists", !!order0);
  test("Order 0 is not active (filled)", order0 && !order0.active);
  test(
    "Order 0 has taker",
    order0 && order0.taker && order0.taker.toLowerCase() === bob.addr.toLowerCase(),
    `Got ${order0?.taker}`
  );
  test("Order 0 tokenA is TKA", order0 && order0.tokenA.symbol === "TKA");
  test("Order 0 tokenB is TKB", order0 && order0.tokenB.symbol === "TKB");
  test(
    "Order 0 amountA is 100 tokens",
    order0 && order0.amountA === parseEther("100").toString()
  );

  test("Order 1 exists", !!order1);
  test("Order 1 is not active (cancelled)", order1 && !order1.active);
  test("Order 1 has no taker", order1 && !order1.taker);

  // Query global stats
  const statsData = await querySubgraph(`{
    globalStats(id: "global") {
      totalOrders
      activeOrders
      filledOrders
      cancelledOrders
    }
  }`);

  const stats = statsData.globalStats;
  test("GlobalStats totalOrders is 2", stats && stats.totalOrders === "2");
  test("GlobalStats activeOrders is 0", stats && stats.activeOrders === "0");
  test("GlobalStats filledOrders is 1", stats && stats.filledOrders === "1");
  test("GlobalStats cancelledOrders is 1", stats && stats.cancelledOrders === "1");

  // Query tokens
  const tokensData = await querySubgraph(`{
    tokens {
      symbol
      decimals
      volumeSold
      volumeBought
      ordersSelling
    }
  }`);

  const tokenA = tokensData.tokens.find((t) => t.symbol === "TKA");
  test("TokenA tracked", !!tokenA);
  test("TokenA decimals is 18", tokenA && tokenA.decimals === 18);
  test(
    "TokenA volumeSold is 100 tokens",
    tokenA && tokenA.volumeSold === parseEther("100").toString()
  );
  test("TokenA ordersSelling is 0", tokenA && tokenA.ordersSelling === "0");

  // Query pair stats
  const pairData = await querySubgraph(`{
    pairStats_collection {
      orderCount
      tradeCount
      tokenA { symbol }
      tokenB { symbol }
    }
  }`);

  const pair = pairData.pairStats_collection[0];
  test("PairStats exists", !!pair);
  test("PairStats orderCount is 2", pair && pair.orderCount === "2");
  test("PairStats tradeCount is 1", pair && pair.tradeCount === "1");

  // ========== Frontend Verification ==========
  console.log("\n--- Frontend Verification ---");

  let puppeteer;
  try {
    puppeteer = await import("puppeteer");
  } catch (e) {
    console.log("  SKIP: Puppeteer not installed");
    return;
  }

  // Create test config for frontend
  const frontendDir = join(__dirname, "..", "frontend");
  // CONFIG lives in lib.js only; app.js imports it from there.
  const libJsPath = join(frontendDir, "lib.js");
  const libJsOriginal = readFileSync(libJsPath, "utf-8");

  // Inject test config
  const libJsTest = libJsOriginal
    .replace(
      /CONTRACT_ADDRESS:\s*"[^"]*"/,
      `CONTRACT_ADDRESS: "${CONFIG.CONTRACT_ADDR}"`
    )
    .replace(
      /SUBGRAPH_URL:\s*"[^"]*"/,
      `SUBGRAPH_URL: "${CONFIG.SUBGRAPH_URL}"`
    );
  writeFileSync(libJsPath, libJsTest);

  try {
    // Allow file:// pages to fetch the local subgraph (CORS / opaque origin)
    const browser = await puppeteer.default.launch({
      headless: "new",
      args: ["--disable-web-security", "--allow-file-access-from-files"],
    });
    const page = await browser.newPage();

    const errors = [];
    page.on("pageerror", (err) => errors.push(err.message));

    // Disable mock.js auto-activation on file:// so we hit the live e2e subgraph
    await page.goto(`file://${join(frontendDir, "index.html")}?mock=false`, {
      waitUntil: "domcontentloaded",
      timeout: 10000,
    });

    // Wait for data to load
    await page.waitForFunction(
      () => document.getElementById("stat-total")?.textContent !== "--",
      { timeout: 10000 }
    );

    // Verify stats
    const statTotal = await page.$eval("#stat-total", (el) => el.textContent);
    test("Frontend shows total orders 2", statTotal === "2", `Got "${statTotal}"`);

    const statFilled = await page.$eval("#stat-filled", (el) => el.textContent);
    test("Frontend shows filled orders 1", statFilled === "1", `Got "${statFilled}"`);

    const statCancelled = await page.$eval("#stat-cancelled", (el) => el.textContent);
    test("Frontend shows cancelled orders 1", statCancelled === "1", `Got "${statCancelled}"`);

    // Verify order table (default: open orders only, should be 0)
    const rowCount = await page.$$eval("#order-table tr", (rows) =>
      rows.filter((r) => !r.textContent.includes("No orders")).length
    );
    test("Frontend shows 0 open orders", rowCount === 0, `Got ${rowCount}`);

    // Switch to "all" filter
    await page.click('input[name="status"][value="all"]');
    await new Promise((r) => setTimeout(r, 500));

    const allRowCount = await page.$$eval("#order-table tr", (rows) =>
      rows.filter((r) => !r.textContent.includes("No orders")).length
    );
    test("Frontend shows 2 total orders", allRowCount === 2, `Got ${allRowCount}`);

    // Check no JS errors
    test("No JavaScript errors", errors.length === 0, errors.join("; "));

    await browser.close();
  } finally {
    // Restore original lib.js
    writeFileSync(libJsPath, libJsOriginal);
  }

  // ========== Summary ==========
  console.log("\n========================================");
  console.log(`Results: ${passed} passed, ${failed} failed`);
  console.log("========================================");

  if (failures.length > 0) {
    console.log("\nFailures:");
    failures.forEach((f, i) => {
      console.log(`  ${i + 1}. ${f.name}`);
      if (f.details) console.log(`     ${f.details}`);
    });
  }

  process.exit(failed > 0 ? 1 : 0);
}

runTests().catch((e) => {
  console.error("E2E test error:", e);
  process.exit(1);
});
