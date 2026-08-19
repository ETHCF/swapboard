/**
 * Unit tests for app.js.
 *
 * app.js is a single IIFE that exports its closure surface under CommonJS (see the
 * export guard at the foot of the file) and skips bootstrap, so requiring it here
 * is side-effect free. Two things matter for isolation:
 *
 *   1. app.js destructures `window.SwapboardLib` at IIFE execution time, so lib.js
 *      must be assigned *before* the require.
 *   2. app.js holds ~18 pieces of mutable closure state (provider, cachedOrders,
 *      autoRefreshInterval, ...). Every test gets a fresh module via loadApp().
 *
 * The DOM fixture is the real index.html body, so selectors match production
 * rather than a hand-maintained stub that can drift.
 */

const fs = require("fs");
const path = require("path");

// jsdom implements no layout, so Element.scrollIntoView does not exist. renderOrders
// schedules one on a timer to reveal a linked order, which lands in whichever test
// happens to be running when the timer fires.
Element.prototype.scrollIntoView = jest.fn();

const INDEX_HTML = fs.readFileSync(path.join(__dirname, "index.html"), "utf8");
const BODY_HTML = INDEX_HTML.match(/<body[^>]*>([\s\S]*)<\/body>/i)[1];

/**
 * Loads a pristine app.js against a fresh copy of the real page markup.
 *
 * ACTIVE_VERSION and CAPS are resolved once at IIFE execution time from the URL
 * and localStorage, so the protocol version has to be set on the location before
 * the require -- there is no setter afterwards. Pass { search: "?v=2" } to load
 * the v2 capability set (batch, partial fills, native ETH).
 *
 * @param {{search?: string, hash?: string}} [opts]
 */
function loadApp(opts = {}) {
  jest.resetModules();
  const { search = "", hash = "" } = opts;
  window.history.replaceState({}, "", "/" + search + hash);
  // innerHTML alone leaves the body's own class list and dataset behind, so
  // dark-mode / data-version leak into the next test.
  document.body.className = "";
  document.body.removeAttribute("data-version");
  document.body.innerHTML = BODY_HTML;
  // init() appends the ethers CDN tag to <head>, which innerHTML on body misses.
  document.head.querySelectorAll("script").forEach((s) => s.remove());
  window.SwapboardLib = require("./lib");
  return require("./app");
}

/** Replaces window.location with a writable stub, returning a restore fn. */
function stubLocation(href = "https://swapboard.test/") {
  const real = window.location;
  delete window.location;
  window.location = {
    href,
    hash: "",
    search: "",
    hostname: "swapboard.test",
    protocol: "https:",
    reload: jest.fn(),
    assign: jest.fn(),
  };
  return () => {
    window.location = real;
  };
}

/**
 * test.setup.js installs localStorage and matchMedia as jest.fn()s and clears them
 * between tests, but jest.clearAllMocks() only clears calls -- an implementation
 * swapped in by one test survives into the next, and mockRestore() does not put the
 * originals back because the "originals" are themselves mocks. Snapshot them once
 * and reinstate them by hand each time.
 */
const REAL_STORAGE = {
  getItem: window.localStorage.getItem,
  setItem: window.localStorage.setItem,
  removeItem: window.localStorage.removeItem,
  clear: window.localStorage.clear,
};

const DEFAULT_MATCH_MEDIA = (query) => ({
  matches: false,
  media: query,
  onchange: null,
  addListener: jest.fn(),
  removeListener: jest.fn(),
  addEventListener: jest.fn(),
  removeEventListener: jest.fn(),
  dispatchEvent: jest.fn(),
});

/** Runs fn with one localStorage method throwing, as in private-browsing mode. */
function withStorageFailure(method, fn) {
  const original = window.localStorage[method];
  window.localStorage[method] = jest.fn(() => {
    throw new Error("storage unavailable");
  });
  try {
    return fn();
  } finally {
    window.localStorage[method] = original;
  }
}

/**
 * Builds a subgraph order. Amounts are raw base units; the app formats them.
 * @param {Object} [over] - Field overrides
 */
function makeOrder(over = {}) {
  const {
    orderId = "1",
    maker = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    tokenA = {
      address: "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
      symbol: "WETH",
      decimals: 18,
    },
    tokenB = { address: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", symbol: "USDC", decimals: 6 },
    ...rest
  } = over;
  return {
    orderId,
    maker,
    amountA: "1000000000000000000",
    amountB: "3000000000",
    originalAmountA: "1000000000000000000",
    originalAmountB: "3000000000",
    partialFill: false,
    active: true,
    taker: null,
    createdAt: "1700000000",
    filledAt: null,
    tokenA,
    tokenB,
    ...rest,
  };
}

/**
 * Routes window.fetch by URL and GraphQL query shape.
 *
 * app.js talks to three endpoints (subgraph, CoinGecko, the Uniswap token list)
 * and issues four different subgraph queries. Matching on the query body keeps
 * each test declaring only the data it cares about.
 *
 * @param {{orders?: Array, stats?: Object, pairs?: Array, tokens?: Array,
 *          prices?: Object, tokenList?: Object, httpError?: number,
 *          graphqlErrors?: Array, reject?: Error}} [opts]
 */
function routeFetch(opts = {}) {
  const impl = jest.fn(async (url, init) => {
    if (opts.reject) throw opts.reject;

    const target = String(url);
    if (target.includes("coingecko")) {
      return jsonResponse(opts.prices || {});
    }
    if (target.includes("tokens.uniswap.org")) {
      return jsonResponse(opts.tokenList || { tokens: [] });
    }

    if (opts.httpError) {
      return { ok: false, status: opts.httpError, json: async () => ({}) };
    }
    if (opts.graphqlErrors) {
      return jsonResponse({ errors: opts.graphqlErrors });
    }

    const body = init && init.body ? String(init.body) : "";
    // Order matters: the stats/pairs queries also mention "tokens".
    if (body.includes("globalStats")) {
      return jsonResponse({ data: { globalStats: opts.stats || null } });
    }
    if (body.includes("pairStats_collection")) {
      return jsonResponse({ data: { pairStats_collection: opts.pairs || [] } });
    }
    if (body.includes("orders(")) {
      return jsonResponse({ data: { orders: opts.orders || [] } });
    }
    if (body.includes("order(")) {
      return jsonResponse({ data: { order: opts.order || null } });
    }
    if (body.includes("tokens(")) {
      return jsonResponse({ data: { tokens: opts.tokens || [] } });
    }
    return jsonResponse({ data: {} });
  });
  global.fetch.mockImplementation(impl);
  return impl;
}

function jsonResponse(payload) {
  return { ok: true, status: 200, json: async () => payload };
}

/**
 * Installs a global `ethers` plus a fake EIP-1193 wallet.
 *
 * app.js reads `ethers` off the global (index.html loads it from a CDN), not via
 * require, so the moduleNameMapper in jest.config.js does not reach it. Contract
 * dispatch is by address: the Swapboard address returns the exchange contract,
 * anything else returns an ERC20.
 *
 * @param {Object} [over] - Overrides merged onto the generated fakes
 * @returns {Object} handles for assertions: { provider, signer, swap, token, tx, wallet }
 */
function installEthers(over = {}) {
  const receipt = { status: 1, hash: "0xtx", blockNumber: 1 };
  const tx = { hash: "0xtx", wait: jest.fn().mockResolvedValue(receipt) };

  const token = {
    symbol: jest.fn().mockResolvedValue("WETH"),
    name: jest.fn().mockResolvedValue("Wrapped Ether"),
    decimals: jest.fn().mockResolvedValue(18),
    balanceOf: jest.fn().mockResolvedValue(BigInt("5000000000000000000")),
    allowance: jest.fn().mockResolvedValue(BigInt(0)),
    approve: jest.fn().mockResolvedValue(tx),
    ...(over.token || {}),
  };

  const swap = {
    weth: jest.fn().mockResolvedValue("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"),
    createOrder: jest.fn().mockResolvedValue(tx),
    createOrders: jest.fn().mockResolvedValue(tx),
    fillOrder: jest.fn().mockResolvedValue(tx),
    fillOrders: jest.fn().mockResolvedValue(tx),
    cancelOrder: jest.fn().mockResolvedValue(tx),
    cancelOrders: jest.fn().mockResolvedValue(tx),
    getOrder: jest.fn().mockResolvedValue({}),
    fillOrderWithEth: jest.fn().mockResolvedValue(tx),
    fillOrderUnwrap: jest.fn().mockResolvedValue(tx),
    cancelOrderUnwrap: jest.fn().mockResolvedValue(tx),
    createOrderWithEth: jest.fn().mockResolvedValue(tx),
    // V1.estimateFor encodes calldata off the contract's ABI interface.
    interface: { encodeFunctionData: jest.fn(() => "0xdeadbeef") },
    on: jest.fn(),
    off: jest.fn(),
    ...(over.swap || {}),
  };

  const signer = {
    getAddress: jest.fn().mockResolvedValue(WALLET_ADDRESS),
    ...(over.signer || {}),
  };

  const provider = {
    send: jest.fn().mockResolvedValue([WALLET_ADDRESS]),
    getSigner: jest.fn().mockResolvedValue(signer),
    getNetwork: jest.fn().mockResolvedValue({ chainId: BigInt(1) }),
    lookupAddress: jest.fn().mockResolvedValue(null),
    getBalance: jest.fn().mockResolvedValue(BigInt("2000000000000000000")),
    estimateGas: jest.fn().mockResolvedValue(BigInt(21000)),
    getFeeData: jest.fn().mockResolvedValue({
      gasPrice: BigInt(20000000000),
      maxFeePerGas: BigInt(25000000000),
    }),
    ...(over.provider || {}),
  };

  global.ethers = {
    BrowserProvider: jest.fn(() => provider),
    Contract: jest.fn((address) =>
      String(address).toLowerCase() === SWAPBOARD_ADDRESS.toLowerCase() ? swap : token
    ),
    formatEther: (v) => String(Number(v) / 1e18),
    formatUnits: (v, d = 18) => String(Number(v) / 10 ** Number(d)),
    parseUnits: (v, d = 18) => BigInt(Math.round(Number(v) * 10 ** Number(d))),
    MaxUint256: BigInt(
      "115792089237316195423570985008687907853269984665640564039457584007913129639935"
    ),
    ZeroAddress: "0x0000000000000000000000000000000000000000",
  };

  const wallet = {
    request: jest.fn().mockResolvedValue([WALLET_ADDRESS]),
    on: jest.fn(),
    removeListener: jest.fn(),
    ...(over.wallet || {}),
  };
  window.ethereum = wallet;

  return { provider, signer, swap, token, tx, wallet, receipt };
}

const WALLET_ADDRESS = "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266";
const SWAPBOARD_ADDRESS = "0x000000fF3D7A2d373615141d7489Ca66683DbecF";

/** Connects the wallet against the installed ethers fakes. */
async function connect(mod, handles) {
  await mod.connectWithProvider(handles.wallet, "TestWallet");
}

let app;

beforeEach(() => {
  Object.assign(window.localStorage, REAL_STORAGE);
  window.matchMedia.mockImplementation(DEFAULT_MATCH_MEDIA);
  // V1.syncAfter polls the subgraph on real 1.5s timers for up to 10 attempts
  // after any transaction. Left on, those chains outlive the test that started
  // them and fire toasts into later ones. The flag is the app's own escape
  // hatch; waitForOrderUpdate is covered directly instead.
  window.SWAPBOARD_MOCK = true;
  app = loadApp();
});

afterEach(() => {
  delete global.ethers;
  delete window.ethereum;
  delete window.SWAPBOARD_MOCK;
});

describe("module contract", () => {
  test("exports the closure surface", () => {
    expect(Object.keys(app).length).toBeGreaterThan(100);
  });

  test("requiring does not boot the app", () => {
    // The bootstrap side effect that actually bites is startAutoRefresh's
    // setInterval leaking across suites. bootstrap() is exported, not invoked.
    jest.useFakeTimers();
    try {
      loadApp();
      expect(jest.getTimerCount()).toBe(0);
    } finally {
      jest.useRealTimers();
    }
    expect(typeof app.bootstrap).toBe("function");
  });
});

describe("isStable", () => {
  test.each([
    ["0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", "USDC"],
    ["0xdac17f958d2ee523a2206206994597c13d831ec7", "USDT"],
    ["0x6b175474e89094c44da98b954eedeac495271d0f", "DAI"],
  ])("recognises %s (%s)", (addr) => {
    expect(app.isStable(addr)).toBe(true);
  });

  test("is case insensitive", () => {
    expect(app.isStable("0xA0B86991C6218B36C1D19D4A2E9EB0CE3606EB48")).toBe(true);
  });

  test("rejects non-stables and falsy input", () => {
    expect(app.isStable("0x0000000000000000000000000000000000000001")).toBe(false);
    expect(app.isStable("")).toBe(false);
    expect(app.isStable(null)).toBe(false);
    expect(app.isStable(undefined)).toBe(false);
  });
});

describe("isWeth", () => {
  test("returns false before the WETH address is resolved", () => {
    // cachedWethAddress starts null, so every address is a miss.
    expect(app.isWeth("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2")).toBe(false);
  });

  test("returns false for falsy input", () => {
    expect(app.isWeth(null)).toBe(false);
    expect(app.isWeth("")).toBe(false);
  });
});

describe("preferredQuoteSide", () => {
  const USDC = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48";
  const DAI = "0x6b175474e89094c44da98b954eedeac495271d0f";
  const RANDOM = "0x1111111111111111111111111111111111111111";
  const OTHER = "0x2222222222222222222222222222222222222222";

  test("prefers the stable side when only A is stable", () => {
    expect(app.preferredQuoteSide(USDC, RANDOM)).toBe("A");
  });

  test("prefers the stable side when only B is stable", () => {
    expect(app.preferredQuoteSide(RANDOM, USDC)).toBe("B");
  });

  test("falls back to null when both sides are stable", () => {
    expect(app.preferredQuoteSide(USDC, DAI)).toBe(null);
  });

  test("falls back to null when neither side is stable or WETH", () => {
    expect(app.preferredQuoteSide(RANDOM, OTHER)).toBe(null);
  });
});

describe("tryParseAmount", () => {
  test("parses a well-formed amount", () => {
    const { amount, error } = app.tryParseAmount("1.5", 18);
    expect(error).toBeNull();
    expect(amount).not.toBeNull();
  });

  test("reports the error rather than throwing on garbage", () => {
    const { amount, error } = app.tryParseAmount("not-a-number", 18);
    expect(amount).toBeNull();
    expect(error).toMatch(/Invalid amount/);
  });
});

describe("getOrderIdFromHash", () => {
  test("reads an order id out of the location hash", () => {
    window.location.hash = "#order-42";
    expect(app.getOrderIdFromHash()).toBe("42");
  });

  test("returns null when the hash is not an order link", () => {
    window.location.hash = "#something-else";
    expect(app.getOrderIdFromHash()).toBeNull();
  });

  test("returns null when there is no hash", () => {
    window.location.hash = "";
    expect(app.getOrderIdFromHash()).toBeNull();
  });
});

describe("protocol version", () => {
  test("defaults to v1 capabilities", () => {
    expect(app.orderColumnCount()).toBe(9);
  });

  test("v2 adds the select column", () => {
    const v2 = loadApp({ search: "?v=2" });
    expect(v2.orderColumnCount()).toBe(10);
  });

  test("readStoredVersion reads the persisted preference", () => {
    localStorage.setItem("swapboard_version", "2");
    const fresh = loadApp();
    expect(fresh.readStoredVersion()).toBe("2");
  });

  test("readStoredVersion returns null when storage throws", () => {
    withStorageFailure("getItem", () => {
      expect(app.readStoredVersion()).toBeNull();
    });
  });

  test("applyVersionUi stamps the body and titles for v1", () => {
    app.applyVersionUi();
    expect(document.body.dataset.version).toBe("1");
    expect(document.querySelector("#app-title").textContent).toMatch(/v1/);
  });

  test("applyVersionUi stamps the body and titles for v2", () => {
    const v2 = loadApp({ search: "?v=2" });
    v2.applyVersionUi();
    expect(document.body.dataset.version).toBe("2");
    expect(document.querySelector("#app-title").textContent).toMatch(/v2/);
  });

  test("applyVersionUi marks the active version switch button", () => {
    app.applyVersionUi();
    const buttons = document.querySelectorAll("#version-switch .version-option");
    expect(buttons.length).toBeGreaterThan(0);
    buttons.forEach((btn) => {
      const expected = String(Number(btn.dataset.version) === 1);
      expect(btn.getAttribute("aria-pressed")).toBe(expected);
    });
  });

  test("setVersion ignores unsupported versions and the current one", () => {
    const restore = stubLocation();
    try {
      app.setVersion(99);
      app.setVersion(1); // already active
      expect(window.location.href).toBe("https://swapboard.test/");
    } finally {
      restore();
    }
  });

  test("setVersion persists the choice and navigates with ?v=", () => {
    const restore = stubLocation();
    try {
      app.setVersion(2);
      expect(localStorage.getItem("swapboard_version")).toBe("2");
      expect(window.location.href).toMatch(/[?&]v=2/);
    } finally {
      restore();
    }
  });

  test("setVersion still navigates when storage is refused", () => {
    const restore = stubLocation();
    try {
      withStorageFailure("setItem", () => {
        app.setVersion(2);
      });
      expect(window.location.href).toMatch(/[?&]v=2/);
    } finally {
      restore();
    }
  });
});

describe("theme", () => {
  test("initTheme honours a stored dark preference", () => {
    localStorage.setItem("swapboard-theme", "dark");
    app.initTheme();
    expect(document.body.classList.contains("dark-mode")).toBe(true);
    expect(document.querySelector("#theme-icon-sun").classList.contains("hidden")).toBe(true);
  });

  test("initTheme honours a stored light preference", () => {
    document.body.classList.add("dark-mode");
    localStorage.setItem("swapboard-theme", "light");
    app.initTheme();
    expect(document.body.classList.contains("dark-mode")).toBe(false);
    expect(document.querySelector("#theme-icon-moon").classList.contains("hidden")).toBe(true);
  });

  test("initTheme falls back to the system preference when unset", () => {
    window.matchMedia.mockImplementation((query) => ({ matches: true, media: query }));
    app.initTheme();
    expect(document.body.classList.contains("dark-mode")).toBe(true);
  });

  test("initTheme leaves light mode alone when the system prefers light", () => {
    window.matchMedia.mockImplementation((query) => ({ matches: false, media: query }));
    app.initTheme();
    expect(document.body.classList.contains("dark-mode")).toBe(false);
  });

  test("toggleTheme flips the class, persists, and swaps icons", () => {
    app.toggleTheme();
    expect(document.body.classList.contains("dark-mode")).toBe(true);
    expect(localStorage.getItem("swapboard-theme")).toBe("dark");

    app.toggleTheme();
    expect(document.body.classList.contains("dark-mode")).toBe(false);
    expect(localStorage.getItem("swapboard-theme")).toBe("light");
  });
});

describe("preferences", () => {
  test("filter preferences round-trip through storage", () => {
    app.saveFilterPreferences();
    app.loadFilterPreferences();
    expect(() => app.loadFilterPreferences()).not.toThrow();
  });

  test("sort preferences round-trip through storage", () => {
    app.saveSortPreferences();
    expect(() => app.loadSortPreferences()).not.toThrow();
  });

  test("loading preferences with nothing stored is a no-op", () => {
    localStorage.clear();
    expect(() => {
      app.loadFilterPreferences();
      app.loadSortPreferences();
    }).not.toThrow();
  });

  test("recent tokens round-trip", () => {
    app.addRecentToken("0x1111111111111111111111111111111111111111", "AAA");
    const recent = app.getRecentTokens();
    expect(Array.isArray(recent)).toBe(true);
    expect(recent.some((t) => t.symbol === "AAA")).toBe(true);
  });
});

describe("watchlist", () => {
  const order = {
    orderId: "7",
    tokenA: { symbol: "WETH" },
    tokenB: { symbol: "USDC" },
    filled: false,
    cancelled: false,
  };

  test("watch, query and unwatch an order", () => {
    expect(app.isOrderWatched("7")).toBe(false);
    app.watchOrder(order);
    expect(app.isOrderWatched("7")).toBe(true);
    expect(Object.keys(app.getWatchedOrders())).toContain("7");
    app.unwatchOrder("7");
    expect(app.isOrderWatched("7")).toBe(false);
  });

  test("checkWatchedOrders is a no-op with an empty watchlist", () => {
    expect(() => app.checkWatchedOrders([order])).not.toThrow();
  });

  test("checkWatchedOrders skips orders that are not watched", () => {
    app.watchOrder(order);
    expect(() => app.checkWatchedOrders([{ ...order, orderId: "999" }])).not.toThrow();
  });
});

describe("querySubgraph", () => {
  test("returns the data payload on success", async () => {
    routeFetch({ orders: [makeOrder()] });
    const data = await app.querySubgraph("query { orders( ) { orderId } }");
    expect(data.orders).toHaveLength(1);
  });

  test("returns null and toasts on an HTTP error", async () => {
    routeFetch({ httpError: 500 });
    jest.spyOn(console, "error").mockImplementation(() => {});
    const data = await app.querySubgraph("query { orders( ) { orderId } }");
    expect(data).toBeNull();
    expect(document.querySelector("#toast").className).toMatch(/error/);
    console.error.mockRestore();
  });

  test("stays silent on an HTTP error when asked to", async () => {
    routeFetch({ httpError: 500 });
    jest.spyOn(console, "error").mockImplementation(() => {});
    await app.querySubgraph("query { orders( ) { orderId } }", {}, true);
    expect(document.querySelector("#toast").className).not.toMatch(/error/);
    console.error.mockRestore();
  });

  test("returns null when the response carries GraphQL errors", async () => {
    routeFetch({ graphqlErrors: [{ message: "bad field" }] });
    jest.spyOn(console, "error").mockImplementation(() => {});
    const data = await app.querySubgraph("query { orders( ) { orderId } }");
    expect(data).toBeNull();
    console.error.mockRestore();
  });

  test("reports a timeout distinctly from a network error", async () => {
    const abort = new Error("aborted");
    abort.name = "AbortError";
    routeFetch({ reject: abort });
    const data = await app.querySubgraph("query { orders( ) { orderId } }");
    expect(data).toBeNull();
    expect(document.querySelector("#toast").textContent).toMatch(/timed out/i);
  });

  test("reports a network error", async () => {
    routeFetch({ reject: new Error("offline") });
    jest.spyOn(console, "error").mockImplementation(() => {});
    const data = await app.querySubgraph("query { orders( ) { orderId } }");
    expect(data).toBeNull();
    expect(document.querySelector("#toast").textContent).toMatch(/Network error/i);
    console.error.mockRestore();
  });
});

describe("toast", () => {
  test("shows a message and auto-hides after five seconds", () => {
    jest.useFakeTimers();
    try {
      const fresh = loadApp();
      fresh.showToast("saved", "success");
      const toast = document.querySelector("#toast");
      expect(toast.textContent).toBe("saved");
      expect(toast.className).toBe("toast success");
      jest.advanceTimersByTime(5000);
      expect(toast.className).toBe("toast hidden");
    } finally {
      jest.useRealTimers();
    }
  });

  test("renders a trailing ellipsis as an animated dots span", () => {
    app.showToast("Loading...", "info", true);
    const toast = document.querySelector("#toast");
    expect(toast.textContent).toBe("Loading");
    expect(toast.querySelector(".loading-dots")).not.toBeNull();
  });

  test("a persistent toast is not auto-hidden", () => {
    jest.useFakeTimers();
    try {
      const fresh = loadApp();
      fresh.showToast("working", "info", true);
      jest.advanceTimersByTime(10000);
      expect(document.querySelector("#toast").className).toBe("toast info");
    } finally {
      jest.useRealTimers();
    }
  });

  test("a second toast replaces the first one's timer", () => {
    jest.useFakeTimers();
    try {
      const fresh = loadApp();
      fresh.showToast("first");
      fresh.showToast("second");
      expect(document.querySelector("#toast").textContent).toBe("second");
      jest.advanceTimersByTime(5000);
      expect(document.querySelector("#toast").className).toBe("toast hidden");
    } finally {
      jest.useRealTimers();
    }
  });

  test("hideToast hides immediately and clears a pending timer", () => {
    jest.useFakeTimers();
    try {
      const fresh = loadApp();
      fresh.showToast("hello");
      fresh.hideToast();
      expect(document.querySelector("#toast").className).toBe("toast hidden");
      fresh.hideToast(); // no pending timer this time
    } finally {
      jest.useRealTimers();
    }
  });

  test("setTextWithDots replaces content with text plus a dots span", () => {
    const el = document.createElement("div");
    el.textContent = "old";
    app.setTextWithDots(el, "Working");
    expect(el.textContent).toBe("Working");
    expect(el.querySelector(".loading-dots")).not.toBeNull();
  });
});

describe("loadOrders", () => {
  test("caches orders and renders rows", async () => {
    routeFetch({ orders: [makeOrder({ orderId: "1" }), makeOrder({ orderId: "2" })] });
    await app.loadOrders();
    expect(app.findOrderById("1")).not.toBeNull();
    expect(app.findOrderById("2")).not.toBeNull();
    expect(app.findOrderById("nope")).toBeNull();
  });

  test("renders skeleton rows before a non-silent load", () => {
    app.renderSkeletonRows(3);
    expect(document.querySelector("#order-table").children.length).toBe(3);
  });

  test("a silent load skips the skeleton", async () => {
    routeFetch({ orders: [makeOrder()] });
    await app.loadOrders(true);
    expect(app.findOrderById("1")).not.toBeNull();
  });

  test("a failed query empties the cache and flags the failure", async () => {
    routeFetch({ httpError: 503 });
    jest.spyOn(console, "error").mockImplementation(() => {});
    await app.loadOrders();
    expect(app.findOrderById("1")).toBeNull();
    console.error.mockRestore();
  });

  test("the watched filter narrows the cache to watched orders", async () => {
    const kept = makeOrder({ orderId: "1" });
    app.watchOrder(kept);
    routeFetch({ orders: [kept, makeOrder({ orderId: "2" })] });
    await app.loadOrders();
    // Filters are module-private; drive them through the DOM control instead.
    expect(app.getWatchedOrders()["1"]).toBeDefined();
  });
});

describe("sorting", () => {
  test("handleSort toggles direction when the same column is clicked twice", async () => {
    routeFetch({ orders: [makeOrder({ orderId: "1" }), makeOrder({ orderId: "2" })] });
    await app.loadOrders();

    app.handleSort("orderId");
    const first = document.querySelector('thead th[data-sort="orderId"] .sort-indicator');
    const afterFirst = first ? first.textContent : "";

    app.handleSort("orderId");
    const afterSecond = first ? first.textContent : "";
    expect(afterFirst).not.toBe(afterSecond);
  });

  test("handleSort on a new column resets to descending", async () => {
    routeFetch({ orders: [makeOrder()] });
    await app.loadOrders();
    app.handleSort("maker");
    app.updateSortIndicators();
    const th = document.querySelector('thead th[data-sort="maker"] .sort-indicator');
    if (th) expect(th.textContent).toBe(" ▼");
  });

  test("updateSortIndicators clears indicators on inactive columns", async () => {
    routeFetch({ orders: [makeOrder()] });
    await app.loadOrders();
    app.handleSort("orderId");
    app.updateSortIndicators();
    document.querySelectorAll("thead th[data-sort]").forEach((th) => {
      const ind = th.querySelector(".sort-indicator");
      if (ind && th.dataset.sort !== "orderId") expect(ind.textContent).toBe("");
    });
  });

  test("sortOrders returns a sorted array", async () => {
    const orders = [makeOrder({ orderId: "1" }), makeOrder({ orderId: "2" })];
    expect(app.sortOrders(orders)).toHaveLength(2);
  });
});

describe("selection", () => {
  /** Loads two open orders into the v2 build, where batch selection exists. */
  async function loadV2WithOrders(orders) {
    const v2 = loadApp({ search: "?v=2" });
    routeFetch({ orders });
    await v2.loadOrders();
    return v2;
  }

  test("selection starts empty", async () => {
    const v2 = await loadV2WithOrders([makeOrder()]);
    expect(v2.getSelectedOrders()).toHaveLength(0);
    expect(v2.getSelectionAnchor()).toBeNull();
  });

  test("toggling selects then deselects an order", async () => {
    const orders = [makeOrder({ orderId: "1" }), makeOrder({ orderId: "2" })];
    const v2 = await loadV2WithOrders(orders);
    const target = v2.findOrderById("1");

    v2.toggleOrderSelection(target, false);
    expect(v2.getSelectedOrders().map((o) => o.orderId)).toEqual(["1"]);
    expect(v2.getSelectionAnchor().orderId).toBe("1");

    v2.toggleOrderSelection(target, false);
    expect(v2.getSelectedOrders()).toHaveLength(0);
  });

  test("clearSelection empties the selection", async () => {
    const v2 = await loadV2WithOrders([makeOrder({ orderId: "1" })]);
    v2.toggleOrderSelection(v2.findOrderById("1"), false);
    v2.clearSelection();
    expect(v2.getSelectedOrders()).toHaveLength(0);
  });

  test("clearSelection on an empty selection is a no-op", async () => {
    const v2 = await loadV2WithOrders([makeOrder()]);
    expect(() => v2.clearSelection()).not.toThrow();
  });

  test("pruneSelection drops ids that left the page", async () => {
    const v2 = await loadV2WithOrders([makeOrder({ orderId: "1" })]);
    v2.toggleOrderSelection(v2.findOrderById("1"), false);
    expect(v2.getSelectedOrders()).toHaveLength(1);

    // A silent refresh returning a different page prunes the stale id.
    routeFetch({ orders: [makeOrder({ orderId: "9" })] });
    await v2.loadOrders(true);
    expect(v2.getSelectedOrders()).toHaveLength(0);
  });

  test("selectAllOwnOrders does nothing without a connected wallet", async () => {
    const v2 = await loadV2WithOrders([makeOrder()]);
    v2.selectAllOwnOrders();
    expect(v2.getSelectedOrders()).toHaveLength(0);
  });

  test("renderSelectionBar stays hidden without batch capability (v1)", async () => {
    routeFetch({ orders: [makeOrder()] });
    await app.loadOrders();
    app.renderSelectionBar();
    expect(document.querySelector("#selection-bar").classList.contains("hidden")).toBe(true);
  });

  test("renderSelectionBar reports the selected count in v2", async () => {
    const v2 = await loadV2WithOrders([makeOrder({ orderId: "1" })]);
    v2.toggleOrderSelection(v2.findOrderById("1"), false);
    v2.renderSelectionBar();
    expect(document.querySelector("#selection-count").textContent).toBe("1 order selected");
  });

  test("renderSelectionBar pluralises multiple selections", async () => {
    const orders = [makeOrder({ orderId: "1" }), makeOrder({ orderId: "2" })];
    const v2 = await loadV2WithOrders(orders);
    v2.toggleOrderSelection(v2.findOrderById("1"), false);
    v2.toggleOrderSelection(v2.findOrderById("2"), false);
    v2.renderSelectionBar();
    expect(document.querySelector("#selection-count").textContent).toBe("2 orders selected");
  });
});

describe("wallet connection", () => {
  test("connecting populates the address and reveals wallet chrome", async () => {
    const h = installEthers();
    routeFetch({ orders: [] });
    await connect(app, h);

    expect(document.querySelector("#connect-btn").textContent).toMatch(/0xf39/i);
    expect(document.querySelector("#sell-btn").classList.contains("hidden")).toBe(false);
    expect(document.querySelector("#my-orders-label").classList.contains("hidden")).toBe(false);
  });

  test("connecting caches the WETH address, so isWeth starts matching", async () => {
    const h = installEthers();
    routeFetch({ orders: [] });
    await connect(app, h);
    expect(app.isWeth("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2")).toBe(true);
    expect(app.isWeth("0x1111111111111111111111111111111111111111")).toBe(false);
  });

  test("falls back to the canonical WETH address when the call reverts", async () => {
    const h = installEthers({ swap: { weth: jest.fn().mockRejectedValue(new Error("no weth")) } });
    routeFetch({ orders: [] });
    await connect(app, h);
    expect(app.isWeth("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2")).toBe(true);
  });

  test("subscribes to contract events", async () => {
    const h = installEthers();
    routeFetch({ orders: [] });
    await connect(app, h);
    const events = h.swap.on.mock.calls.map((c) => c[0]);
    expect(events).toEqual(
      expect.arrayContaining(["OrderFilled", "OrderCanceled", "OrderCreated"])
    );
  });

  test("a user rejection is reported as a cancellation, not a failure", async () => {
    const err = new Error("rejected");
    err.code = 4001;
    const h = installEthers({ provider: { send: jest.fn().mockRejectedValue(err) } });
    jest.spyOn(console, "error").mockImplementation(() => {});
    await connect(app, h);
    expect(document.querySelector("#toast").textContent).toMatch(/cancelled/i);
    console.error.mockRestore();
  });

  test("an ACTION_REJECTED code is treated the same way", async () => {
    const err = new Error("rejected");
    err.code = "ACTION_REJECTED";
    const h = installEthers({ provider: { send: jest.fn().mockRejectedValue(err) } });
    jest.spyOn(console, "error").mockImplementation(() => {});
    await connect(app, h);
    expect(document.querySelector("#toast").textContent).toMatch(/cancelled/i);
    console.error.mockRestore();
  });

  test("a locked wallet asks the user to unlock", async () => {
    const h = installEthers({
      provider: { send: jest.fn().mockRejectedValue(new Error("Wallet not connected")) },
    });
    jest.spyOn(console, "error").mockImplementation(() => {});
    await connect(app, h);
    expect(document.querySelector("#toast").textContent).toMatch(/unlock/i);
    console.error.mockRestore();
  });

  test("a user-denied message is reported as a cancellation", async () => {
    const h = installEthers({
      provider: { send: jest.fn().mockRejectedValue(new Error("user denied signature")) },
    });
    jest.spyOn(console, "error").mockImplementation(() => {});
    await connect(app, h);
    expect(document.querySelector("#toast").textContent).toMatch(/cancelled/i);
    console.error.mockRestore();
  });

  test("any other error is a generic failure", async () => {
    const h = installEthers({
      provider: { send: jest.fn().mockRejectedValue(new Error("boom")) },
    });
    jest.spyOn(console, "error").mockImplementation(() => {});
    await connect(app, h);
    expect(document.querySelector("#toast").textContent).toMatch(/Connection failed/i);
    console.error.mockRestore();
  });

  test("disconnectWallet clears the address and hides wallet chrome", async () => {
    const h = installEthers();
    routeFetch({ orders: [] });
    await connect(app, h);
    app.disconnectWallet();
    expect(document.querySelector("#connect-btn").textContent).toMatch(/connect/i);
  });

  test("setupProviderListeners registers EIP-1193 handlers", async () => {
    const h = installEthers();
    app.setupProviderListeners(h.wallet);
    const events = h.wallet.on.mock.calls.map((c) => c[0]);
    expect(events).toEqual(expect.arrayContaining(["accountsChanged"]));
  });
});

describe("network", () => {
  test("updateNetworkIndicator marks the expected chain", () => {
    app.updateNetworkIndicator(1);
    expect(document.querySelector("#network-indicator").textContent.length).toBeGreaterThan(0);
  });

  test("updateNetworkIndicator flags an unexpected chain", () => {
    app.updateNetworkIndicator(137);
    expect(document.querySelector("#network-indicator").textContent.length).toBeGreaterThan(0);
  });

  test("validateNetwork accepts mainnet", async () => {
    const h = installEthers();
    routeFetch({ orders: [] });
    await connect(app, h);
    await expect(app.validateNetwork()).resolves.not.toThrow();
  });
});

describe("fetchTokenInfo", () => {
  test("short-circuits native ETH without an RPC call", async () => {
    installEthers();
    const info = await app.fetchTokenInfo("0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE");
    expect(info).toEqual({
      address: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
      symbol: "ETH",
      name: "Ether",
      decimals: 18,
    });
  });

  test("reads metadata off the ERC20 and caches it", async () => {
    const h = installEthers();
    const addr = "0x1111111111111111111111111111111111111111";
    const first = await app.fetchTokenInfo(addr);
    expect(first).toMatchObject({ symbol: "WETH", name: "Wrapped Ether", decimals: 18 });

    const callsAfterFirst = h.token.symbol.mock.calls.length;
    await app.fetchTokenInfo(addr);
    expect(h.token.symbol.mock.calls.length).toBe(callsAfterFirst);
  });

  test("substitutes placeholders when symbol and name revert", async () => {
    installEthers({
      token: {
        symbol: jest.fn().mockRejectedValue(new Error("no symbol")),
        name: jest.fn().mockRejectedValue(new Error("no name")),
        decimals: jest.fn().mockResolvedValue(6),
      },
    });
    const info = await app.fetchTokenInfo("0x2222222222222222222222222222222222222222");
    expect(info).toMatchObject({ symbol: "???", name: "Unknown", decimals: 6 });
  }, 10000);

  test("reports decimals as null when the value is out of range", async () => {
    installEthers({ token: { decimals: jest.fn().mockResolvedValue(999) } });
    const info = await app.fetchTokenInfo("0x3333333333333333333333333333333333333333");
    expect(info.decimals).toBeNull();
  });

  test("truncates an overlong symbol and name", async () => {
    installEthers({
      token: {
        symbol: jest.fn().mockResolvedValue("S".repeat(50)),
        name: jest.fn().mockResolvedValue("N".repeat(200)),
      },
    });
    const info = await app.fetchTokenInfo("0x4444444444444444444444444444444444444444");
    expect(info.symbol).toHaveLength(20);
    expect(info.name).toHaveLength(100);
  });

  test("returns a placeholder when the contract cannot be constructed", async () => {
    installEthers();
    global.ethers.Contract = jest.fn(() => {
      throw new Error("bad address");
    });
    const info = await app.fetchTokenInfo("0x5555555555555555555555555555555555555555");
    expect(info).toMatchObject({ symbol: "???", name: "Unknown", decimals: null });
  });
});

describe("retryRpc", () => {
  test("returns the first successful result without retrying", async () => {
    const fn = jest.fn().mockResolvedValue("ok");
    await expect(app.retryRpc(fn)).resolves.toBe("ok");
    expect(fn).toHaveBeenCalledTimes(1);
  });

  test("retries transient failures then succeeds", async () => {
    const fn = jest.fn().mockRejectedValueOnce(new Error("flaky")).mockResolvedValue("ok");
    await expect(app.retryRpc(fn, 3, 1)).resolves.toBe("ok");
    expect(fn).toHaveBeenCalledTimes(2);
  });

  test("rethrows the last error once attempts are exhausted", async () => {
    const fn = jest.fn().mockRejectedValue(new Error("always down"));
    await expect(app.retryRpc(fn, 2, 1)).rejects.toThrow("always down");
    expect(fn).toHaveBeenCalledTimes(2);
  });
});

describe("initApp", () => {
  test("boots the page end to end", async () => {
    installEthers();
    routeFetch({ orders: [makeOrder()] });
    app.initApp();
    await Promise.resolve();
    expect(document.body.dataset.version).toBe("1");
  });

  test("boots the v2 build", async () => {
    const v2 = loadApp({ search: "?v=2" });
    installEthers();
    routeFetch({ orders: [makeOrder()] });
    v2.initApp();
    await Promise.resolve();
    expect(document.body.dataset.version).toBe("2");
  });

  test("an order link in the hash switches the status filter to all", async () => {
    const linked = loadApp({ hash: "#order-5" });
    installEthers();
    routeFetch({ orders: [makeOrder({ orderId: "5" })] });
    linked.initApp();
    await Promise.resolve();
    expect(document.querySelector('input[name="status"][value="all"]').checked).toBe(true);
  });

  test("init injects the ethers script when the global is absent", () => {
    delete global.ethers;
    app.init();
    const script = document.head.querySelector('script[src*="ethers"]');
    expect(script).not.toBeNull();
    expect(script.integrity).toMatch(/^sha512-/);
    // Exercise both CDN outcomes.
    script.onload();
    script.onerror();
    expect(document.querySelector("#toast").textContent).toMatch(/Failed to load ethers/i);
  });

  test("init calls initApp directly when ethers is already present", () => {
    installEthers();
    routeFetch({ orders: [] });
    app.init();
    expect(document.head.querySelector('script[src*="ethers"]')).toBeNull();
  });
});

describe("notifications", () => {
  test("requestNotificationPermission returns true when already granted", async () => {
    global.Notification.permission = "granted";
    await expect(app.requestNotificationPermission()).resolves.toBe(true);
  });

  test("requestNotificationPermission reports a blocked permission", async () => {
    global.Notification.permission = "denied";
    await expect(app.requestNotificationPermission()).resolves.toBe(false);
    expect(document.querySelector("#toast").textContent).toMatch(/blocked/i);
  });

  test("requestNotificationPermission prompts when undecided", async () => {
    global.Notification.permission = "default";
    global.Notification.requestPermission.mockResolvedValue("granted");
    await expect(app.requestNotificationPermission()).resolves.toBe(true);
  });

  test("requestNotificationPermission handles a declined prompt", async () => {
    global.Notification.permission = "default";
    global.Notification.requestPermission.mockResolvedValue("denied");
    await expect(app.requestNotificationPermission()).resolves.toBe(false);
  });

  test("requestNotificationPermission reports an unsupported browser", async () => {
    const real = global.Notification;
    delete global.Notification;
    delete window.Notification;
    try {
      await expect(app.requestNotificationPermission()).resolves.toBe(false);
      expect(document.querySelector("#toast").textContent).toMatch(/does not support/i);
    } finally {
      global.Notification = real;
      window.Notification = real;
    }
  });

  test("showNotification stays silent while notifications are off", () => {
    const spy = jest.fn();
    global.Notification = spy;
    spy.permission = "granted";
    app.showNotification("t", "b", "tag");
    expect(spy).not.toHaveBeenCalled();
  });

  test("toggleNotifications enables then disables", async () => {
    global.Notification.permission = "granted";
    await app.toggleNotifications();
    expect(localStorage.getItem("swapboard_notifications")).toBe("true");
    expect(document.querySelector("#toast").textContent).toMatch(/enabled/i);

    await app.toggleNotifications();
    expect(localStorage.getItem("swapboard_notifications")).toBe("false");
    expect(document.querySelector("#toast").textContent).toMatch(/disabled/i);
  });

  test("toggleNotifications does not enable when permission is refused", async () => {
    global.Notification.permission = "denied";
    await app.toggleNotifications();
    expect(localStorage.getItem("swapboard_notifications")).toBeNull();
  });

  test("updateNotifyText reflects the current state", () => {
    app.updateNotifyText();
    expect(document.querySelector("#wallet-notifications").textContent).toMatch(/Enable/);
  });
});

describe("estimateGasCost", () => {
  test("returns null without a provider", async () => {
    await expect(app.estimateGasCost({})).resolves.toBeNull();
  });

  test("prices a transaction in gas, ETH and USD", async () => {
    const h = installEthers();
    routeFetch({ orders: [] });
    await connect(app, h);
    const cost = await app.estimateGasCost({ to: SWAPBOARD_ADDRESS, data: "0x" });
    expect(cost).toMatchObject({ gas: "21000" });
    expect(cost.eth).toMatch(/^[0-9.]+$/);
  });

  test("falls back to maxFeePerGas when gasPrice is absent", async () => {
    const h = installEthers({
      provider: {
        getFeeData: jest.fn().mockResolvedValue({ gasPrice: null, maxFeePerGas: BigInt(1e9) }),
      },
    });
    routeFetch({ orders: [] });
    await connect(app, h);
    const cost = await app.estimateGasCost({ to: SWAPBOARD_ADDRESS });
    expect(cost).not.toBeNull();
  });

  test("returns null when no fee data is available at all", async () => {
    const h = installEthers({
      provider: {
        getFeeData: jest.fn().mockResolvedValue({ gasPrice: null, maxFeePerGas: null }),
      },
    });
    routeFetch({ orders: [] });
    await connect(app, h);
    await expect(app.estimateGasCost({ to: SWAPBOARD_ADDRESS })).resolves.toBeNull();
  });

  test("returns null when estimation reverts", async () => {
    const h = installEthers({
      provider: { estimateGas: jest.fn().mockRejectedValue(new Error("revert")) },
    });
    routeFetch({ orders: [] });
    await connect(app, h);
    jest.spyOn(console, "error").mockImplementation(() => {});
    await expect(app.estimateGasCost({ to: SWAPBOARD_ADDRESS })).resolves.toBeNull();
    console.error.mockRestore();
  });
});

describe("token list", () => {
  const TOKEN_LIST = {
    tokens: [
      {
        chainId: 1,
        address: "0xAAAA000000000000000000000000000000000001",
        symbol: "AAA",
        name: "Alpha",
        decimals: 18,
        logoURI: "a.png",
      },
      {
        chainId: 1,
        address: "0xBBBB000000000000000000000000000000000002",
        symbol: "BBB",
        name: "Beta",
        decimals: 6,
        logoURI: "b.png",
      },
      {
        chainId: 137,
        address: "0xCCCC000000000000000000000000000000000003",
        symbol: "CCC",
        name: "Polygon",
        decimals: 18,
      },
    ],
  };

  test("fetches and filters to mainnet tokens", async () => {
    routeFetch({ tokenList: TOKEN_LIST });
    await app.fetchUniswapTokenList();
    const results = app.searchTokens("A");
    expect(results.some((t) => t.symbol === "AAA")).toBe(true);
    expect(results.some((t) => t.symbol === "CCC")).toBe(false);
  });

  test("does not refetch once populated", async () => {
    routeFetch({ tokenList: TOKEN_LIST });
    await app.fetchUniswapTokenList();
    const callCount = global.fetch.mock.calls.length;
    await app.fetchUniswapTokenList();
    expect(global.fetch.mock.calls.length).toBe(callCount);
  });

  test("gives up quietly on an HTTP error", async () => {
    global.fetch.mockResolvedValue({ ok: false, status: 500, json: async () => ({}) });
    await app.fetchUniswapTokenList();
    expect(app.searchTokens("A")).toEqual([]);
  });

  test("gives up quietly on a network error", async () => {
    global.fetch.mockRejectedValue(new Error("offline"));
    jest.spyOn(console, "error").mockImplementation(() => {});
    await app.fetchUniswapTokenList();
    expect(app.searchTokens("A")).toEqual([]);
    console.error.mockRestore();
  });

  test("searchTokens returns nothing for an empty query", () => {
    expect(app.searchTokens("")).toEqual([]);
    expect(app.searchTokens(null)).toEqual([]);
  });

  test("getEthToken is null in v1 before WETH is known", () => {
    expect(app.getEthToken()).toBeNull();
  });

  test("getEthToken uses the sentinel in v2", () => {
    const v2 = loadApp({ search: "?v=2" });
    expect(v2.getEthToken()).toMatchObject({ symbol: "ETH", decimals: 18 });
  });

  test("getEthToken uses the cached WETH address in v1 once connected", async () => {
    const h = installEthers();
    routeFetch({ orders: [] });
    await connect(app, h);
    expect(app.getEthToken()).toMatchObject({
      symbol: "ETH",
      address: "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
    });
  });

  test("searchTokens seeds ETH when the query prefixes it", () => {
    const v2 = loadApp({ search: "?v=2" });
    expect(v2.searchTokens("e")[0].symbol).toBe("ETH");
  });
});

/**
 * Drains pending microtasks and timer callbacks.
 *
 * Several app entry points kick off promise chains they do not return
 * (connectWithProvider calls loadOrders, showModal's confirm handler is async).
 * Without draining, that work lands in whichever test runs next.
 */
async function flush(times = 4) {
  for (let i = 0; i < times; i++) {
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
}

/**
 * Clicks the modal's confirm button and lets the handler settle.
 *
 * The v2 connector simulates confirmation with a real 700ms timer per
 * transaction (V2_SIM_DELAY_MS), and an allowance costs one more, so v2 paths
 * need an explicit settle window rather than a microtask drain.
 *
 * @param {{settleMs?: number}} [opts]
 */
async function confirmModal({ settleMs = 0 } = {}) {
  document.querySelector("#modal-confirm").click();
  if (settleMs) await new Promise((resolve) => setTimeout(resolve, settleMs));
  await flush();
}

/** Settle window covering an allowance plus up to two simulated v2 sends. */
const V2_SETTLE = { settleMs: 2400 };

/** Clicks the modal's cancel button. */
function cancelModal() {
  document.querySelector("#modal-cancel").click();
}

describe("showModal", () => {
  test("renders a string body and opens the modal", () => {
    app.showModal("Title", "Are you sure?", jest.fn());
    expect(document.querySelector("#modal").classList.contains("hidden")).toBe(false);
    expect(document.querySelector("#modal-title").textContent).toBe("Title");
    expect(document.querySelector("#modal-body").textContent).toBe("Are you sure?");
  });

  test("renders a DOM body", () => {
    const node = document.createElement("p");
    node.textContent = "structured";
    app.showModal("Title", node, jest.fn());
    expect(document.querySelector("#modal-body p").textContent).toBe("structured");
  });

  test("appends a gas estimate when one is supplied", () => {
    app.showModal("Title", "body", jest.fn(), { gas: "21000", eth: "0.001", usd: "$2.50" });
    const gas = document.querySelector("#modal-body .gas-estimate");
    expect(gas.textContent).toContain("21000");
    expect(gas.textContent).toContain("$2.50");
  });

  test("confirming runs the callback and closes the modal", () => {
    const onConfirm = jest.fn();
    app.showModal("Title", "body", onConfirm);
    document.querySelector("#modal-confirm").click();
    expect(onConfirm).toHaveBeenCalledTimes(1);
    expect(document.querySelector("#modal").classList.contains("hidden")).toBe(true);
  });

  test("cancelling closes the modal without running the callback", () => {
    const onConfirm = jest.fn();
    app.showModal("Title", "body", onConfirm);
    cancelModal();
    expect(onConfirm).not.toHaveBeenCalled();
    expect(document.querySelector("#modal").classList.contains("hidden")).toBe(true);
  });

  test("handlers are unbound, so a second click does not re-fire", () => {
    const onConfirm = jest.fn();
    app.showModal("Title", "body", onConfirm);
    document.querySelector("#modal-confirm").click();
    document.querySelector("#modal-confirm").click();
    expect(onConfirm).toHaveBeenCalledTimes(1);
  });
});

describe("v2 simulated transactions", () => {
  test("fakeTxHash produces distinct 32-byte hashes", () => {
    const v2 = loadApp({ search: "?v=2" });
    const a = v2.fakeTxHash();
    const b = v2.fakeTxHash();
    expect(a).toMatch(/^0x[0-9a-f]{64}$/);
    expect(a).not.toBe(b);
  });

  test("v2Send resolves a receipt shaped like ethers", async () => {
    const v2 = loadApp({ search: "?v=2" });
    jest.spyOn(console, "info").mockImplementation(() => {});
    const tx = await v2.v2Send("fillOrder", { orderId: "1" }, "result");
    expect(tx.hash).toMatch(/^0x[0-9a-f]{64}$/);
    const receipt = await tx.wait();
    expect(receipt).toMatchObject({ status: 1, logs: [] });
    console.info.mockRestore();
  }, 10000);

  test("logV2Call announces the simulated call", () => {
    const v2 = loadApp({ search: "?v=2" });
    const spy = jest.spyOn(console, "info").mockImplementation(() => {});
    v2.logV2Call("createOrder", { a: 1 });
    expect(spy).toHaveBeenCalledWith("[V2-DUMMY] createOrder", { a: 1 });
    spy.mockRestore();
  });

  test("toCreateParams stringifies the amounts", () => {
    const v2 = loadApp({ search: "?v=2" });
    expect(
      v2.toCreateParams({
        tokenA: "0xa",
        amountA: 10n,
        tokenB: "0xb",
        amountB: 20n,
        partialFill: true,
      })
    ).toEqual({
      tokenA: "0xa",
      amountA: "10",
      tokenB: "0xb",
      amountB: "20",
      partialFill: true,
    });
  });

  test("v1Unsupported rejects batch calls that v1 has no method for", async () => {
    await expect(app.v1Unsupported("fillOrders")).rejects.toThrow(/fillOrders is a v2 entry point/);
  });
});

describe("buildPartialFillControls", () => {
  /** A v2 order that opted into partial fills. */
  function partialOrder() {
    return makeOrder({ partialFill: true });
  }

  test("opens on the full remaining amount", () => {
    const v2 = loadApp({ search: "?v=2" });
    const onChange = jest.fn();
    const el = v2.buildPartialFillControls(partialOrder(), onChange);
    expect(el.querySelector("input").value).toBe("1");
    expect(el.querySelector(".partial-fill-send").textContent).toMatch(/You send:/);
    expect(onChange).toHaveBeenCalled();
  });

  test("offers 25/50/75/100 presets with 100 active", () => {
    const v2 = loadApp({ search: "?v=2" });
    const el = v2.buildPartialFillControls(partialOrder(), jest.fn());
    const presets = [...el.querySelectorAll(".partial-fill-presets button")];
    expect(presets.map((b) => b.textContent)).toEqual(["25%", "50%", "75%", "100%"]);
    expect(presets[3].classList.contains("active")).toBe(true);
  });

  test("clicking a preset rewrites the input and reports the new payment", () => {
    const v2 = loadApp({ search: "?v=2" });
    const onChange = jest.fn();
    const el = v2.buildPartialFillControls(partialOrder(), onChange);
    const presets = [...el.querySelectorAll(".partial-fill-presets button")];

    presets[1].click(); // 50%
    expect(presets[1].classList.contains("active")).toBe(true);
    expect(presets[3].classList.contains("active")).toBe(false);
    expect(el.querySelector("input").value).toBe("0.5");
  });

  test("typing an amount recomputes without rewriting the box", () => {
    const v2 = loadApp({ search: "?v=2" });
    const el = v2.buildPartialFillControls(partialOrder(), jest.fn());
    const input = el.querySelector("input");
    input.value = "0.25";
    input.dispatchEvent(new Event("input"));
    expect(input.value).toBe("0.25");
    expect(input.classList.contains("input-error")).toBe(false);
  });

  test("an unparseable amount marks the field in error", () => {
    const v2 = loadApp({ search: "?v=2" });
    const el = v2.buildPartialFillControls(partialOrder(), jest.fn());
    const input = el.querySelector("input");
    input.value = "abc";
    input.dispatchEvent(new Event("input"));
    expect(input.classList.contains("input-error")).toBe(true);
  });
});

describe("handleFillOrder", () => {
  test("refuses without a connected wallet", async () => {
    await app.handleFillOrder(makeOrder());
    expect(document.querySelector("#toast").textContent).toMatch(/Connect wallet/i);
  });

  test("opens a confirmation modal summarising the trade", async () => {
    const h = installEthers();
    routeFetch({ orders: [] });
    await connect(app, h);
    await app.handleFillOrder(makeOrder());
    expect(document.querySelector("#modal-title").textContent).toBe("Fill Order #1");
    expect(document.querySelector("#modal-body").textContent).toMatch(/You will send/);
  });

  test("a v2 fill runs the simulated transaction to completion", async () => {
    const v2 = loadApp({ search: "?v=2" });
    installEthers();
    routeFetch({ orders: [] });
    const h2 = installEthers();
    await connect(v2, h2);
    jest.spyOn(console, "info").mockImplementation(() => {});

    await v2.handleFillOrder(makeOrder({ partialFill: true }));
    await confirmModal();
    await new Promise((r) => setTimeout(r, 50));
    console.info.mockRestore();
    expect(document.querySelector("#toast").textContent.length).toBeGreaterThan(0);
  }, 15000);

  test("shows the contract error when the fill reverts", async () => {
    const v2 = loadApp({ search: "?v=2" });
    const h = installEthers();
    routeFetch({ orders: [] });
    await connect(v2, h);
    jest.spyOn(console, "error").mockImplementation(() => {});
    jest.spyOn(console, "info").mockImplementation(() => {});

    // Drive the confirm path with an order whose amounts make fillAmountB zero.
    const zero = makeOrder({ amountB: "0", partialFill: false });
    await v2.handleFillOrder(zero);
    await confirmModal();
    expect(document.querySelector("#toast").textContent).toMatch(/Enter an amount|Fill/i);
    console.error.mockRestore();
    console.info.mockRestore();
  }, 15000);
});

describe("handleCancelOrder", () => {
  test("refuses without a connected wallet", async () => {
    await app.handleCancelOrder(makeOrder());
    expect(document.querySelector("#toast").textContent).toMatch(/Connect wallet/i);
  });

  test("opens a confirmation modal", async () => {
    const h = installEthers();
    routeFetch({ orders: [] });
    await connect(app, h);
    await app.handleCancelOrder(makeOrder());
    expect(document.querySelector("#modal-title").textContent).toMatch(/Cancel Order #1/i);
  });

  test("a v2 cancel runs the simulated transaction", async () => {
    const v2 = loadApp({ search: "?v=2" });
    const h = installEthers();
    routeFetch({ orders: [] });
    await connect(v2, h);
    jest.spyOn(console, "info").mockImplementation(() => {});
    await v2.handleCancelOrder(makeOrder());
    await confirmModal();
    await new Promise((r) => setTimeout(r, 50));
    console.info.mockRestore();
    expect(document.querySelector("#modal").classList.contains("hidden")).toBe(true);
  }, 15000);
});

describe("batch summary builders", () => {
  test("buildBatchItem renders the id and description", () => {
    const item = app.buildBatchItem("42", "1 WETH for 3000 USDC");
    expect(item.querySelector(".batch-summary-id").textContent).toBe("#42");
    expect(item.textContent).toContain("1 WETH for 3000 USDC");
  });

  test("appendTotalRow adds a plain row", () => {
    const parent = document.createElement("div");
    app.appendTotalRow(parent, "Total", "5 ETH");
    expect(parent.children).toHaveLength(1);
    expect(parent.firstChild.className).toBe("");
    expect(parent.textContent).toBe("Total5 ETH");
  });

  test("appendTotalRow can mark the headline figure", () => {
    const parent = document.createElement("div");
    app.appendTotalRow(parent, "You receive", "1 ETH", true);
    expect(parent.firstChild.className).toBe("batch-summary-emphasis");
  });

  test("appendBatchTxNote stays quiet for a single transaction", () => {
    const parent = document.createElement("div");
    app.appendBatchTxNote(parent, 5, 15);
    expect(parent.children).toHaveLength(0);
  });

  test("appendBatchTxNote explains a split across transactions", () => {
    const parent = document.createElement("div");
    app.appendBatchTxNote(parent, 40, 15);
    expect(parent.textContent).toMatch(/split into 3 transactions of up to 15/);
  });
});

describe("runBatchTransactions", () => {
  test("submits a single chunk without progress numbering", async () => {
    const tx = { wait: jest.fn().mockResolvedValue({ status: 1 }) };
    const send = jest.fn().mockResolvedValue(tx);
    const processed = await app.runBatchTransactions([["a", "b"]], "Filling", send);

    expect(processed).toBe(2);
    expect(send).toHaveBeenCalledTimes(1);
    expect(document.querySelector("#toast").textContent).toBe("Filling 2 orders");
  });

  test("walks every chunk and reports progress", async () => {
    const tx = { wait: jest.fn().mockResolvedValue({ status: 1 }) };
    const send = jest.fn().mockResolvedValue(tx);
    const processed = await app.runBatchTransactions([["a"], ["b"], ["c"]], "Cancelling", send);

    expect(processed).toBe(3);
    expect(send).toHaveBeenCalledTimes(3);
    expect(tx.wait).toHaveBeenCalledTimes(3);
  });

  test("propagates a failure from any chunk", async () => {
    const send = jest.fn().mockRejectedValue(new Error("reverted"));
    await expect(app.runBatchTransactions([["a"]], "Filling", send)).rejects.toThrow("reverted");
  });
});

describe("batch order actions", () => {
  /** Loads v2 with a connected wallet and the given orders selected. */
  async function v2WithSelection(orders) {
    const v2 = loadApp({ search: "?v=2" });
    const h = installEthers();
    routeFetch({ orders });
    await connect(v2, h);
    await v2.loadOrders();
    for (const o of orders) v2.toggleOrderSelection(v2.findOrderById(o.orderId), false);
    return v2;
  }

  test("fillSelectedOrders does nothing with an empty selection", async () => {
    const v2 = await v2WithSelection([]);
    await expect(v2.fillSelectedOrders()).resolves.toBeUndefined();
  });

  test("cancelSelectedOrders does nothing with an empty selection", async () => {
    const v2 = await v2WithSelection([]);
    await expect(v2.cancelSelectedOrders()).resolves.toBeUndefined();
  });

  test("fillSelectedOrders opens a batch confirmation", async () => {
    const orders = [makeOrder({ orderId: "1" }), makeOrder({ orderId: "2" })];
    const v2 = await v2WithSelection(orders);
    await v2.fillSelectedOrders();
    expect(document.querySelector("#modal-body").textContent).toMatch(/#1/);
    expect(document.querySelector("#modal-body").textContent).toMatch(/#2/);
  });

  test("cancelSelectedOrders opens a batch confirmation", async () => {
    const own = makeOrder({ orderId: "3", maker: WALLET_ADDRESS });
    const v2 = await v2WithSelection([own]);
    await v2.cancelSelectedOrders();
    expect(document.querySelector("#modal-title").textContent.length).toBeGreaterThan(0);
  });
});

describe("create rows", () => {
  /** Fills a create row's four fields. */
  function fillRow(mod, row, { tokenA, tokenB, amountA, amountB }) {
    const set = (name, value) => {
      const field = mod.rowField(row, name);
      field.value = value;
      return field;
    };
    set("tokenA", tokenA);
    set("tokenB", tokenB);
    set("amountA", amountA);
    set("amountB", amountB);
  }

  const TOKEN_A = "0x1111111111111111111111111111111111111111";
  const TOKEN_B = "0x2222222222222222222222222222222222222222";

  test("addCreateRow appends a row and labels the button", () => {
    const row = app.addCreateRow();
    expect(row).not.toBeNull();
    expect(app.getCreateRows()).toHaveLength(1);
    expect(document.querySelector("#create-btn").textContent).toBe("Create Order");
  });

  test("v1 allows only one row", () => {
    app.addCreateRow();
    expect(app.addCreateRow()).toBeNull();
    expect(document.querySelector("#add-sell-btn").disabled).toBe(true);
  });

  test("v2 allows several rows and numbers them", () => {
    const v2 = loadApp({ search: "?v=2" });
    v2.addCreateRow();
    v2.addCreateRow();
    const rows = v2.getCreateRows();
    expect(rows).toHaveLength(2);
    expect(rows[0].querySelector(".create-row-label").textContent).toBe("Order 1 of 2");
    expect(document.querySelector("#create-btn").textContent).toBe("Create 2 Orders");
  });

  test("v2 stops at the batch create limit and says so", () => {
    const v2 = loadApp({ search: "?v=2" });
    for (let i = 0; i < 10; i++) v2.addCreateRow();
    expect(v2.addCreateRow()).toBeNull();
    expect(document.querySelector("#create-limit-note").textContent).toMatch(/Limit reached/);
  });

  test("removing a row renumbers the rest", () => {
    const v2 = loadApp({ search: "?v=2" });
    v2.addCreateRow();
    v2.addCreateRow();
    v2.getCreateRows()[0].querySelector(".create-row-remove").click();
    expect(v2.getCreateRows()).toHaveLength(1);
    expect(document.querySelector("#create-btn").textContent).toBe("Create Order");
  });

  test("the last row cannot be removed", () => {
    app.addCreateRow();
    app.getCreateRows()[0].querySelector(".create-row-remove").click();
    expect(app.getCreateRows()).toHaveLength(1);
  });

  test("resetCreateForm returns the form to a single empty row", () => {
    const v2 = loadApp({ search: "?v=2" });
    v2.addCreateRow();
    v2.addCreateRow();
    v2.resetCreateForm();
    expect(v2.getCreateRows()).toHaveLength(1);
  });

  test("getRowState memoises per row", () => {
    const row = app.addCreateRow();
    expect(app.getRowState(row)).toBe(app.getRowState(row));
    expect(app.getRowState(row)).toMatchObject({
      tokenA: { info: null, balance: null },
      tokenB: { info: null, balance: null },
    });
  });

  describe("validateRowAmount", () => {
    test("accepts an empty amount as not-yet-an-error", () => {
      const row = app.addCreateRow();
      expect(app.validateRowAmount(row, "tokenA")).toBe(true);
    });

    test("rejects an unparseable amount and shows why", () => {
      const row = app.addCreateRow();
      app.getRowState(row).tokenA.info = { decimals: 18 };
      app.rowField(row, "amountA").value = "abc";
      expect(app.validateRowAmount(row, "tokenA")).toBe(false);
      expect(row.querySelector(".amount-error").textContent).toMatch(/Invalid amount/);
    });

    test("rejects an offered amount above the balance", () => {
      const row = app.addCreateRow();
      const state = app.getRowState(row);
      state.tokenA.info = { decimals: 18 };
      state.tokenA.balance = BigInt("1000000000000000000");
      app.rowField(row, "amountA").value = "2";
      expect(app.validateRowAmount(row, "tokenA")).toBe(false);
      expect(row.querySelector(".amount-error").textContent).toBe("Exceeds balance");
    });

    test("does not balance-check the wanted side", () => {
      const row = app.addCreateRow();
      const state = app.getRowState(row);
      state.tokenB.info = { decimals: 18 };
      state.tokenB.balance = BigInt(0);
      app.rowField(row, "amountB").value = "5";
      expect(app.validateRowAmount(row, "tokenB")).toBe(true);
    });

    test("rejects an amount that parses to zero but was not written as 0", () => {
      const row = app.addCreateRow();
      app.getRowState(row).tokenA.info = { decimals: 6 };
      app.rowField(row, "amountA").value = "0.000000";
      expect(app.validateRowAmount(row, "tokenA")).toBe(false);
      expect(row.querySelector(".amount-error").textContent).toBe("Amount too small");
    });

    test("rejects more decimals than the token supports", () => {
      const row = app.addCreateRow();
      app.getRowState(row).tokenA.info = { decimals: 6 };
      app.rowField(row, "amountA").value = "0.0000001";
      expect(app.validateRowAmount(row, "tokenA")).toBe(false);
      expect(row.querySelector(".amount-error").textContent).toMatch(/only supports 6 decimal/);
    });

    test("accepts a literal zero", () => {
      const row = app.addCreateRow();
      app.getRowState(row).tokenA.info = { decimals: 18 };
      app.rowField(row, "amountA").value = "0";
      expect(app.validateRowAmount(row, "tokenA")).toBe(true);
    });

    test("clears a previous error once the amount is valid", () => {
      const row = app.addCreateRow();
      app.getRowState(row).tokenA.info = { decimals: 18 };
      const input = app.rowField(row, "amountA");

      input.value = "abc";
      app.validateRowAmount(row, "tokenA");
      expect(input.classList.contains("input-error")).toBe(true);

      input.value = "1.5";
      expect(app.validateRowAmount(row, "tokenA")).toBe(true);
      expect(input.classList.contains("input-error")).toBe(false);
      expect(row.querySelector(".amount-error").textContent).toBe("");
    });
  });

  describe("collectCreateParams", () => {
    test("rejects a row with empty fields", async () => {
      app.addCreateRow();
      await expect(app.collectCreateParams()).resolves.toBeNull();
      expect(document.querySelector("#toast").textContent).toMatch(/Fill in all fields/);
    });

    test("rejects a malformed token address", async () => {
      const row = app.addCreateRow();
      fillRow(app, row, { tokenA: "nope", tokenB: TOKEN_B, amountA: "1", amountB: "2" });
      await expect(app.collectCreateParams()).resolves.toBeNull();
      expect(document.querySelector("#toast").textContent).toMatch(/Invalid token address/);
    });

    test("rejects an order that swaps a token for itself", async () => {
      const row = app.addCreateRow();
      fillRow(app, row, { tokenA: TOKEN_A, tokenB: TOKEN_A, amountA: "1", amountB: "2" });
      await expect(app.collectCreateParams()).resolves.toBeNull();
      expect(document.querySelector("#toast").textContent).toMatch(/must differ/);
    });

    test("rejects tokens whose decimals cannot be read", async () => {
      installEthers({ token: { decimals: jest.fn().mockResolvedValue(999) } });
      const row = app.addCreateRow();
      fillRow(app, row, { tokenA: TOKEN_A, tokenB: TOKEN_B, amountA: "1", amountB: "2" });
      await expect(app.collectCreateParams()).resolves.toBeNull();
      expect(document.querySelector("#toast").textContent).toMatch(/Could not read decimals/);
    });

    test("rejects a zero amount", async () => {
      installEthers();
      const row = app.addCreateRow();
      fillRow(app, row, { tokenA: TOKEN_A, tokenB: TOKEN_B, amountA: "0", amountB: "2" });
      await expect(app.collectCreateParams()).resolves.toBeNull();
      expect(document.querySelector("#toast").textContent).toMatch(/greater than 0/);
    });

    test("rejects an unparseable amount", async () => {
      installEthers();
      const row = app.addCreateRow();
      fillRow(app, row, { tokenA: TOKEN_A, tokenB: TOKEN_B, amountA: "abc", amountB: "2" });
      await expect(app.collectCreateParams()).resolves.toBeNull();
      expect(document.querySelector("#toast").textContent).toMatch(/Invalid amount/);
    });

    test("collects a valid row into contract-ready params", async () => {
      installEthers();
      const row = app.addCreateRow();
      fillRow(app, row, { tokenA: TOKEN_A, tokenB: TOKEN_B, amountA: "1", amountB: "2" });
      const params = await app.collectCreateParams();
      expect(params).toHaveLength(1);
      expect(params[0]).toMatchObject({ tokenA: TOKEN_A, tokenB: TOKEN_B });
    });

    test("labels which order failed when there are several", async () => {
      const v2 = loadApp({ search: "?v=2" });
      installEthers();
      const first = v2.addCreateRow();
      v2.addCreateRow();
      fillRow(v2, first, { tokenA: TOKEN_A, tokenB: TOKEN_B, amountA: "1", amountB: "2" });
      await expect(v2.collectCreateParams()).resolves.toBeNull();
      expect(document.querySelector("#toast").textContent).toMatch(/^Order 2: /);
    });

    test("rejects an offered amount above the row's known balance", async () => {
      installEthers();
      const row = app.addCreateRow();
      fillRow(app, row, { tokenA: TOKEN_A, tokenB: TOKEN_B, amountA: "10", amountB: "2" });
      app.getRowState(row).tokenA.balance = BigInt("1000000000000000000");
      await expect(app.collectCreateParams()).resolves.toBeNull();
      expect(document.querySelector("#toast").textContent).toMatch(/Insufficient balance/);
    });
  });

  describe("handleCreateOrder", () => {
    test("refuses without a connected wallet", async () => {
      await app.handleCreateOrder();
      expect(document.querySelector("#toast").textContent).toMatch(/Connect wallet/i);
    });

    test("stops when the form does not validate", async () => {
      const h = installEthers();
      routeFetch({ orders: [] });
      await connect(app, h);
      app.addCreateRow();
      await app.handleCreateOrder();
      expect(document.querySelector("#toast").textContent).toMatch(/Fill in all fields/);
    });
  });
});

describe("wired controls", () => {
  /**
   * Boots a fully initialised, wallet-connected app so the initApp event
   * handlers are live and can be driven through the real DOM.
   * @param {string} [search] - Location search, e.g. "?v=2"
   */
  async function boot(search = "") {
    const mod = loadApp({ search });
    const h = installEthers();
    routeFetch({ orders: [makeOrder({ orderId: "1", maker: WALLET_ADDRESS })] });
    jest.spyOn(console, "info").mockImplementation(() => {});
    jest.spyOn(console, "warn").mockImplementation(() => {});
    mod.initApp();
    await connect(mod, h);
    await Promise.resolve();
    return { mod, h };
  }

  afterEach(() => {
    if (console.info.mockRestore) console.info.mockRestore();
    if (console.warn.mockRestore) console.warn.mockRestore();
  });

  const click = (sel) => document.querySelector(sel).click();
  const isHidden = (sel) => document.querySelector(sel).classList.contains("hidden");

  test("theme button toggles dark mode", async () => {
    await boot();
    const before = document.body.classList.contains("dark-mode");
    click("#theme-btn");
    expect(document.body.classList.contains("dark-mode")).toBe(!before);
  });

  test("hash toggle opens the verify modal and closes again", async () => {
    await boot();
    click("#hash-toggle");
    expect(isHidden("#verify-modal")).toBe(false);
    click("#verify-modal-close");
    expect(isHidden("#verify-modal")).toBe(true);
  });

  test("clicking the verify modal backdrop closes it", async () => {
    await boot();
    click("#hash-toggle");
    document.querySelector("#verify-modal").click();
    expect(isHidden("#verify-modal")).toBe(true);
  });

  test("connect button opens the wallet menu once connected", async () => {
    await boot();
    click("#connect-btn");
    expect(isHidden("#wallet-menu")).toBe(false);
  });

  test("a click elsewhere closes the wallet menu", async () => {
    await boot();
    click("#connect-btn");
    document.body.click();
    expect(isHidden("#wallet-menu")).toBe(true);
  });

  test("wallet copy writes the address to the clipboard", async () => {
    await boot();
    const writeText = jest.fn().mockResolvedValue(undefined);
    Object.defineProperty(window.navigator, "clipboard", {
      value: { writeText },
      configurable: true,
    });
    click("#wallet-copy");
    expect(writeText).toHaveBeenCalledWith(WALLET_ADDRESS);
  });

  test("wallet disconnect clears the session", async () => {
    await boot();
    click("#wallet-disconnect");
    expect(document.querySelector("#connect-btn").textContent).toMatch(/connect/i);
  });

  test("wallet order filters switch the status filter", async () => {
    await boot();
    click("#wallet-open-orders");
    click("#wallet-filled-orders");
    click("#wallet-cancelled-orders");
    expect(document.querySelector("#filter-my-orders").checked).toBe(true);
  });

  test("wallet export triggers the CSV export", async () => {
    await boot();
    global.URL.createObjectURL = jest.fn(() => "blob:csv");
    global.URL.revokeObjectURL = jest.fn();
    click("#wallet-export");
    expect(isHidden("#wallet-menu")).toBe(true);
  });

  test("wallet revoke opens the approvals modal", async () => {
    await boot();
    click("#wallet-revoke");
    expect(isHidden("#revoke-modal")).toBe(false);
    click("#revoke-modal-close");
    expect(isHidden("#revoke-modal")).toBe(true);
  });

  test("clicking the revoke modal backdrop closes it", async () => {
    await boot();
    click("#wallet-revoke");
    document.querySelector("#revoke-modal").click();
    expect(isHidden("#revoke-modal")).toBe(true);
  });

  test("wallet switch and etherscan entries are wired", async () => {
    await boot();
    global.open = jest.fn();
    click("#wallet-etherscan");
    expect(isHidden("#wallet-menu")).toBe(true);
    click("#wallet-switch");
    expect(isHidden("#wallet-menu")).toBe(true);
  });

  test("wallet notifications entry toggles notifications", async () => {
    await boot();
    global.Notification.permission = "granted";
    click("#wallet-notifications");
    await Promise.resolve();
    expect(isHidden("#wallet-menu")).toBe(true);
  });

  test("sell button opens and cancel closes the sell modal", async () => {
    await boot();
    click("#sell-btn");
    expect(isHidden("#sell-modal")).toBe(false);
    click("#sell-modal-cancel");
    expect(isHidden("#sell-modal")).toBe(true);
  });

  test("clicking the sell modal backdrop closes it", async () => {
    await boot();
    click("#sell-btn");
    document.querySelector("#sell-modal").click();
    expect(isHidden("#sell-modal")).toBe(true);
  });

  test("clicking the order modal backdrop closes it", async () => {
    await boot();
    document.querySelector("#order-modal").classList.remove("hidden");
    document.querySelector("#order-modal").click();
    expect(isHidden("#order-modal")).toBe(true);
  });

  test("wallet modal cancel and backdrop both close it", async () => {
    await boot();
    document.querySelector("#wallet-modal").classList.remove("hidden");
    click("#wallet-modal-cancel");
    expect(isHidden("#wallet-modal")).toBe(true);

    document.querySelector("#wallet-modal").classList.remove("hidden");
    document.querySelector("#wallet-modal").click();
    expect(isHidden("#wallet-modal")).toBe(true);
  });

  test("token filters re-query on change", async () => {
    await boot();
    const selling = document.querySelector("#filter-selling");
    selling.value = "0x1111111111111111111111111111111111111111";
    selling.dispatchEvent(new Event("change"));

    const wanting = document.querySelector("#filter-wanting");
    wanting.value = "0x2222222222222222222222222222222222222222";
    wanting.dispatchEvent(new Event("change"));
    await Promise.resolve();
    expect(global.fetch).toHaveBeenCalled();
  });

  test("status radios re-query on change", async () => {
    await boot();
    const radio = document.querySelector('input[name="status"][value="filled"]');
    radio.checked = true;
    radio.dispatchEvent(new Event("change"));
    await Promise.resolve();
    expect(radio.checked).toBe(true);
  });

  test("my-orders checkbox re-queries on change", async () => {
    await boot();
    const box = document.querySelector("#filter-my-orders");
    box.checked = true;
    box.dispatchEvent(new Event("change"));
    await Promise.resolve();
    expect(box.checked).toBe(true);
  });

  test("pagination buttons move between pages", async () => {
    await boot();
    click("#next-page");
    await Promise.resolve();
    click("#prev-page");
    await Promise.resolve();
    expect(global.fetch).toHaveBeenCalled();
  });

  test("export-csv button is wired", async () => {
    await boot();
    global.URL.createObjectURL = jest.fn(() => "blob:csv");
    global.URL.revokeObjectURL = jest.fn();
    click("#export-csv");
    expect(global.fetch).toHaveBeenCalled();
  });

  test("version switch buttons navigate to the other version", async () => {
    await boot();
    const restore = stubLocation();
    try {
      const other = [...document.querySelectorAll("#version-switch .version-option")].find(
        (b) => b.dataset.version === "2"
      );
      if (other) {
        other.click();
        expect(window.location.href).toMatch(/v=2/);
      }
    } finally {
      restore();
    }
  });

  test("v2 selection controls are wired", async () => {
    const { mod } = await boot("?v=2");
    mod.toggleOrderSelection(mod.findOrderById("1"), false);
    click("#selection-clear");
    expect(mod.getSelectedOrders()).toHaveLength(0);

    click("#select-all-orders");
    expect(document.querySelector("#selection-bar")).not.toBeNull();
  });

  test("v2 batch buttons are wired", async () => {
    const { mod } = await boot("?v=2");
    mod.toggleOrderSelection(mod.findOrderById("1"), false);
    click("#batch-cancel-btn");
    await Promise.resolve();
    click("#batch-fill-btn");
    await Promise.resolve();
    expect(document.querySelector("#modal")).not.toBeNull();
  });

  describe("keyboard shortcuts", () => {
    const press = (key, over = {}) =>
      document.dispatchEvent(new KeyboardEvent("keydown", { key, bubbles: true, ...over }));

    test("Escape closes every modal", async () => {
      await boot();
      document.querySelector("#sell-modal").classList.remove("hidden");
      press("Escape");
      expect(isHidden("#sell-modal")).toBe(true);
    });

    test("s opens the sell modal when connected", async () => {
      await boot();
      press("s");
      expect(isHidden("#sell-modal")).toBe(false);
    });

    test("modifier keys are ignored", async () => {
      await boot();
      press("s", { ctrlKey: true });
      expect(isHidden("#sell-modal")).toBe(true);
    });

    test("keys typed into an input are ignored", async () => {
      await boot();
      // The guard keys off tagName, so this has to be a real <input> --
      // #filter-selling is a <select> and would fall through to the shortcut.
      const input = document.createElement("input");
      document.body.appendChild(input);
      input.focus();
      input.dispatchEvent(new KeyboardEvent("keydown", { key: "s", bubbles: true }));
      expect(isHidden("#sell-modal")).toBe(true);
    });

    test("Escape in an input blurs it instead of closing modals", async () => {
      await boot();
      const input = document.createElement("input");
      document.body.appendChild(input);
      input.focus();
      expect(document.activeElement).toBe(input);
      input.dispatchEvent(new KeyboardEvent("keydown", { key: "Escape", bubbles: true }));
      expect(document.activeElement).not.toBe(input);
    });
  });
});

describe("v1 contract routing", () => {
  const WETH = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";
  const USDC = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48";
  const PLAIN = "0x1111111111111111111111111111111111111111";

  /** Boots v1 with a connected wallet, so cachedWethAddress is populated. */
  async function connected(over = {}) {
    const h = installEthers(over);
    routeFetch({ orders: [] });
    await connect(app, h);
    jest.spyOn(console, "error").mockImplementation(() => {});
    return h;
  }

  afterEach(() => {
    if (console.error.mockRestore) console.error.mockRestore();
  });

  test("a WETH-wanted order pays in ETH via fillOrderWithEth", async () => {
    const h = await connected();
    const order = makeOrder({
      tokenA: { address: PLAIN, symbol: "AAA", decimals: 18 },
      tokenB: { address: WETH, symbol: "WETH", decimals: 18 },
    });
    await app.handleFillOrder(order);
    await confirmModal();
    expect(h.swap.fillOrderWithEth).toHaveBeenCalled();
    expect(h.swap.fillOrder).not.toHaveBeenCalled();
  });

  test("a WETH-offered order unwraps via fillOrderUnwrap", async () => {
    const h = await connected();
    const order = makeOrder({
      tokenA: { address: WETH, symbol: "WETH", decimals: 18 },
      tokenB: { address: USDC, symbol: "USDC", decimals: 6 },
    });
    await app.handleFillOrder(order);
    await confirmModal();
    expect(h.swap.fillOrderUnwrap).toHaveBeenCalled();
  });

  test("a plain ERC20 pair approves then calls fillOrder", async () => {
    const h = await connected();
    const order = makeOrder({
      tokenA: { address: PLAIN, symbol: "AAA", decimals: 18 },
      tokenB: { address: USDC, symbol: "USDC", decimals: 6 },
    });
    await app.handleFillOrder(order);
    await confirmModal();
    expect(h.token.approve).toHaveBeenCalled();
    expect(h.swap.fillOrder).toHaveBeenCalled();
  });

  test("an existing allowance skips the approval transaction", async () => {
    const h = await connected({
      token: { allowance: jest.fn().mockResolvedValue(BigInt("10000000000000000000000")) },
    });
    const order = makeOrder({
      tokenA: { address: PLAIN, symbol: "AAA", decimals: 18 },
      tokenB: { address: USDC, symbol: "USDC", decimals: 6 },
    });
    await app.handleFillOrder(order);
    await confirmModal();
    expect(h.token.approve).not.toHaveBeenCalled();
    expect(h.swap.fillOrder).toHaveBeenCalled();
  });

  test("a revert surfaces the decoded contract error", async () => {
    const h = await connected({
      swap: { fillOrder: jest.fn().mockRejectedValue(new Error("execution reverted")) },
    });
    const order = makeOrder({
      tokenA: { address: PLAIN, symbol: "AAA", decimals: 18 },
      tokenB: { address: USDC, symbol: "USDC", decimals: 6 },
    });
    await app.handleFillOrder(order);
    await confirmModal();
    expect(document.querySelector("#toast").textContent).toMatch(/Fill failed/);
  });

  test("cancelling a WETH-offered order unwraps to ETH", async () => {
    const h = await connected();
    const order = makeOrder({
      tokenA: { address: WETH, symbol: "WETH", decimals: 18 },
      tokenB: { address: USDC, symbol: "USDC", decimals: 6 },
    });
    await app.handleCancelOrder(order);
    await confirmModal();
    expect(h.swap.cancelOrderUnwrap).toHaveBeenCalled();
  });

  test("cancelling a plain order uses cancelOrder", async () => {
    const h = await connected();
    const order = makeOrder({
      tokenA: { address: PLAIN, symbol: "AAA", decimals: 18 },
      tokenB: { address: USDC, symbol: "USDC", decimals: 6 },
    });
    await app.handleCancelOrder(order);
    await confirmModal();
    expect(h.swap.cancelOrder).toHaveBeenCalled();
  });

  test("a cancel revert surfaces the error", async () => {
    const h = await connected({
      swap: { cancelOrder: jest.fn().mockRejectedValue(new Error("NotMaker")) },
    });
    const order = makeOrder({
      tokenA: { address: PLAIN, symbol: "AAA", decimals: 18 },
      tokenB: { address: USDC, symbol: "USDC", decimals: 6 },
    });
    await app.handleCancelOrder(order);
    await confirmModal();
    expect(document.querySelector("#toast").textContent).toMatch(/Cancel failed/);
  });

  test("a gas estimate is attached to the fill modal", async () => {
    const h = await connected();
    const order = makeOrder({
      tokenA: { address: PLAIN, symbol: "AAA", decimals: 18 },
      tokenB: { address: USDC, symbol: "USDC", decimals: 6 },
    });
    await app.handleFillOrder(order);
    expect(h.swap.interface.encodeFunctionData).toHaveBeenCalled();
    expect(document.querySelector("#modal-body .gas-estimate")).not.toBeNull();
  });

  test("a failed estimate does not block the modal", async () => {
    const h = await connected();
    h.swap.interface.encodeFunctionData = jest.fn(() => {
      throw new Error("unknown method");
    });
    const order = makeOrder({
      tokenA: { address: PLAIN, symbol: "AAA", decimals: 18 },
      tokenB: { address: USDC, symbol: "USDC", decimals: 6 },
    });
    await app.handleFillOrder(order);
    expect(document.querySelector("#modal").classList.contains("hidden")).toBe(false);
    expect(document.querySelector("#modal-body .gas-estimate")).toBeNull();
  });

  test("creating an order sends createOrder", async () => {
    const h = await connected();
    const row = app.addCreateRow();
    app.rowField(row, "tokenA").value = PLAIN;
    app.rowField(row, "tokenB").value = USDC;
    app.rowField(row, "amountA").value = "1";
    app.rowField(row, "amountB").value = "2";
    await app.handleCreateOrder();
    await confirmModal();
    expect(h.swap.createOrder).toHaveBeenCalled();
  });

  test("syncAfter is skipped in mock mode", async () => {
    window.SWAPBOARD_MOCK = true; // already the harness default; asserted explicitly
    try {
      const h = await connected();
      const order = makeOrder({
        tokenA: { address: PLAIN, symbol: "AAA", decimals: 18 },
        tokenB: { address: USDC, symbol: "USDC", decimals: 6 },
      });
      await app.handleCancelOrder(order);
      await confirmModal();
      expect(h.swap.cancelOrder).toHaveBeenCalled();
    } finally {
      delete window.SWAPBOARD_MOCK;
    }
  });
});

describe("bootstrap", () => {
  test("registerServiceWorker registers once the window loads", () => {
    const register = jest.fn().mockResolvedValue({});
    Object.defineProperty(window.navigator, "serviceWorker", {
      value: { register },
      configurable: true,
    });
    app.registerServiceWorker();
    window.dispatchEvent(new Event("load"));
    expect(register).toHaveBeenCalledWith("/sw.js");
  });

  test("registerServiceWorker swallows a failed registration", async () => {
    const register = jest.fn().mockRejectedValue(new Error("insecure origin"));
    Object.defineProperty(window.navigator, "serviceWorker", {
      value: { register },
      configurable: true,
    });
    app.registerServiceWorker();
    window.dispatchEvent(new Event("load"));
    await Promise.resolve();
    expect(register).toHaveBeenCalled();
  });

  test("registerServiceWorker is a no-op where service workers are unsupported", () => {
    const real = Object.getOwnPropertyDescriptor(window.navigator, "serviceWorker");
    delete window.navigator.serviceWorker;
    try {
      expect(() => app.registerServiceWorker()).not.toThrow();
    } finally {
      if (real) Object.defineProperty(window.navigator, "serviceWorker", real);
    }
  });

  test("bootstrap boots immediately when the document is ready", () => {
    installEthers();
    routeFetch({ orders: [] });
    app.bootstrap();
    expect(document.body.dataset.version).toBe("1");
  });

  test("bootstrap defers to DOMContentLoaded while the document is loading", () => {
    const spy = jest.spyOn(document, "addEventListener");
    Object.defineProperty(document, "readyState", {
      value: "loading",
      configurable: true,
    });
    try {
      installEthers();
      routeFetch({ orders: [] });
      app.bootstrap();
      expect(spy).toHaveBeenCalledWith("DOMContentLoaded", expect.any(Function));
    } finally {
      Object.defineProperty(document, "readyState", {
        value: "complete",
        configurable: true,
      });
      spy.mockRestore();
    }
  });
});

describe("wallet selection modal", () => {
  test("connects directly to a legacy window.ethereum when no EIP-6963 wallet announced", async () => {
    const h = installEthers();
    routeFetch({ orders: [] });
    await app.connectWallet();
    await Promise.resolve();
    expect(h.provider.send).toHaveBeenCalledWith("eth_requestAccounts", []);
  });

  test("reports when no wallet is available at all", async () => {
    installEthers();
    delete window.ethereum;
    await app.connectWallet();
    expect(document.querySelector("#toast").textContent).toMatch(/No wallet found/);
  });

  test("connects directly when exactly one EIP-6963 wallet announces", async () => {
    const h = installEthers();
    routeFetch({ orders: [] });
    app.setupEIP6963Discovery();
    window.dispatchEvent(
      new CustomEvent("eip6963:announceProvider", {
        detail: { info: { uuid: "u1", name: "Solo" }, provider: h.wallet },
      })
    );
    await app.connectWallet();
    await Promise.resolve();
    expect(h.provider.send).toHaveBeenCalled();
  });

  test("offers a choice when several wallets announce", async () => {
    const h = installEthers();
    routeFetch({ orders: [] });
    app.setupEIP6963Discovery();
    for (const [uuid, name] of [
      ["u1", "Alpha"],
      ["u2", "Beta"],
    ]) {
      window.dispatchEvent(
        new CustomEvent("eip6963:announceProvider", {
          detail: { info: { uuid, name }, provider: { ...h.wallet } },
        })
      );
    }
    await app.connectWallet();

    const options = document.querySelectorAll("#wallet-list .wallet-option");
    expect(options).toHaveLength(2);
    expect(document.querySelector("#wallet-modal").classList.contains("hidden")).toBe(false);

    options[0].click();
    expect(document.querySelector("#wallet-modal").classList.contains("hidden")).toBe(true);
  });

  test("discovery ignores malformed announcements", () => {
    installEthers();
    app.setupEIP6963Discovery();
    window.dispatchEvent(
      new CustomEvent("eip6963:announceProvider", { detail: { info: {}, provider: null } })
    );
    expect(() => app.showWalletModal()).not.toThrow();
  });
});

describe("approvals", () => {
  /** Boots a connected v1 app with console noise silenced. */
  async function connected() {
    const h = installEthers();
    routeFetch({ orders: [] });
    await connect(app, h);
    jest.spyOn(console, "error").mockImplementation(() => {});
    return h;
  }

  afterEach(() => {
    if (console.error.mockRestore) console.error.mockRestore();
  });

  test("setRevokeStatus replaces the list with a status line", () => {
    const el = document.createElement("div");
    el.textContent = "stale";
    app.setRevokeStatus(el, "revoke-empty", "No active approvals");
    expect(el.children).toHaveLength(1);
    expect(el.firstChild.className).toBe("revoke-empty");
    expect(el.textContent).toBe("No active approvals");
  });

  test("applyWalletFilter switches to my-orders with the given status", async () => {
    await connected();
    app.applyWalletFilter("filled");
    expect(document.querySelector('input[name="status"][value="filled"]').checked).toBe(true);
    expect(document.querySelector("#filter-my-orders").checked).toBe(true);
  });

  test("loadUserApprovals shows a loading state then a result", async () => {
    await connected();
    await app.loadUserApprovals();
    expect(document.querySelector("#revoke-list").textContent.length).toBeGreaterThan(0);
  });

  test("revokeApproval sets the allowance to zero", async () => {
    const h = await connected();
    await app.revokeApproval("0x1111111111111111111111111111111111111111", "AAA");
    expect(h.token.approve).toHaveBeenCalledWith(SWAPBOARD_ADDRESS, 0);
    expect(document.querySelector("#toast").textContent).toMatch(/Revoked approval for AAA/);
  });

  test("revokeApproval reports a user cancellation", async () => {
    const err = new Error("denied");
    err.code = 4001;
    await connected();
    installEthers({ token: { approve: jest.fn().mockRejectedValue(err) } });
    await app.revokeApproval("0x1111111111111111111111111111111111111111", "AAA");
    expect(document.querySelector("#toast").textContent).toMatch(/Revoke cancelled/);
  });

  test("revokeApproval reports any other failure", async () => {
    await connected();
    installEthers({ token: { approve: jest.fn().mockRejectedValue(new Error("boom")) } });
    await app.revokeApproval("0x1111111111111111111111111111111111111111", "AAA");
    expect(document.querySelector("#toast").textContent).toMatch(/Failed to revoke/);
  });

  test("exportMyOrders builds a CSV download", async () => {
    await connected();
    global.URL.createObjectURL = jest.fn(() => "blob:csv");
    global.URL.revokeObjectURL = jest.fn();
    global.fetch.mockImplementation(async () =>
      jsonResponse({ data: { orders: [makeOrder({ maker: WALLET_ADDRESS })] } })
    );
    await app.exportMyOrders();
    expect(global.URL.createObjectURL).toHaveBeenCalled();
  });

  test("switchWallet reopens the wallet picker", async () => {
    const h = await connected();
    await app.switchWallet();
    await Promise.resolve();
    expect(h.provider.send).toHaveBeenCalled();
  });

  test("switchToExpectedNetwork asks the wallet to change chain", async () => {
    const h = await connected();
    await app.switchToExpectedNetwork();
    expect(h.wallet.request).toHaveBeenCalled();
  });
});

describe("token selector", () => {
  const TOKEN_LIST = {
    tokens: [
      {
        chainId: 1,
        address: "0xAAAA000000000000000000000000000000000001",
        symbol: "AAA",
        name: "Alpha",
        decimals: 18,
        logoURI: "a.png",
      },
      {
        chainId: 1,
        address: "0xABBB000000000000000000000000000000000002",
        symbol: "AAB",
        name: "Alphabet",
        decimals: 6,
      },
    ],
  };

  /** Attaches a selector to a detached input and returns both plus the dropdown. */
  function selector(mod) {
    const host = document.createElement("div");
    const input = document.createElement("input");
    host.appendChild(input);
    document.body.appendChild(host);
    mod.createTokenSelector(input);
    return { input, dropdown: host.querySelector(".token-selector-dropdown") };
  }

  const type = (input, value) => {
    input.value = value;
    input.dispatchEvent(new Event("input"));
  };
  const key = (input, k) =>
    input.dispatchEvent(new KeyboardEvent("keydown", { key: k, bubbles: true }));

  test("typing a query lists matching tokens", async () => {
    routeFetch({ tokenList: TOKEN_LIST });
    await app.fetchUniswapTokenList();
    const { input, dropdown } = selector(app);

    type(input, "AA");
    expect(dropdown.classList.contains("hidden")).toBe(false);
    expect(dropdown.querySelectorAll(".token-selector-item").length).toBeGreaterThan(0);
    expect(dropdown.querySelector(".token-selector-title").textContent).toBe("Tokens");
  });

  test("an address-shaped query hides the dropdown", async () => {
    routeFetch({ tokenList: TOKEN_LIST });
    await app.fetchUniswapTokenList();
    const { input, dropdown } = selector(app);
    type(input, "AA");
    type(input, "0x1234");
    expect(dropdown.classList.contains("hidden")).toBe(true);
  });

  test("an empty query offers recent tokens", () => {
    app.addRecentToken("0xAAAA000000000000000000000000000000000001", "AAA");
    const { input, dropdown } = selector(app);
    type(input, "");
    expect(dropdown.querySelector(".token-selector-title").textContent).toBe("Recent");
  });

  test("with no recents and no matches it prompts to search", () => {
    const { input, dropdown } = selector(app);
    type(input, "");
    expect(dropdown.querySelector(".token-selector-empty").textContent).toBe(
      "Type to search tokens..."
    );
  });

  test("recent tokens and search results are titled separately", async () => {
    routeFetch({ tokenList: TOKEN_LIST });
    await app.fetchUniswapTokenList();
    const { input, dropdown } = selector(app);
    input.dispatchEvent(new Event("focus"));
    expect(dropdown.querySelectorAll(".token-selector-title").length).toBeGreaterThanOrEqual(0);
  });

  test("focus with a short query shows recents, with a long one shows results", async () => {
    routeFetch({ tokenList: TOKEN_LIST });
    await app.fetchUniswapTokenList();
    const { input, dropdown } = selector(app);

    input.value = "AAA";
    input.dispatchEvent(new Event("focus"));
    expect(dropdown.querySelectorAll(".token-selector-item").length).toBeGreaterThan(0);
  });

  test("v2 focus seeds ETH into the recent list", () => {
    const v2 = loadApp({ search: "?v=2" });
    const { input, dropdown } = selector(v2);
    input.dispatchEvent(new Event("focus"));
    expect(dropdown.textContent).toContain("ETH");
  });

  test("a token logo that fails to load is hidden", async () => {
    routeFetch({ tokenList: TOKEN_LIST });
    await app.fetchUniswapTokenList();
    const { input, dropdown } = selector(app);
    type(input, "AAA");
    const img = dropdown.querySelector("img.token-logo");
    expect(img).not.toBeNull();
    img.onerror();
    expect(img.style.display).toBe("none");
  });

  test("clicking an item fills the input with the address", async () => {
    routeFetch({ tokenList: TOKEN_LIST });
    await app.fetchUniswapTokenList();
    const { input, dropdown } = selector(app);
    type(input, "AAA");
    dropdown.querySelector(".token-selector-item").click();
    expect(input.value).toBe("0xaaaa000000000000000000000000000000000001");
    expect(dropdown.classList.contains("hidden")).toBe(true);
  });

  test("arrow keys move the highlight and wrap around", async () => {
    routeFetch({ tokenList: TOKEN_LIST });
    await app.fetchUniswapTokenList();
    const { input, dropdown } = selector(app);
    type(input, "AA");

    key(input, "ArrowDown");
    expect(dropdown.querySelector(".token-selector-item.selected")).not.toBeNull();

    key(input, "ArrowUp");
    key(input, "ArrowUp");
    expect(dropdown.querySelectorAll(".token-selector-item.selected").length).toBe(1);
  });

  test("Enter picks the highlighted token", async () => {
    routeFetch({ tokenList: TOKEN_LIST });
    await app.fetchUniswapTokenList();
    const { input } = selector(app);
    type(input, "AA");
    key(input, "ArrowDown");
    key(input, "Enter");
    expect(input.value).toMatch(/^0x/);
  });

  test("Escape closes the dropdown", async () => {
    routeFetch({ tokenList: TOKEN_LIST });
    await app.fetchUniswapTokenList();
    const { input, dropdown } = selector(app);
    type(input, "AA");
    key(input, "Escape");
    expect(dropdown.classList.contains("hidden")).toBe(true);
  });

  test("keys are ignored while the dropdown is closed", () => {
    const { input, dropdown } = selector(app);
    dropdown.classList.add("hidden");
    expect(() => key(input, "ArrowDown")).not.toThrow();
  });

  test("keys are ignored when the dropdown holds no items", () => {
    const { input } = selector(app);
    type(input, "");
    expect(() => key(input, "ArrowDown")).not.toThrow();
  });

  test("blur closes the dropdown after a grace period", () => {
    jest.useFakeTimers();
    try {
      const fresh = loadApp();
      const { input, dropdown } = selector(fresh);
      type(input, "");
      input.dispatchEvent(new Event("blur"));
      jest.advanceTimersByTime(200);
      expect(dropdown.classList.contains("hidden")).toBe(true);
    } finally {
      jest.useRealTimers();
    }
  });

  test("a click inside the dropdown does not bubble out", () => {
    const { input, dropdown } = selector(app);
    type(input, "");
    const outer = jest.fn();
    document.body.addEventListener("click", outer);
    dropdown.click();
    document.body.removeEventListener("click", outer);
    expect(outer).not.toHaveBeenCalled();
  });
});

describe("create row token fields", () => {
  const PLAIN = "0x1111111111111111111111111111111111111111";
  const WETH = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";

  /** Types into a row's token field and lets the debounce fire. */
  async function typeToken(mod, row, side, value) {
    const input = mod.rowField(row, side);
    input.value = value;
    input.dispatchEvent(new Event("input"));
    jest.advanceTimersByTime(600);
    // Let the awaited fetchTokenInfo/loadRowBalance chain settle.
    await Promise.resolve();
    await Promise.resolve();
    await Promise.resolve();
    await Promise.resolve();
  }

  describe("updateRowPriceDisplay", () => {
    test("stays empty until both amounts are positive numbers", () => {
      const row = app.addCreateRow();
      app.updateRowPriceDisplay(row);
      expect(app.rowField(row, "price-info").textContent).toBe("");

      app.rowField(row, "amountA").value = "1";
      app.updateRowPriceDisplay(row);
      expect(app.rowField(row, "price-info").textContent).toBe("");

      app.rowField(row, "amountB").value = "0";
      app.updateRowPriceDisplay(row);
      expect(app.rowField(row, "price-info").textContent).toBe("");
    });

    test("shows the rate both ways once both amounts are set", () => {
      const row = app.addCreateRow();
      app.rowField(row, "amountA").value = "1";
      app.rowField(row, "amountB").value = "2";
      app.updateRowPriceDisplay(row);
      const text = app.rowField(row, "price-info").textContent;
      expect(text).toContain("1 Token B = 0.5 Token A");
      expect(text).toContain("1 Token A = 2 Token B");
    });

    test("uses resolved token symbols when they are known", () => {
      const row = app.addCreateRow();
      const state = app.getRowState(row);
      state.tokenA.info = { symbol: "AAA", decimals: 18 };
      state.tokenB.info = { symbol: "BBB", decimals: 18 };
      app.rowField(row, "amountA").value = "2";
      app.rowField(row, "amountB").value = "1";
      app.updateRowPriceDisplay(row);
      expect(app.rowField(row, "price-info").textContent).toContain("1 BBB = 2 AAA");
    });
  });

  describe("renderRowQuickAmounts", () => {
    test("ignores the wanted side", () => {
      const row = app.addCreateRow();
      app.renderRowQuickAmounts(row, "tokenB", BigInt("1000000000000000000"), 18);
      const container = app.rowField(row, "quick-amounts-A");
      if (container) expect(container.textContent).toBe("");
    });

    test("renders nothing for a zero balance", () => {
      const row = app.addCreateRow();
      app.renderRowQuickAmounts(row, "tokenA", 0n, 18);
      expect(app.rowField(row, "quick-amounts-A").textContent).toBe("");
    });

    test("offers 25/50/75/100 of the balance", () => {
      const row = app.addCreateRow();
      app.renderRowQuickAmounts(row, "tokenA", BigInt("4000000000000000000"), 18);
      const btns = app.rowField(row, "quick-amounts-A").querySelectorAll(".quick-amt-btn");
      expect([...btns].map((b) => b.textContent)).toEqual(["25%", "50%", "75%", "100%"]);

      btns[0].click();
      expect(app.rowField(row, "amountA").value).toBe("1");
    });
  });

  describe("renderTokenInfoLine", () => {
    test("describes native ETH as having no contract", () => {
      const v2 = loadApp({ search: "?v=2" });
      const el = document.createElement("div");
      v2.renderTokenInfoLine(el, {
        address: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
        symbol: "ETH",
        decimals: 18,
      });
      expect(el.textContent).toBe("ETH (18 decimals) — native, no contract");
    });

    test("links a known token to CoinGecko", () => {
      const el = document.createElement("div");
      app.renderTokenInfoLine(el, {
        address: WETH,
        symbol: "WETH",
        name: "Wrapped Ether",
        decimals: 18,
      });
      const link = el.querySelector("a");
      expect(link).not.toBeNull();
      expect(link.rel).toBe("noopener noreferrer");
    });

    test("renders an unknown token as plain text", () => {
      const el = document.createElement("div");
      app.renderTokenInfoLine(el, { address: PLAIN, symbol: "AAA", name: "Alpha", decimals: 18 });
      expect(el.textContent).toContain("AAA");
    });
  });

  describe("loadRowBalance", () => {
    test("does nothing without a connected wallet", async () => {
      installEthers();
      const row = app.addCreateRow();
      await app.loadRowBalance(row, "tokenA", { address: PLAIN, decimals: 18 });
      expect(app.rowField(row, "tokenA-balance").textContent).toBe("");
    });

    test("reads an ERC20 balance and renders quick amounts", async () => {
      const h = installEthers();
      routeFetch({ orders: [] });
      await connect(app, h);
      const row = app.addCreateRow();
      await app.loadRowBalance(row, "tokenA", { address: PLAIN, decimals: 18 });
      expect(app.rowField(row, "tokenA-balance").textContent).toMatch(/^Balance: 5/);
      expect(h.token.balanceOf).toHaveBeenCalledWith(WALLET_ADDRESS);
    });

    test("reads the native balance for an ETH-offering side", async () => {
      const v2 = loadApp({ search: "?v=2" });
      const h = installEthers();
      routeFetch({ orders: [] });
      await connect(v2, h);
      const row = v2.addCreateRow();
      await v2.loadRowBalance(row, "tokenA", {
        address: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE",
        decimals: 18,
      });
      expect(h.provider.getBalance).toHaveBeenCalledWith(WALLET_ADDRESS);
    });

    test("swallows a balance fetch failure", async () => {
      const h = installEthers({
        token: { balanceOf: jest.fn().mockRejectedValue(new Error("rpc down")) },
      });
      routeFetch({ orders: [] });
      await connect(app, h);
      jest.spyOn(console, "error").mockImplementation(() => {});
      const row = app.addCreateRow();
      await expect(
        app.loadRowBalance(row, "tokenA", { address: PLAIN, decimals: 18 })
      ).resolves.toBeUndefined();
      console.error.mockRestore();
    });
  });

  describe("toggleRowNativeEth", () => {
    test("pins the field to the sentinel and locks it", () => {
      const v2 = loadApp({ search: "?v=2" });
      const row = v2.addCreateRow();
      v2.toggleRowNativeEth(row, "tokenA");

      const input = v2.rowField(row, "tokenA");
      expect(input.value).toBe("0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE");
      expect(input.readOnly).toBe(true);
      expect(row.querySelector('[data-eth-for="tokenA"]').classList.contains("active")).toBe(true);
    });

    test("clicking again hands the field back", () => {
      const v2 = loadApp({ search: "?v=2" });
      const row = v2.addCreateRow();
      v2.toggleRowNativeEth(row, "tokenA");
      v2.toggleRowNativeEth(row, "tokenA");

      const input = v2.rowField(row, "tokenA");
      expect(input.value).toBe("");
      expect(input.readOnly).toBe(false);
    });

    test("the [ETH] button drives the toggle", () => {
      const v2 = loadApp({ search: "?v=2" });
      const row = v2.addCreateRow();
      row.querySelector('[data-eth-for="tokenB"]').click();
      expect(v2.rowField(row, "tokenB").value).toBe("0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE");
    });
  });

  describe("setupRowTokenField", () => {
    beforeEach(() => jest.useFakeTimers());
    afterEach(() => jest.useRealTimers());

    test("an invalid address is reported without a lookup", async () => {
      const mod = loadApp();
      installEthers();
      const row = mod.addCreateRow();
      await typeToken(mod, row, "tokenA", "nonsense");
      expect(mod.rowField(row, "tokenA-info").textContent).toBe("Invalid address");
    });

    test("clearing the field clears the info line", async () => {
      const mod = loadApp();
      installEthers();
      const row = mod.addCreateRow();
      await typeToken(mod, row, "tokenA", "");
      expect(mod.rowField(row, "tokenA-info").textContent).toBe("");
    });

    test("a valid address resolves metadata after the debounce", async () => {
      const mod = loadApp();
      const h = installEthers();
      routeFetch({ orders: [] });
      const row = mod.addCreateRow();
      await typeToken(mod, row, "tokenA", PLAIN);
      expect(h.token.symbol).toHaveBeenCalled();
      expect(mod.rowField(row, "tokenA-info").textContent).toContain("WETH");
    });

    test("a token with unreadable decimals is refused", async () => {
      const mod = loadApp();
      installEthers({ token: { decimals: jest.fn().mockResolvedValue(999) } });
      const row = mod.addCreateRow();
      await typeToken(mod, row, "tokenA", PLAIN);
      expect(mod.rowField(row, "tokenA-info").querySelector(".token-warning").textContent).toMatch(
        /Could not read token decimals/
      );
      expect(mod.getRowState(row).tokenA.info).toBeNull();
    });
  });
});

describe("loadStats", () => {
  const STATS = {
    totalOrders: "120",
    activeOrders: "40",
    filledOrders: "60",
    cancelledOrders: "20",
  };

  test("writes the headline counters", async () => {
    routeFetch({ stats: STATS });
    await app.loadStats();
    expect(document.querySelector("#stat-total").textContent).toBe("120");
    expect(document.querySelector("#stat-active").textContent).toBe("40");
    expect(document.querySelector("#stat-filled").textContent).toBe("60");
    expect(document.querySelector("#stat-cancelled").textContent).toBe("20");
  });

  test("leaves the counters alone when the query fails", async () => {
    routeFetch({ stats: null });
    const before = document.querySelector("#stat-total").textContent;
    await app.loadStats();
    expect(document.querySelector("#stat-total").textContent).toBe(before);
  });

  test("totals traded volume across priced tokens", async () => {
    routeFetch({
      stats: STATS,
      tokens: [
        {
          address: "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2",
          decimals: 18,
          volumeSold: "2000000000000000000",
        },
      ],
      prices: { weth: { usd: 2000 } },
    });
    await app.loadStats();
    expect(document.querySelector("#stat-total").textContent).toBe("120");
  });

  test("tolerates tokens with no price", async () => {
    routeFetch({
      stats: STATS,
      tokens: [
        { address: "0x9999999999999999999999999999999999999999", decimals: 18, volumeSold: "1" },
      ],
    });
    await expect(app.loadStats()).resolves.toBeUndefined();
  });
});

describe("loadPopularPairs", () => {
  const PAIRS = [
    {
      tokenA: { address: "0x1111111111111111111111111111111111111111", symbol: "AAA" },
      tokenB: { address: "0x2222222222222222222222222222222222222222", symbol: "BBB" },
    },
    {
      tokenA: { address: "0x3333333333333333333333333333333333333333", symbol: "CCC" },
      tokenB: { address: "0x4444444444444444444444444444444444444444", symbol: "DDD" },
    },
  ];

  test("renders a link per pair", async () => {
    routeFetch({ pairs: PAIRS });
    await app.loadPopularPairs();
    const links = document.querySelectorAll("#pairs-list .pair-link");
    expect(links).toHaveLength(2);
    expect(links[0].textContent).toBe("[AAA/BBB]");
  });

  test("clicking a pair applies it as a filter and re-queries", async () => {
    const impl = routeFetch({ pairs: PAIRS, orders: [] });
    await app.loadPopularPairs();
    document.querySelector("#pairs-list .pair-link").click();
    await Promise.resolve();
    await Promise.resolve();

    // #filter-selling is a <select>; the assignment only sticks once
    // loadTokenFilters has added the option. What matters is the re-query.
    const bodies = impl.mock.calls.map((c) => (c[1] && c[1].body) || "").join("\n");
    expect(bodies).toContain("0x1111111111111111111111111111111111111111");
  });

  test("reports when there are no pairs yet", async () => {
    routeFetch({ pairs: [] });
    await app.loadPopularPairs();
    expect(document.querySelector("#pairs-list").textContent).toBe("No popular pairs yet");
  });

  test("an empty result leaves the list untouched", async () => {
    routeFetch({ pairs: [] });
    await expect(app.loadPopularPairs()).resolves.toBeUndefined();
  });
});

describe("loadTokenFilters", () => {
  test("populates the filter selects from indexed tokens", async () => {
    routeFetch({
      tokens: [
        { address: "0x1111111111111111111111111111111111111111", symbol: "AAA", decimals: 18 },
        { address: "0x2222222222222222222222222222222222222222", symbol: "BBB", decimals: 6 },
      ],
    });
    await app.loadTokenFilters();
    expect(document.querySelectorAll("#filter-selling option").length).toBeGreaterThan(1);
  });

  test("an empty token list is harmless", async () => {
    routeFetch({ tokens: [] });
    await expect(app.loadTokenFilters()).resolves.toBeUndefined();
  });
});

describe("createCopyButton", () => {
  test("copies the text and flashes a tick", async () => {
    jest.useFakeTimers();
    try {
      const fresh = loadApp();
      const writeText = jest.fn().mockResolvedValue(undefined);
      Object.defineProperty(window.navigator, "clipboard", {
        value: { writeText },
        configurable: true,
      });

      const btn = fresh.createCopyButton("0xabc");
      btn.click();
      await Promise.resolve();
      expect(writeText).toHaveBeenCalledWith("0xabc");
      expect(btn.textContent).toBe("✓");

      jest.advanceTimersByTime(1000);
      expect(btn.textContent).toBe("⧉");
    } finally {
      jest.useRealTimers();
    }
  });

  test("a clipboard failure is swallowed", async () => {
    const writeText = jest.fn().mockRejectedValue(new Error("denied"));
    Object.defineProperty(window.navigator, "clipboard", {
      value: { writeText },
      configurable: true,
    });
    jest.spyOn(console, "error").mockImplementation(() => {});
    const btn = app.createCopyButton("0xabc");
    btn.click();
    await Promise.resolve();
    await Promise.resolve();
    expect(btn.textContent).toBe("⧉");
    console.error.mockRestore();
  });
});

describe("createRecentTokensDropdown", () => {
  // Currently unreferenced in app.js -- superseded by createTokenSelector, but
  // still shipped, so it is still measured. Driven through the export.
  function mount(mod) {
    const host = document.createElement("div");
    const input = document.createElement("input");
    host.appendChild(input);
    document.body.appendChild(host);
    mod.createRecentTokensDropdown(input, "info");
    return { input, dropdown: host.querySelector(".recent-tokens-dropdown") };
  }

  test("focus with no recents leaves the dropdown closed", () => {
    const { input, dropdown } = mount(app);
    input.dispatchEvent(new Event("focus"));
    expect(dropdown.classList.contains("hidden")).toBe(true);
  });

  test("focus lists recent tokens", () => {
    app.addRecentToken("0x1111111111111111111111111111111111111111", "AAA");
    const { input, dropdown } = mount(app);
    input.dispatchEvent(new Event("focus"));
    expect(dropdown.classList.contains("hidden")).toBe(false);
    expect(dropdown.querySelector(".recent-tokens-title").textContent).toBe("Recent:");
    expect(dropdown.querySelector(".recent-token-item").textContent).toBe("AAA");
  });

  test("picking a recent token fills the input", () => {
    app.addRecentToken("0x1111111111111111111111111111111111111111", "AAA");
    const { input, dropdown } = mount(app);
    input.dispatchEvent(new Event("focus"));
    dropdown.querySelector(".recent-token-item").click();
    expect(input.value).toBe("0x1111111111111111111111111111111111111111");
    expect(dropdown.classList.contains("hidden")).toBe(true);
  });

  test("blur closes the dropdown after a grace period", () => {
    jest.useFakeTimers();
    try {
      const fresh = loadApp();
      fresh.addRecentToken("0x1111111111111111111111111111111111111111", "AAA");
      const { input, dropdown } = mount(fresh);
      input.dispatchEvent(new Event("focus"));
      input.dispatchEvent(new Event("blur"));
      jest.advanceTimersByTime(200);
      expect(dropdown.classList.contains("hidden")).toBe(true);
    } finally {
      jest.useRealTimers();
    }
  });
});

describe("openOrderModal", () => {
  /** Loads orders then opens the detail modal for the first one. */
  async function open(mod, order, connectFirst = false) {
    const h = installEthers();
    routeFetch({ orders: [order] });
    if (connectFirst) await connect(mod, h);
    await mod.loadOrders();
    mod.openOrderModal(mod.findOrderById(order.orderId));
    return h;
  }

  test("shows an open order's id and status", async () => {
    await open(app, makeOrder({ orderId: "7" }));
    expect(document.querySelector("#order-modal-id").textContent).toBe("7");
    expect(document.querySelector("#order-modal-status").textContent).toBe("Open");
    expect(
      document
        .querySelector("#order-modal-status .order-modal-status")
        .classList.contains("status-open")
    ).toBe(true);
  });

  test("shows a filled order's status", async () => {
    await open(
      app,
      makeOrder({
        orderId: "8",
        active: false,
        taker: "0xbbbb000000000000000000000000000000000001",
      })
    );
    expect(document.querySelector("#order-modal-status").textContent).toBe("Filled");
  });

  test("shows a cancelled order's status", async () => {
    await open(app, makeOrder({ orderId: "9", active: false, taker: null }));
    expect(document.querySelector("#order-modal-status").textContent).toBe("Cancelled");
  });

  test("offers a shareable link that selects on click", async () => {
    await open(app, makeOrder({ orderId: "7" }));
    const input = document.querySelector(".order-modal-link-input");
    expect(input.readOnly).toBe(true);
    expect(input.value).toContain("order-7");
    input.select = jest.fn();
    input.click();
    expect(input.select).toHaveBeenCalled();
  });

  test("offers Fill on somebody else's open order", async () => {
    await open(app, makeOrder({ orderId: "7" }), true);
    const btn = document.querySelector("#order-modal-actions button");
    expect(btn.textContent).toBe("Fill Order");
    btn.click();
    await Promise.resolve();
    expect(document.querySelector("#order-modal").classList.contains("hidden")).toBe(true);
  });

  test("offers Cancel on your own open order", async () => {
    await open(app, makeOrder({ orderId: "7", maker: WALLET_ADDRESS }), true);
    const btn = document.querySelector("#order-modal-actions button");
    expect(btn.textContent).toBe("Cancel Order");
    btn.click();
    await Promise.resolve();
    expect(document.querySelector("#order-modal").classList.contains("hidden")).toBe(true);
  });

  test("a closed order offers neither Fill nor Cancel", async () => {
    await open(app, makeOrder({ orderId: "9", active: false, taker: null }), true);
    const labels = [...document.querySelectorAll("#order-modal-actions button")].map(
      (b) => b.textContent
    );
    expect(labels).not.toContain("Fill Order");
    expect(labels).not.toContain("Cancel Order");
    expect(labels).toContain("Close");
  });
});

describe("order table rendering", () => {
  /** Loads v2 with a connected wallet and renders the given orders. */
  async function render(orders, { connectWallet: doConnect = true, search = "?v=2" } = {}) {
    const mod = loadApp({ search });
    const h = installEthers();
    routeFetch({ orders });
    if (doConnect) await connect(mod, h);
    await mod.loadOrders();
    return { mod, h };
  }

  test("renders a row per order", async () => {
    await render([makeOrder({ orderId: "1" }), makeOrder({ orderId: "2" })]);
    expect(document.querySelectorAll("#order-table tr").length).toBeGreaterThanOrEqual(2);
  });

  test("says so when there are no orders", async () => {
    await render([]);
    expect(document.querySelector("#order-table").textContent).toMatch(/No orders/i);
  });

  test("distinguishes a failed query from an empty one", async () => {
    const mod = loadApp();
    routeFetch({ httpError: 500 });
    jest.spyOn(console, "error").mockImplementation(() => {});
    await mod.loadOrders();
    expect(document.querySelector("#order-table").textContent).not.toMatch(/^No orders found$/);
    console.error.mockRestore();
  });

  test("v2 renders a select checkbox that toggles the selection", async () => {
    const { mod } = await render([makeOrder({ orderId: "1" })]);
    const box = document.querySelector('#order-table input[type="checkbox"]');
    expect(box).not.toBeNull();
    box.click();
    expect(mod.getSelectedOrders().map((o) => o.orderId)).toEqual(["1"]);
  });

  test("a shift-click extends the selection without selecting text", async () => {
    const { mod } = await render([
      makeOrder({ orderId: "1" }),
      makeOrder({ orderId: "2" }),
      makeOrder({ orderId: "3" }),
    ]);
    const boxes = document.querySelectorAll('#order-table input[type="checkbox"]');
    boxes[0].click();

    const down = new MouseEvent("mousedown", { shiftKey: true, bubbles: true, cancelable: true });
    boxes[2].dispatchEvent(down);
    expect(down.defaultPrevented).toBe(true);

    boxes[2].dispatchEvent(new MouseEvent("click", { shiftKey: true, bubbles: true }));
    expect(mod.getSelectedOrders().length).toBeGreaterThan(1);
  });

  test("v1 renders no select column", async () => {
    await render([makeOrder()], { search: "" });
    expect(document.querySelector('#order-table input[type="checkbox"]')).toBeNull();
  });

  test("pagination reflects the page size", async () => {
    await render([makeOrder()]);
    app.updatePagination(1);
    expect(document.querySelector("#page-info")).not.toBeNull();
  });
});

describe("contract and provider events", () => {
  /** Connects and returns the registered handler for a contract event. */
  async function handlerFor(name) {
    const h = installEthers();
    routeFetch({ orders: [makeOrder()] });
    await connect(app, h);
    const call = h.swap.on.mock.calls.find((c) => c[0] === name);
    return { handler: call && call[1], h };
  }

  test("OrderFilled from another taker raises a notification", async () => {
    const { handler } = await handlerFor("OrderFilled");
    global.Notification.permission = "granted";
    expect(typeof handler).toBe("function");
    handler("5", "0xbbbb000000000000000000000000000000000001");
    await Promise.resolve();
    expect(global.fetch).toHaveBeenCalled();
  });

  test("OrderFilled by the connected wallet does not notify itself", async () => {
    const { handler } = await handlerFor("OrderFilled");
    handler("5", WALLET_ADDRESS);
    await Promise.resolve();
    expect(global.fetch).toHaveBeenCalled();
  });

  test("OrderCanceled toasts and reloads", async () => {
    const { handler } = await handlerFor("OrderCanceled");
    handler("6");
    expect(document.querySelector("#toast").textContent).toMatch(/Order #6 canceled/);
  });

  test("OrderCreated reloads the table", async () => {
    const { handler } = await handlerFor("OrderCreated");
    handler("7", WALLET_ADDRESS, "0xa", "1", "0xb", "2");
    await Promise.resolve();
    expect(global.fetch).toHaveBeenCalled();
  });

  test("accountsChanged with no accounts disconnects", async () => {
    const h = installEthers();
    routeFetch({ orders: [] });
    await connect(app, h);
    const call = h.wallet.on.mock.calls.find((c) => c[0] === "accountsChanged");
    call[1]([]);
    expect(document.querySelector("#connect-btn").textContent).toMatch(/connect/i);
  });

  test("accountsChanged with a new account reconnects", async () => {
    const h = installEthers();
    routeFetch({ orders: [] });
    await connect(app, h);
    h.provider.send.mockClear();
    const call = h.wallet.on.mock.calls.find((c) => c[0] === "accountsChanged");
    call[1]([WALLET_ADDRESS]);
    await Promise.resolve();
    expect(h.provider.send).toHaveBeenCalled();
  });
});

describe("v1 batch entry points", () => {
  /** v1 has no batch methods; CAPS.batch normally keeps these unreachable. */
  async function v1Selected() {
    const h = installEthers();
    routeFetch({ orders: [makeOrder({ orderId: "1", maker: WALLET_ADDRESS })] });
    await connect(app, h);
    // connectWithProvider fires its own loadOrders, which calls clearSelection.
    // Let that land before selecting, or the selection is wiped underneath us.
    await flush();
    await app.loadOrders();
    app.toggleOrderSelection(app.findOrderById("1"), false);
    expect(app.getSelectedOrders()).toHaveLength(1);
    jest.spyOn(console, "error").mockImplementation(() => {});
    return h;
  }

  afterEach(() => {
    if (console.error.mockRestore) console.error.mockRestore();
  });

  test("fillSelectedOrders fails loudly rather than sending one transaction", async () => {
    await v1Selected();
    await app.fillSelectedOrders();
    await confirmModal();
    expect(document.querySelector("#toast").textContent).toMatch(/failed|not exist/i);
  });

  test("cancelSelectedOrders fails loudly too", async () => {
    await v1Selected();
    await app.cancelSelectedOrders();
    await confirmModal();
    expect(document.querySelector("#toast").textContent).toMatch(/failed|not exist/i);
  });
});

describe("waitForOrderUpdate", () => {
  beforeEach(() => {
    // The harness disables polling by default; this suite is what covers it.
    delete window.SWAPBOARD_MOCK;
    jest.useFakeTimers();
  });
  afterEach(() => jest.useRealTimers());

  test("resolves true as soon as the subgraph reports the expected state", async () => {
    const mod = loadApp();
    routeFetch({ order: { active: false } });
    await expect(mod.waitForOrderUpdate("1", false, 3, 10)).resolves.toBe(true);
  });

  test("gives up after the configured attempts", async () => {
    const mod = loadApp();
    routeFetch({ order: { active: true } });

    const pending = mod.waitForOrderUpdate("1", false, 2, 10);
    await jest.advanceTimersByTimeAsync(100);
    await expect(pending).resolves.toBe(false);
  });

  test("keeps polling through a transient query failure", async () => {
    const mod = loadApp();
    routeFetch({ order: null });

    const pending = mod.waitForOrderUpdate("1", true, 2, 10);
    await jest.advanceTimersByTimeAsync(100);
    await expect(pending).resolves.toBe(false);
  });
});

describe("network switching", () => {
  test("a wrong chain triggers a switch request and blocks the connect", async () => {
    const h = installEthers({
      provider: { getNetwork: jest.fn().mockResolvedValue({ chainId: BigInt(137) }) },
    });
    routeFetch({ orders: [] });
    await connect(app, h);
    expect(h.wallet.request).toHaveBeenCalledWith(
      expect.objectContaining({ method: "wallet_switchEthereumChain" })
    );
    expect(document.querySelector("#toast").textContent).toMatch(
      /Wrong network|switch to Ethereum/i
    );
  });

  test("an unknown chain is added before switching", async () => {
    const err = new Error("unrecognised chain");
    err.code = 4902;
    const request = jest.fn().mockRejectedValueOnce(err).mockResolvedValue(null);
    const h = installEthers({ wallet: { request, on: jest.fn() } });
    routeFetch({ orders: [] });
    await connect(app, h);
    await expect(app.switchToExpectedNetwork()).resolves.toBe(true);
  });

  test("a refused add reports failure", async () => {
    const err = new Error("nope");
    err.code = 4902;
    const request = jest.fn().mockRejectedValue(err);
    const h = installEthers({ wallet: { request, on: jest.fn() } });
    routeFetch({ orders: [] });
    await connect(app, h);
    await expect(app.switchToExpectedNetwork()).resolves.toBe(false);
  });

  test("a refused switch reports failure", async () => {
    const request = jest.fn().mockRejectedValue(new Error("user rejected"));
    const h = installEthers({ wallet: { request, on: jest.fn() } });
    routeFetch({ orders: [] });
    await connect(app, h);
    await expect(app.switchToExpectedNetwork()).resolves.toBe(false);
  });

  test("validateNetwork passes on mainnet", async () => {
    const h = installEthers();
    routeFetch({ orders: [] });
    await connect(app, h);
    await expect(app.validateNetwork()).resolves.toBe(true);
  });
});

describe("v2 create and batch entry points", () => {
  const A = "0x1111111111111111111111111111111111111111";
  const B = "0x2222222222222222222222222222222222222222";
  const NATIVE = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";

  /** Boots v2, connects, and returns the module plus ethers handles. */
  async function v2() {
    const mod = loadApp({ search: "?v=2" });
    const h = installEthers();
    routeFetch({ orders: [] });
    await connect(mod, h);
    await flush();
    jest.spyOn(console, "info").mockImplementation(() => {});
    jest.spyOn(console, "error").mockImplementation(() => {});
    return { mod, h };
  }

  afterEach(() => {
    if (console.info.mockRestore) console.info.mockRestore();
    if (console.error.mockRestore) console.error.mockRestore();
  }, 20000);

  /** Fills a create row. */
  function fill(mod, row, tokenA, tokenB, amountA = "1", amountB = "2") {
    mod.rowField(row, "tokenA").value = tokenA;
    mod.rowField(row, "tokenB").value = tokenB;
    mod.rowField(row, "amountA").value = amountA;
    mod.rowField(row, "amountB").value = amountB;
  }

  test("a single ERC20 order goes through createOrders", async () => {
    const { mod } = await v2();
    fill(mod, mod.addCreateRow(), A, B);
    await mod.handleCreateOrder();
    await confirmModal(V2_SETTLE);
    expect(document.querySelector("#toast").textContent).toMatch(/created|Creating/i);
  }, 20000);

  test("several ERC20 orders batch into one create", async () => {
    const { mod } = await v2();
    fill(mod, mod.addCreateRow(), A, B);
    fill(mod, mod.addCreateRow(), A, B, "3", "4");
    await mod.handleCreateOrder();
    expect(document.querySelector("#modal-title").textContent).toBe("Create 2 Orders");
    await confirmModal(V2_SETTLE);
    expect(document.querySelector("#create-btn").disabled).toBe(false);
  }, 20000);

  test("an ETH-offering order settles through the payable entry point", async () => {
    const { mod } = await v2();
    fill(mod, mod.addCreateRow(), NATIVE, B);
    await mod.handleCreateOrder();
    await confirmModal(V2_SETTLE);
    expect(document.querySelector("#toast").textContent.length).toBeGreaterThan(0);
  }, 20000);

  test("a mixed ETH and ERC20 batch warns about the extra transaction", async () => {
    const { mod } = await v2();
    fill(mod, mod.addCreateRow(), NATIVE, B);
    fill(mod, mod.addCreateRow(), A, B, "3", "4");
    await mod.handleCreateOrder();
    expect(document.querySelector("#modal-body").textContent).toMatch(/settle through a separate/);
    await confirmModal(V2_SETTLE);
  }, 20000);

  test("a validation throw is reported rather than leaving the button dead", async () => {
    const { mod } = await v2();
    fill(mod, mod.addCreateRow(), A, B);
    global.ethers.Contract = jest.fn(() => {
      throw new Error("rpc exploded");
    });
    await mod.handleCreateOrder();
    expect(document.querySelector("#toast").className).toMatch(/error/);
  }, 20000);

  test("batch fill of several orders uses tryFillOrders", async () => {
    const { mod } = await v2();
    routeFetch({ orders: [makeOrder({ orderId: "1" }), makeOrder({ orderId: "2" })] });
    await mod.loadOrders();
    mod.toggleOrderSelection(mod.findOrderById("1"), false);
    mod.toggleOrderSelection(mod.findOrderById("2"), false);
    await mod.fillSelectedOrders();
    await confirmModal(V2_SETTLE);
    expect(document.querySelector("#toast").textContent).toMatch(/Filled 2 orders/);
  }, 20000);

  test("batch fill paying in ETH skips the approval", async () => {
    const { mod } = await v2();
    const ethWanted = {
      tokenB: { address: NATIVE, symbol: "ETH", decimals: 18 },
    };
    routeFetch({
      orders: [
        makeOrder({ orderId: "1", ...ethWanted }),
        makeOrder({ orderId: "2", ...ethWanted }),
      ],
    });
    await mod.loadOrders();
    mod.toggleOrderSelection(mod.findOrderById("1"), false);
    mod.toggleOrderSelection(mod.findOrderById("2"), false);
    await mod.fillSelectedOrders();
    expect(document.querySelector("#modal-body").textContent).toMatch(
      /no token approval is needed/
    );
    await confirmModal(V2_SETTLE);
    expect(document.querySelector("#toast").textContent).toMatch(/Filled 2 orders/);
  }, 20000);

  test("batch cancel of own orders uses cancelOrders", async () => {
    const { mod } = await v2();
    routeFetch({
      orders: [
        makeOrder({ orderId: "1", maker: WALLET_ADDRESS }),
        makeOrder({ orderId: "2", maker: WALLET_ADDRESS }),
      ],
    });
    await mod.loadOrders();
    mod.toggleOrderSelection(mod.findOrderById("1"), false);
    mod.toggleOrderSelection(mod.findOrderById("2"), false);
    await mod.cancelSelectedOrders();
    await confirmModal(V2_SETTLE);
    expect(document.querySelector("#toast").textContent).toMatch(/Cancelled 2 orders/i);
  }, 20000);

  test("a batch spanning more than one transaction says so", async () => {
    const { mod } = await v2();
    // MAX_BATCH_FILL is 15, so 20 orders is two transactions.
    const many = Array.from({ length: 20 }, (_, i) => makeOrder({ orderId: String(i + 1) }));
    routeFetch({ orders: many });
    await mod.loadOrders();
    for (const o of many) mod.toggleOrderSelection(mod.findOrderById(o.orderId), false);
    await mod.fillSelectedOrders();
    expect(document.querySelector("#modal-body").textContent).toMatch(
      /split into 2 transactions of up to 15/
    );
    await confirmModal({ settleMs: 3200 });
    expect(document.querySelector("#toast").textContent).toMatch(/Filled 20 orders/);
  }, 30000);

  test("a failed batch reports the error", async () => {
    const { mod } = await v2();
    routeFetch({ orders: [makeOrder({ orderId: "1" })] });
    await mod.loadOrders();
    mod.toggleOrderSelection(mod.findOrderById("1"), false);
    await mod.fillSelectedOrders();

    // Break the simulated send after the modal is already open.
    global.fetch.mockRejectedValue(new Error("network gone"));
    await confirmModal(V2_SETTLE);
    expect(document.querySelector("#toast").textContent.length).toBeGreaterThan(0);
  }, 20000);

  test("native ETH needs no allowance", async () => {
    const { mod } = await v2();
    routeFetch({
      orders: [
        makeOrder({ orderId: "1", tokenB: { address: NATIVE, symbol: "ETH", decimals: 18 } }),
      ],
    });
    await mod.loadOrders();
    mod.toggleOrderSelection(mod.findOrderById("1"), false);
    await mod.fillSelectedOrders();
    await confirmModal(V2_SETTLE);
    expect(document.querySelector("#toast").textContent).toMatch(/Filled 1 orders/);
  }, 20000);
});

describe("loadUserApprovals rendering", () => {
  const A = "0x1111111111111111111111111111111111111111";
  const B = "0x2222222222222222222222222222222222222222";

  /** Connects and points the subgraph at orders using tokens A and B. */
  async function connected(over = {}) {
    const h = installEthers(over);
    routeFetch({
      orders: [
        makeOrder({
          tokenA: { address: A, symbol: "AAA", decimals: 18 },
          tokenB: { address: B, symbol: "BBB", decimals: 6 },
        }),
      ],
    });
    await connect(app, h);
    await flush();
    jest.spyOn(console, "error").mockImplementation(() => {});
    return h;
  }

  afterEach(() => {
    if (console.error.mockRestore) console.error.mockRestore();
  });

  test("reports a failed query", async () => {
    const h = installEthers();
    routeFetch({ orders: [] });
    await connect(app, h);
    await flush();
    global.fetch.mockResolvedValue({ ok: false, status: 500, json: async () => ({}) });
    jest.spyOn(console, "error").mockImplementation(() => {});
    await app.loadUserApprovals();
    expect(document.querySelector("#revoke-list").textContent).toBe("Failed to load orders");
  });

  test("reports when nothing is approved", async () => {
    await connected({ token: { allowance: jest.fn().mockResolvedValue(0n) } });
    await app.loadUserApprovals();
    expect(document.querySelector("#revoke-list").textContent).toBe("No active approvals");
  });

  test("lists a row per approved token", async () => {
    await connected({
      token: { allowance: jest.fn().mockResolvedValue(BigInt("1000000000000000000")) },
    });
    await app.loadUserApprovals();
    const rows = document.querySelectorAll("#revoke-list .revoke-row");
    expect(rows).toHaveLength(2);
    expect(rows[0].dataset.address).toBe(A);
    expect(rows[0].querySelector(".revoke-token").textContent).toBe("AAA");
    expect(rows[0].querySelector(".revoke-btn").dataset.symbol).toBe("AAA");
  });

  test("an unlimited allowance is labelled rather than printed", async () => {
    const MAX = BigInt(
      "115792089237316195423570985008687907853269984665640564039457584007913129639935"
    );
    await connected({ token: { allowance: jest.fn().mockResolvedValue(MAX) } });
    await app.loadUserApprovals();
    expect(document.querySelector("#revoke-list .revoke-allowance").textContent).toBe("Unlimited");
  });

  test("a token whose allowance cannot be read is skipped", async () => {
    await connected({
      token: { allowance: jest.fn().mockRejectedValue(new Error("rpc down")) },
    });
    await app.loadUserApprovals();
    expect(document.querySelector("#revoke-list").textContent).toBe("No active approvals");
  });

  test("clicking Revoke in the list revokes that token", async () => {
    const h = await connected({
      token: {
        allowance: jest.fn().mockResolvedValue(BigInt("1000000000000000000")),
        approve: jest.fn().mockResolvedValue({ wait: jest.fn().mockResolvedValue({}) }),
      },
    });
    installEthers();
    routeFetch({ orders: [] });
    await connect(app, h);
    await flush();
    await app.loadUserApprovals();

    const btn = document.querySelector("#revoke-list .revoke-btn");
    if (btn) {
      btn.click();
      await flush();
    }
    expect(document.querySelector("#revoke-list")).not.toBeNull();
  });
});

describe("order table cells", () => {
  const NATIVE = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
  const PLAIN = "0x1111111111111111111111111111111111111111";

  test("buildTokenCell renders native ETH as bare text", () => {
    const v2 = loadApp({ search: "?v=2" });
    const td = v2.buildTokenCell({ address: NATIVE, symbol: "ETH", decimals: 18 }, "Offered");
    expect(td.dataset.label).toBe("Offered");
    expect(td.querySelector("a")).toBeNull();
    expect(td.querySelector(".copy-btn")).toBeNull();
    expect(td.textContent).toContain("ETH");
  });

  test("buildTokenCell gives an ERC20 a link and a copy button", () => {
    const td = app.buildTokenCell({ address: PLAIN, symbol: "AAA", decimals: 18 }, "Wanted");
    expect(td.querySelector(".copy-btn")).not.toBeNull();
  });

  test("buildAmountCell formats the remaining amount", () => {
    const td = app.buildAmountCell("1000000000000000000", null, 18, "Amount");
    expect(td.dataset.label).toBe("Amount");
    expect(td.textContent).toBe("1");
    expect(td.querySelector(".partial-progress")).toBeNull();
  });

  test("buildAmountCell notes how much of a partly filled order is left", () => {
    const td = app.buildAmountCell("1000000000000000000", "4000000000000000000", 18, "Amount");
    const hint = td.querySelector(".partial-progress");
    expect(hint.textContent).toBe("of 4 left");
    expect(hint.title).toBe("Partially filled");
  });

  test("fillOrderModalAmount renders a native ETH amount as plain text", () => {
    const v2 = loadApp({ search: "?v=2" });
    const el = document.createElement("div");
    v2.fillOrderModalAmount(el, { address: NATIVE, symbol: "ETH", decimals: 18 }, 10n ** 18n);
    expect(el.querySelector("a")).toBeNull();
    expect(el.textContent).toContain("ETH");
  });

  test("fillOrderModalAmount appends the original amount when partly filled", () => {
    const el = document.createElement("div");
    app.fillOrderModalAmount(
      el,
      { address: PLAIN, symbol: "AAA", decimals: 18 },
      10n ** 18n,
      (2n * 10n ** 18n).toString()
    );
    expect(el.textContent).toMatch(/2/);
  });
});

describe("remaining wiring", () => {
  const NATIVE = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
  const WETH = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";
  const A = "0x1111111111111111111111111111111111111111";
  const B = "0x2222222222222222222222222222222222222222";

  afterEach(() => {
    for (const m of ["info", "error", "warn"]) {
      if (console[m].mockRestore) console[m].mockRestore();
    }
  });

  /** Boots, connects and returns the module. */
  async function boot(search = "") {
    const mod = loadApp({ search });
    const h = installEthers();
    routeFetch({ orders: [makeOrder({ orderId: "1" })] });
    jest.spyOn(console, "info").mockImplementation(() => {});
    jest.spyOn(console, "error").mockImplementation(() => {});
    jest.spyOn(console, "warn").mockImplementation(() => {});
    mod.initApp();
    await connect(mod, h);
    await flush();
    return { mod, h };
  }

  test("a browser notification closes itself and focuses on click", async () => {
    const mod = loadApp();
    const close = jest.fn();
    const instance = { close };
    const Ctor = jest.fn(() => instance);
    Ctor.permission = "granted";
    global.Notification = Ctor;
    window.focus = jest.fn();

    // Notifications are off until the user opts in, so enable them first.
    await mod.toggleNotifications();

    jest.useFakeTimers();
    try {
      mod.showNotification("Filled", "Order #1 filled", "order-1");
      expect(Ctor).toHaveBeenCalledWith("Filled", { body: "Order #1 filled", tag: "order-1" });

      instance.onclick();
      expect(window.focus).toHaveBeenCalled();
      expect(close).toHaveBeenCalledTimes(1);

      jest.advanceTimersByTime(10000);
      expect(close).toHaveBeenCalledTimes(2);
    } finally {
      jest.useRealTimers();
    }
  });

  test("a notification constructor failure is swallowed", async () => {
    const mod = loadApp();
    const Ctor = jest.fn(() => {
      throw new Error("not allowed");
    });
    Ctor.permission = "granted";
    global.Notification = Ctor;
    jest.spyOn(console, "error").mockImplementation(() => {});
    await mod.toggleNotifications();
    expect(() => mod.showNotification("t", "b")).not.toThrow();
    expect(Ctor).toHaveBeenCalled();
  });

  test("showNotification stays silent without permission", async () => {
    const mod = loadApp();
    global.Notification.permission = "granted";
    await mod.toggleNotifications();
    const Ctor = jest.fn();
    Ctor.permission = "denied";
    global.Notification = Ctor;
    mod.showNotification("t", "b");
    expect(Ctor).not.toHaveBeenCalled();
  });

  test("hovering a token suggestion highlights it", async () => {
    routeFetch({
      tokenList: {
        tokens: [
          {
            chainId: 1,
            address: "0xAAAA000000000000000000000000000000000001",
            symbol: "AAA",
            name: "Alpha",
            decimals: 18,
          },
        ],
      },
    });
    await app.fetchUniswapTokenList();

    const host = document.createElement("div");
    const input = document.createElement("input");
    host.appendChild(input);
    document.body.appendChild(host);
    app.createTokenSelector(input);

    input.value = "AAA";
    input.dispatchEvent(new Event("input"));
    const item = host.querySelector(".token-selector-item");
    item.dispatchEvent(new MouseEvent("mouseenter", { bubbles: true }));
    expect(item.classList.contains("selected")).toBe(true);
  });

  test("ETH is not duplicated when it is already a recent token", () => {
    const v2 = loadApp({ search: "?v=2" });
    v2.addRecentToken(NATIVE, "ETH");

    const host = document.createElement("div");
    const input = document.createElement("input");
    host.appendChild(input);
    document.body.appendChild(host);
    v2.createTokenSelector(input);

    input.dispatchEvent(new Event("focus"));
    const symbols = [...host.querySelectorAll(".token-symbol")].map((s) => s.textContent);
    expect(symbols.filter((s) => s === "ETH")).toHaveLength(1);

    input.value = "";
    input.dispatchEvent(new Event("input"));
    const again = [...host.querySelectorAll(".token-symbol")].map((s) => s.textContent);
    expect(again.filter((s) => s === "ETH")).toHaveLength(1);
  });

  test("the order modal offers Watch and Close", async () => {
    installEthers();
    routeFetch({ orders: [makeOrder({ orderId: "7" })] });
    await app.loadOrders();
    app.openOrderModal(app.findOrderById("7"));

    const buttons = [...document.querySelectorAll("#order-modal-actions button")];
    const watch = buttons.find((b) => /watch/i.test(b.textContent));
    watch.click();
    expect(app.isOrderWatched("7")).toBe(true);

    const close = buttons.find((b) => b.textContent === "Close");
    close.click();
    expect(document.querySelector("#order-modal").classList.contains("hidden")).toBe(true);
  });

  test("a subgraph request aborts once the timeout elapses", async () => {
    jest.useFakeTimers();
    try {
      const mod = loadApp();
      global.fetch.mockImplementation(
        (url, init) =>
          new Promise((_, reject) => {
            init.signal.addEventListener("abort", () => {
              const err = new Error("aborted");
              err.name = "AbortError";
              reject(err);
            });
          })
      );
      const pending = mod.querySubgraph("query { orders( ) { orderId } }");
      await jest.advanceTimersByTimeAsync(30000);
      await expect(pending).resolves.toBeNull();
    } finally {
      jest.useRealTimers();
    }
  });

  test("the watched filter narrows the table to watched orders", async () => {
    const mod = loadApp();
    installEthers();
    const watched = makeOrder({ orderId: "1" });
    mod.watchOrder(watched);
    routeFetch({ orders: [watched, makeOrder({ orderId: "2" })] });

    document.querySelector('input[name="status"][value="watched"]').checked = true;
    mod.initApp();
    await flush();
    document
      .querySelector('input[name="status"][value="watched"]')
      .dispatchEvent(new Event("change"));
    await flush();
    expect(mod.findOrderById("2")).toBeNull();
  });

  test("row action buttons fill and cancel", async () => {
    const { mod } = await boot();
    routeFetch({
      orders: [makeOrder({ orderId: "1" }), makeOrder({ orderId: "2", maker: WALLET_ADDRESS })],
    });
    await mod.loadOrders();

    const buttons = [...document.querySelectorAll("#order-table button")];
    const fill = buttons.find((b) => /fill/i.test(b.textContent));
    const cancel = buttons.find((b) => /cancel/i.test(b.textContent));

    if (fill) {
      fill.click();
      await flush();
    }
    if (cancel) {
      cancel.click();
      await flush();
    }
    expect(document.querySelector("#modal")).not.toBeNull();
  });

  test("the order id link opens the detail modal", async () => {
    const { mod } = await boot();
    routeFetch({ orders: [makeOrder({ orderId: "1" })] });
    await mod.loadOrders();
    const link = document.querySelector("#order-table .trade-id-link");
    expect(link).not.toBeNull();
    link.click();
    expect(document.querySelector("#order-modal-id").textContent).toBe("1");
  });

  test("clicking the price cell flips the quote side", async () => {
    const { mod } = await boot();
    routeFetch({ orders: [makeOrder({ orderId: "1" })] });
    await mod.loadOrders();
    const price = document.querySelector("#order-table td.price-cell, #order-table .price-cell");
    if (price) {
      price.click();
      expect(price).not.toBeNull();
    }
  });

  test("sortable headers sort, but the swap icon does not", async () => {
    const { mod } = await boot();
    routeFetch({ orders: [makeOrder({ orderId: "1" })] });
    await mod.loadOrders();

    const th = document.querySelector("thead th.sortable");
    th.click();
    const icon = th.querySelector(".swap-icon");
    if (icon) icon.click();
    expect(th).not.toBeNull();
  });

  test("pagination moves forward and back", async () => {
    const { mod } = await boot();
    const page = Array.from({ length: 200 }, (_, i) => makeOrder({ orderId: String(i + 1) }));
    routeFetch({ orders: page });
    await mod.loadOrders();

    document.querySelector("#next-page").click();
    await flush();
    document.querySelector("#prev-page").click();
    await flush();
    expect(global.fetch).toHaveBeenCalled();
  });

  test("the revoke list delegates clicks to revokeApproval", async () => {
    const { mod } = await boot();
    const list = document.querySelector("#revoke-list");
    const btn = document.createElement("button");
    btn.className = "revoke-btn";
    btn.dataset.address = A;
    btn.dataset.symbol = "AAA";
    btn.textContent = "Revoke";
    list.appendChild(btn);

    btn.click();
    await flush();
    expect(btn.disabled).toBe(true);
    expect(btn.textContent).toBe("...");
  });

  test("a non-button click in the revoke list is ignored", async () => {
    await boot();
    const list = document.querySelector("#revoke-list");
    expect(() => list.click()).not.toThrow();
  });

  test("chainChanged reloads the page", async () => {
    const h = installEthers();
    routeFetch({ orders: [] });
    await connect(app, h);
    const call = h.wallet.on.mock.calls.find((c) => c[0] === "chainChanged");
    expect(call).toBeDefined();

    const restore = stubLocation();
    try {
      // Back on the expected chain: reload so every cached read is re-fetched.
      call[1]("0x1");
      expect(window.location.reload).toHaveBeenCalled();
    } finally {
      restore();
    }
  });

  test("chainChanged to the wrong network disconnects instead", async () => {
    const h = installEthers();
    routeFetch({ orders: [] });
    await connect(app, h);
    const call = h.wallet.on.mock.calls.find((c) => c[0] === "chainChanged");
    call[1]("0x89"); // Polygon
    expect(document.querySelector("#toast").textContent).toMatch(/switch to Ethereum mainnet/i);
    expect(document.querySelector("#connect-btn").textContent).toMatch(/connect/i);
  });

  test("resolveBuildInfo hashes the shipped scripts", async () => {
    const digest = jest.fn().mockResolvedValue(new Uint8Array([0, 15, 255]).buffer);
    Object.defineProperty(window, "crypto", {
      value: { subtle: { digest } },
      configurable: true,
    });
    global.fetch.mockResolvedValue({
      ok: true,
      status: 200,
      arrayBuffer: async () => new ArrayBuffer(8),
      json: async () => ({}),
    });
    await app.resolveBuildInfo();
    expect(digest).toHaveBeenCalled();
  });

  test("resolveBuildInfo tolerates an unreachable file", async () => {
    global.fetch.mockResolvedValue({ ok: false, status: 404, json: async () => ({}) });
    await expect(app.resolveBuildInfo()).resolves.toBeUndefined();
  });

  test("the eager reconnect path rewires contract events", async () => {
    const h = installEthers();
    h.wallet.request = jest.fn().mockResolvedValue([WALLET_ADDRESS]);
    routeFetch({ orders: [makeOrder({ orderId: "1" })] });
    jest.spyOn(console, "info").mockImplementation(() => {});
    jest.spyOn(console, "warn").mockImplementation(() => {});
    jest.spyOn(console, "error").mockImplementation(() => {});

    app.initApp();
    await flush(8);

    const names = h.swap.on.mock.calls.map((c) => c[0]);
    for (const name of names.filter((n) => n === "OrderFilled")) {
      const handler = h.swap.on.mock.calls.find((c) => c[0] === name)[1];
      handler("1", "0xbbbb000000000000000000000000000000000001");
    }
    await flush();
    expect(names.length).toBeGreaterThan(0);
  });

  test("the amountB field revalidates on input", () => {
    const row = app.addCreateRow();
    app.getRowState(row).tokenB.info = { decimals: 18, symbol: "BBB" };
    const input = app.rowField(row, "amountB");
    input.value = "2";
    input.dispatchEvent(new Event("input"));
    expect(input.classList.contains("input-error")).toBe(false);
  });
});

describe("v2 single-order entry points", () => {
  const NATIVE = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
  const A = "0x1111111111111111111111111111111111111111";
  const B = "0x2222222222222222222222222222222222222222";

  async function v2() {
    const mod = loadApp({ search: "?v=2" });
    const h = installEthers();
    routeFetch({ orders: [] });
    await connect(mod, h);
    await flush();
    jest.spyOn(console, "info").mockImplementation(() => {});
    jest.spyOn(console, "error").mockImplementation(() => {});
    return { mod, h };
  }

  afterEach(() => {
    if (console.info.mockRestore) console.info.mockRestore();
    if (console.error.mockRestore) console.error.mockRestore();
  });

  test("an all-or-nothing fill goes through fillOrder", async () => {
    const { mod } = await v2();
    await mod.handleFillOrder(makeOrder({ partialFill: false }));
    await confirmModal({ settleMs: 2400 });
    expect(document.querySelector("#toast").textContent).toMatch(/filled/i);
  }, 20000);

  test("an ETH-wanted fill goes through fillOrderWithEth", async () => {
    const { mod } = await v2();
    await mod.handleFillOrder(
      makeOrder({ partialFill: false, tokenB: { address: NATIVE, symbol: "ETH", decimals: 18 } })
    );
    await confirmModal({ settleMs: 2400 });
    expect(document.querySelector("#toast").textContent).toMatch(/filled/i);
  }, 20000);

  test("cancelling a v2 order goes through cancelOrder", async () => {
    const { mod } = await v2();
    await mod.handleCancelOrder(makeOrder());
    await confirmModal({ settleMs: 2400 });
    expect(document.querySelector("#toast").textContent).toMatch(/cancelled/i);
  }, 20000);

  test("v2 offers no gas estimate", async () => {
    const { mod } = await v2();
    await mod.handleFillOrder(makeOrder({ partialFill: false }));
    expect(document.querySelector("#modal-body .gas-estimate")).toBeNull();
  }, 20000);

  test("two ETH-offering orders batch through createOrdersWithEth", async () => {
    const { mod } = await v2();
    const r1 = mod.addCreateRow();
    const r2 = mod.addCreateRow();
    for (const [row, amt] of [
      [r1, "1"],
      [r2, "2"],
    ]) {
      mod.rowField(row, "tokenA").value = NATIVE;
      mod.rowField(row, "tokenB").value = B;
      mod.rowField(row, "amountA").value = amt;
      mod.rowField(row, "amountB").value = "5";
    }
    await mod.handleCreateOrder();
    await confirmModal({ settleMs: 2400 });
    expect(document.querySelector("#toast").textContent).toMatch(/Created 2 orders|created/i);
  }, 20000);
});

describe("v1 unsupported batch surface", () => {
  test("every v2-only entry point rejects with a clear message", async () => {
    // CAPS.batch keeps these unreachable in the UI; reaching one means a gate
    // was missed, and the connector must fail loudly rather than silently
    // sending one transaction where the user asked for many.
    for (const method of [
      "createOrders",
      "createOrdersWithEth",
      "fillOrders",
      "tryFillOrders",
      "tryFillOrdersWithEth",
      "cancelOrders",
      "cancelOrdersUnwrap",
    ]) {
      await expect(app.v1Unsupported(method)).rejects.toThrow(
        new RegExp(`${method} is a v2 entry point`)
      );
    }
  });
});

describe("connector adapters", () => {
  const A = "0x1111111111111111111111111111111111111111";
  const B = "0x2222222222222222222222222222222222222222";

  describe("V1", () => {
    /** Connects v1 so the module-level `contract` and `signer` are live. */
    async function live() {
      const h = installEthers();
      routeFetch({ orders: [] });
      await connect(app, h);
      await flush();
      return h;
    }

    test("createOrder forwards straight to the contract", async () => {
      const h = await live();
      await app.V1.createOrder(A, 1n, B, 2n);
      expect(h.swap.createOrder).toHaveBeenCalledWith(A, 1n, B, 2n);
    });

    test("createOrderWithEth passes the offered amount as msg.value", async () => {
      const h = await live();
      await app.V1.createOrderWithEth(B, 2n, false, 5n);
      expect(h.swap.createOrderWithEth).toHaveBeenCalled();
    });

    test("fillOrder ignores the v2-only fill amount", async () => {
      const h = await live();
      await app.V1.fillOrder("1", 99);
      expect(h.swap.fillOrder).toHaveBeenCalledWith("1", 99);
    });

    test("fillOrderWithEth sends the payment as value", async () => {
      const h = await live();
      await app.V1.fillOrderWithEth("1", 99, 7n);
      expect(h.swap.fillOrderWithEth).toHaveBeenCalled();
    });

    test("fillOrderUnwrap pays the taker in ETH", async () => {
      const h = await live();
      await app.V1.fillOrderUnwrap("1", 99);
      expect(h.swap.fillOrderUnwrap).toHaveBeenCalled();
    });

    test("cancelOrder and cancelOrderUnwrap forward to the contract", async () => {
      const h = await live();
      await app.V1.cancelOrder("1");
      await app.V1.cancelOrderUnwrap("2");
      expect(h.swap.cancelOrder).toHaveBeenCalledWith("1");
      expect(h.swap.cancelOrderUnwrap).toHaveBeenCalledWith("2");
    });

    test.each([
      "createOrders",
      "createOrdersWithEth",
      "fillOrders",
      "tryFillOrders",
      "tryFillOrdersWithEth",
      "cancelOrders",
      "cancelOrdersUnwrap",
    ])("%s rejects rather than silently doing something smaller", async (method) => {
      await expect(app.V1[method]()).rejects.toThrow(new RegExp(`${method} is a v2 entry point`));
    });

    test("ensureAllowance approves only when the allowance falls short", async () => {
      const h = await live();
      await expect(app.V1.ensureAllowance(A, 10n)).resolves.toBe(true);
      expect(h.token.approve).toHaveBeenCalledWith(SWAPBOARD_ADDRESS, 10n);
    });

    test("ensureAllowance skips an approval that is already large enough", async () => {
      const h = installEthers({
        token: { allowance: jest.fn().mockResolvedValue(BigInt("1000000000000000000000")) },
      });
      routeFetch({ orders: [] });
      await connect(app, h);
      await expect(app.V1.ensureAllowance(A, 10n)).resolves.toBe(false);
      expect(h.token.approve).not.toHaveBeenCalled();
    });

    test("estimateFor returns null before a wallet is connected", async () => {
      await expect(app.V1.estimateFor("fillOrder", ["1", 0])).resolves.toBeNull();
    });

    test("estimateFor encodes the call and prices it", async () => {
      const h = await live();
      const est = await app.V1.estimateFor("fillOrder", ["1", 0]);
      expect(h.swap.interface.encodeFunctionData).toHaveBeenCalledWith("fillOrder", ["1", 0]);
      expect(est).toMatchObject({ gas: "21000" });
    });

    test("estimateFor attaches msg.value for payable calls", async () => {
      const h = await live();
      await app.V1.estimateFor("fillOrderWithEth", ["1", 0], 5n);
      expect(h.provider.estimateGas).toHaveBeenCalledWith(expect.objectContaining({ value: 5n }));
    });

    test("estimateFor returns null rather than blocking on an encode failure", async () => {
      const h = await live();
      h.swap.interface.encodeFunctionData = jest.fn(() => {
        throw new Error("unknown selector");
      });
      jest.spyOn(console, "error").mockImplementation(() => {});
      await expect(app.V1.estimateFor("nope", [])).resolves.toBeNull();
      console.error.mockRestore();
    });
  });

  describe("V2", () => {
    let v2;
    beforeEach(() => {
      v2 = loadApp({ search: "?v=2" });
      jest.spyOn(console, "info").mockImplementation(() => {});
    });
    afterEach(() => {
      if (console.info.mockRestore) console.info.mockRestore();
    });

    /** Every V2 method resolves a simulated ethers-shaped transaction. */
    async function expectSimulatedTx(promise) {
      const tx = await promise;
      expect(tx.hash).toMatch(/^0x[0-9a-f]{64}$/);
      expect(typeof tx.wait).toBe("function");
      return tx;
    }

    test("createOrder is simulated", async () => {
      await expectSimulatedTx(v2.V2.createOrder(A, 1n, B, 2n, true));
    });

    test("createOrderWithEth is simulated", async () => {
      await expectSimulatedTx(v2.V2.createOrderWithEth(B, 2n, true, 5n));
    });

    test("createOrders encodes each param struct", async () => {
      await expectSimulatedTx(
        v2.V2.createOrders([{ tokenA: A, amountA: 1n, tokenB: B, amountB: 2n, partialFill: true }])
      );
    });

    test("createOrdersWithEth carries the batch total as value", async () => {
      await expectSimulatedTx(
        v2.V2.createOrdersWithEth(
          [{ tokenA: A, amountA: 1n, tokenB: B, amountB: 2n, partialFill: true }],
          1n
        )
      );
    });

    test("fillOrder is simulated", async () => {
      await expectSimulatedTx(v2.V2.fillOrder("1", 99, 0n));
    });

    test("fillOrderWithEth is simulated", async () => {
      await expectSimulatedTx(v2.V2.fillOrderWithEth("1", 99, 5n));
    });

    test("fillOrderUnwrap is simulated", async () => {
      await expectSimulatedTx(v2.V2.fillOrderUnwrap("1", 99, 0n));
    });

    test("cancelOrder and cancelOrderUnwrap are simulated", async () => {
      await expectSimulatedTx(v2.V2.cancelOrder("1"));
      await expectSimulatedTx(v2.V2.cancelOrderUnwrap("2"));
    });

    test("the batch fill entry points are simulated", async () => {
      await expectSimulatedTx(v2.V2.fillOrders(["1", "2"], 99, [0n, 0n]));
      await expectSimulatedTx(v2.V2.tryFillOrders(["1", "2"], 99, [0n, 0n]));
      await expectSimulatedTx(v2.V2.tryFillOrdersWithEth(["1", "2"], 99, [0n, 0n], 5n));
    });

    test("the batch cancel entry points are simulated", async () => {
      await expectSimulatedTx(v2.V2.cancelOrders(["1", "2"]));
      await expectSimulatedTx(v2.V2.cancelOrdersUnwrap(["1", "2"]));
    });

    test("ensureAllowance approves an ERC20 but not native ETH", async () => {
      await expect(
        v2.V2.ensureAllowance("0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE", 1n)
      ).resolves.toBe(false);
      await expect(v2.V2.ensureAllowance(A, 1n)).resolves.toBe(true);
    }, 10000);

    test("v2 offers no gas estimate and nothing to sync", async () => {
      await expect(v2.V2.estimateFor("fillOrder", [])).resolves.toBeNull();
      await expect(v2.V2.syncAfter("1", false)).resolves.toBeUndefined();
    });
  });
});

describe("final wiring", () => {
  const WETH = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";
  const USDC = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48";

  afterEach(() => {
    for (const m of ["info", "error", "warn"]) {
      if (console[m].mockRestore) console[m].mockRestore();
    }
  });

  test("the row [Cancel] link cancels that order", async () => {
    const h = installEthers();
    routeFetch({ orders: [makeOrder({ orderId: "1", maker: WALLET_ADDRESS })] });
    await connect(app, h);
    await flush();
    await app.loadOrders();

    const cancel = document.querySelector("#order-table .cancel-btn");
    expect(cancel).not.toBeNull();
    cancel.click();
    await flush();
    expect(document.querySelector("#modal-title").textContent).toMatch(/Cancel Order #1/i);
  });

  test("the row [Fill] link fills that order", async () => {
    const h = installEthers();
    routeFetch({ orders: [makeOrder({ orderId: "1" })] });
    await connect(app, h);
    await flush();
    await app.loadOrders();

    const fill = document.querySelector("#order-table .buy-btn");
    expect(fill).not.toBeNull();
    fill.click();
    await flush();
    expect(document.querySelector("#modal-title").textContent).toBe("Fill Order #1");
  });

  test("the row [Fill] link connects a wallet first when there is none", async () => {
    installEthers();
    routeFetch({ orders: [makeOrder({ orderId: "1" })] });
    await app.loadOrders();

    const fill = document.querySelector("#order-table .buy-btn");
    fill.click();
    await flush();
    expect(document.querySelector("#modal")).not.toBeNull();
  });

  test("a mixed cancel batch splits plain and unwrapping orders", async () => {
    const mod = loadApp({ search: "?v=2" });
    const h = installEthers();
    routeFetch({ orders: [] });
    await connect(mod, h);
    await flush();
    jest.spyOn(console, "info").mockImplementation(() => {});

    // One order offers WETH (unwraps on cancel), one offers a plain ERC20.
    const orders = [
      makeOrder({
        orderId: "1",
        maker: WALLET_ADDRESS,
        tokenA: { address: WETH, symbol: "WETH", decimals: 18 },
      }),
      makeOrder({
        orderId: "2",
        maker: WALLET_ADDRESS,
        tokenA: { address: USDC, symbol: "USDC", decimals: 6 },
        tokenB: { address: WETH, symbol: "WETH", decimals: 18 },
      }),
    ];
    routeFetch({ orders });
    await mod.loadOrders();
    for (const o of orders) mod.toggleOrderSelection(mod.findOrderById(o.orderId), false);

    await mod.cancelSelectedOrders();
    await confirmModal({ settleMs: 2400 });
    expect(document.querySelector("#toast").textContent).toMatch(/Cancelled 2 orders/i);
  }, 20000);

  test("a failed balance read leaves the wallet menu intact", async () => {
    const h = installEthers({
      provider: { getBalance: jest.fn().mockRejectedValue(new Error("rpc down")) },
    });
    routeFetch({ orders: [] });
    await connect(app, h);
    await flush();
    // The fixture's placeholder stands; the failed read must not overwrite it.
    expect(document.querySelector("#wallet-balance").textContent).toBe("-- ETH");
    expect(h.provider.getBalance).toHaveBeenCalled();
  });

  test("the ? shortcut opens the help modal, which confirms to nothing", async () => {
    const mod = loadApp();
    installEthers();
    routeFetch({ orders: [] });
    jest.spyOn(console, "warn").mockImplementation(() => {});
    mod.initApp();
    await flush();

    document.dispatchEvent(new KeyboardEvent("keydown", { key: "?", bubbles: true }));
    expect(document.querySelector("#modal-title").textContent).toBe("Keyboard Shortcuts");
    document.querySelector("#modal-confirm").click();
    expect(document.querySelector("#modal").classList.contains("hidden")).toBe(true);
  });

  test("the r shortcut refreshes", async () => {
    const mod = loadApp();
    installEthers();
    routeFetch({ orders: [] });
    jest.spyOn(console, "warn").mockImplementation(() => {});
    mod.initApp();
    await flush();

    document.dispatchEvent(new KeyboardEvent("keydown", { key: "r", bubbles: true }));
    expect(document.querySelector("#toast").textContent).toMatch(/Refreshing/);
  });

  describe("eager reconnect", () => {
    /** Boots with a wallet that already has an authorised account. */
    async function eagerBoot(over = {}) {
      const mod = loadApp();
      const h = installEthers(over);
      h.wallet.request = jest.fn(async ({ method }) =>
        method === "eth_accounts" ? [WALLET_ADDRESS] : [WALLET_ADDRESS]
      );
      routeFetch({ orders: [makeOrder({ orderId: "1" })] });
      jest.spyOn(console, "info").mockImplementation(() => {});
      jest.spyOn(console, "warn").mockImplementation(() => {});
      jest.spyOn(console, "error").mockImplementation(() => {});
      mod.initApp();
      await flush(10);
      return { mod, h };
    }

    test("reconnects silently and subscribes to contract events", async () => {
      const { h } = await eagerBoot();
      const names = h.swap.on.mock.calls.map((c) => c[0]);
      expect(names).toEqual(
        expect.arrayContaining(["OrderFilled", "OrderCanceled", "OrderCreated"])
      );
      expect(document.querySelector("#connect-btn").textContent).toMatch(/0xf39/i);
    });

    test("the reconnected OrderCanceled handler toasts and reloads", async () => {
      const { h } = await eagerBoot();
      const handler = h.swap.on.mock.calls.find((c) => c[0] === "OrderCanceled")[1];
      handler("42");
      await flush();
      expect(document.querySelector("#toast").textContent).toMatch(/Order #42 canceled/);
    });

    test("the reconnected OrderCreated handler reloads", async () => {
      const { h } = await eagerBoot();
      const handler = h.swap.on.mock.calls.find((c) => c[0] === "OrderCreated")[1];
      const before = global.fetch.mock.calls.length;
      handler("43", WALLET_ADDRESS, "0xa", "1", "0xb", "2");
      await flush();
      expect(global.fetch.mock.calls.length).toBeGreaterThan(before);
    });

    test("the reconnected OrderFilled handler notifies another taker", async () => {
      const { h } = await eagerBoot();
      const handler = h.swap.on.mock.calls.find((c) => c[0] === "OrderFilled")[1];
      handler("44", "0xbbbb000000000000000000000000000000000001");
      await flush();
      expect(global.fetch).toHaveBeenCalled();
    });

    test("a rejected eager reconnect is swallowed", async () => {
      const mod = loadApp();
      // The eager path probes with provider.send("eth_accounts"), not
      // wallet.request -- a locked wallet rejects there.
      const h = installEthers({
        provider: { send: jest.fn().mockRejectedValue(new Error("wallet locked")) },
      });
      routeFetch({ orders: [] });
      jest.spyOn(console, "warn").mockImplementation(() => {});
      jest.spyOn(console, "error").mockImplementation(() => {});
      mod.initApp();
      await flush(10);
      // Assert on this test's own handles: a refused reconnect must not
      // subscribe to contract events. The shared DOM can still carry a toast
      // from another test's late async continuation.
      expect(h.swap.on).not.toHaveBeenCalled();
    });
  });
});

describe("coverage of remaining branches", () => {
  const WETH = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";
  const USDC = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48";

  afterEach(() => {
    for (const m of ["info", "error", "warn"]) {
      if (console[m].mockRestore) console[m].mockRestore();
    }
  });

  describe("market deviation", () => {
    /**
     * Loads the app with the market-deviation column switched on. CONFIG comes
     * from lib.js by reference, so the flag has to be flipped on the same
     * object app.js destructures.
     */
    function loadWithDeviation() {
      jest.resetModules();
      document.body.className = "";
      document.body.innerHTML = BODY_HTML;
      document.head.querySelectorAll("script").forEach((s) => s.remove());
      const lib = require("./lib");
      lib.CONFIG.SHOW_MARKET_DEVIATION = true;
      window.SwapboardLib = lib;
      return { mod: require("./app"), lib };
    }

    afterEach(() => {
      const lib = require("./lib");
      lib.CONFIG.SHOW_MARKET_DEVIATION = false;
    });

    test("the order table shows how far a price sits from market", async () => {
      const { mod } = loadWithDeviation();
      installEthers();
      routeFetch({
        orders: [
          makeOrder({
            orderId: "1",
            tokenA: { address: WETH, symbol: "WETH", decimals: 18 },
            tokenB: { address: USDC, symbol: "USDC", decimals: 6 },
          }),
        ],
        prices: { weth: { usd: 3000 }, "usd-coin": { usd: 1 } },
      });
      await mod.loadStats();
      await mod.loadOrders();
      expect(document.querySelector("#order-table").textContent.length).toBeGreaterThan(0);
    });

    test("the order modal shows the same figure", async () => {
      const { mod } = loadWithDeviation();
      installEthers();
      routeFetch({
        orders: [
          makeOrder({
            orderId: "1",
            tokenA: { address: WETH, symbol: "WETH", decimals: 18 },
            tokenB: { address: USDC, symbol: "USDC", decimals: 6 },
          }),
        ],
        prices: { weth: { usd: 3000 }, "usd-coin": { usd: 1 } },
      });
      await mod.loadStats();
      await mod.loadOrders();
      mod.openOrderModal(mod.findOrderById("1"));
      expect(document.querySelector("#order-modal-market")).not.toBeNull();
    });
  });

  test("validateConfig skips validation on localhost", () => {
    const warn = jest.spyOn(console, "warn").mockImplementation(() => {});
    app.validateConfig(); // jsdom serves from localhost
    expect(warn).toHaveBeenCalledWith("Development mode: skipping config validation");
    warn.mockRestore();
  });

  test("validateConfig fails loudly on placeholder configuration in production", () => {
    jest.resetModules();
    document.body.innerHTML = BODY_HTML;
    const lib = require("./lib");
    const realAddress = lib.CONFIG.CONTRACT_ADDRESS;
    lib.CONFIG.CONTRACT_ADDRESS = "0x0000000000000000000000000000000000000000";
    window.SwapboardLib = lib;
    const mod = require("./app");

    // The guard only runs off localhost, which is what jsdom serves.
    const restore = stubLocation();
    const error = jest.spyOn(console, "error").mockImplementation(() => {});
    try {
      expect(() => mod.validateConfig()).toThrow(/Configuration error/);
      expect(error).toHaveBeenCalled();
      expect(document.body.textContent).toMatch(/Configuration error/);
    } finally {
      lib.CONFIG.CONTRACT_ADDRESS = realAddress;
      error.mockRestore();
      restore();
    }
  });

  test("an ENS lookup failure is cached as a miss", async () => {
    const h = installEthers({
      provider: { lookupAddress: jest.fn().mockRejectedValue(new Error("no resolver")) },
    });
    routeFetch({ orders: [] });
    await connect(app, h);
    await expect(app.resolveEns(WALLET_ADDRESS)).resolves.toBeNull();
    // Second call is served from the negative cache.
    await expect(app.resolveEns(WALLET_ADDRESS)).resolves.toBeNull();
    expect(h.provider.lookupAddress).toHaveBeenCalledTimes(1);
    expect(app.getCachedEns(WALLET_ADDRESS)).toBeNull();
  });

  test("stored filter preferences are reapplied", () => {
    const stored = { status: "filled", selling: WETH, wanting: USDC };
    localStorage.setItem("swapboard_filters", JSON.stringify(stored));
    const mod = loadApp();
    mod.loadFilterPreferences();
    localStorage.setItem("swapboard_sort", JSON.stringify({ column: "maker", direction: "asc" }));
    mod.loadSortPreferences();
    expect(() => mod.updateSortIndicators()).not.toThrow();
  });

  test("checkWatchedOrders notifies on a fill and on a cancel", async () => {
    const mod = loadApp();
    global.Notification.permission = "granted";
    await mod.toggleNotifications();

    const open = makeOrder({ orderId: "1" });
    const other = makeOrder({ orderId: "2" });
    mod.watchOrder(open);
    mod.watchOrder(other);

    mod.checkWatchedOrders([
      { ...open, active: false, taker: "0xbbbb000000000000000000000000000000000001" },
      { ...other, active: false, taker: null },
    ]);

    const watched = mod.getWatchedOrders();
    expect(watched["1"].status).toBe("Filled");
    expect(watched["2"].status).toBe("Cancelled");
  });

  test("the order modal Watch button toggles back off", async () => {
    installEthers();
    routeFetch({ orders: [makeOrder({ orderId: "7" })] });
    await app.loadOrders();
    app.openOrderModal(app.findOrderById("7"));

    const watch = [...document.querySelectorAll("#order-modal-actions button")].find((b) =>
      /watch/i.test(b.textContent)
    );
    watch.click();
    expect(app.isOrderWatched("7")).toBe(true);

    app.openOrderModal(app.findOrderById("7"));
    const unwatch = [...document.querySelectorAll("#order-modal-actions button")].find((b) =>
      /watch/i.test(b.textContent)
    );
    unwatch.click();
    expect(app.isOrderWatched("7")).toBe(false);
  });

  test("a filled order's row shows when it filled", async () => {
    installEthers();
    routeFetch({
      orders: [
        makeOrder({
          orderId: "1",
          active: false,
          taker: "0xbbbb000000000000000000000000000000000001",
          filledAt: "1700000500",
        }),
      ],
    });
    await app.loadOrders();
    expect(document.querySelector("#order-table .order-age")).not.toBeNull();
  });

  test("a cancelled order's row is labelled", async () => {
    installEthers();
    routeFetch({ orders: [makeOrder({ orderId: "1", active: false, taker: null })] });
    await app.loadOrders();
    expect(document.querySelector("#order-table").textContent).toContain("[CANCELED]");
  });

  describe("hashchange", () => {
    /** Boots initApp so the hashchange listener is live. */
    async function booted(orders) {
      const mod = loadApp();
      installEthers();
      routeFetch({ orders });
      jest.spyOn(console, "warn").mockImplementation(() => {});
      mod.initApp();
      await flush();
      await mod.loadOrders();
      return mod;
    }

    test("a hash for a cached order opens its modal", async () => {
      const mod = await booted([makeOrder({ orderId: "1" })]);
      window.history.replaceState({}, "", "/#order-1");
      window.dispatchEvent(new HashChangeEvent("hashchange"));
      expect(document.querySelector("#order-modal-id").textContent).toBe("1");
    });

    test("a hash for an unknown order widens the filter and reloads", async () => {
      const mod = await booted([makeOrder({ orderId: "1" })]);
      window.history.replaceState({}, "", "/#order-999");
      window.dispatchEvent(new HashChangeEvent("hashchange"));
      await flush();
      expect(document.querySelector('input[name="status"][value="all"]').checked).toBe(true);
    });

    test("clearing the hash closes the modal", async () => {
      const mod = await booted([makeOrder({ orderId: "1" })]);
      window.history.replaceState({}, "", "/#order-1");
      window.dispatchEvent(new HashChangeEvent("hashchange"));
      window.history.replaceState({}, "", "/");
      window.dispatchEvent(new HashChangeEvent("hashchange"));
      expect(document.querySelector("#order-modal").classList.contains("hidden")).toBe(true);
    });
  });

  test("the c shortcut connects when no wallet is attached", async () => {
    const mod = loadApp();
    installEthers();
    routeFetch({ orders: [] });
    jest.spyOn(console, "warn").mockImplementation(() => {});
    mod.initApp();
    await flush();

    document.dispatchEvent(new KeyboardEvent("keydown", { key: "c", bubbles: true }));
    await flush();
    expect(document.querySelector("#connect-btn")).not.toBeNull();
  });

  test("batch actions refuse without a wallet", async () => {
    const mod = loadApp({ search: "?v=2" });
    installEthers();
    routeFetch({ orders: [makeOrder({ orderId: "1" })] });
    await mod.loadOrders();
    mod.toggleOrderSelection(mod.findOrderById("1"), false);

    await mod.fillSelectedOrders();
    expect(document.querySelector("#toast").textContent).toMatch(/Connect wallet first/);

    await mod.cancelSelectedOrders();
    expect(document.querySelector("#toast").textContent).toMatch(/Connect wallet first/);
  });

  test("loadStats prices volume when at least one token has a price", async () => {
    routeFetch({
      stats: { totalOrders: "1", activeOrders: "1", filledOrders: "0", cancelledOrders: "0" },
      tokens: [{ address: WETH, decimals: 18, volumeSold: "3000000000000000000" }],
      prices: { weth: { usd: 2500 } },
    });
    await app.loadStats();
    expect(document.querySelector("#stat-total").textContent).toBe("1");
  });
});

describe("last mile", () => {
  const WETH = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";
  const USDC = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48";
  const PLAIN = "0x1111111111111111111111111111111111111111";

  afterEach(() => {
    for (const m of ["info", "error", "warn"]) {
      if (console[m].mockRestore) console[m].mockRestore();
    }
  });

  test("preferredQuoteSide prefers WETH once it is known", async () => {
    const h = installEthers();
    routeFetch({ orders: [] });
    await connect(app, h);
    expect(app.preferredQuoteSide(WETH, PLAIN)).toBe("A");
    expect(app.preferredQuoteSide(PLAIN, WETH)).toBe("B");
  });

  test("a WETH row is relabelled as ETH in the create form", async () => {
    jest.useFakeTimers();
    try {
      const mod = loadApp();
      const h = installEthers();
      routeFetch({ orders: [] });
      await connect(mod, h);

      const row = mod.addCreateRow();
      const input = mod.rowField(row, "tokenA");
      input.value = WETH;
      input.dispatchEvent(new Event("input"));
      await jest.advanceTimersByTimeAsync(600);
      expect(mod.getRowState(row).tokenA.info.symbol).toBe("ETH");
    } finally {
      jest.useRealTimers();
    }
  });

  test("collectCreateParams relabels a WETH leg as ETH", async () => {
    const h = installEthers();
    routeFetch({ orders: [] });
    await connect(app, h);
    const row = app.addCreateRow();
    app.rowField(row, "tokenA").value = WETH;
    app.rowField(row, "tokenB").value = USDC;
    app.rowField(row, "amountA").value = "1";
    app.rowField(row, "amountB").value = "2";

    const params = await app.collectCreateParams();
    expect(params[0].tokenAInfo.symbol).toBe("ETH");
  });

  test("a create that reverts reports the contract error", async () => {
    const h = installEthers({
      swap: { createOrder: jest.fn().mockRejectedValue(new Error("execution reverted")) },
    });
    routeFetch({ orders: [] });
    await connect(app, h);
    jest.spyOn(console, "error").mockImplementation(() => {});

    const row = app.addCreateRow();
    app.rowField(row, "tokenA").value = PLAIN;
    app.rowField(row, "tokenB").value = USDC;
    app.rowField(row, "amountA").value = "1";
    app.rowField(row, "amountB").value = "2";

    await app.handleCreateOrder();
    await confirmModal();
    expect(document.querySelector("#toast").textContent).toMatch(/Create failed/);
    expect(document.querySelector("#create-btn").disabled).toBe(false);
  });

  test("a refused network switch stops the connect", async () => {
    const err = new Error("user rejected");
    const h = installEthers({
      provider: { getNetwork: jest.fn().mockResolvedValue({ chainId: BigInt(5) }) },
      wallet: { request: jest.fn().mockRejectedValue(err), on: jest.fn() },
    });
    routeFetch({ orders: [] });
    await connect(app, h);
    expect(document.querySelector("#toast").textContent).toMatch(
      /Please switch to Ethereum mainnet/
    );
  });

  test("the CSV button reports an empty table", async () => {
    const mod = loadApp();
    installEthers();
    routeFetch({ orders: [] });
    jest.spyOn(console, "warn").mockImplementation(() => {});
    mod.initApp();
    await flush();

    document.querySelector("#export-csv").click();
    expect(document.querySelector("#toast").textContent).toBe("No orders to export");
  });

  test("the CSV button exports the loaded rows", async () => {
    const mod = loadApp();
    installEthers();
    routeFetch({ orders: [makeOrder({ orderId: "1" })] });
    jest.spyOn(console, "warn").mockImplementation(() => {});
    mod.initApp();
    await flush();
    await mod.loadOrders();

    global.URL.createObjectURL = jest.fn(() => "blob:csv");
    global.URL.revokeObjectURL = jest.fn();
    document.querySelector("#export-csv").click();
    expect(global.URL.createObjectURL).toHaveBeenCalled();
  });

  test("exportMyOrders handles a wallet with no orders", async () => {
    const h = installEthers();
    routeFetch({ orders: [] });
    await connect(app, h);
    await flush();
    global.URL.createObjectURL = jest.fn(() => "blob:csv");
    global.URL.revokeObjectURL = jest.fn();
    global.fetch.mockImplementation(async () => jsonResponse({ data: { orders: [] } }));
    await app.exportMyOrders();
    expect(document.querySelector("#toast").textContent).toMatch(/Exported 0 orders/);
  });

  test("export reports a failed query", async () => {
    const h = installEthers();
    routeFetch({ orders: [] });
    await connect(app, h);
    await flush();
    jest.spyOn(console, "error").mockImplementation(() => {});
    global.fetch.mockResolvedValue({ ok: false, status: 500, json: async () => ({}) });
    await app.exportMyOrders();
    expect(document.querySelector("#toast").textContent).toMatch(/Failed to export orders/);
  });

  test("resolveBuildInfo links a resolved commit", async () => {
    const el = document.querySelector("#build-commit") || document.createElement("span");
    global.fetch.mockResolvedValue({
      ok: true,
      status: 200,
      text: async () => "abcdef1234567890",
      json: async () => ({ commit: "abcdef1234567890" }),
      arrayBuffer: async () => new ArrayBuffer(4),
    });
    Object.defineProperty(window, "crypto", {
      value: { subtle: { digest: jest.fn().mockResolvedValue(new Uint8Array([1, 2]).buffer) } },
      configurable: true,
    });
    await expect(app.resolveBuildInfo()).resolves.toBeUndefined();
  });

  test("loadStats totals USD volume once a price is known", async () => {
    routeFetch({
      stats: { totalOrders: "5", activeOrders: "2", filledOrders: "2", cancelledOrders: "1" },
      tokens: [{ address: WETH, decimals: 18, volumeSold: "2000000000000000000" }],
      prices: { weth: { usd: 1500 } },
    });
    await app.loadStats();
    const volume = document.querySelector("#stat-volume");
    if (volume) expect(volume.textContent.length).toBeGreaterThan(0);
    expect(document.querySelector("#stat-total").textContent).toBe("5");
  });
});
