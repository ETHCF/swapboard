/**
 * @fileoverview Unit tests for Swapboard lib.js
 *
 * Test methodology:
 * 1. Each test validates specific expected behavior
 * 2. Each test has an identified source mutation that would break it
 * 3. No smoke tests - every assertion checks concrete values
 */

const {
  escapeHtml,
  isValidAddress,
  truncateAddress,
  getOrderIdFromHash,
  getOrderShareUrl,
  formatUsd,
  formatAmount,
  formatNumber,
  formatTimeAgo,
  formatRatio,
  formatTinyDecimal,
  setNumberText,
  parseAmount,
  getCachedPrice,
  getTokenPrice,
  fetchPrices,
  coinGeckoUrl,
  permitKindFor,
  supportsPermit,
  isSignablePermitKind,
  PERMIT2_ADDRESS,
  MAX_PERMIT2_BATCH,
  PERMIT_TTL_SECONDS,
  PERMIT_TYPES,
  PERMIT2_TYPES,
  permit2Domain,
  buildPermitMessage,
  buildPermit2Message,
  permit2Nonce,
  permitDeadline,
  choosePullStrategy,
  planBatchPulls,
  priceRatio,
  calculateMarketDeviation,
  searchTokens,
  orderStatus,
  RECENT_TOKENS_KEY,
  MAX_RECENT_TOKENS,
  FILTERS_KEY,
  SORT_KEY,
  WATCHED_ORDERS_KEY,
  getRecentTokens,
  addRecentToken,
  getWatchedOrders,
  watchOrder,
  unwatchOrder,
  isOrderWatched,
  saveFilterPreferences,
  loadFilterPreferences,
  saveSortPreferences,
  loadSortPreferences,
  sortOrders,
  ERROR_SIGNATURES,
  ERROR_MESSAGES,
  decodeErrorArgs,
  decodeContractError,
  parseContractError,
  validateConfig,
  NATIVE_ETH,
  isNativeEth,
  nativeEthTotal,
  chunkArray,
  resolveSelectionMode,
  isSamePair,
  canSelectOrder,
  getShiftRangeIds,
  quoteFill,
  computeFillFromReceive,
  computeFillFromPayment,
  allowsPartialFill,
  summarizeFillBatch,
  VERSION_STORAGE_KEY,
  DEFAULT_VERSION,
  SUPPORTED_VERSIONS,
  VERSION_CAPS,
  parseVersion,
  resolveVersion,
  capsFor,
  deploymentFor,
  ORDER_STATUS,
  orderQuerySelection,
  statusFilterCondition,
  normalizeOrder,
  statsQuerySelection,
  normalizeStats,
  popularPairsQuery,
  offersEthDirectly,
  CHAINS,
  ACTIVE_CHAIN,
  EXPECTED_CHAIN_ID,
} = require("./lib");

// ============================================================================
// Chain target
// ============================================================================

describe("chain target", () => {
  // MUTATION: Mistype a chain's hex id
  // BREAKS: wallet_switchEthereumChain asks the wallet for a chain the page
  //         then rejects as the wrong network, forever
  test("every chain's EIP-3085 chainId is its numeric id in hex", () => {
    for (const { id, chain } of Object.values(CHAINS)) {
      expect(chain.chainId).toBe("0x" + id.toString(16));
    }
  });

  // MUTATION: Swap the mainnet and Sepolia ids or explorers
  // BREAKS: a Sepolia build links every address to mainnet Etherscan
  test("mainnet and Sepolia carry their own ids and explorers", () => {
    expect(CHAINS.mainnet.id).toBe(1);
    expect(CHAINS.mainnet.chain.blockExplorerUrls).toEqual(["https://etherscan.io"]);
    expect(CHAINS.sepolia.id).toBe(11155111);
    expect(CHAINS.sepolia.chain.blockExplorerUrls).toEqual(["https://sepolia.etherscan.io"]);
  });

  // MUTATION: Leave EXPECTED_CHAIN_ID hardcoded
  // BREAKS: a Sepolia build still rejects Sepolia as the wrong network
  test("EXPECTED_CHAIN_ID follows the active chain", () => {
    expect(Object.values(CHAINS)).toContain(ACTIVE_CHAIN);
    expect(EXPECTED_CHAIN_ID).toBe(ACTIVE_CHAIN.id);
  });
});

// ============================================================================
// escapeHtml
// ============================================================================

describe("escapeHtml", () => {
  // MUTATION: Remove "&": "&amp;" from escape map
  // BREAKS: Returns "a & b" instead of "a &amp; b"
  test("escapes ampersand to &amp;", () => {
    expect(escapeHtml("a & b")).toBe("a &amp; b");
  });

  // MUTATION: Remove "<": "&lt;" from escape map
  // BREAKS: Returns "<script>" instead of "&lt;script&gt;"
  test("escapes less-than to &lt;", () => {
    expect(escapeHtml("<script>")).toBe("&lt;script&gt;");
  });

  // MUTATION: Remove ">": "&gt;" from escape map
  // BREAKS: Returns ">" instead of "&gt;"
  test("escapes greater-than to &gt;", () => {
    expect(escapeHtml(">")).toBe("&gt;");
  });

  // MUTATION: Remove '"': "&quot;" from escape map
  // BREAKS: Returns '"' instead of "&quot;"
  test("escapes double quote to &quot;", () => {
    expect(escapeHtml('"')).toBe("&quot;");
  });

  // MUTATION: Remove "'": "&#039;" from escape map
  // BREAKS: Returns "'" instead of "&#039;"
  test("escapes single quote to &#039;", () => {
    expect(escapeHtml("'")).toBe("&#039;");
  });

  // MUTATION: Return null for null input instead of ""
  // BREAKS: Returns null, typeof would be "object"
  test("returns empty string for null input", () => {
    const result = escapeHtml(null);
    expect(result).toBe("");
  });

  // MUTATION: Return undefined for undefined input
  // BREAKS: Returns undefined instead of ""
  test("returns empty string for undefined input", () => {
    const result = escapeHtml(undefined);
    expect(result).toBe("");
  });

  // MUTATION: Remove String() wrapper
  // BREAKS: .replace() throws on number input
  test("converts number to string before escaping", () => {
    expect(escapeHtml(123)).toBe("123");
  });

  // MUTATION: Add unnecessary escaping for alphanumerics
  // BREAKS: "hello" would become "&#104;&#101;&#108;&#108;&#111;"
  test("preserves alphanumeric characters unchanged", () => {
    expect(escapeHtml("hello123")).toBe("hello123");
  });

  // MUTATION: Escape only first occurrence (no /g flag)
  // BREAKS: "a & b & c" becomes "a &amp; b & c"
  test("escapes all occurrences of special characters", () => {
    expect(escapeHtml("a & b & c")).toBe("a &amp; b &amp; c");
  });

  // MUTATION: Missing forward slash in escape map
  // BREAKS: XSS via closing script tags e.g. </script>
  test("escapes forward slash to &#x2F;", () => {
    expect(escapeHtml("a/b")).toBe("a&#x2F;b");
    expect(escapeHtml("</script>")).toBe("&lt;&#x2F;script&gt;");
  });
});

// ============================================================================
// isValidAddress
// ============================================================================

describe("isValidAddress", () => {
  // MUTATION: Change regex to not require 0x prefix
  // BREAKS: Returns true for address without 0x
  test("requires 0x prefix", () => {
    expect(isValidAddress("c02aaa39b223fe8d0a0e5c4f27ead9083c756cc2")).toBe(false);
    expect(isValidAddress("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2")).toBe(true);
  });

  // MUTATION: Change {40} to {39,41} in regex
  // BREAKS: Returns true for 39-char address
  test("requires exactly 40 hex characters after 0x", () => {
    expect(isValidAddress("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc")).toBe(false); // 39
    expect(isValidAddress("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2")).toBe(true); // 40
    expect(isValidAddress("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2a")).toBe(false); // 41
  });

  // MUTATION: Change [a-fA-F0-9] to [a-zA-Z0-9]
  // BREAKS: Returns true for address with 'g'
  test("only accepts valid hex characters 0-9 a-f A-F", () => {
    expect(isValidAddress("0xgggggggggggggggggggggggggggggggggggggggg")).toBe(false);
    expect(isValidAddress("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2")).toBe(true);
  });

  // MUTATION: Remove typeof check
  // BREAKS: Returns true for number that coerces to valid-looking string
  test("rejects non-string input types", () => {
    expect(isValidAddress(null)).toBe(false);
    expect(isValidAddress(undefined)).toBe(false);
    expect(isValidAddress(123)).toBe(false);
    expect(isValidAddress({})).toBe(false);
  });

  // MUTATION: Change regex to be case-sensitive (only lowercase)
  // BREAKS: Returns false for uppercase address
  test("accepts both uppercase and lowercase hex", () => {
    expect(isValidAddress("0xC02AAA39B223FE8D0A0E5C4F27EAD9083C756CC2")).toBe(true);
    expect(isValidAddress("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2")).toBe(true);
  });

  // MUTATION: Remove ^ anchor from regex /^0x.../
  // BREAKS: Returns true for "prefix0x..." which contains valid address
  test("rejects addresses with prefix before 0x (requires ^ anchor)", () => {
    expect(isValidAddress("xx0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2")).toBe(false);
    expect(isValidAddress("a0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2")).toBe(false);
  });
});

// ============================================================================
// truncateAddress
// ============================================================================

describe("truncateAddress", () => {
  // MUTATION: Return addr.slice(0, 10) instead of full address
  // BREAKS: Returns "0xc02aaa39" instead of full address
  test("returns full address for valid input", () => {
    const addr = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";
    expect(truncateAddress(addr)).toBe(addr);
    expect(truncateAddress(addr).length).toBe(42);
  });

  // MUTATION: Return the input unchanged for invalid addresses
  // BREAKS: Returns "invalid" instead of ""
  test("returns empty string for invalid address", () => {
    expect(truncateAddress("invalid")).toBe("");
    expect(truncateAddress("0x123")).toBe("");
  });

  // MUTATION: Return "null" string for null input
  // BREAKS: Returns "null" instead of ""
  test("returns empty string for null", () => {
    expect(truncateAddress(null)).toBe("");
  });
});

// ============================================================================
// getOrderIdFromHash
// ============================================================================

describe("getOrderIdFromHash", () => {
  // MUTATION: Change regex from /^#order-(\d+)$/ to /order-(\d+)/
  // BREAKS: Would match "foo#order-123bar"
  test("parses #order-{id} format with exact match", () => {
    expect(getOrderIdFromHash("#order-123")).toBe("123");
    expect(getOrderIdFromHash("#order-0")).toBe("0");
    expect(getOrderIdFromHash("foo#order-123")).toBe(null); // Must start with #
  });

  // MUTATION: Remove the #order=(\d+) regex branch
  // BREAKS: Returns null for #order=123
  test("parses #order={id} format for backwards compatibility", () => {
    expect(getOrderIdFromHash("#order=456")).toBe("456");
  });

  // MUTATION: Remove the #(\d+) regex branch
  // BREAKS: Returns null for #789
  test("parses #{id} simple format", () => {
    expect(getOrderIdFromHash("#789")).toBe("789");
  });

  // MUTATION: Return "0" for empty hash instead of null
  // BREAKS: Returns "0" instead of null
  test("returns null for empty or missing hash", () => {
    expect(getOrderIdFromHash("")).toBe(null);
    expect(getOrderIdFromHash(null)).toBe(null);
    expect(getOrderIdFromHash(undefined)).toBe(null);
  });

  // MUTATION: Change \d+ to .+ in regex
  // BREAKS: Returns "abc" for #order-abc
  test("only matches numeric order IDs", () => {
    expect(getOrderIdFromHash("#order-abc")).toBe(null);
    expect(getOrderIdFromHash("#order-12abc")).toBe(null);
  });

  // MUTATION: Remove $ anchor from /^#order=(\d+)$/
  // BREAKS: Returns "123" for "#order=123extra"
  test("rejects #order= format with trailing characters (requires $ anchor)", () => {
    expect(getOrderIdFromHash("#order=123extra")).toBe(null);
    expect(getOrderIdFromHash("#order=456xyz")).toBe(null);
  });

  // MUTATION: Remove $ anchor from /^#(\d+)$/
  // BREAKS: Returns "123" for "#123extra"
  test("rejects simple format with trailing characters (requires $ anchor)", () => {
    expect(getOrderIdFromHash("#123extra")).toBe(null);
    expect(getOrderIdFromHash("#789abc")).toBe(null);
  });

  // MUTATION: Remove ^ anchor from /#order=(\d+)$/
  // BREAKS: Returns match for "prefix#order=123"
  test("rejects #order= format with prefix before # (requires ^ anchor)", () => {
    expect(getOrderIdFromHash("prefix#order=123")).toBe(null);
  });

  // MUTATION: Remove ^ anchor from /#(\d+)$/
  // BREAKS: Returns match for "text#123"
  test("rejects simple format with prefix before # (requires ^ anchor)", () => {
    expect(getOrderIdFromHash("text#123")).toBe(null);
  });
});

// ============================================================================
// getOrderShareUrl
// ============================================================================

describe("getOrderShareUrl", () => {
  // MUTATION: Use #order={id} instead of #order-{id}
  // BREAKS: Returns "...#order=123" instead of "...#order-123"
  test("creates URL with #order-{id} hash format", () => {
    const url = getOrderShareUrl("123", "https://example.com/");
    expect(url).toBe("https://example.com/#order-123");
  });

  // MUTATION: Replace entire URL instead of just setting hash
  // BREAKS: Loses the path /app/
  test("preserves URL path when setting hash", () => {
    const url = getOrderShareUrl("456", "https://example.com/app/");
    expect(url).toBe("https://example.com/app/#order-456");
  });

  // MUTATION: Append hash instead of replacing
  // BREAKS: Returns "...#existing#order-789"
  test("replaces existing hash", () => {
    const url = getOrderShareUrl("789", "https://example.com/#existing");
    expect(url).toBe("https://example.com/#order-789");
    expect(url.match(/#/g).length).toBe(1); // Only one hash
  });

  // MUTATION: Clear query string when setting hash
  // BREAKS: Loses ?foo=bar
  test("preserves query string", () => {
    const url = getOrderShareUrl("111", "https://example.com/?foo=bar");
    expect(url).toBe("https://example.com/?foo=bar#order-111");
  });
});

// ============================================================================
// formatUsd
// ============================================================================

describe("formatUsd", () => {
  // MUTATION: Return "$0" for null
  // BREAKS: Returns "$0" instead of "$--"
  test("returns $-- for null", () => {
    expect(formatUsd(null)).toBe("$--");
  });

  // MUTATION: Return "$NaN" for undefined (no check)
  // BREAKS: Returns "$NaN"
  test("returns $-- for undefined", () => {
    expect(formatUsd(undefined)).toBe("$--");
  });

  // MUTATION: Change threshold from 1000000 to 1000
  // BREAKS: 1500 would show as "$1.50M"
  test("formats values >= 1M with M suffix", () => {
    expect(formatUsd(1000000)).toBe("$1.00M");
    expect(formatUsd(2500000)).toBe("$2.50M");
    expect(formatUsd(999999)).toBe("$999,999"); // Just under 1M
  });

  // MUTATION: Remove comma insertion regex
  // BREAKS: Returns "$1500" instead of "$1,500"
  test("formats values >= 1000 with comma separators", () => {
    expect(formatUsd(1000)).toBe("$1,000");
    expect(formatUsd(1500)).toBe("$1,500");
    expect(formatUsd(999999)).toBe("$999,999");
  });

  // MUTATION: Use toFixed(0) instead of toFixed(2)
  // BREAKS: Returns "$6" instead of "$5.50"
  test("formats values >= 1 with 2 decimal places", () => {
    expect(formatUsd(5.5)).toBe("$5.50");
    expect(formatUsd(1.0)).toBe("$1.00");
    expect(formatUsd(999.99)).toBe("$999.99");
  });

  // MUTATION: Change threshold from 0.01 to 0.001
  // BREAKS: 0.05 would show as exponential
  test("formats values >= 0.01 with 4 decimal places", () => {
    expect(formatUsd(0.01)).toBe("$0.0100");
    expect(formatUsd(0.05)).toBe("$0.0500");
    expect(formatUsd(0.0123)).toBe("$0.0123");
  });

  // MUTATION: Use toFixed(4) for values < 0.01
  // BREAKS: 0.00123 shows as "$0.0012"
  test("shows up to 6 plain decimals for values < 0.01 >= 0.0001", () => {
    expect(formatUsd(0.001)).toBe("$0.001");
    expect(formatUsd(0.00123)).toBe("$0.00123");
    expect(formatUsd(0.0001)).toBe("$0.0001");
  });

  // MUTATION: Use toFixed(6) for tiny values
  // BREAKS: 0.0000017163 shows as "$0.000002"
  test("keeps 4 significant digits for values < 0.0001", () => {
    expect(formatUsd(0.000001)).toBe("$0.000001");
    expect(formatUsd(0.0000017163)).toBe("$0.000001716");
  });
});

// ============================================================================
// formatAmount
// ============================================================================

describe("formatAmount", () => {
  // MUTATION: Hardcode divisor as 10**18 instead of 10**decimals
  // BREAKS: 6-decimal token shows wrong value
  test("divides by 10^decimals", () => {
    expect(formatAmount("1000000000000000000", 18)).toBe("1"); // 1e18 / 1e18 = 1
    expect(formatAmount("1000000", 6)).toBe("1"); // 1e6 / 1e6 = 1
  });

  // MUTATION: Show all 18 decimal places instead of truncating to 4
  // BREAKS: Returns "1.234567890000000000" instead of "1.2345"
  test("shows at most 4 decimal places", () => {
    expect(formatAmount("1234567890000000000", 18)).toBe("1.2345");
  });

  // MUTATION: Don't remove trailing zeros
  // BREAKS: Returns "1.5000" instead of "1.5"
  test("removes trailing zeros from decimal part", () => {
    expect(formatAmount("1500000000000000000", 18)).toBe("1.5");
    expect(formatAmount("1100000000000000000", 18)).toBe("1.1");
  });

  // MUTATION: Skip formatNumber for whole part
  // BREAKS: Returns "1000000" instead of "1,000,000"
  test("adds comma separators to large whole numbers", () => {
    expect(formatAmount("1000000000000000000000000", 18)).toBe("1,000,000");
  });

  // MUTATION: Return "NaN" for zero input
  // BREAKS: Returns "NaN" instead of "0"
  test("handles zero amount", () => {
    expect(formatAmount("0", 18)).toBe("0");
    expect(formatAmount("0", 6)).toBe("0");
  });

  // MUTATION: Don't convert BigInt input to string
  // BREAKS: Throws or returns wrong value
  test("accepts BigInt input", () => {
    expect(formatAmount(BigInt("1000000000000000000"), 18)).toBe("1");
  });
});

// ============================================================================
// formatNumber
// ============================================================================

describe("formatNumber", () => {
  // MUTATION: Use wrong regex that places commas incorrectly
  // BREAKS: Returns "10,00" instead of "1,000"
  test("places commas every 3 digits from right", () => {
    expect(formatNumber(1000)).toBe("1,000");
    expect(formatNumber(1000000)).toBe("1,000,000");
    expect(formatNumber(1234567890)).toBe("1,234,567,890");
  });

  // MUTATION: Add comma even for small numbers
  // BREAKS: Returns ",999" or "9,99"
  test("no comma for numbers under 1000", () => {
    expect(formatNumber(999)).toBe("999");
    expect(formatNumber(100)).toBe("100");
    expect(formatNumber(0)).toBe("0");
  });
});

// ============================================================================
// formatTimeAgo
// ============================================================================

describe("formatTimeAgo", () => {
  const now = Math.floor(Date.now() / 1000);

  // MUTATION: Drop the seconds bucket, folding it into "just now"
  // BREAKS: A just-placed order reads as ageless while it is the freshest row
  test("shows seconds under a minute", () => {
    expect(formatTimeAgo(now - 1)).toBe("1s ago");
    expect(formatTimeAgo(now - 45)).toBe("45s ago");
    expect(formatTimeAgo(now - 59)).toBe("59s ago");
  });

  // MUTATION: Divide by 3600 instead of 60 for minutes
  // BREAKS: 120 seconds shows "0h ago" instead of "2m ago"
  test("shows minutes for 1-59 minutes ago", () => {
    expect(formatTimeAgo(now - 60)).toBe("1m ago"); // Exactly 60 = 1m
    expect(formatTimeAgo(now - 120)).toBe("2m ago");
    expect(formatTimeAgo(now - 3540)).toBe("59m ago");
  });

  // MUTATION: Change hour threshold from 86400 to 43200
  // BREAKS: 13 hours shows "1d ago" instead of "13h ago"
  test("shows hours for 1-23 hours ago", () => {
    expect(formatTimeAgo(now - 3600)).toBe("1h ago");
    expect(formatTimeAgo(now - 7200)).toBe("2h ago");
    expect(formatTimeAgo(now - 82800)).toBe("23h ago");
  });

  // MUTATION: Change day threshold from 604800 to 172800
  // BREAKS: 3 days jumps straight to weeks
  test("shows days for 1-6 days ago", () => {
    expect(formatTimeAgo(now - 86400)).toBe("1d ago");
    expect(formatTimeAgo(now - 172800)).toBe("2d ago");
    expect(formatTimeAgo(now - 518400)).toBe("6d ago");
  });

  // MUTATION: Fall back to a locale date at 7 days
  // BREAKS: The age column mixes relative ages with absolute dates
  test("shows weeks from 7 days to 30 days", () => {
    expect(formatTimeAgo(now - 604800)).toBe("1w ago"); // Exactly 7 days
    expect(formatTimeAgo(now - 1209600)).toBe("2w ago");
    expect(formatTimeAgo(now - 2591999)).toBe("4w ago");
  });

  // MUTATION: Cap the scale at weeks
  // BREAKS: A year-old order reads as "52w ago"
  test("shows months beyond 30 days, and stays relative indefinitely", () => {
    expect(formatTimeAgo(now - 2592000)).toBe("1mo ago"); // Exactly 30 days
    expect(formatTimeAgo(now - 5184000)).toBe("2mo ago");
    expect(formatTimeAgo(now - 31536000)).toBe("12mo ago"); // A year
  });

  // MUTATION: Remove the falsy guard
  // BREAKS: An unfilled order's absent filledAt renders as 12/31/1969
  test("renders nothing when there is no timestamp", () => {
    expect(formatTimeAgo(null)).toBe("");
    expect(formatTimeAgo(undefined)).toBe("");
    expect(formatTimeAgo(0)).toBe("");
  });

  // MUTATION: Drop the string coercion
  // BREAKS: Subgraph timestamps arrive as strings; "now - str" is NaN
  test("accepts the string timestamps the subgraph returns", () => {
    expect(formatTimeAgo(String(now - 7200))).toBe("2h ago");
    expect(formatTimeAgo(String(now - 172800))).toBe("2d ago");
  });

  // MUTATION: Let a negative diff fall through to the seconds bucket
  // BREAKS: Clock skew renders as "-3s ago"
  test("treats a timestamp ahead of the clock as just now", () => {
    expect(formatTimeAgo(now + 300)).toBe("just now");
  });
});

// ============================================================================
// formatRatio
// ============================================================================

describe("formatRatio", () => {
  // MUTATION: Return "0.00e+0" for zero
  // BREAKS: Returns scientific notation instead of "0"
  test("returns 0 for zero value", () => {
    expect(formatRatio(0)).toBe("0");
  });

  // MUTATION: Change M threshold from 1000000 to 1000
  // BREAKS: 1500 shows as "1.50M"
  test("formats millions with M suffix", () => {
    expect(formatRatio(1000000)).toBe("1.00M");
    expect(formatRatio(1500000)).toBe("1.50M");
    expect(formatRatio(999999)).toBe("999,999"); // Just under 1M
  });

  // MUTATION: Remove comma formatting for thousands
  // BREAKS: Returns "1500" instead of "1,500"
  test("formats thousands with comma separators", () => {
    expect(formatRatio(1000)).toBe("1,000");
    expect(formatRatio(1500)).toBe("1,500");
  });

  // MUTATION: Use 2 decimals instead of 4 for values >= 1
  // BREAKS: 1.2345 shows as "1.23"
  test("shows up to 4 significant decimals for values >= 1", () => {
    expect(formatRatio(1.2345)).toBe("1.2345");
    expect(formatRatio(1.5)).toBe("1.5"); // Trailing zeros removed
  });

  // MUTATION: Change num >= 1 to num > 1
  // BREAKS: Exactly 1 would fall through to 6-decimal format
  test("boundary: exactly 1 uses 4-decimal format (>= not >)", () => {
    // 1.00005 with toFixed(4) = "1.0001" (rounded)
    // 1.00005 with toFixed(6) = "1.00005" (not rounded)
    // This catches the >= vs > mutation
    expect(formatRatio(1.00005)).toBe("1.0001");
    expect(formatRatio(1.0001)).toBe("1.0001");
  });

  // MUTATION: Use 4 decimals instead of 6 for values < 1
  // BREAKS: 0.000123 shows as "0.0001"
  test("shows up to 6 decimals for values < 1 >= 0.0001", () => {
    expect(formatRatio(0.123456)).toBe("0.123456");
    expect(formatRatio(0.0001)).toBe("0.0001");
  });

  // MUTATION: Use toFixed(6) for tiny values
  // BREAKS: 0.000000018 shows as "0"
  test("keeps 4 significant digits for values < 0.0001", () => {
    expect(formatRatio(0.00001)).toBe("0.00001");
    expect(formatRatio(0.000000018)).toBe("0.000000018");
  });
});

// ============================================================================
// formatTinyDecimal
// ============================================================================

describe("formatTinyDecimal", () => {
  // MUTATION: Use 3 significant digits instead of 4
  // BREAKS: 0.0000123456 shows as "0.0000123"
  test("rounds to 4 significant digits and strips trailing zeros", () => {
    expect(formatTinyDecimal(0.0000017163)).toBe("0.000001716");
    expect(formatTinyDecimal(0.0000123456)).toBe("0.00001235");
    expect(formatTinyDecimal(0.0000120001)).toBe("0.000012");
  });

  // MUTATION: Remove the Math.min(100, ...) cap
  // BREAKS: toFixed throws RangeError for more than 100 digits
  test("caps precision at toFixed's 100 digit limit", () => {
    expect(formatTinyDecimal(2.5e-21)).toBe("0.0000000000000000000025");
    expect(formatTinyDecimal(1e-120)).toBe("0");
  });

  // MUTATION: Remove the non-positive guard
  // BREAKS: 0 hits log10(0) and toFixed(Infinity) throws
  test("returns 0 for zero, negative or NaN input", () => {
    expect(formatTinyDecimal(0)).toBe("0");
    expect(formatTinyDecimal(-0.00001)).toBe("0");
    expect(formatTinyDecimal(NaN)).toBe("0");
  });
});

// ============================================================================
// setNumberText
// ============================================================================

describe("setNumberText", () => {
  // MUTATION: Put the zeros in data-n only and drop them from the DOM
  // BREAKS: textContent reads "0.01716" instead of the real value
  test("collapses 4+ zeros after 0. but keeps the real value in textContent", () => {
    const el = document.createElement("span");
    setNumberText(el, "$0.000001716 / WETH");
    const run = el.querySelector(".zero-run");
    expect(run.dataset.n).toBe("5");
    expect(run.querySelector(".zero-run-digits").textContent).toBe("0000");
    expect(el.firstChild.textContent).toBe("$0.0");
    expect(el.textContent).toBe("$0.000001716 / WETH");
  });

  // MUTATION: Use 0{3,} in ZERO_RUN_RE
  // BREAKS: 0.0001 gets collapsed to 0.0₃1
  test("leaves short zero runs and non-decimal zeros as plain text", () => {
    const el = document.createElement("span");
    for (const text of ["0.0001", "$0.00123", "10.000005", "$ --", "0.00000"]) {
      setNumberText(el, text);
      expect(el.querySelector(".zero-run")).toBeNull();
      expect(el.textContent).toBe(text);
    }
  });

  // MUTATION: Stop after the first match
  // BREAKS: second value in the string stays uncollapsed
  test("collapses every run in the string and replaces old content", () => {
    const el = document.createElement("span");
    el.textContent = "stale";
    setNumberText(el, "(~0.00000123 ETH / $0.0000045)");
    const runs = el.querySelectorAll(".zero-run");
    expect([...runs].map((r) => r.dataset.n)).toEqual(["5", "5"]);
    expect(el.textContent).toBe("(~0.00000123 ETH / $0.0000045)");
  });
});

// ============================================================================
// parseAmount
// ============================================================================

describe("parseAmount", () => {
  // MUTATION: Multiply by 10^6 instead of 10^decimals
  // BREAKS: parseAmount("1", 18) returns 1000000n instead of 1e18
  test("multiplies by 10^decimals for whole numbers", () => {
    expect(parseAmount("1", 18)).toBe(BigInt("1000000000000000000"));
    expect(parseAmount("1", 6)).toBe(BigInt("1000000"));
    expect(parseAmount("100", 18)).toBe(BigInt("100000000000000000000"));
  });

  // MUTATION: Ignore the fractional part
  // BREAKS: "1.5" parses as 1e18 instead of 1.5e18
  test("handles decimal input correctly", () => {
    expect(parseAmount("1.5", 18)).toBe(BigInt("1500000000000000000"));
    expect(parseAmount("0.5", 6)).toBe(BigInt("500000"));
  });

  // MUTATION: Don't strip commas before validating
  // BREAKS: A pasted "1,000" is rejected as malformed
  test("strips commas from input", () => {
    expect(parseAmount("1,000", 6)).toBe(BigInt("1000000000"));
    expect(parseAmount("1,000,000", 18)).toBe(BigInt("1000000000000000000000000"));
  });

  // MUTATION: Remove .trim()
  // BREAKS: A value pasted with surrounding space is rejected
  test("trims whitespace from input", () => {
    expect(parseAmount(" 1.5 ", 6)).toBe(BigInt("1500000"));
    expect(parseAmount("  100  ", 18)).toBe(BigInt("100000000000000000000"));
  });

  // MUTATION: Don't pad short fractions
  // BREAKS: "1.5" at 6 decimals gives 15n instead of 1500000n
  test("pads short decimal input", () => {
    expect(parseAmount("1.5", 6)).toBe(BigInt("1500000"));
    expect(parseAmount("1.1", 18)).toBe(BigInt("1100000000000000000"));
  });

  // MUTATION: Change fracPart.length > decimals to >= decimals
  // BREAKS: A fraction at exactly the token's precision loses its last digit
  test("boundary: a fraction at exactly token precision is not truncated", () => {
    expect(parseAmount("1.123456", 6)).toBe(BigInt("1123456"));
    expect(parseAmount("1.123456789012345678", 18)).toBe(BigInt("1123456789012345678"));
  });

  // MUTATION: Throw whenever decimals are truncated, not only when the result is zero
  // BREAKS: A legitimate 1.0000001 WETH order is refused as "too many decimals"
  test("truncates excess decimals silently when a non-zero amount survives", () => {
    expect(parseAmount("1.1234567", 6)).toBe(BigInt("1123456"));
    expect(parseAmount("1.0000001", 6)).toBe(BigInt("1000000"));
    // Dust below the precision still counts when other digits survive it
    expect(parseAmount("0.0000015", 6)).toBe(BigInt("1"));
  });

  // MUTATION: Drop the intPart === "0" check, or the /^0*$/ test
  // BREAKS: Dust silently becomes a zero-amount order the contract then reverts
  test("throws when truncation would take the whole amount to zero", () => {
    expect(() => parseAmount("0.0000001", 6)).toThrow(
      "Too many decimals. This token only supports 6 decimal places."
    );
    expect(() => parseAmount("0.0000000000000000001", 18)).toThrow(/only supports 18 decimal/);
  });

  // MUTATION: Return 0n / null instead of throwing
  // BREAKS: Malformed input silently becomes a zero-amount transaction
  test("throws on malformed input", () => {
    expect(() => parseAmount("abc", 18)).toThrow("Invalid amount format. Use numbers only.");
    expect(() => parseAmount("1.2.3", 18)).toThrow("Invalid amount format. Use numbers only.");
    expect(() => parseAmount("-1", 18)).toThrow("Invalid amount format. Use numbers only.");
    expect(() => parseAmount("1e18", 18)).toThrow("Invalid amount format. Use numbers only.");
  });

  // MUTATION: Relax the regex to /^\d*\.?\d*$/
  // BREAKS: Half-typed values like "." parse instead of rejecting
  test("requires digits on both sides of the decimal point", () => {
    expect(() => parseAmount(".5", 18)).toThrow("Invalid amount format. Use numbers only.");
    expect(() => parseAmount("5.", 18)).toThrow("Invalid amount format. Use numbers only.");
    expect(() => parseAmount(".", 18)).toThrow("Invalid amount format. Use numbers only.");
  });

  // MUTATION: Remove the typeof guard ahead of .trim()
  // BREAKS: A non-string escapes as "str.trim is not a function", which the
  //         form then shows the user verbatim
  test("rejects non-strings with the same message as other bad input", () => {
    expect(() => parseAmount(null, 18)).toThrow("Invalid amount format. Use numbers only.");
    expect(() => parseAmount(undefined, 18)).toThrow("Invalid amount format. Use numbers only.");
    expect(() => parseAmount(123, 18)).toThrow("Invalid amount format. Use numbers only.");
    expect(() => parseAmount({}, 18)).toThrow("Invalid amount format. Use numbers only.");
  });

  // MUTATION: Throw on an empty string instead of returning 0n
  // BREAKS: An untouched amount field errors on every keystroke elsewhere
  test("an empty or blank string is zero, not a rejection", () => {
    expect(parseAmount("", 18)).toBe(BigInt(0));
    expect(parseAmount("   ", 18)).toBe(BigInt(0));
  });

  // MUTATION: Assume decimals is always > 0
  // BREAKS: A 0-decimal token drags its fraction into the integer part
  test("handles a zero-decimal token", () => {
    expect(parseAmount("5", 0)).toBe(BigInt(5));
    expect(parseAmount("5.9", 0)).toBe(BigInt(5));
  });
});

// ============================================================================
// getCachedPrice
// ============================================================================

describe("getCachedPrice", () => {
  // MUTATION: Return undefined instead of null
  // BREAKS: Returns undefined instead of null
  test("returns null for cache miss", () => {
    const cache = new Map();
    expect(getCachedPrice("weth", cache, 60000)).toBe(null);
  });

  // MUTATION: Always return null (ignore cache)
  // BREAKS: Returns null even when valid entry exists
  test("returns cached entry when within TTL", () => {
    const cache = new Map();
    const entry = { usd: 3500, fetchedAt: Date.now() - 30000 }; // 30s ago
    cache.set("weth", entry);
    expect(getCachedPrice("weth", cache, 60000)).toBe(entry);
  });

  // MUTATION: Don't check TTL (always return if exists)
  // BREAKS: Returns stale entry
  test("returns null when entry exceeds TTL", () => {
    const cache = new Map();
    const staleEntry = { usd: 3500, fetchedAt: Date.now() - 120000 }; // 2 min ago
    cache.set("weth", staleEntry);
    expect(getCachedPrice("weth", cache, 60000)).toBe(null); // 1 min TTL
  });

  // MUTATION: Use <= instead of > for TTL check
  // BREAKS: Entry at exactly TTL boundary behaves wrong
  test("TTL boundary: expired at exactly TTL+1ms", () => {
    jest.useFakeTimers();
    jest.setSystemTime(1_000_000);
    const cache = new Map();
    const exactlyExpired = { usd: 3500, fetchedAt: 1_000_000 - 60001 };
    cache.set("weth", exactlyExpired);
    expect(getCachedPrice("weth", cache, 60000)).toBe(null);
    jest.useRealTimers();
  });

  // MUTATION: Change > to >= in TTL check
  // BREAKS: Entry at exactly TTL is incorrectly expired
  test("TTL boundary: valid at exactly TTL (> not >=)", () => {
    jest.useFakeTimers();
    jest.setSystemTime(1_000_000);
    const cache = new Map();
    const exactlyAtTTL = { usd: 3500, fetchedAt: 1_000_000 - 60000 };
    cache.set("weth", exactlyAtTTL);
    expect(getCachedPrice("weth", cache, 60000)).toBe(exactlyAtTTL);
    jest.useRealTimers();
  });
});

// ============================================================================
// getTokenPrice
// ============================================================================

describe("getTokenPrice", () => {
  // MUTATION: Use wrong key in COINGECKO_ID_MAP lookup
  // BREAKS: Returns null for known token
  test("returns price for token in COINGECKO_ID_MAP", () => {
    const cache = new Map();
    cache.set("weth", { usd: 3500, fetchedAt: Date.now() });
    // WETH address -> "weth" ID
    const price = getTokenPrice("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2", cache, 60000);
    expect(price).toBe(3500);
  });

  // MUTATION: Return 0 for unknown token
  // BREAKS: Returns 0 instead of null
  test("returns null for token not in mapping", () => {
    const cache = new Map();
    const price = getTokenPrice("0x0000000000000000000000000000000000000001", cache, 60000);
    expect(price).toBe(null);
  });

  // MUTATION: Don't lowercase address before lookup
  // BREAKS: Returns null for checksummed address
  test("address lookup is case-insensitive", () => {
    const cache = new Map();
    cache.set("weth", { usd: 3500, fetchedAt: Date.now() });
    expect(getTokenPrice("0xC02AAA39B223FE8D0A0E5C4F27EAD9083C756CC2", cache, 60000)).toBe(3500);
  });

  // MUTATION: Change if (!id) to if (false)
  // BREAKS: Would try to look up undefined in cache, returning wrong value or error
  test("returns null immediately when token not in mapping (!id check)", () => {
    const cache = new Map();
    // Put something in cache that could be accidentally matched
    cache.set(undefined, { usd: 9999, fetchedAt: Date.now() });
    cache.set("undefined", { usd: 8888, fetchedAt: Date.now() });
    // Unknown token should still return null, not some cached value
    const price = getTokenPrice("0x0000000000000000000000000000000000000001", cache, 60000);
    expect(price).toBe(null);
  });
});

// ============================================================================
// fetchPrices
// ============================================================================

describe("fetchPrices", () => {
  const ok = (body) => ({ ok: true, status: 200, json: async () => body });
  let warn;

  beforeEach(() => {
    warn = jest.spyOn(console, "warn").mockImplementation(() => {});
  });
  afterEach(() => {
    warn.mockRestore();
    jest.useRealTimers();
  });

  // MUTATION: Write the raw response instead of {usd, fetchedAt}
  // BREAKS: getCachedPrice cannot read a TTL off the entry and every price expires
  test("populates the cache with a usd price and a fetch time", async () => {
    global.fetch.mockImplementation(async () => ok({ weth: { usd: 3500 } }));
    const cache = new Map();

    await fetchPrices(["weth"], cache);

    expect(cache.get("weth").usd).toBe(3500);
    expect(typeof cache.get("weth").fetchedAt).toBe("number");
    expect(getTokenPrice("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2", cache, 60000)).toBe(3500);
  });

  // MUTATION: Request every id rather than only the uncached ones
  // BREAKS: Every render re-requests prices already held, and CoinGecko rate limits
  test("requests only the ids that are not already cached", async () => {
    global.fetch.mockImplementation(async () => ok({ dai: { usd: 1 } }));
    const cache = new Map([["weth", { usd: 3500, fetchedAt: Date.now() }]]);

    await fetchPrices(["weth", "dai"], cache);

    expect(global.fetch).toHaveBeenCalledTimes(1);
    expect(global.fetch.mock.calls[0][0]).toContain("ids=dai");
    expect(global.fetch.mock.calls[0][0]).not.toContain("weth");
  });

  // MUTATION: Drop the early return when nothing needs fetching
  // BREAKS: A no-op call still hits the network
  test("makes no request when every id is cached", async () => {
    const cache = new Map([["weth", { usd: 3500, fetchedAt: Date.now() }]]);

    await fetchPrices(["weth"], cache);

    expect(global.fetch).not.toHaveBeenCalled();
  });

  // MUTATION: Ignore res.ok
  // BREAKS: An error body is parsed as prices and poisons the cache
  test("a failed response leaves the cache untouched", async () => {
    global.fetch.mockImplementation(async () => ({
      ok: false,
      status: 429,
      json: async () => ({}),
    }));
    const cache = new Map();

    await fetchPrices(["weth"], cache);

    expect(cache.size).toBe(0);
    expect(warn).toHaveBeenCalledWith("[Price] Rate limited by CoinGecko");
  });

  // MUTATION: Let the fetch rejection escape
  // BREAKS: A network blip rejects into a render path and blanks the table
  test("a network failure is swallowed, not thrown", async () => {
    global.fetch.mockImplementation(async () => {
      throw new Error("network down");
    });
    const cache = new Map();

    await expect(fetchPrices(["weth"], cache)).resolves.toBeUndefined();
    expect(cache.size).toBe(0);
    expect(warn).toHaveBeenCalledWith("[Price] Fetch failed:", "network down");
  });

  // MUTATION: Report an abort as a generic failure
  // BREAKS: A timeout is indistinguishable from a real error in the console
  test("an aborted request is reported as a timeout", async () => {
    global.fetch.mockImplementation(async () => {
      const e = new Error("aborted");
      e.name = "AbortError";
      throw e;
    });

    await fetchPrices(["weth"], new Map());

    expect(warn).toHaveBeenCalledWith("[Price] Request timed out");
  });

  // MUTATION: Skip the typeof check on the usd field
  // BREAKS: A null or string price is cached and renders as NaN
  test("ignores entries whose price is not a number", async () => {
    global.fetch.mockImplementation(async () =>
      ok({ weth: { usd: null }, dai: { usd: "1" }, tether: { usd: 1 } })
    );
    const cache = new Map();

    await fetchPrices(["weth", "dai", "tether"], cache);

    expect(cache.has("weth")).toBe(false);
    expect(cache.has("dai")).toBe(false);
    expect(cache.get("tether").usd).toBe(1);
  });

  // MUTATION: Never arm the abort timer
  // BREAKS: A hung CoinGecko request pins priceFetchInProgress and no price ever
  //         refreshes again for the life of the page
  test("aborts a request that outruns the timeout", async () => {
    jest.useFakeTimers();
    global.fetch.mockImplementation(
      (url, { signal }) =>
        new Promise((_resolve, reject) =>
          signal.addEventListener("abort", () => {
            const e = new Error("aborted");
            e.name = "AbortError";
            reject(e);
          })
        )
    );

    const pending = fetchPrices(["weth"], new Map());
    await Promise.resolve();
    jest.advanceTimersByTime(10000);
    await pending;

    expect(warn).toHaveBeenCalledWith("[Price] Request timed out");
  });

  // MUTATION: Drop the in-flight guard
  // BREAKS: Every concurrent caller fires its own request
  test("concurrent calls coalesce onto one request", async () => {
    let resolveFetch;
    global.fetch.mockImplementation(
      () => new Promise((r) => (resolveFetch = () => r(ok({ weth: { usd: 3500 } }))))
    );
    const cache = new Map();

    const both = Promise.all([fetchPrices(["weth"], cache), fetchPrices(["weth"], cache)]);
    await Promise.resolve();
    resolveFetch();
    await both;

    expect(global.fetch).toHaveBeenCalledTimes(1);
  });
});

// ============================================================================
// calculateMarketDeviation
// ============================================================================

describe("calculateMarketDeviation", () => {
  const mockGetPrice = (addr) => {
    const prices = {
      "0xtoken_a": 100,
      "0xtoken_b": 50,
      "0xtoken_zero": 0,
    };
    return prices[addr.toLowerCase()] || null;
  };

  // MUTATION: Swap orderRate and marketRate in deviation formula
  // BREAKS: Positive deviation becomes negative
  test("calculates positive deviation when asking more than market", () => {
    // Market: 1 tokenA ($100) = 2 tokenB ($50 each)
    // Order: 1 tokenA for 2.5 tokenB = +25% premium
    const order = {
      tokenA: { address: "0xtoken_a", decimals: 18 },
      tokenB: { address: "0xtoken_b", decimals: 18 },
      availableA: "1000000000000000000", // 1 token
      availableB: "2500000000000000000", // 2.5 tokens
    };
    const result = calculateMarketDeviation(order, mockGetPrice);
    expect(result.deviation).toBeCloseTo(25, 0);
    expect(result.label).toBe("+25.0%");
  });

  // MUTATION: Use absolute value, hiding discount
  // BREAKS: Negative deviation shows as positive
  test("calculates negative deviation for discount", () => {
    // Order: 1 tokenA for 1.5 tokenB = -25% discount
    const order = {
      tokenA: { address: "0xtoken_a", decimals: 18 },
      tokenB: { address: "0xtoken_b", decimals: 18 },
      availableA: "1000000000000000000",
      availableB: "1500000000000000000",
    };
    const result = calculateMarketDeviation(order, mockGetPrice);
    expect(result.deviation).toBeCloseTo(-25, 0);
    expect(result.label).toBe("-25.0%");
  });

  // MUTATION: Change threshold from 0.5 to 5
  // BREAKS: 1% deviation shows as "~market"
  test("shows ~market for deviation under 0.5%", () => {
    const order = {
      tokenA: { address: "0xtoken_a", decimals: 18 },
      tokenB: { address: "0xtoken_b", decimals: 18 },
      availableA: "1000000000000000000",
      availableB: "2000000000000000000", // Exact market rate
    };
    const result = calculateMarketDeviation(order, mockGetPrice);
    expect(result.label).toBe("~market");
  });

  // MUTATION: Don't check for null price
  // BREAKS: Throws on null / NaN calculation
  test("returns null when price unavailable", () => {
    const order = {
      tokenA: { address: "0xunknown", decimals: 18 },
      tokenB: { address: "0xtoken_b", decimals: 18 },
      availableA: "1000000000000000000",
      availableB: "2000000000000000000",
    };
    expect(calculateMarketDeviation(order, mockGetPrice)).toBe(null);
  });

  // MUTATION: Don't check for zero price
  // BREAKS: Division by zero gives Infinity
  test("returns null when price is zero", () => {
    const order = {
      tokenA: { address: "0xtoken_a", decimals: 18 },
      tokenB: { address: "0xtoken_zero", decimals: 18 },
      availableA: "1000000000000000000",
      availableB: "2000000000000000000",
    };
    expect(calculateMarketDeviation(order, mockGetPrice)).toBe(null);
  });

  // MUTATION: Don't check for zero amount
  // BREAKS: Division by zero
  test("returns null when amount is zero", () => {
    const order = {
      tokenA: { address: "0xtoken_a", decimals: 18 },
      tokenB: { address: "0xtoken_b", decimals: 18 },
      availableA: "0",
      availableB: "2000000000000000000",
    };
    expect(calculateMarketDeviation(order, mockGetPrice)).toBe(null);
  });

  // MUTATION: Don't check for amountB === 0n
  // BREAKS: Division by zero or wrong calculation
  test("returns null when amountB is zero", () => {
    const order = {
      tokenA: { address: "0xtoken_a", decimals: 18 },
      tokenB: { address: "0xtoken_b", decimals: 18 },
      availableA: "1000000000000000000",
      availableB: "0",
    };
    expect(calculateMarketDeviation(order, mockGetPrice)).toBe(null);
  });

  // MUTATION: Don't check for priceA === 0
  // BREAKS: Division by zero in marketRate calculation
  test("returns null when priceA is zero", () => {
    const mockGetPriceWithZeroA = (addr) => {
      if (addr.toLowerCase() === "0xtoken_a") return 0;
      if (addr.toLowerCase() === "0xtoken_b") return 50;
      return null;
    };
    const order = {
      tokenA: { address: "0xtoken_a", decimals: 18 },
      tokenB: { address: "0xtoken_b", decimals: 18 },
      availableA: "1000000000000000000",
      availableB: "2000000000000000000",
    };
    expect(calculateMarketDeviation(order, mockGetPriceWithZeroA)).toBe(null);
  });

  // MUTATION: Change < 0.5 to <= 0.5
  // BREAKS: 0.6% deviation shows ~market instead of +0.6%
  test("boundary: 0.6% deviation shows +0.6% (< not <=)", () => {
    // Market rate: priceA/priceB = 100/50 = 2
    // We want deviation > 0.5%, so use 0.6%
    // orderRate = marketRate * 1.006 = 2.012
    const order = {
      tokenA: { address: "0xtoken_a", decimals: 18 },
      tokenB: { address: "0xtoken_b", decimals: 18 },
      availableA: "1000000000000000000", // 1 token
      availableB: "2012000000000000000", // 2.012 tokens = 0.6% above market
    };
    const result = calculateMarketDeviation(order, mockGetPrice);
    expect(result.deviation).toBeCloseTo(0.6, 1);
    expect(result.label).toBe("+0.6%");
  });

  // MUTATION: Change < 0.5 to <= 0.5 (boundary test)
  // BREAKS: 0.4% deviation shows positive label instead of ~market
  test("boundary: 0.4% deviation shows ~market (< 0.5)", () => {
    // Market rate = 2, deviation = 0.4%
    // orderRate = 2 * 1.004 = 2.008
    const order = {
      tokenA: { address: "0xtoken_a", decimals: 18 },
      tokenB: { address: "0xtoken_b", decimals: 18 },
      availableA: "1000000000000000000",
      availableB: "2008000000000000000", // 2.008 tokens = 0.4% above market
    };
    const result = calculateMarketDeviation(order, mockGetPrice);
    expect(Math.abs(result.deviation)).toBeLessThan(0.5);
    expect(result.label).toBe("~market");
  });

  // MUTATION: Change > 0 to >= 0
  // BREAKS: Exactly 0 deviation (after rounding) would show +0.0% instead of ~market
  test("boundary: deviation of exactly 0 shows ~market", () => {
    const order = {
      tokenA: { address: "0xtoken_a", decimals: 18 },
      tokenB: { address: "0xtoken_b", decimals: 18 },
      availableA: "1000000000000000000",
      availableB: "2000000000000000000", // Exact market rate
    };
    const result = calculateMarketDeviation(order, mockGetPrice);
    expect(result.deviation).toBeCloseTo(0, 1);
    expect(result.label).toBe("~market");
  });

  // MUTATION: Change humanAmountB / humanAmountA to * humanAmountA
  // BREAKS: Order rate calculation would be wrong (multiplication instead of division)
  test("calculates order rate as availableB / availableA (division not multiplication)", () => {
    // Market rate = 100/50 = 2
    // With division: orderRate = 4/2 = 2 (matches market, ~market)
    // With multiplication: orderRate = 4*2 = 8 (huge deviation)
    const order = {
      tokenA: { address: "0xtoken_a", decimals: 18 },
      tokenB: { address: "0xtoken_b", decimals: 18 },
      availableA: "2000000000000000000", // 2 tokens
      availableB: "4000000000000000000", // 4 tokens (rate = 2)
    };
    const result = calculateMarketDeviation(order, mockGetPrice);
    // With correct division: deviation should be ~0 (market rate is 2)
    expect(Math.abs(result.deviation)).toBeLessThan(1);
    expect(result.label).toBe("~market");
  });
});

// ============================================================================
// searchTokens
// ============================================================================

describe("searchTokens", () => {
  const tokenList = [
    { symbol: "WETH", name: "Wrapped Ether" },
    { symbol: "USDC", name: "USD Coin" },
    { symbol: "USDT", name: "Tether USD" },
    { symbol: "WETHABC", name: "Fake WETH" },
    { symbol: "LINK", name: "Chainlink" },
  ];

  // MUTATION: Return all tokens for empty query
  // BREAKS: Returns 5 tokens instead of []
  test("returns empty array for empty query", () => {
    expect(searchTokens("", tokenList)).toEqual([]);
    expect(searchTokens(null, tokenList)).toEqual([]);
  });

  // MUTATION: Don't prioritize exact matches
  // BREAKS: WETHABC comes before WETH
  test("exact symbol match appears first", () => {
    const results = searchTokens("WETH", tokenList);
    expect(results[0].symbol).toBe("WETH");
  });

  // MUTATION: Use case-sensitive comparison
  // BREAKS: "weth" returns []
  test("search is case-insensitive", () => {
    expect(searchTokens("weth", tokenList)[0].symbol).toBe("WETH");
    expect(searchTokens("WETH", tokenList)[0].symbol).toBe("WETH");
  });

  // MUTATION: Ignore limit parameter
  // BREAKS: Returns all 3 matches instead of 2
  test("respects limit parameter", () => {
    const results = searchTokens("W", tokenList, 2);
    expect(results.length).toBe(2);
  });

  // MUTATION: Only search symbol, not name
  // BREAKS: "chain" returns [] instead of [LINK]
  test("searches by name as well as symbol", () => {
    const results = searchTokens("chain", tokenList);
    expect(results[0].symbol).toBe("LINK");
  });

  // MUTATION: Don't deduplicate results
  // BREAKS: Same token appears twice
  test("returns unique results (no duplicates)", () => {
    const results = searchTokens("WETH", tokenList);
    const symbols = results.map((t) => t.symbol);
    expect(new Set(symbols).size).toBe(symbols.length);
  });

  // MUTATION: Change >= limit to > limit in first loop
  // BREAKS: Returns limit+1 results when limit exact matches found
  test("boundary: returns exactly limit results (>= not >)", () => {
    const manyTokens = [
      { symbol: "AAA", name: "Token A" },
      { symbol: "AAB", name: "Token B" },
      { symbol: "AAC", name: "Token C" },
      { symbol: "AAD", name: "Token D" },
    ];
    const results = searchTokens("AA", manyTokens, 3);
    expect(results.length).toBe(3);
  });

  // MUTATION: Remove exact match loop (first for loop)
  // BREAKS: Exact matches not prioritized when startsWith also matches
  test("exact match prioritized over startsWith match", () => {
    const tokens = [
      { symbol: "WETHX", name: "Extended" },
      { symbol: "WETH", name: "Wrapped Ether" },
    ];
    const results = searchTokens("WETH", tokens, 10);
    expect(results[0].symbol).toBe("WETH"); // Exact first, not WETHX
  });

  // MUTATION: Remove startsWith loop (second for loop)
  // BREAKS: Prefix matches not found
  test("finds tokens by symbol prefix (startsWith)", () => {
    const tokens = [
      { symbol: "BITCOIN", name: "Bitcoin" },
      { symbol: "BIT", name: "Bit Token" },
    ];
    // "BI" doesn't exact-match anything, so falls to startsWith
    const results = searchTokens("BI", tokens, 10);
    expect(results.length).toBe(2);
    expect(results.some((t) => t.symbol === "BIT")).toBe(true);
  });

  // MUTATION: Change startsWith to endsWith
  // BREAKS: "WE" wouldn't match "WETH"
  test("startsWith matches prefix not suffix", () => {
    const results = searchTokens("WE", tokenList, 10);
    expect(results.some((t) => t.symbol === "WETH")).toBe(true);
    expect(results.some((t) => t.symbol === "WETHABC")).toBe(true);
  });

  // MUTATION: Use toUpperCase instead of toLowerCase in any loop
  // BREAKS: Lowercase query wouldn't match uppercase symbol
  test("all loops use lowercase comparison", () => {
    // Test all three loops with lowercase query
    expect(searchTokens("weth", tokenList, 10)[0].symbol).toBe("WETH"); // exact
    expect(searchTokens("wet", tokenList, 10).some((t) => t.symbol === "WETH")).toBe(true); // startsWith
    expect(searchTokens("eth", tokenList, 10).some((t) => t.symbol === "WETH")).toBe(true); // includes
  });

  // MUTATION: Change query.length < 1 to false
  // BREAKS: Single character query would be rejected
  test("accepts single character query (length >= 1)", () => {
    const results = searchTokens("W", tokenList, 10);
    expect(results.length).toBeGreaterThan(0);
    expect(results.some((t) => t.symbol.startsWith("W"))).toBe(true);
  });

  // MUTATION: Remove startsWith loop (for loop at line 328)
  // BREAKS: Prefix-only matches not found when no exact match exists
  test("startsWith loop finds prefix matches that are not exact", () => {
    const tokens = [
      { symbol: "ABCDEF", name: "Token ABC" },
      { symbol: "XYZABC", name: "Token XYZ" },
    ];
    // "ABC" has no exact match but ABCDEF starts with ABC
    const results = searchTokens("ABC", tokens, 10);
    expect(results[0].symbol).toBe("ABCDEF"); // Found via startsWith, not includes
  });

  // MUTATION: Change startsWith to endsWith in second loop
  // BREAKS: Prefix search wouldn't work
  test("second loop uses startsWith not endsWith", () => {
    const tokens = [
      { symbol: "ENDING", name: "Token" }, // ends with ING
      { symbol: "INGEST", name: "Token" }, // starts with ING
    ];
    // "ING" with startsWith finds INGEST first
    const results = searchTokens("ING", tokens, 10);
    expect(results[0].symbol).toBe("INGEST");
  });

  // MUTATION: Block statement removal in startsWith loop
  // BREAKS: Matches found but not added to results
  test("startsWith loop adds matches to results", () => {
    const tokens = [
      { symbol: "PREFIX1", name: "Token 1" },
      { symbol: "PREFIX2", name: "Token 2" },
      { symbol: "OTHER", name: "Token 3" },
    ];
    const results = searchTokens("PRE", tokens, 10);
    expect(results.length).toBe(2);
    expect(results.every((t) => t.symbol.startsWith("PRE"))).toBe(true);
  });

  // MUTATION: Change >= limit to > limit in includes loop (line 339)
  // BREAKS: Returns limit+1 results when hitting limit in includes loop
  test("includes loop respects limit boundary (>= not >)", () => {
    // Create tokens that will only match via includes (not exact or startsWith)
    const tokens = [
      { symbol: "XYZABC", name: "Contains ABC 1" },
      { symbol: "DEFABC", name: "Contains ABC 2" },
      { symbol: "GHIABC", name: "Contains ABC 3" },
    ];
    // Query "ABC" will find these via includes (symbol contains ABC)
    // With limit 2, should return exactly 2
    const results = searchTokens("ABC", tokens, 2);
    expect(results.length).toBe(2);
  });

  // MUTATION: Remove includes loop return statement
  // BREAKS: Would continue searching past limit
  test("includes loop returns early when limit reached", () => {
    const tokens = [];
    for (let i = 0; i < 20; i++) {
      tokens.push({ symbol: `TOKEN${i}`, name: `Contains XYZ ${i}` });
    }
    // "XYZ" matches via name.includes, limit 5 should stop early
    const results = searchTokens("XYZ", tokens, 5);
    expect(results.length).toBe(5);
  });

  // MUTATION: Change toLowerCase to toUpperCase in includes loop
  // BREAKS: Lowercase query wouldn't match uppercase symbol/name
  test("includes loop is case-insensitive", () => {
    const tokens = [
      // Symbol that WON'T match "xyz" via exact or startsWith, only via includes
      { symbol: "ABCXYZ", name: "Token with XYZ in symbol" },
    ];
    // "xyz" matches via includes in symbol (not exact, not startsWith)
    const results = searchTokens("xyz", tokens, 10);
    expect(results.length).toBe(1);
    expect(results[0].symbol).toBe("ABCXYZ");
  });

  // MUTATION: Change toLowerCase to toUpperCase in name.includes check
  // BREAKS: Lowercase query wouldn't match name
  test("includes loop matches name case-insensitively", () => {
    const tokens = [{ symbol: "NOTSEARCH", name: "Contains FINDME Here" }];
    // "findme" (lowercase) should match "FINDME" in name via includes
    const results = searchTokens("findme", tokens, 10);
    expect(results.length).toBe(1);
    expect(results[0].name).toContain("FINDME");
  });
});

// ============================================================================
// localStorage: Recent Tokens
// ============================================================================

describe("searchTokens prepend", () => {
  const LIST = [
    { symbol: "WETH", name: "Wrapped Ether" },
    { symbol: "ETHFI", name: "ether.fi" },
    { symbol: "USDC", name: "USD Coin" },
  ];
  const ETH = { symbol: "ETH", name: "Ether" };

  // MUTATION: Append the seed instead of prepending it
  // BREAKS: Native ETH sorts below WETH in the token dropdown
  test("seeded entries come first", () => {
    const results = searchTokens("eth", LIST, 10, [ETH]);
    expect(results[0]).toBe(ETH);
  });

  // MUTATION: Exclude the seed from the limit count
  // BREAKS: The dropdown renders one row more than it was asked for
  test("seeded entries count toward the limit", () => {
    expect(searchTokens("eth", LIST, 2, [ETH])).toHaveLength(2);
  });

  // MUTATION: Default prepend to something other than []
  // BREAKS: Every existing three-argument caller changes behavior
  test("omitting prepend leaves behavior unchanged", () => {
    expect(searchTokens("eth", LIST, 10)).toEqual(searchTokens("eth", LIST, 10, []));
  });

  // MUTATION: Seed before the empty-query guard
  // BREAKS: An empty search box shows a lone ETH row
  test("an empty query returns nothing, seed included", () => {
    expect(searchTokens("", LIST, 10, [ETH])).toEqual([]);
  });
});

// ============================================================================
// coinGeckoUrl
// ============================================================================

describe("coinGeckoUrl", () => {
  // MUTATION: Drop the toLowerCase() before the lookup
  // BREAKS: Checksummed addresses miss the all-lowercase registry keys
  test("resolves a listed token regardless of address casing", () => {
    expect(coinGeckoUrl("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2")).toBe(
      "https://www.coingecko.com/en/coins/weth"
    );
    expect(coinGeckoUrl("0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48")).toBe(
      "https://www.coingecko.com/en/coins/usd-coin"
    );
  });

  // MUTATION: Return the bare URL prefix instead of null for unknown tokens
  // BREAKS: Unlisted tokens link to a CoinGecko 404
  test("returns null for a token with no CoinGecko id", () => {
    expect(coinGeckoUrl("0x1111111111111111111111111111111111111111")).toBeNull();
  });

  // MUTATION: Skip the typeof guard
  // BREAKS: Throws on a token whose address never loaded
  test("returns null rather than throwing on bad input", () => {
    expect(coinGeckoUrl(null)).toBeNull();
    expect(coinGeckoUrl(undefined)).toBeNull();
    expect(coinGeckoUrl(42)).toBeNull();
  });
});

// ============================================================================
// Permit registry
// ============================================================================

describe("permitKindFor", () => {
  const MAINNET = 1;
  const SEPOLIA = 11155111;

  // MUTATION: Drop the toLowerCase() before the lookup
  // BREAKS: Checksummed addresses miss the all-lowercase registry keys and
  //         every token falls back to approve()
  test("resolves each permit flavour regardless of address casing", () => {
    expect(permitKindFor("0xA0b86991c6218b36c1D19D4a2e9Eb0cE3606eB48", MAINNET)).toBe("eip2612");
    expect(permitKindFor("0x6b175474e89094c44da98b954eedeac495271d0f", MAINNET)).toBe("dai");
    expect(permitKindFor("0xa882606494d86804b5514e07e6bd2d6a6ee6d68a", MAINNET)).toBe("both");
    expect(permitKindFor("0xa258c4606ca8206d8aa700ce2143d7db854d168c", MAINNET)).toBe(
      "nonstandard"
    );
    expect(permitKindFor("0x48ab4e39ac59f4e88974804b04a991b3a402717f", MAINNET)).toBe("unverified");
    expect(permitKindFor("0xdac17f958d2ee523a2206206994597c13d831ec7", MAINNET)).toBe("none");
  });

  // MUTATION: Look the address up across every chain section instead of the
  //           caller's, or drop the chainId argument entirely
  // BREAKS: A Sepolia build reports mainnet verdicts for addresses that are
  //         unrelated contracts on Sepolia, and signs permits that revert
  test("keeps each chain's verdicts to that chain", () => {
    const mainnetUsdc = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48";
    const sepoliaUsdc = "0x1c7d4b196cb0c7b01d743fbc6116a902379c7238";

    expect(permitKindFor(mainnetUsdc, MAINNET)).toBe("eip2612");
    expect(permitKindFor(mainnetUsdc, SEPOLIA)).toBe("unknown");

    expect(permitKindFor(sepoliaUsdc, SEPOLIA)).toBe("eip2612");
    expect(permitKindFor(sepoliaUsdc, MAINNET)).toBe("unknown");
  });

  // MUTATION: Treat a missing chain section as an empty lookup that still
  //           consults some default
  // BREAKS: An unsupported chain inherits another chain's answers
  test("answers 'unknown' for a chain the registry has no section for", () => {
    expect(permitKindFor("0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", 8453)).toBe("unknown");
  });

  // MUTATION: Return the raw undefined lookup instead of "unknown"
  // BREAKS: Callers comparing against a string get undefined for unlisted tokens
  test("returns 'unknown' for a token outside the registry", () => {
    expect(permitKindFor("0x1111111111111111111111111111111111111111", MAINNET)).toBe("unknown");
  });

  // MUTATION: Skip the typeof guard
  // BREAKS: Throws on a token whose address never loaded
  test("returns 'unknown' rather than throwing on bad input", () => {
    expect(permitKindFor(null, MAINNET)).toBe("unknown");
    expect(permitKindFor(undefined, MAINNET)).toBe("unknown");
    expect(permitKindFor(42, MAINNET)).toBe("unknown");
  });
});

describe("supportsPermit", () => {
  const MAINNET = 1;
  const SEPOLIA = 11155111;

  // MUTATION: Drop "both" from the accepted set
  // BREAKS: Tokens that can be approved by signature get a needless approve() send
  test("accepts the flavours a signature flow can drive", () => {
    expect(supportsPermit("0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", MAINNET)).toBe(true);
    expect(supportsPermit("0xa882606494d86804b5514e07e6bd2d6a6ee6d68a", MAINNET)).toBe(true);
  });

  // MUTATION: Accept "dai" alongside "eip2612"
  // BREAKS: Swapboard's Permit struct is EIP-2612 shaped and there is no
  //         DAI-flavour overload on chain, so permit(holder,spender,nonce,
  //         expiry,allowed,v,r,s) tokens would be signed for and then revert
  test("rejects the DAI flavour, which the contract has no overload for", () => {
    expect(supportsPermit("0x6b175474e89094c44da98b954eedeac495271d0f", MAINNET)).toBe(false);
  });

  // MUTATION: Treat "nonstandard" as permit-capable
  // BREAKS: Yearn-style tokens answer DOMAIN_SEPARATOR() and nonces() like a 2612
  //         token, so the UI signs a permit that reverts and the swap fails
  test("rejects the Yearn-style permit that only looks like EIP-2612", () => {
    expect(supportsPermit("0xa258c4606ca8206d8aa700ce2143d7db854d168c", MAINNET)).toBe(false);
  });

  // MUTATION: Default unresolved tokens to true
  // BREAKS: Anything unlisted or unverified sends a permit that reverts, instead
  //         of paying one extra transaction for approve()
  test("falls back to approve() whenever support is not established", () => {
    expect(supportsPermit("0xdac17f958d2ee523a2206206994597c13d831ec7", MAINNET)).toBe(false);
    expect(supportsPermit("0x48ab4e39ac59f4e88974804b04a991b3a402717f", MAINNET)).toBe(false);
    expect(supportsPermit("0x1111111111111111111111111111111111111111", MAINNET)).toBe(false);
    expect(supportsPermit(null, MAINNET)).toBe(false);
  });

  // MUTATION: Drop the chainId pass-through to permitKindFor
  // BREAKS: A Sepolia build offers permit on mainnet verdicts, and misses the
  //         Sepolia tokens that genuinely support it
  test("resolves support against the caller's chain", () => {
    expect(supportsPermit("0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48", SEPOLIA)).toBe(false);
    expect(supportsPermit("0x1c7d4b196cb0c7b01d743fbc6116a902379c7238", SEPOLIA)).toBe(true);
    expect(supportsPermit("0xfff9976782d46cc05630d1f6ebab18b2324d6b14", SEPOLIA)).toBe(false);
  });
});

// ============================================================================
// priceRatio
// ============================================================================

// ============================================================================
// Signature-based approvals
// ============================================================================

describe("choosePullStrategy", () => {
  /** A token with nothing going for it: no allowance, no permit, no Permit2. */
  const base = {
    isNative: false,
    allowance: 0n,
    amount: 100n,
    permitKind: "none",
    permit2Allowance: 0n,
  };
  const strategy = (over) => choosePullStrategy({ ...base, ...over });

  // MUTATION: Drop the isNative short-circuit
  // BREAKS: The ETH sentinel is not a contract, so reading an allowance off it
  //         throws and every ETH-offering order dies before it is sent
  test("native ETH needs nothing, whatever else is true of it", () => {
    expect(strategy({ isNative: true })).toBe("none");
    expect(strategy({ isNative: true, permitKind: "eip2612" })).toBe("none");
    expect(strategy({ isNative: true, permit2Allowance: 999n })).toBe("none");
  });

  // MUTATION: Compare with > instead of >=
  // BREAKS: An allowance that exactly covers the pull is treated as short, so
  //         the user is asked to approve again for nothing
  test("an allowance that already covers the pull asks for nothing", () => {
    expect(strategy({ allowance: 100n })).toBe("none");
    expect(strategy({ allowance: 101n })).toBe("none");
    expect(strategy({ allowance: 99n })).toBe("approve");
  });

  // MUTATION: Prefer the allowance check only after the permit check
  // BREAKS: A standing allowance still costs the user a signature, which is a
  //         wallet prompt for an approval they already granted
  test("a standing allowance wins over a signature the token could give", () => {
    expect(strategy({ allowance: 100n, permitKind: "eip2612" })).toBe("none");
    expect(strategy({ allowance: 100n, permit2Allowance: 100n })).toBe("none");
  });

  // MUTATION: Skip the zero-amount guard
  // BREAKS: A zero-amount leg signs a permit for nothing, and the contract then
  //         reverts UnusedPermit because no pull spends it
  test("a zero pull needs nothing", () => {
    expect(strategy({ amount: 0n })).toBe("none");
    expect(strategy({ amount: 0n, permitKind: "eip2612" })).toBe("none");
  });

  // MUTATION: Accept any permitKind, or drop isSignablePermitKind
  // BREAKS: DAI-flavour and Yearn-style tokens are signed for with the EIP-2612
  //         struct the contract expects, and revert the swap
  test("only the flavours the contract has an overload for take the permit path", () => {
    expect(strategy({ permitKind: "eip2612" })).toBe("permit");
    expect(strategy({ permitKind: "both" })).toBe("permit");
    expect(strategy({ permitKind: "dai" })).toBe("approve");
    expect(strategy({ permitKind: "nonstandard" })).toBe("approve");
    expect(strategy({ permitKind: "unverified" })).toBe("approve");
    expect(strategy({ permitKind: "unknown" })).toBe("approve");
    expect(strategy({ permitKind: "none" })).toBe("approve");
  });

  // MUTATION: Check Permit2 before the token's own permit
  // BREAKS: A token that could be approved with one signature is instead pulled
  //         through Permit2, which only works if the user already approved it
  test("the token's own permit is preferred to Permit2", () => {
    expect(strategy({ permitKind: "eip2612", permit2Allowance: 999n })).toBe("permit");
  });

  // MUTATION: Ignore permit2Allowance and always offer Permit2
  // BREAKS: A Permit2 signature is produced for a user who never approved
  //         Permit2, so the transfer reverts instead of falling back to approve()
  test("Permit2 is only offered when Permit2 is actually approved", () => {
    expect(strategy({ permit2Allowance: 100n })).toBe("permit2");
    expect(strategy({ permit2Allowance: 99n })).toBe("approve");
    expect(strategy({ permit2Allowance: 0n })).toBe("approve");
  });

  // MUTATION: Compare the amounts as strings or numbers
  // BREAKS: "9" > "100" lexically and 1e18-scale amounts lose precision as
  //         numbers, so the comparison silently answers backwards
  test("compares amounts numerically, not as strings", () => {
    expect(strategy({ allowance: "9", amount: "100" })).toBe("approve");
    expect(strategy({ allowance: "100", amount: "9" })).toBe("none");
  });
});

describe("isSignablePermitKind", () => {
  // MUTATION: Return true for "dai"
  // BREAKS: Swapboard's Permit struct is EIP-2612 shaped and has no DAI-flavour
  //         overload, so the signature encodes cleanly and reverts on chain
  test("accepts only what the contract's Permit struct can express", () => {
    expect(isSignablePermitKind("eip2612")).toBe(true);
    expect(isSignablePermitKind("both")).toBe(true);
    expect(isSignablePermitKind("dai")).toBe(false);
    expect(isSignablePermitKind("nonstandard")).toBe(false);
    expect(isSignablePermitKind("unverified")).toBe(false);
    expect(isSignablePermitKind("unknown")).toBe(false);
    expect(isSignablePermitKind(undefined)).toBe(false);
  });
});

describe("permit2Domain", () => {
  // MUTATION: Add a `version` field to the domain
  // BREAKS: Permit2's own domain has no version, so adding one changes the
  //         separator and Permit2 rejects every signature as an invalid signer
  test("omits version, and names the canonical contract", () => {
    const domain = permit2Domain(1);
    expect(domain).toEqual({
      name: "Permit2",
      chainId: 1,
      verifyingContract: PERMIT2_ADDRESS,
    });
    expect("version" in domain).toBe(false);
  });

  // MUTATION: Hardcode the chain id
  // BREAKS: A Sepolia signature carries a mainnet domain and is not spendable
  test("carries the chain it was asked for", () => {
    expect(permit2Domain(11155111).chainId).toBe(11155111);
  });
});

describe("PERMIT2_ADDRESS", () => {
  // MUTATION: Change any character of the address
  // BREAKS: Swapboard hardcodes the canonical Permit2 as _PERMIT2, so a
  //         signature naming a different verifying contract can never be spent,
  //         and the Permit2 allowance is read off the wrong spender
  test("matches the constant the contract hardcodes", () => {
    expect(PERMIT2_ADDRESS).toBe("0x000000000022D473030F116dDEE9F6B43aC78BA3");
  });
});

describe("buildPermitMessage", () => {
  // MUTATION: Reorder the fields, or drop one
  // BREAKS: EIP-712 hashes the struct by its type definition, so a missing or
  //         renamed field produces a digest the token will not recognise
  test("carries exactly the EIP-2612 Permit fields", () => {
    const message = buildPermitMessage({
      owner: "0xowner",
      spender: "0xspender",
      value: 100n,
      nonce: 7n,
      deadline: 1234,
    });
    expect(message).toEqual({
      owner: "0xowner",
      spender: "0xspender",
      value: "100",
      nonce: "7",
      deadline: 1234,
    });
    expect(Object.keys(message)).toEqual(PERMIT_TYPES.Permit.map((f) => f.name));
  });

  // MUTATION: Pass the BigInt through instead of stringifying
  // BREAKS: JSON.stringify throws on a BigInt, and the wallet is handed the
  //         typed-data payload as JSON
  test("stringifies the amounts so the payload survives JSON", () => {
    const message = buildPermitMessage({
      owner: "0xowner",
      spender: "0xspender",
      value: 10n ** 30n,
      nonce: 0,
      deadline: 1,
    });
    expect(() => JSON.stringify(message)).not.toThrow();
    expect(message.value).toBe("1000000000000000000000000000000");
  });
});

describe("buildPermit2Message", () => {
  // MUTATION: Flatten permitted.token / permitted.amount onto the top level
  // BREAKS: Permit2 hashes TokenPermissions as a nested struct, so a flattened
  //         message hashes to something no nonce can spend
  test("nests the token permissions the way Permit2 hashes them", () => {
    const message = buildPermit2Message({
      token: "0xtoken",
      amount: 500n,
      spender: "0xspender",
      nonce: 42n,
      deadline: 99,
    });
    expect(message).toEqual({
      permitted: { token: "0xtoken", amount: "500" },
      spender: "0xspender",
      nonce: "42",
      deadline: 99,
    });
    expect(Object.keys(message)).toEqual(PERMIT2_TYPES.PermitTransferFrom.map((f) => f.name));
    expect(Object.keys(message.permitted)).toEqual(
      PERMIT2_TYPES.TokenPermissions.map((f) => f.name)
    );
  });
});

describe("permit2Nonce", () => {
  // MUTATION: Read fewer than 32 bytes, or shift by something other than 8
  // BREAKS: A nonce drawn from a narrow range collides with one already spent,
  //         and Permit2 rejects the reused bit
  test("packs 32 bytes into one 256-bit nonce", () => {
    const allOnes = new Uint8Array(32).fill(0xff);
    expect(permit2Nonce(allOnes)).toBe(2n ** 256n - 1n);

    const zero = new Uint8Array(32);
    expect(permit2Nonce(zero)).toBe(0n);
  });

  // MUTATION: Use the bytes in reverse, or mask off the high byte
  // BREAKS: Two different draws map to the same nonce
  test("is big-endian over the bytes it is given", () => {
    const bytes = new Uint8Array(32);
    bytes[31] = 1;
    expect(permit2Nonce(bytes)).toBe(1n);

    const high = new Uint8Array(32);
    high[0] = 1;
    expect(permit2Nonce(high)).toBe(2n ** 248n);
  });

  // MUTATION: Drop the & 0xff
  // BREAKS: A signed or oversized byte corrupts every higher bit of the nonce
  test("masks each byte to 8 bits", () => {
    const bytes = new Array(32).fill(0);
    bytes[31] = 0x1ff;
    expect(permit2Nonce(bytes)).toBe(0xffn);
  });
});

describe("permitDeadline", () => {
  // MUTATION: Return the raw nowSec, or subtract the ttl
  // BREAKS: The signature is already expired when it reaches the contract
  test("is the given ttl into the future", () => {
    expect(permitDeadline(1000, 60)).toBe(1060);
    expect(permitDeadline(1000)).toBe(1000 + PERMIT_TTL_SECONDS);
  });

  // MUTATION: Drop the Math.floor
  // BREAKS: Date.now() / 1000 is fractional, and a non-integer deadline cannot
  //         be encoded as uint256
  test("floors a fractional clock reading", () => {
    expect(Number.isInteger(permitDeadline(1000.7, 60))).toBe(true);
    expect(permitDeadline(1000.7, 60)).toBe(1060);
  });
});

describe("planBatchPulls", () => {
  /** Shapes one leg, defaulting everything the test does not care about. */
  const leg = (over) => ({
    token: "0xaaa",
    amount: 10n,
    isNative: false,
    allowance: 0n,
    permitKind: "none",
    permit2Allowance: 0n,
    ...over,
  });

  // MUTATION: Push every leg through without aggregating
  // BREAKS: Two rows offering the same token produce two entries for it, and the
  //         contract reverts DuplicatePermitToken
  test("aggregates repeated tokens into one entry for their total", () => {
    const plan = planBatchPulls([
      leg({ token: "0xAAA", amount: 50n, permitKind: "eip2612" }),
      leg({ token: "0xaaa", amount: 60n, permitKind: "eip2612" }),
    ]);
    expect(plan.strategy).toBe("permit");
    expect(plan.entries).toHaveLength(1);
    expect(plan.entries[0].amount).toBe(110n);
  });

  // MUTATION: Key the aggregation on the raw address
  // BREAKS: The same token written two ways counts as two, which is the
  //         DuplicatePermitToken revert again
  test("treats differently-cased addresses as the same token", () => {
    const plan = planBatchPulls([
      leg({ token: "0xAbCd", amount: 1n, permitKind: "eip2612" }),
      leg({ token: "0xaBcD", amount: 2n, permitKind: "eip2612" }),
    ]);
    expect(plan.entries).toHaveLength(1);
    expect(plan.entries[0].amount).toBe(3n);
  });

  // MUTATION: Include native legs
  // BREAKS: The ETH sentinel is not an ERC20, and the contract reverts
  //         PermitOnNative for a permit naming it
  test("leaves native ETH out of the plan entirely", () => {
    const plan = planBatchPulls([
      leg({ token: "0xeee", isNative: true, amount: 5n }),
      leg({ token: "0xbbb", amount: 5n, permitKind: "eip2612" }),
    ]);
    expect(plan.entries).toHaveLength(1);
    expect(plan.entries[0].token).toBe("0xbbb");
    expect(plan.approvals).toHaveLength(0);
    expect(plan.demoted).toHaveLength(0);
  });

  // MUTATION: Emit entries for tokens that need no pull
  // BREAKS: An entry nothing spends reverts UnusedPermit / UnusedPermit2
  test("emits no entry for a token whose allowance already covers it", () => {
    const plan = planBatchPulls([
      leg({ token: "0xaaa", amount: 10n, allowance: 10n, permitKind: "eip2612" }),
      leg({ token: "0xbbb", amount: 10n, permitKind: "eip2612" }),
    ]);
    expect(plan.entries.map((e) => e.token)).toEqual(["0xbbb"]);
  });

  // MUTATION: Mix permit and permit2 entries into one call
  // BREAKS: A call takes TokenPermit[] or TokenPermit2[], never both, so the
  //         mixed batch cannot be encoded against any overload
  test("commits the batch to one signature flavour, demoting the other", () => {
    const plan = planBatchPulls([
      leg({ token: "0xaaa", permitKind: "eip2612" }),
      leg({ token: "0xbbb", permitKind: "eip2612" }),
      leg({ token: "0xccc", permit2Allowance: 999n }),
    ]);
    expect(plan.strategy).toBe("permit");
    expect(plan.entries.map((e) => e.token)).toEqual(["0xaaa", "0xbbb"]);
    expect(plan.demoted.map((e) => e.token)).toEqual(["0xccc"]);
  });

  // MUTATION: Always pick "permit"
  // BREAKS: A batch that is mostly Permit2 sends more approve() transactions
  //         than it needs to
  test("gives the overload to whichever signature group is larger", () => {
    const plan = planBatchPulls([
      leg({ token: "0xaaa", permitKind: "eip2612" }),
      leg({ token: "0xbbb", permit2Allowance: 999n }),
      leg({ token: "0xccc", permit2Allowance: 999n }),
    ]);
    expect(plan.strategy).toBe("permit2");
    expect(plan.entries.map((e) => e.token)).toEqual(["0xbbb", "0xccc"]);
    expect(plan.demoted.map((e) => e.token)).toEqual(["0xaaa"]);
  });

  // MUTATION: Break the tie towards permit2
  // BREAKS: The tie-break stops matching choosePullStrategy's single-token
  //         preference, so one token behaves differently alone and in a batch
  test("breaks a tie towards EIP-2612, as the single-token order does", () => {
    const plan = planBatchPulls([
      leg({ token: "0xaaa", permitKind: "eip2612" }),
      leg({ token: "0xbbb", permit2Allowance: 999n }),
    ]);
    expect(plan.strategy).toBe("permit");
    expect(plan.entries.map((e) => e.token)).toEqual(["0xaaa"]);
  });

  // MUTATION: Fold approve-only tokens into `demoted`
  // BREAKS: They are approved again inside the chunk loop, one transaction per
  //         chunk, instead of once for the whole batch
  test("keeps never-signable tokens apart from demoted ones", () => {
    const plan = planBatchPulls([
      leg({ token: "0xaaa", permitKind: "eip2612" }),
      leg({ token: "0xbbb", permitKind: "dai" }),
      leg({ token: "0xccc", permit2Allowance: 999n }),
    ]);
    expect(plan.approvals.map((e) => e.token)).toEqual(["0xbbb"]);
    expect(plan.demoted.map((e) => e.token)).toEqual(["0xccc"]);
  });

  // MUTATION: Report a signature strategy with no entries
  // BREAKS: The caller sends a permit overload carrying an empty array, which
  //         the contract accepts and then reverts on for an unpulled token
  test("reports no strategy when nothing can be signed for", () => {
    const plan = planBatchPulls([leg({ token: "0xaaa" }), leg({ token: "0xbbb" })]);
    expect(plan.strategy).toBe("none");
    expect(plan.entries).toHaveLength(0);
    expect(plan.approvals.map((e) => e.token)).toEqual(["0xaaa", "0xbbb"]);
  });

  // MUTATION: Drop the MAX_PERMIT2_BATCH splice, or use > instead of >=
  // BREAKS: The contract tracks used entries in a single uint256 and reverts
  //         TooManyPermit2 past 256, so the whole batch becomes unsendable
  test("caps a Permit2 batch at the bitmap limit and approves the tail", () => {
    const legs = [];
    for (let i = 0; i < MAX_PERMIT2_BATCH + 3; i++) {
      legs.push(leg({ token: "0x" + String(i).padStart(40, "0"), permit2Allowance: 999n }));
    }
    const plan = planBatchPulls(legs);
    expect(plan.strategy).toBe("permit2");
    expect(plan.entries).toHaveLength(MAX_PERMIT2_BATCH);
    expect(plan.demoted).toHaveLength(3);
  });

  // MUTATION: Mutate the caller's leg objects while aggregating
  // BREAKS: The amounts the confirmation modal quoted change underneath it
  test("does not mutate the legs it was given", () => {
    const legs = [
      leg({ token: "0xaaa", amount: 5n, permitKind: "eip2612" }),
      leg({ token: "0xaaa", amount: 7n, permitKind: "eip2612" }),
    ];
    planBatchPulls(legs);
    expect(legs[0].amount).toBe(5n);
    expect(legs[1].amount).toBe(7n);
  });
});

describe("priceRatio", () => {
  // MUTATION: Flip the sign of the decimals exponent
  // BREAKS: A WETH/USDC price comes out as 1e-24 instead of ~2000
  test("scales the decimals of both sides back out", () => {
    // 1 WETH (18dp) for 2000 USDC (6dp) -> 2000 USDC per WETH
    const price = priceRatio("2000000000", "1000000000000000000", 6, 18);
    expect(price).toBeCloseTo(2000, 6);
  });

  // MUTATION: Drop the exponent entirely
  // BREAKS: Same-decimal pairs happen to pass, so this pins the equal case too
  test("needs no scaling when both sides share decimals", () => {
    expect(priceRatio("300", "100", 18, 18)).toBeCloseTo(3, 9);
  });

  // MUTATION: Divide anyway when the denominator is zero
  // BREAKS: Returns Infinity/NaN, which sorts ahead of every real price
  test("returns 0 for an empty denominator", () => {
    expect(priceRatio("100", "0", 18, 18)).toBe(0);
  });

  // MUTATION: Accept Numbers only
  // BREAKS: Subgraph amounts arrive as strings and overflow Number precision
  test("accepts base units as strings or bigints", () => {
    expect(priceRatio(300n, 100n, 18, 18)).toBeCloseTo(3, 9);
  });
});

// ============================================================================
// orderStatus
// ============================================================================

describe("orderStatus", () => {
  // MUTATION: Return "Filled" for an open order
  // BREAKS: Open orders show as filled and fire spurious watch notifications
  test("an open order is Open", () => {
    expect(orderStatus({ status: ORDER_STATUS.OPEN })).toBe("Open");
  });

  // MUTATION: Fold PARTIALLY_FILLED in with FILLED
  // BREAKS: A still-fillable order is presented as finished, and the Fill
  // button disappears from an order that can still be filled
  test("a partially filled order says so, and is not Filled", () => {
    expect(orderStatus({ status: ORDER_STATUS.PARTIALLY_FILLED })).toBe("Partially Filled");
  });

  // MUTATION: Collapse the two closed states into one
  // BREAKS: Filled and cancelled orders become indistinguishable
  test("the two closed states stay distinct", () => {
    expect(orderStatus({ status: ORDER_STATUS.FILLED })).toBe("Filled");
    expect(orderStatus({ status: ORDER_STATUS.CANCELED })).toBe("Cancelled");
  });

  // MUTATION: Throw or return undefined on an unrecognised status
  // BREAKS: One unexpected enum value from a future schema blanks the column
  test("an unknown or missing status reads as Open", () => {
    expect(orderStatus({})).toBe("Open");
    expect(orderStatus({ status: "SOMETHING_NEW" })).toBe("Open");
  });
});

describe("getRecentTokens / addRecentToken", () => {
  // MUTATION: Return null instead of []
  // BREAKS: Callers doing .map() would crash
  test("getRecentTokens returns [] for missing key", () => {
    expect(getRecentTokens(localStorage)).toEqual([]);
  });

  // MUTATION: Return raw string instead of parsed JSON
  // BREAKS: Returns "[{...}]" string instead of array
  test("getRecentTokens parses stored JSON", () => {
    const tokens = [{ address: "0x123", symbol: "TEST" }];
    localStorage.setItem(RECENT_TOKENS_KEY, JSON.stringify(tokens));
    expect(getRecentTokens(localStorage)).toEqual(tokens);
  });

  // MUTATION: Throw on parse error instead of returning []
  // BREAKS: Corrupt storage crashes app
  test("getRecentTokens returns [] on JSON parse error", () => {
    localStorage.setItem(RECENT_TOKENS_KEY, "invalid{{{");
    expect(getRecentTokens(localStorage)).toEqual([]);
  });

  // MUTATION: Append instead of prepend
  // BREAKS: New token at end instead of front
  test("addRecentToken adds to front of list", () => {
    localStorage.setItem(RECENT_TOKENS_KEY, JSON.stringify([{ address: "0xold", symbol: "OLD" }]));
    addRecentToken("0xnew", "NEW", localStorage);
    expect(getRecentTokens(localStorage)[0].symbol).toBe("NEW");
  });

  // MUTATION: Don't remove duplicates
  // BREAKS: Same address appears twice
  test("addRecentToken removes existing entry before adding", () => {
    localStorage.setItem(RECENT_TOKENS_KEY, JSON.stringify([{ address: "0x123", symbol: "OLD" }]));
    addRecentToken("0x123", "UPDATED", localStorage);
    const result = getRecentTokens(localStorage);
    expect(result.length).toBe(1);
    expect(result[0].symbol).toBe("UPDATED");
  });

  // MUTATION: Case-sensitive address comparison
  // BREAKS: 0xABC and 0xabc both in list
  test("addRecentToken deduplicates case-insensitively", () => {
    localStorage.setItem(RECENT_TOKENS_KEY, JSON.stringify([{ address: "0xABC", symbol: "OLD" }]));
    addRecentToken("0xabc", "NEW", localStorage);
    expect(getRecentTokens(localStorage).length).toBe(1);
  });

  // MUTATION: Don't limit list length
  // BREAKS: List grows forever
  test("addRecentToken limits to MAX_RECENT_TOKENS", () => {
    const tokens = Array.from({ length: 10 }, (_, i) => ({
      address: `0x${i}`,
      symbol: `T${i}`,
    }));
    localStorage.setItem(RECENT_TOKENS_KEY, JSON.stringify(tokens));
    addRecentToken("0xnew", "NEW", localStorage);
    expect(getRecentTokens(localStorage).length).toBe(MAX_RECENT_TOKENS);
  });

  // MUTATION: Allow empty address
  // BREAKS: { address: "", symbol: "X" } stored
  test("addRecentToken rejects empty address", () => {
    addRecentToken("", "TEST", localStorage);
    expect(getRecentTokens(localStorage)).toEqual([]);
  });

  // MUTATION: Allow empty symbol
  // BREAKS: { address: "0x1", symbol: "" } stored
  test("addRecentToken rejects empty symbol", () => {
    addRecentToken("0x123", "", localStorage);
    expect(getRecentTokens(localStorage)).toEqual([]);
  });
});

// ============================================================================
// localStorage: Watched Orders
// ============================================================================

describe("watchOrder / unwatchOrder / isOrderWatched", () => {
  // MUTATION: Hardcode status as "Open"
  // BREAKS: Filled orders show status "Open"
  test("watchOrder stores correct status based on order state", () => {
    const tokens = { tokenA: { symbol: "A" }, tokenB: { symbol: "B" } };

    watchOrder(Object.assign({ orderId: "1", status: ORDER_STATUS.OPEN }, tokens), localStorage);
    expect(getWatchedOrders(localStorage)["1"].status).toBe("Open");

    watchOrder(Object.assign({ orderId: "2", status: ORDER_STATUS.FILLED }, tokens), localStorage);
    expect(getWatchedOrders(localStorage)["2"].status).toBe("Filled");

    watchOrder(
      Object.assign({ orderId: "3", status: ORDER_STATUS.CANCELED }, tokens),
      localStorage
    );
    expect(getWatchedOrders(localStorage)["3"].status).toBe("Cancelled");

    watchOrder(
      Object.assign({ orderId: "4", status: ORDER_STATUS.PARTIALLY_FILLED }, tokens),
      localStorage
    );
    expect(getWatchedOrders(localStorage)["4"].status).toBe("Partially Filled");
  });

  // MUTATION: Store only tokenA symbol
  // BREAKS: symbol is "A" instead of "A/B"
  test("watchOrder stores symbol pair", () => {
    watchOrder(
      {
        orderId: "1",
        active: true,
        taker: null,
        tokenA: { symbol: "WETH" },
        tokenB: { symbol: "USDC" },
      },
      localStorage
    );
    expect(getWatchedOrders(localStorage)["1"].symbol).toBe("WETH/USDC");
  });

  // MUTATION: Clear entire storage on unwatch
  // BREAKS: All watched orders deleted
  test("unwatchOrder removes only specified order", () => {
    localStorage.setItem(
      WATCHED_ORDERS_KEY,
      JSON.stringify({
        1: { status: "Open", symbol: "A/B" },
        2: { status: "Filled", symbol: "C/D" },
      })
    );
    unwatchOrder("1", localStorage);
    const watched = getWatchedOrders(localStorage);
    expect(watched["1"]).toBeUndefined();
    expect(watched["2"].status).toBe("Filled");
  });

  // MUTATION: Return truthy object instead of boolean
  // BREAKS: Returns { status: "Open" } instead of true
  test("isOrderWatched returns boolean", () => {
    localStorage.setItem(
      WATCHED_ORDERS_KEY,
      JSON.stringify({
        1: { status: "Open", symbol: "A/B" },
      })
    );
    expect(isOrderWatched("1", localStorage)).toBe(true);
    expect(isOrderWatched("999", localStorage)).toBe(false);
  });

  // MUTATION: Throw on corrupt JSON instead of returning {}
  // BREAKS: App crashes when localStorage is corrupt
  test("getWatchedOrders returns empty object on parse error", () => {
    localStorage.setItem(WATCHED_ORDERS_KEY, "invalid{json");
    expect(getWatchedOrders(localStorage)).toEqual({});
  });
});

// ============================================================================
// localStorage: Filter/Sort Preferences
// ============================================================================

describe("filter/sort preferences", () => {
  // MUTATION: Store object directly without JSON.stringify
  // BREAKS: Storage contains "[object Object]"
  test("saveFilterPreferences stores valid JSON", () => {
    const filters = { status: "filled", selling: "0x123" };
    saveFilterPreferences(filters, localStorage);
    const stored = localStorage.getItem(FILTERS_KEY);
    expect(JSON.parse(stored)).toEqual(filters);
  });

  // MUTATION: Return {} instead of null
  // BREAKS: Callers checking === null get {}
  test("loadFilterPreferences returns null for missing key", () => {
    expect(loadFilterPreferences(localStorage)).toBe(null);
  });

  // MUTATION: Throw on corrupt JSON
  // BREAKS: App crashes
  test("loadFilterPreferences returns null on parse error", () => {
    localStorage.setItem(FILTERS_KEY, "invalid{{{");
    expect(loadFilterPreferences(localStorage)).toBe(null);
  });

  // MUTATION: Use wrong storage key
  // BREAKS: Save/load don't match
  test("saveSortPreferences and loadSortPreferences use same key", () => {
    const sort = { column: "amountA", direction: "asc" };
    saveSortPreferences(sort, localStorage);
    expect(loadSortPreferences(localStorage)).toEqual(sort);
  });

  // MUTATION: Throw on corrupt JSON instead of returning null
  // BREAKS: App crashes when localStorage is corrupt
  test("loadSortPreferences returns null on parse error", () => {
    localStorage.setItem(SORT_KEY, "not{valid:json");
    expect(loadSortPreferences(localStorage)).toBe(null);
  });
});

// ============================================================================
// sortOrders
// ============================================================================

describe("sortOrders", () => {
  // WETH 18dp, USDC 6dp, DAI 18dp -- deliberately mixed precision, because
  // that is exactly what base-unit comparison gets wrong.
  const WETH = { symbol: "WETH", address: "0xweth", decimals: 18 };
  const USDC = { symbol: "USDC", address: "0xusdc", decimals: 6 };
  const DAI = { symbol: "DAI", address: "0xdai", decimals: 18 };

  const orders = [
    // 1 WETH for 3500 USDC
    {
      orderId: "1",
      maker: "0xaaa",
      tokenA: WETH,
      tokenB: USDC,
      amountA: "1000000000000000000",
      amountB: "3500000000",
    },
    // 2000 USDC for 0.5 WETH
    {
      orderId: "2",
      maker: "0xbbb",
      tokenA: USDC,
      tokenB: WETH,
      amountA: "2000000000",
      amountB: "500000000000000000",
    },
    // 5000 DAI for 5000 USDC
    {
      orderId: "3",
      maker: "0xccc",
      tokenA: DAI,
      tokenB: USDC,
      amountA: "5000000000000000000000",
      amountB: "5000000000",
    },
    // Untouched orders, so what is left is the whole order. The columns sort on
    // the remainder, since that is what they display.
  ].map((o) => Object.assign({ availableA: o.amountA, availableB: o.amountB }, o));
  const ids = (result) => result.map((o) => o.orderId);

  // MUTATION: Use string comparison for orderId
  // BREAKS: "10" sorts before "2"
  test("sorts orderId numerically", () => {
    expect(ids(sortOrders(orders, "orderId", "asc"))).toEqual(["1", "2", "3"]);
    expect(ids(sortOrders(orders, "orderId", "desc"))).toEqual(["3", "2", "1"]);
  });

  // MUTATION: Drop the .toLowerCase()
  // BREAKS: Uppercase symbols sort ahead of every lowercase one
  test("sorts symbol columns alphabetically", () => {
    expect(ids(sortOrders(orders, "tokenA", "asc"))).toEqual(["3", "2", "1"]); // DAI, USDC, WETH
    expect(ids(sortOrders(orders, "maker", "asc"))).toEqual(["1", "2", "3"]);
  });

  // MUTATION: Read tokenA's symbol in the tokenB case
  // BREAKS: The Wanted column sorts by the offered token
  test("sorts the wanted column by tokenB's symbol", () => {
    // tokenB symbols: 1=USDC, 2=WETH, 3=USDC -- WETH sorts last ascending
    expect(ids(sortOrders(orders, "tokenB", "desc"))[0]).toBe("2");
    expect(ids(sortOrders(orders, "tokenB", "asc"))[2]).toBe("2");
  });

  // MUTATION: Compare BigInt base units instead of scaling by decimals
  // BREAKS: 1 WETH (1e18 base units) outranks 5000 DAI and 2000 USDC purely
  //         because it has more decimal places
  test("compares amounts in human units, not base units", () => {
    // Human amounts: 5000 DAI > 2000 USDC > 1 WETH
    expect(ids(sortOrders(orders, "amountA", "desc"))).toEqual(["3", "2", "1"]);
    expect(ids(sortOrders(orders, "amountA", "asc"))).toEqual(["1", "2", "3"]);
    // Base units would have ordered these 3, 1, 2 -- pin that it does not
    expect(ids(sortOrders(orders, "amountA", "desc"))).not.toEqual(["3", "1", "2"]);
  });

  // MUTATION: Read amountB's scale from tokenA
  // BREAKS: The wanted-side amount is scaled by the wrong token's decimals
  test("scales amountB by tokenB's decimals", () => {
    // Human amountB: 5000 USDC > 3500 USDC > 0.5 WETH
    expect(ids(sortOrders(orders, "amountB", "desc"))).toEqual(["3", "1", "2"]);
  });

  // MUTATION: Ignore getPriceFn and read a precomputed field
  // BREAKS: The USD column silently stops sorting
  test("computes USD value from the injected price function", () => {
    const prices = { "0xweth": 3500, "0xusdc": 1, "0xdai": 1 };
    const getPrice = (addr) => prices[addr] ?? null;
    // USD of the offered side: 5000 DAI > 3500 (1 WETH) > 2000 USDC
    expect(ids(sortOrders(orders, "usdVal", "desc", getPrice))).toEqual(["3", "1", "2"]);
  });

  // MUTATION: Treat an unknown price as 0 rather than -1
  // BREAKS: Unpriced orders tie with genuinely zero-value ones instead of sinking
  test("orders with no known price sink to the bottom", () => {
    const getPrice = (addr) => (addr === "0xusdc" ? 1 : null);
    expect(ids(sortOrders(orders, "usdVal", "desc", getPrice))[0]).toBe("2");
  });

  // MUTATION: Ignore quoteSideFn and always quote wanted-per-offered
  // BREAKS: The Price column sorts on a different number than it displays
  test("sorts price on the side quoteSideFn selects", () => {
    const quoteB = () => "B"; // wanted per offered
    const quoteA = () => "A"; // offered per wanted
    expect(ids(sortOrders(orders, "price", "desc", undefined, quoteB))).toEqual(["1", "3", "2"]);
    // Quoting the other side inverts every ratio, so the order reverses
    expect(ids(sortOrders(orders, "price", "desc", undefined, quoteA))).toEqual(["2", "3", "1"]);
  });

  // MUTATION: Make the injected functions required
  // BREAKS: Every caller that only wants to sort by id or symbol has to supply them
  test("the injected functions are optional", () => {
    expect(() => sortOrders(orders, "usdVal", "asc")).not.toThrow();
    expect(() => sortOrders(orders, "price", "asc")).not.toThrow();
    // With no prices at all every order ties at -1, so input order survives
    expect(ids(sortOrders(orders, "usdVal", "desc"))).toEqual(["1", "2", "3"]);
  });

  // MUTATION: Sort in place
  // BREAKS: The caller's array is reordered underneath it
  test("does not mutate the input array", () => {
    const before = ids(orders);
    sortOrders(orders, "orderId", "desc");
    expect(ids(orders)).toEqual(before);
  });

  // MUTATION: Fall through to a comparison for an unknown column
  // BREAKS: Sorting on a column that does not exist scrambles the table
  test("an unknown column leaves the order untouched", () => {
    expect(ids(sortOrders(orders, "nope", "asc"))).toEqual(["1", "2", "3"]);
  });
});

// ============================================================================
// decodeContractError
// ============================================================================

describe("decodeContractError", () => {
  const pad = (n) => n.toString(16).padStart(64, "0");

  // MUTATION: Wrong selector in ERROR_SIGNATURES
  // BREAKS: The error is not recognized and falls through to a generic message
  test("maps a selector to its error name and message", () => {
    expect(decodeContractError("0xd92e233d")).toEqual({
      name: "ZeroAddress",
      message: "Invalid token address",
    });
  });

  // MUTATION: Use an exact string match instead of slice(0, 10)
  // BREAKS: Any error carrying arguments stops being recognized
  test("reads the selector off data that carries arguments", () => {
    expect(decodeContractError("0xd92e233d" + pad(4660)).name).toBe("ZeroAddress");
  });

  // MUTATION: Drop the argument decoding and use a static string
  // BREAKS: "Order #7 is no longer active" degrades to "Order is not active"
  test("interpolates decoded arguments into the message", () => {
    expect(decodeContractError("0xd2c02610" + pad(7)).message).toBe("Order #7 is no longer active");
    expect(decodeContractError("0x4e90badc" + pad(1234)).message).toBe("Order #1234 not found");
    expect(decodeContractError("0x457802f0" + pad(42)).message).toBe(
      "Order #42 changed while you were editing it. Refresh and try again."
    );
  });

  // MUTATION: Omit the v2 selectors from the table
  // BREAKS: Every partial-fill failure — the most common way a v2 fill fails —
  //         reports "Transaction failed. Please try again." and the user has no
  //         idea the order simply moved underneath them
  test("names the order in each v2 fill failure", () => {
    // FillAmountTooHigh and FillAmountMismatch carry three words; only the
    // first is used, so the trailing arguments must not shift it.
    expect(decodeContractError("0xed38596f" + pad(7)).message).toBe(
      "Order #7 must be filled in full"
    );
    expect(decodeContractError("0x535a34f0" + pad(8) + pad(500) + pad(100)).message).toBe(
      "Order #8 has less left than you asked for. Refresh and try again."
    );
    expect(decodeContractError("0x19113a72" + pad(9) + pad(10) + pad(20)).message).toBe(
      "Order #9 repriced while you were confirming. Refresh and try again."
    );
    expect(decodeContractError("0x54b9c511" + pad(12)).message).toBe(
      "Order #12 appears twice in this batch"
    );
  });

  // MUTATION: Omit the OpenZeppelin selectors
  // BREAKS: v2 replaced v1's hand-rolled ETHTransferFailed with Address and
  //         SafeERC20's errors, so a failed payout would decode as nothing
  test("recognizes the library errors v2 reverts with", () => {
    expect(decodeContractError("0xd6bda275").name).toBe("FailedCall");
    expect(decodeContractError("0xcf479181" + pad(1) + pad(2)).name).toBe("InsufficientBalance");
    expect(decodeContractError("0x5274afe7" + pad(0)).name).toBe("SafeERC20FailedOperation");
    expect(decodeContractError("0x3ee5aeb5").name).toBe("ReentrancyGuardReentrantCall");
  });

  // MUTATION: Leave out the maker-edit errors
  // BREAKS: a modify that raced a fill, or that changed nothing, would report a
  //         generic failure instead of saying what happened
  test("recognizes the v2 maker-edit errors", () => {
    expect(decodeContractError("0xa88ee577").name).toBe("NoChange");
    expect(decodeContractError("0x457802f0" + pad(7))).toEqual({
      name: "OrderStateMismatch",
      message: "Order #7 changed while you were editing it. Refresh and try again.",
    });
  });

  // MUTATION: Drop the v1-only selectors when adding the v2 ones
  // BREAKS: v1 is the deployed, live version — its WETH errors would stop
  //         decoding for every user on mainnet
  test("still recognizes the v1-only WETH errors", () => {
    expect(decodeContractError("0x6bdafcae").name).toBe("ZeroETH");
    expect(decodeContractError("0xcfc02c6e").name).toBe("NotWETH");
    expect(decodeContractError("0x1c988062").name).toBe("ETHTransferFailed");
    expect(decodeContractError("0x8a8b41ec" + pad(0)).name).toBe("NotAContract");
  });

  // MUTATION: Omit DeadlineExpired from the table
  // BREAKS: A fill that sat too long in the mempool reports a generic failure
  test("recognizes DeadlineExpired", () => {
    expect(decodeContractError("0x1ab7da6b")).toEqual({
      name: "DeadlineExpired",
      message: "Transaction deadline passed. Please try again.",
    });
  });

  test("recognizes PermitOnNative", () => {
    expect(decodeContractError("0x62898bac")).toEqual({
      name: "PermitOnNative",
      message: "Cannot permit native ETH",
    });
  });

  test("recognizes InvalidPermit", () => {
    expect(decodeContractError("0xddafbaef")).toEqual({
      name: "InvalidPermit",
      message: "Permit signature is invalid",
    });
  });

  test("recognizes UnusedPermit", () => {
    expect(decodeContractError("0xb1df4e7e")).toEqual({
      name: "UnusedPermit",
      message: "Permit signature was not used in this transaction",
    });
  });

  test("recognizes DuplicatePermitToken", () => {
    expect(decodeContractError("0xc87bfe90")).toEqual({
      name: "DuplicatePermitToken",
      message: "Duplicate permit token",
    });
  });

  test("recognizes InvalidPermit2", () => {
    expect(decodeContractError("0x32d1c8da")).toEqual({
      name: "InvalidPermit2",
      message: "Permit2 signature is missing",
    });
  });

  test("recognizes UnusedPermit2", () => {
    expect(decodeContractError("0xc1abc68b")).toEqual({
      name: "UnusedPermit2",
      message: "Permit2 signature was not used in this transaction",
    });
  });

  test("recognizes TooManyPermit2", () => {
    expect(decodeContractError("0x35d2fb43")).toEqual({
      name: "TooManyPermit2",
      message: "Too many Permit2 entries (maximum 256)",
    });
  });

  test("recognizes SelfFill", () => {
    expect(decodeContractError("0x9d7a930f")).toEqual({
      name: "SelfFill",
      message: "You cannot fill your own order",
    });
  });

  test("recognizes NoChange", () => {
    expect(decodeContractError("0xa88ee577")).toEqual({
      name: "NoChange",
      message: "Nothing to change: the order already has these settings",
    });
  });

  // MUTATION: Return a partial object instead of null
  // BREAKS: An unknown revert renders as "undefined"
  test("returns null for input it cannot decode", () => {
    expect(decodeContractError("0xdeadbeef")).toBeNull();
    expect(decodeContractError("0x")).toBeNull();
    expect(decodeContractError("")).toBeNull();
    expect(decodeContractError(null)).toBeNull();
    expect(decodeContractError(undefined)).toBeNull();
    expect(decodeContractError(12345)).toBeNull();
  });

  // MUTATION: Lower-case only the table keys, not the input
  // BREAKS: A provider that upper-cases hex stops matching
  test("matches a selector case-insensitively", () => {
    expect(decodeContractError("0xD92E233D").name).toBe("ZeroAddress");
  });

  // MUTATION: Assume every selector maps to a template
  // BREAKS: Adding a signature without a message throws instead of degrading
  test("every known signature has a message", () => {
    for (const name of Object.values(ERROR_SIGNATURES)) {
      expect(ERROR_MESSAGES[name]).toBeDefined();
    }
  });
});

// ============================================================================
// decodeErrorArgs
// ============================================================================

describe("decodeErrorArgs", () => {
  const pad = (n) => n.toString(16).padStart(64, "0");

  // MUTATION: Read 32 hex characters per word instead of 64
  // BREAKS: Every decoded order id is wrong
  test("reads one bigint per 32-byte word", () => {
    expect(decodeErrorArgs("0xd2c02610" + pad(7))).toEqual([7n]);
    expect(decodeErrorArgs("0x98cd7222" + pad(1) + pad(2) + pad(3))).toEqual([1n, 2n, 3n]);
  });

  // MUTATION: Emit a trailing partial word
  // BREAKS: Truncated revert data yields a garbage final argument
  test("ignores a trailing partial word", () => {
    expect(decodeErrorArgs("0xd2c02610" + pad(7) + "abcd")).toEqual([7n]);
  });

  test("returns an empty list for an argument-free error", () => {
    expect(decodeErrorArgs("0xd92e233d")).toEqual([]);
  });

  // MUTATION: Let the BigInt conversion throw
  // BREAKS: Malformed revert data throws out of the error handler itself
  test("stops at the first word it cannot read", () => {
    const pad = (n) => n.toString(16).padStart(64, "0");
    expect(decodeErrorArgs("0xd2c02610" + pad(7) + "z".repeat(64))).toEqual([7n]);
    expect(decodeErrorArgs("0xd2c02610" + "z".repeat(64))).toEqual([]);
  });
});

// ============================================================================
// extractRevertData
// ============================================================================

describe("parseContractError data locations", () => {
  // MUTATION: Check only e.data
  // BREAKS: ethers v6 puts revert data in three different places depending on
  //         how the call failed; two of them stop being decoded
  test("finds revert data wherever the provider put it", () => {
    expect(parseContractError({ data: "0x98cd7222" })).toBe("You are not the maker of this order");
    expect(parseContractError({ error: { data: "0x98cd7222" } })).toBe(
      "You are not the maker of this order"
    );
    expect(parseContractError({ info: { error: { data: "0x98cd7222" } } })).toBe(
      "You are not the maker of this order"
    );
  });

  // MUTATION: Drop the message regex
  // BREAKS: Providers that only embed data in the message text lose it
  test('extracts revert data embedded in the message as data="0x..."', () => {
    const e = { message: 'execution reverted (data="0x1f2a2005", code=CALL_EXCEPTION)' };
    expect(parseContractError(e)).toBe("Amount too small (check decimal places)");
  });

  // MUTATION: Accept any string as revert data
  // BREAKS: A non-hex `data` field is fed to the decoder
  test("ignores a data field that is not hex", () => {
    expect(parseContractError({ data: "nope", message: "timeout" })).toBe(
      "Request timed out. Please try again."
    );
  });
});

// ============================================================================
// parseContractError
// ============================================================================

describe("parseContractError", () => {
  // MUTATION: Detect rejection by message text only
  // BREAKS: A wallet reporting code 4001 with terse wording is not recognized
  test("recognizes a user rejection by error code", () => {
    expect(parseContractError({ code: 4001, message: "denied" })).toBe("Transaction cancelled");
    expect(parseContractError({ code: "ACTION_REJECTED", message: "x" })).toBe(
      "Transaction cancelled"
    );
  });

  // MUTATION: Remove the text fallback for rejection
  // BREAKS: Wallets that set no code but say "user rejected" fall through
  test("recognizes a user rejection by message text", () => {
    expect(parseContractError({ message: "MetaMask Tx Signature: User rejected" })).toBe(
      "Transaction cancelled"
    );
    expect(parseContractError({ message: "User denied transaction signature" })).toBe(
      "Transaction cancelled"
    );
  });

  // MUTATION: Return a fixed string for execution reverted
  // BREAKS: A require() message from the chain is discarded
  test('surfaces a reason="..." string from the chain', () => {
    const e = { message: 'execution reverted (reason="Pausable: paused")' };
    expect(parseContractError(e)).toBe("Pausable: paused");
  });

  // MUTATION: Test "insufficient" before "allowance"
  // BREAKS: "ERC20: insufficient allowance" reports a balance problem instead
  //         of an approval one, sending the user to fix the wrong thing
  test("an allowance failure is not mistaken for a balance failure", () => {
    expect(parseContractError({ message: "ERC20: insufficient allowance" })).toBe(
      "Token approval failed"
    );
    expect(parseContractError({ message: "transfer amount exceeds balance" })).toBe(
      "Insufficient token balance"
    );
    expect(parseContractError({ message: "insufficient funds for gas * price" })).toBe(
      "Insufficient funds for transaction"
    );
  });

  // MUTATION: Drop individual entries from ERROR_PATTERNS
  // BREAKS: Recognizable provider failures degrade to a generic message
  test("maps provider failures to actionable text", () => {
    const cases = [
      ["nonce has already been used", "Transaction conflict, try again"],
      ["could not decode result data", "Token contract not found on this network"],
      ["missing revert data", "Transaction failed. Order may already be filled or cancelled."],
      ["gas estimation failed", "Transaction would fail. Check order status and try again."],
      ["network is disconnected", "Network error. Check your connection."],
      ["Request TIMEOUT after 30s", "Request timed out. Please try again."],
      ["replacement transaction underpriced", "Gas price too low. Try again with higher gas."],
      ["execution reverted", "Transaction failed. The order may no longer be available."],
    ];
    for (const [message, expected] of cases) {
      expect(parseContractError({ message })).toBe(expected);
    }
  });

  // MUTATION: Fall back to e.message
  // BREAKS: A multi-line ethers error with a docs URL lands in a toast
  test("never surfaces a raw technical message", () => {
    const e = {
      message:
        "cannot estimate gas; transaction may fail [ See: https://links.ethers.org/v5-errors ] (reason=null, code=UNPREDICTABLE_GAS_LIMIT)",
    };
    expect(parseContractError(e)).toBe("Transaction failed. Please try again.");
  });

  // MUTATION: Drop the length cap on shortMessage
  // BREAKS: An arbitrarily long "short" message is shown verbatim
  test("uses shortMessage only when it is short enough to read", () => {
    expect(parseContractError({ message: "zzz", shortMessage: "could not coalesce error" })).toBe(
      "could not coalesce error"
    );
    expect(parseContractError({ message: "zzz", shortMessage: "x".repeat(150) })).toBe(
      "Transaction failed. Please try again."
    );
  });

  // MUTATION: Check revert data after the text patterns
  // BREAKS: A decodable contract error is reported as a generic revert
  test("revert data wins over the message text", () => {
    const e = { data: "0xd2c02610" + "7".padStart(64, "0"), message: "execution reverted" };
    expect(parseContractError(e)).toMatch(/is no longer active/);
  });

  // MUTATION: Dereference e without a guard
  // BREAKS: Throws while handling an error, masking the original failure
  test("survives a missing or empty error object", () => {
    expect(parseContractError(null)).toBe("Transaction failed. Please try again.");
    expect(parseContractError(undefined)).toBe("Transaction failed. Please try again.");
    expect(parseContractError({})).toBe("Transaction failed. Please try again.");
  });
});

// ============================================================================
// validateConfig
// ============================================================================

describe("validateConfig", () => {
  // MUTATION: Validate even in local mode
  // BREAKS: Local development requires real config
  test("skips validation in local mode", () => {
    const result = validateConfig(
      { CONTRACT_ADDRESS: "0x0000000000000000000000000000000000000000" },
      true
    );
    expect(result.valid).toBe(true);
  });

  // MUTATION: Accept zero address
  // BREAKS: Transactions would go to zero address
  test("rejects zero address for contract", () => {
    const result = validateConfig(
      {
        CONTRACT_ADDRESS: "0x0000000000000000000000000000000000000000",
        SUBGRAPH_URL: "https://valid.url",
      },
      false
    );
    expect(result.valid).toBe(false);
    expect(result.errors).toContain("CONTRACT_ADDRESS is not configured");
  });

  // MUTATION: Accept YOUR_ID placeholder
  // BREAKS: Subgraph queries would 404
  test("rejects placeholder in subgraph URL", () => {
    const result = validateConfig(
      {
        CONTRACT_ADDRESS: "0x1234567890123456789012345678901234567890",
        SUBGRAPH_URL: "https://api.thegraph.com/YOUR_ID/subgraph",
      },
      false
    );
    expect(result.valid).toBe(false);
    expect(result.errors).toContain("SUBGRAPH_URL is not configured");
  });

  // MUTATION: Only report first error
  // BREAKS: User fixes one issue, still broken
  test("reports all errors at once", () => {
    const result = validateConfig(
      {
        CONTRACT_ADDRESS: "0x0000000000000000000000000000000000000000",
        SUBGRAPH_URL: "https://YOUR_ID/subgraph",
      },
      false
    );
    expect(result.errors.length).toBe(2);
  });

  // MUTATION: Return invalid for valid config
  // BREAKS: Production deployment blocked
  test("accepts valid configuration", () => {
    const result = validateConfig(
      {
        CONTRACT_ADDRESS: "0x1234567890123456789012345678901234567890",
        SUBGRAPH_URL: "https://api.goldsky.com/valid/subgraph",
      },
      false
    );
    expect(result.valid).toBe(true);
    expect(result.errors).toEqual([]);
  });
});

// ============================================================================
// V2: Native ETH
// ============================================================================

describe("isNativeEth", () => {
  // MUTATION: Compare without lowercasing
  // BREAKS: Checksummed sentinel from the UI stops matching a lowercased one
  test("matches the sentinel regardless of case", () => {
    expect(isNativeEth(NATIVE_ETH)).toBe(true);
    expect(isNativeEth(NATIVE_ETH.toLowerCase())).toBe(true);
    expect(isNativeEth(NATIVE_ETH.toUpperCase())).toBe(true);
  });

  // MUTATION: Treat any address as native ETH
  // BREAKS: WETH orders lose their contract link and approval step
  test("rejects other addresses", () => {
    expect(isNativeEth("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2")).toBe(false);
    expect(isNativeEth("0x0000000000000000000000000000000000000000")).toBe(false);
  });

  // MUTATION: Skip the type guard
  // BREAKS: Throws on an order with a missing token address
  test("rejects non-strings", () => {
    expect(isNativeEth(null)).toBe(false);
    expect(isNativeEth(undefined)).toBe(false);
    expect(isNativeEth(123)).toBe(false);
  });
});

// ============================================================================
// V2: Batching
// ============================================================================

describe("chunkArray", () => {
  // MUTATION: Off-by-one on chunk size
  // BREAKS: A transaction exceeds the gas limit and reverts
  test("splits into chunks of exactly the requested size", () => {
    expect(chunkArray([1, 2, 3, 4, 5], 2)).toEqual([[1, 2], [3, 4], [5]]);
  });

  // MUTATION: Drop the trailing partial chunk
  // BREAKS: Orders silently never get filled
  test("keeps the remainder", () => {
    expect(chunkArray([1, 2, 3, 4, 5, 6, 7], 3).flat()).toEqual([1, 2, 3, 4, 5, 6, 7]);
  });

  test("returns a single chunk when it fits", () => {
    expect(chunkArray([1, 2, 3], 10)).toEqual([[1, 2, 3]]);
  });

  test("returns no chunks for an empty list", () => {
    expect(chunkArray([], 5)).toEqual([]);
  });

  // MUTATION: Allow size 0
  // BREAKS: Infinite loop hangs the tab
  test("rejects unusable sizes", () => {
    expect(chunkArray([1, 2, 3], 0)).toEqual([]);
    expect(chunkArray([1, 2, 3], -1)).toEqual([]);
    expect(chunkArray([1, 2, 3], 1.5)).toEqual([]);
  });

  test("rejects non-arrays", () => {
    expect(chunkArray(null, 5)).toEqual([]);
    expect(chunkArray("abc", 5)).toEqual([]);
  });
});

// ============================================================================
// V2: Multi-select rules
// ============================================================================

const USER = "0xAAAAaaaAAAAaaAAAaAAaAaaAaaAaaAAAaaAaAAaA";
const OTHER = "0xBBBbbbBBbbbBBBbBbbbbbBBbBbbBBBbBBbBbbBBb";

function makeOrder(overrides) {
  const base = Object.assign(
    {
      orderId: "1",
      maker: OTHER,
      active: true,
      status: "OPEN",
      partialFillAllowed: false,
      amountA: "1000",
      amountB: "2000",
      tokenA: { address: "0xAAA0000000000000000000000000000000000001", symbol: "A", decimals: 18 },
      tokenB: { address: "0xBBB0000000000000000000000000000000000002", symbol: "B", decimals: 18 },
    },
    overrides
  );
  // Remaining defaults to the whole order unless a test is specifically about
  // a part-filled one, so overriding amountA alone does not imply a fill.
  if (base.availableA === undefined) base.availableA = base.amountA;
  if (base.availableB === undefined) base.availableB = base.amountB;
  return base;
}

describe("resolveSelectionMode", () => {
  // MUTATION: Compare addresses without lowercasing
  // BREAKS: Own orders classified as other people's -> Fill All on your own order
  test("classifies own orders case-insensitively", () => {
    const order = makeOrder({ maker: USER.toLowerCase() });
    expect(resolveSelectionMode(order, USER)).toBe("own");
  });

  test("classifies other makers' orders", () => {
    expect(resolveSelectionMode(makeOrder(), USER)).toBe("other");
  });

  // MUTATION: Return "own" when disconnected
  // BREAKS: Disconnected user offered [Cancel All] on strangers' orders
  test("treats every order as someone else's when disconnected", () => {
    expect(resolveSelectionMode(makeOrder({ maker: USER }), null)).toBe("other");
  });

  test("returns null for an unusable order", () => {
    expect(resolveSelectionMode(null, USER)).toBe(null);
    expect(resolveSelectionMode({}, USER)).toBe(null);
  });
});

describe("isSamePair", () => {
  test("matches identical pairs case-insensitively", () => {
    const a = makeOrder();
    const b = makeOrder({
      orderId: "2",
      tokenA: { address: a.tokenA.address.toLowerCase(), symbol: "A", decimals: 18 },
      tokenB: { address: a.tokenB.address.toUpperCase(), symbol: "B", decimals: 18 },
    });
    expect(isSamePair(a, b)).toBe(true);
  });

  // MUTATION: Ignore direction
  // BREAKS: A reversed pair joins the batch, so totals and price are nonsense
  test("treats a reversed pair as different", () => {
    const a = makeOrder();
    const b = makeOrder({ orderId: "2", tokenA: a.tokenB, tokenB: a.tokenA });
    expect(isSamePair(a, b)).toBe(false);
  });

  test("returns false when token data is missing", () => {
    expect(isSamePair(makeOrder(), null)).toBe(false);
    expect(isSamePair(makeOrder(), { tokenA: null, tokenB: null })).toBe(false);
  });
});

describe("canSelectOrder", () => {
  // MUTATION: Allow closed orders
  // BREAKS: Batch includes unfillable orders and wastes gas
  test("rejects closed orders", () => {
    expect(canSelectOrder(makeOrder({ active: false }), null, USER)).toBe(false);
  });

  test("allows any open order as the first pick", () => {
    expect(canSelectOrder(makeOrder(), null, USER)).toBe(true);
    expect(canSelectOrder(makeOrder({ maker: USER }), null, USER)).toBe(true);
  });

  test("allows re-selecting the anchor itself", () => {
    const anchor = makeOrder();
    expect(canSelectOrder(anchor, anchor, USER)).toBe(true);
  });

  // MUTATION: Permit mixing own and other orders
  // BREAKS: [Fill All] and [Cancel All] both apply and the batch is ambiguous
  test("refuses to mix own orders with other makers' orders", () => {
    const mine = makeOrder({ orderId: "1", maker: USER });
    const theirs = makeOrder({ orderId: "2", maker: OTHER });
    expect(canSelectOrder(theirs, mine, USER)).toBe(false);
    expect(canSelectOrder(mine, theirs, USER)).toBe(false);
  });

  // MUTATION: Enforce the pair check on own orders too
  // BREAKS: Cancel All can't span pairs, which the spec allows
  test("allows own orders across different pairs", () => {
    const mine = makeOrder({ orderId: "1", maker: USER });
    const otherPair = makeOrder({
      orderId: "2",
      maker: USER,
      tokenA: { address: "0xCCC0000000000000000000000000000000000003", symbol: "C", decimals: 6 },
    });
    expect(canSelectOrder(otherPair, mine, USER)).toBe(true);
  });

  // MUTATION: Skip the pair check on other makers' orders
  // BREAKS: Fill All batches mixed pairs, so one approval can't cover it
  test("locks other makers' orders to a single pair", () => {
    const anchor = makeOrder({ orderId: "1" });
    const samePair = makeOrder({ orderId: "2" });
    const otherPair = makeOrder({
      orderId: "3",
      tokenB: { address: "0xCCC0000000000000000000000000000000000003", symbol: "C", decimals: 6 },
    });
    expect(canSelectOrder(samePair, anchor, USER)).toBe(true);
    expect(canSelectOrder(otherPair, anchor, USER)).toBe(false);
  });

  test("rejects a missing order", () => {
    expect(canSelectOrder(null, null, USER)).toBe(false);
  });
});

describe("getShiftRangeIds", () => {
  const orders = [
    makeOrder({ orderId: "1" }),
    makeOrder({ orderId: "2" }),
    makeOrder({ orderId: "3", active: false }),
    makeOrder({ orderId: "4", maker: USER }),
    makeOrder({ orderId: "5" }),
  ];

  // MUTATION: Exclusive range
  // BREAKS: The shift-clicked row itself is left unselected
  test("includes both endpoints", () => {
    expect(getShiftRangeIds(orders, "1", "2", orders[0], USER)).toEqual(["1", "2"]);
  });

  // MUTATION: Only walk forwards
  // BREAKS: Shift-clicking upwards selects nothing
  test("works in either direction", () => {
    expect(getShiftRangeIds(orders, "5", "1", orders[0], USER)).toEqual(
      getShiftRangeIds(orders, "1", "5", orders[0], USER)
    );
  });

  // MUTATION: Skip the per-order validity check
  // BREAKS: Closed and own orders get swept into a Fill All batch
  test("skips orders that fail the selection rules", () => {
    expect(getShiftRangeIds(orders, "1", "5", orders[0], USER)).toEqual(["1", "2", "5"]);
  });

  test("returns nothing when an endpoint is not on screen", () => {
    expect(getShiftRangeIds(orders, "1", "99", orders[0], USER)).toEqual([]);
    expect(getShiftRangeIds(orders, "99", "1", orders[0], USER)).toEqual([]);
  });

  test("returns nothing for a non-array", () => {
    expect(getShiftRangeIds(null, "1", "2", null, USER)).toEqual([]);
  });
});

// ============================================================================
// V2: Partial fill math
// ============================================================================

describe("quoteFill", () => {
  const order = { availableA: "1000", availableB: "2000" };

  // MUTATION: Ceil the proportion instead of flooring it
  // BREAKS: The quote promises more tokenA than the contract pays, and the
  // fill reverts with FillAmountMismatch
  test("floors a partial proportion, in the maker's favour", () => {
    // 1 of 2 at 3:2 -> 1.5, floored to 1
    expect(quoteFill({ availableA: "3", availableB: "2" }, 1n)).toBe(1n);
    // 3 * 1000 / 2000 = 1.5 -> 1
    expect(quoteFill(order, 3n)).toBe(1n);
    expect(quoteFill(order, 1000n)).toBe(500n);
  });

  test("paying the whole remainder takes exactly the remainder", () => {
    expect(quoteFill(order, 2000n)).toBe(1000n);
  });

  // MUTATION: Clamp an over-large payment to the remainder
  // BREAKS: The UI quotes a fill the contract rejects with FillAmountTooHigh
  test("quotes zero for a payment larger than the order", () => {
    expect(quoteFill(order, 2001n)).toBe(0n);
  });

  test("returns zero for an empty payment or an exhausted order", () => {
    expect(quoteFill(order, 0n)).toBe(0n);
    expect(quoteFill(order, -5n)).toBe(0n);
    expect(quoteFill({ availableA: "0", availableB: "0" }, 10n)).toBe(0n);
    expect(quoteFill({ availableA: "0", availableB: "1000" }, 10n)).toBe(0n);
  });

  // The contract reverts ZeroAmount on a quote of 0, so the UI must see it too.
  test("returns zero for a payment too small to earn a base unit", () => {
    expect(quoteFill({ availableA: "1", availableB: "1000" }, 999n)).toBe(0n);
  });

  // The formula this has to match, spelled out. If Swapboard._quoteFill ever
  // changes, this is the test that should fail first.
  test("agrees with the contract's floor division across the range", () => {
    const o = { availableA: "1301", availableB: "997" };
    for (let pay = 1n; pay < 997n; pay += 37n) {
      expect(quoteFill(o, pay)).toBe((pay * 1301n) / 997n);
    }
  });
});

describe("computeFillFromReceive", () => {
  const order = { availableA: "1000", availableB: "2000" };

  test("returns the pair of values a fill is submitted with", () => {
    expect(computeFillFromReceive(order, 500n)).toEqual({ amountB: 1000n, minAmountA: 500n });
  });

  // MUTATION: Floor the payment
  // BREAKS: The fill pays out less than the taker asked for
  test("rounds the payment up so the request is covered", () => {
    // 1 of 3 at 3:2 -> pay 2/3, ceiled to 1, which buys floor(1.5) = 1
    const odd = { availableA: "3", availableB: "2" };
    expect(computeFillFromReceive(odd, 1n)).toEqual({ amountB: 1n, minAmountA: 1n });
  });

  // MUTATION: Return the typed amount as minAmountA instead of the quote
  // BREAKS: The UI shows less than the fill will actually pay out
  test("reports the contract's quote, which can exceed the request", () => {
    // 2 of 3 at 3:2 -> pay 4/3, ceiled to 2: the whole remainder, so all 3
    const odd = { availableA: "3", availableB: "2" };
    expect(computeFillFromReceive(odd, 2n)).toEqual({ amountB: 2n, minAmountA: 3n });
  });

  test("pays the least tokenB that covers the request", () => {
    const o = { availableA: "997", availableB: "1301" };
    for (let want = 1n; want <= 997n; want += 41n) {
      const { amountB, minAmountA } = computeFillFromReceive(o, want);
      expect(minAmountA).toBe(quoteFill(o, amountB));
      expect(minAmountA).toBeGreaterThanOrEqual(want);
      expect(quoteFill(o, amountB - 1n)).toBeLessThan(want);
    }
  });

  // MUTATION: Pass the request through unclamped
  // BREAKS: FillAmountTooHigh, on an order that shrank under an open modal
  test("clamps a request larger than the order to what is left", () => {
    expect(computeFillFromReceive(order, 1000n)).toEqual({ amountB: 2000n, minAmountA: 1000n });
    expect(computeFillFromReceive(order, 5000n)).toEqual({ amountB: 2000n, minAmountA: 1000n });
  });

  test("returns zero for a zero or negative request", () => {
    expect(computeFillFromReceive(order, 0n)).toEqual({ amountB: 0n, minAmountA: 0n });
    expect(computeFillFromReceive(order, -1n)).toEqual({ amountB: 0n, minAmountA: 0n });
  });

  // MUTATION: Divide without guarding
  // BREAKS: Division by zero on an exhausted order
  test("returns zero on an empty order", () => {
    expect(computeFillFromReceive({ availableA: "0", availableB: "0" }, 10n)).toEqual({
      amountB: 0n,
      minAmountA: 0n,
    });
    expect(computeFillFromReceive({ availableA: "1000", availableB: "0" }, 10n)).toEqual({
      amountB: 0n,
      minAmountA: 0n,
    });
  });
});

describe("computeFillFromPayment", () => {
  const order = { availableA: "1000", availableB: "2000" };

  test("returns the receive and the exact payment", () => {
    expect(computeFillFromPayment(order, 1000n)).toEqual({ amountA: 500n, amountB: 1000n });
  });

  // MUTATION: Round the receive up
  // BREAKS: The UI promises tokenA the contract will not pay out
  test("floors the receive the way the contract will", () => {
    const odd = { availableA: "2", availableB: "3" };
    expect(computeFillFromPayment(odd, 2n)).toEqual({ amountA: 1n, amountB: 2n });
  });

  // MUTATION: Pass the payment through unclamped
  // BREAKS: FillAmountTooHigh, on an order that shrank under an open modal
  test("clamps a payment larger than the order to what is left", () => {
    expect(computeFillFromPayment(order, 2000n)).toEqual({ amountA: 1000n, amountB: 2000n });
    expect(computeFillFromPayment(order, 5000n)).toEqual({ amountA: 1000n, amountB: 2000n });
  });

  // MUTATION: Report the payment's receive as at least 1
  // BREAKS: The controls would offer a fill the contract rejects with ZeroAmount
  test("reports no receive for a payment too small to buy one base unit", () => {
    expect(computeFillFromPayment({ availableA: "1", availableB: "3" }, 1n)).toEqual({
      amountA: 0n,
      amountB: 1n,
    });
  });

  test("returns zero for a zero or negative payment", () => {
    expect(computeFillFromPayment(order, 0n)).toEqual({ amountA: 0n, amountB: 0n });
    expect(computeFillFromPayment(order, -1n)).toEqual({ amountA: 0n, amountB: 0n });
  });
});

describe("allowsPartialFill", () => {
  // MUTATION: Treat a missing flag as permission
  // BREAKS: Partial-fill controls appear on an all-or-nothing order, and every
  // fill from them reverts with PartialFillNotAllowed
  test("only a flag set to true allows a partial fill", () => {
    expect(allowsPartialFill({ partialFillAllowed: true })).toBe(true);
    expect(allowsPartialFill({ partialFillAllowed: false })).toBe(false);
    expect(allowsPartialFill({})).toBe(false);
    expect(allowsPartialFill(null)).toBe(false);
  });
});

describe("summarizeFillBatch", () => {
  const pair = {
    tokenA: { address: "0xA", symbol: "A", decimals: 18 },
    tokenB: { address: "0xB", symbol: "B", decimals: 18 },
  };
  const batch = [
    Object.assign({ availableA: "1000000000000000000", availableB: "2000000000000000000" }, pair),
    Object.assign({ availableA: "3000000000000000000", availableB: "6000000000000000000" }, pair),
  ];

  // MUTATION: Sum only the first order
  // BREAKS: Confirmation understates what the user is about to spend
  test("sums both sides across the batch", () => {
    const result = summarizeFillBatch(batch);
    expect(result.count).toBe(2);
    expect(result.totalSend).toBe(8000000000000000000n);
    expect(result.totalReceive).toBe(4000000000000000000n);
  });

  // MUTATION: Average the per-order prices instead of dividing the totals
  // BREAKS: Average price misreports a batch of unequal sizes
  test("prices the batch as a whole", () => {
    expect(summarizeFillBatch(batch).avgPrice).toBe(2);
  });

  // MUTATION: Ignore decimals
  // BREAKS: Price is off by orders of magnitude on mixed-decimal pairs
  test("accounts for differing token decimals", () => {
    const mixed = [
      {
        availableA: "1000000000000000000", // 1.0 (18dp)
        availableB: "3000000", // 3.0 (6dp)
        tokenA: { address: "0xA", symbol: "A", decimals: 18 },
        tokenB: { address: "0xB", symbol: "B", decimals: 6 },
      },
    ];
    expect(summarizeFillBatch(mixed).avgPrice).toBe(3);
  });

  test("returns an empty summary for no orders", () => {
    expect(summarizeFillBatch([])).toEqual({
      count: 0,
      totalSend: 0n,
      totalReceive: 0n,
      avgPrice: null,
    });
    expect(summarizeFillBatch(null).count).toBe(0);
  });

  // MUTATION: Divide without guarding
  // BREAKS: NaN price shown when there is nothing to receive
  test("reports no price when there is nothing to receive", () => {
    const empty = [Object.assign({ availableA: "0", availableB: "100" }, pair)];
    expect(summarizeFillBatch(empty).avgPrice).toBe(null);
  });
});

// ============================================================================
// Protocol version
// ============================================================================

describe("parseVersion", () => {
  // MUTATION: Return the raw value instead of a number
  // BREAKS: VERSION_CAPS lookups are keyed by number and would all miss
  test("coerces numeric strings to numbers", () => {
    expect(parseVersion("1")).toBe(1);
    expect(parseVersion("2")).toBe(2);
    expect(parseVersion(2)).toBe(2);
  });

  // MUTATION: Drop the leading-v strip
  // BREAKS: ?v=v2 — the form users actually type — silently falls back to v1
  test("accepts a leading v, in either case", () => {
    expect(parseVersion("v2")).toBe(2);
    expect(parseVersion("V1")).toBe(1);
    expect(parseVersion(" v2 ")).toBe(2);
  });

  // MUTATION: Skip the SUPPORTED_VERSIONS check
  // BREAKS: ?v=3 yields capsFor(3), and every capability reads undefined
  test("rejects unsupported and unparseable values", () => {
    expect(parseVersion("3")).toBe(null);
    expect(parseVersion("0")).toBe(null);
    expect(parseVersion("banana")).toBe(null);
    expect(parseVersion("")).toBe(null);
    expect(parseVersion(null)).toBe(null);
    expect(parseVersion(undefined)).toBe(null);
  });
});

describe("resolveVersion", () => {
  // MUTATION: Change DEFAULT_VERSION to 2
  // BREAKS: a first-time visitor lands on the version whose subgraph query
  //         errors out and whose contracts are not deployed
  test("defaults to v1 when nothing selects a version", () => {
    expect(resolveVersion({})).toEqual({ version: 1, pinned: false });
    expect(resolveVersion()).toEqual({ version: 1, pinned: false });
    expect(DEFAULT_VERSION).toBe(1);
  });

  // MUTATION: Check localStorage before the URL parameter
  // BREAKS: a shared ?v=2 link opens on whatever the recipient last chose
  test("the URL parameter outranks the stored preference", () => {
    expect(resolveVersion({ search: "?v=2", stored: "1" })).toEqual({
      version: 2,
      pinned: true,
    });
    expect(resolveVersion({ search: "?v=1", stored: "2" })).toEqual({
      version: 1,
      pinned: true,
    });
  });

  // MUTATION: Ignore the stored value
  // BREAKS: the switcher appears not to stick — every reload reverts to v1
  test("falls back to the stored preference", () => {
    expect(resolveVersion({ stored: "2" })).toEqual({ version: 2, pinned: false });
    expect(resolveVersion({ search: "?other=1", stored: "2" }).version).toBe(2);
  });

  // MUTATION: Trust the stored value without parsing
  // BREAKS: corrupted storage pins the app to a version that does not exist
  test("ignores an unusable stored value", () => {
    expect(resolveVersion({ stored: "banana" }).version).toBe(1);
    expect(resolveVersion({ stored: "9" }).version).toBe(1);
  });

  // MUTATION: Let the URLSearchParams throw escape
  // BREAKS: a malformed query string takes down startup before first render
  test("survives a search string it cannot parse", () => {
    const Orig = URLSearchParams;
    global.URLSearchParams = class {
      constructor() {
        throw new TypeError("bad search");
      }
    };
    try {
      expect(resolveVersion({ search: "?v=1", stored: "2" })).toEqual({
        version: 2,
        pinned: false,
      });
    } finally {
      global.URLSearchParams = Orig;
    }
  });

  test("exposes the storage key it resolves against", () => {
    expect(VERSION_STORAGE_KEY).toBe("swapboard_version");
    expect(SUPPORTED_VERSIONS).toEqual([1, 2]);
  });
});

describe("capsFor", () => {
  // MUTATION: Swap which version claims batch/partialFill
  // BREAKS: v1 renders batch controls for entry points its contract lacks
  test("v1 has none of the v2 features", () => {
    const v1 = capsFor(1);
    expect(v1.partialFill).toBe(false);
    expect(v1.batch).toBe(false);
    expect(v1.nativeEth).toBe(false);
    expect(v1.multiCreate).toBe(false);
    expect(v1.remainingAmounts).toBe(false);
  });

  // MUTATION: Turn either version's gas estimates or subgraph polling off
  // BREAKS: the modal loses a figure its real ABI can price, or a transaction
  //         reloads the table before the subgraph has indexed it
  test("both versions estimate gas and poll a subgraph", () => {
    expect(capsFor(1).gasEstimate).toBe(true);
    expect(capsFor(1).subgraphPolling).toBe(true);
    expect(capsFor(2).gasEstimate).toBe(true);
    expect(capsFor(2).subgraphPolling).toBe(true);
  });

  // MUTATION: Mark either version as not live
  // BREAKS: validateConfig stops demanding deployment coordinates for a version
  //         that has them, so a bad deploy ships unnoticed
  test("both versions are live", () => {
    expect(capsFor(1).live).toBe(true);
    expect(capsFor(2).live).toBe(true);
  });

  // MUTATION: Offer permit on v1
  // BREAKS: v1 has no permit overloads, so the call would be encoded against a
  //         signature its ABI does not carry
  test("only v2 can settle an approval by signature", () => {
    expect(capsFor(1).permit).toBe(false);
    expect(capsFor(2).permit).toBe(true);
  });

  // MUTATION: Return undefined for an unknown version
  // BREAKS: every `CAPS.x` read throws instead of degrading to v1
  test("falls back to the default version's capabilities", () => {
    expect(capsFor(99)).toBe(VERSION_CAPS[DEFAULT_VERSION]);
    expect(capsFor(undefined)).toBe(VERSION_CAPS[DEFAULT_VERSION]);
  });
});

describe("deploymentFor", () => {
  // MUTATION: Return the same contract address for both versions
  // BREAKS: one version signs transactions against the other's contract
  test("each version resolves its own deployment", () => {
    const v1 = deploymentFor(1);
    const v2 = deploymentFor(2);
    expect(v1.CONTRACT_ADDRESS).toBe(VERSION_CAPS[1].contractAddress);
    expect(v1.SUBGRAPH_URL).toBe(VERSION_CAPS[1].subgraphUrl);
    expect(v2.CONTRACT_ADDRESS).toBe(VERSION_CAPS[2].contractAddress);
    expect(v2.SUBGRAPH_URL).toBe(VERSION_CAPS[2].subgraphUrl);
  });

  // MUTATION: Let the two versions share a contract address or subgraph URL
  // BREAKS: this is the whole point of the split — deploy.sh patches one slot
  //         per release, and a shared value means shipping v2 repoints v1
  test("the versions never share a deployment", () => {
    expect(deploymentFor(1).CONTRACT_ADDRESS).not.toBe(deploymentFor(2).CONTRACT_ADDRESS);
    expect(deploymentFor(1).SUBGRAPH_URL).not.toBe(deploymentFor(2).SUBGRAPH_URL);
  });

  // MUTATION: Drop the deploy: markers, or reflow them onto their own line
  // BREAKS: deploy.sh anchors its rewrite on them and refuses to write without
  //         them, so a release fails rather than silently patching nothing
  test("both versions carry a real deployment", () => {
    for (const version of [1, 2]) {
      expect(deploymentFor(version).CONTRACT_ADDRESS).toMatch(/^0x[a-fA-F0-9]{40}$/);
      expect(deploymentFor(version).CONTRACT_ADDRESS).not.toBe(
        "0x0000000000000000000000000000000000000000"
      );
      expect(deploymentFor(version).SUBGRAPH_URL).toMatch(/^https:\/\//);
    }
  });

  // MUTATION: Return the same deployment for both versions
  // BREAKS: one version silently points at the other's contract, and orders are
  //         read from a board they were never created on
  test("the two versions point at different contracts", () => {
    expect(deploymentFor(1).CONTRACT_ADDRESS).not.toBe(deploymentFor(2).CONTRACT_ADDRESS);
    expect(deploymentFor(1).SUBGRAPH_URL).not.toBe(deploymentFor(2).SUBGRAPH_URL);
  });

  // MUTATION: Return undefined for an unknown version
  // BREAKS: destructuring CONTRACT_ADDRESS off it throws at startup
  test("falls back to the default version's deployment", () => {
    expect(deploymentFor(99)).toEqual(deploymentFor(DEFAULT_VERSION));
  });
});

describe("orderQuerySelection", () => {
  // MUTATION: Include a v2 field in the v1 selection
  // BREAKS: the deployed v1 subgraph errors on the unknown field and returns no
  //         orders at all — graph-node rejects the whole query, not just the field
  test("omits every v2-only field on v1", () => {
    const selection = orderQuerySelection(1);
    for (const field of ["availableA", "availableB", "partialFillAllowed", "status", "fills"]) {
      expect(selection).not.toContain(field);
    }
  });

  // MUTATION: Drop a v2 field
  // BREAKS: partial-fill progress silently stops rendering on v2
  test("requests the v2-only fields on v2", () => {
    const selection = orderQuerySelection(2);
    for (const field of ["availableA", "availableB", "partialFillAllowed", "status"]) {
      expect(selection).toContain(field);
    }
  });

  // MUTATION: Select `maker` as a scalar on v2
  // BREAKS: maker is an Account entity there, so the query is rejected outright
  test("v2 selects maker as a relation and v1 as a scalar", () => {
    expect(orderQuerySelection(2)).toMatch(/maker \{\s*\n\s*id\s*\n\s*\}/);
    expect(orderQuerySelection(1)).toMatch(/^maker$/m);
  });

  // MUTATION: Ask v2 for `taker` on the order
  // BREAKS: v2 moved the taker onto Fill, so the field does not exist and the
  //         whole order list comes back empty
  test("only v1 asks the order for a taker", () => {
    expect(orderQuerySelection(1)).toMatch(/^taker$/m);
    expect(orderQuerySelection(2)).not.toMatch(/^taker$/m);
    expect(orderQuerySelection(2)).toContain("fills(");
  });

  // MUTATION: Drop a shared field from one branch
  // BREAKS: a column renders blank in exactly one version
  test("both versions request every shared field", () => {
    const shared = ["orderId", "amountA", "amountB", "active", "createdAt", "filledAt"];
    for (const field of shared) {
      expect(orderQuerySelection(1)).toContain(field);
      expect(orderQuerySelection(2)).toContain(field);
    }
  });

  // MUTATION: Omit the token sub-selections
  // BREAKS: every row loses its symbols and decimals, and formatAmount throws
  test("both versions select both tokens with symbol and decimals", () => {
    for (const version of [1, 2]) {
      const selection = orderQuerySelection(version);
      expect(selection).toContain("tokenA {");
      expect(selection).toContain("tokenB {");
      expect(selection).toContain("decimals");
      expect(selection).toContain("symbol");
    }
  });
});

describe("statusFilterCondition", () => {
  // MUTATION: Use the v1 taker conditions on v2
  // BREAKS: `taker` does not exist on a v2 order, so filtering to Filled or
  //         Cancelled returns nothing instead of a filtered list
  test("v2 filters on the status enum", () => {
    expect(statusFilterCondition(2, "filled")).toBe("status: FILLED");
    expect(statusFilterCondition(2, "cancelled")).toBe("status: CANCELED");
  });

  // MUTATION: Use the v2 enum on v1
  // BREAKS: the deployed subgraph has no status field, so the query is rejected
  test("v1 infers the state from active and taker", () => {
    expect(statusFilterCondition(1, "filled")).toBe("active: false, taker_not: null");
    expect(statusFilterCondition(1, "cancelled")).toBe("active: false, taker: null");
  });

  test("both versions filter open orders on active", () => {
    expect(statusFilterCondition(1, "open")).toBe("active: true");
    expect(statusFilterCondition(2, "open")).toBe("active: true");
  });

  // MUTATION: Return a condition for the client-side filters
  // BREAKS: "watched" and "all" would be sent to the subgraph as a field name
  test("client-side filters add no condition", () => {
    for (const version of [1, 2]) {
      expect(statusFilterCondition(version, "watched")).toBe(null);
      expect(statusFilterCondition(version, "all")).toBe(null);
      expect(statusFilterCondition(version, "")).toBe(null);
    }
  });
});

describe("statsQuerySelection / normalizeStats", () => {
  // MUTATION: Ask v2 for activeOrders / cancelledOrders
  // BREAKS: v2 renamed both, so the stats query is rejected and every tile
  //         stays on its placeholder
  test("each version asks for the counters it actually has", () => {
    expect(statsQuerySelection(1)).toContain("activeOrders");
    expect(statsQuerySelection(1)).toContain("cancelledOrders");
    expect(statsQuerySelection(2)).toContain("openOrders");
    expect(statsQuerySelection(2)).toContain("canceledOrders");
    expect(statsQuerySelection(2)).not.toContain("activeOrders");
    expect(statsQuerySelection(1)).not.toContain("openOrders");
  });

  test("normalizes both spellings onto the same four tiles", () => {
    expect(
      normalizeStats(
        {
          totalOrders: "10",
          activeOrders: "4",
          filledOrders: "3",
          cancelledOrders: "3",
        },
        1
      )
    ).toEqual({ total: "10", open: "4", filled: "3", cancelled: "3" });

    expect(
      normalizeStats(
        {
          totalOrders: "10",
          openOrders: "4",
          partiallyFilledOrders: "1",
          filledOrders: "3",
          canceledOrders: "3",
        },
        2
      )
    ).toEqual({ total: "10", open: "4", filled: "3", cancelled: "3" });
  });

  // MUTATION: Return zeroed counters instead of null
  // BREAKS: a failed stats query would render as a board with nothing on it,
  //         rather than leaving the previous values in place
  test("reports nothing when the query returned nothing", () => {
    expect(normalizeStats(null, 1)).toBe(null);
    expect(normalizeStats(undefined, 2)).toBe(null);
  });

  // MUTATION: Drop the "0" fallbacks
  // BREAKS: formatNumber(undefined) renders "undefined" in a stat tile
  test("missing counters read as zero", () => {
    expect(normalizeStats({}, 1)).toEqual({
      total: "0",
      open: "0",
      filled: "0",
      cancelled: "0",
    });
    expect(normalizeStats({}, 2)).toEqual({
      total: "0",
      open: "0",
      filled: "0",
      cancelled: "0",
    });
  });
});

describe("popularPairsQuery", () => {
  // MUTATION: Use one root field for both versions
  // BREAKS: Popular Pairs is permanently stuck on "No popular pairs yet" in
  //         whichever version got the other's entity name
  test("each version names its own entity and counter", () => {
    expect(popularPairsQuery(1)).toEqual({ root: "pairStats_collection", orderBy: "tradeCount" });
    expect(popularPairsQuery(2)).toEqual({ root: "pairs", orderBy: "fillCount" });
  });
});

describe("normalizeOrder", () => {
  // MUTATION: Leave availableA undefined on v1
  // BREAKS: renderOrders calls BigInt(undefined) and throws mid-render
  test("backfills the remaining amounts a v1 subgraph never returns", () => {
    const order = normalizeOrder({ amountA: "100", amountB: "250", active: true }, 1);
    expect(order.availableA).toBe("100");
    expect(order.availableB).toBe("250");
    expect(order.partialFillAllowed).toBe(false);
  });

  // MUTATION: Set the remainder to something other than the whole amount
  // BREAKS: every v1 order renders a bogus "of X left" partial-fill hint,
  //         since that hint shows exactly when the original exceeds the remainder
  test("a v1 order reads as untouched, never partly filled", () => {
    const order = normalizeOrder({ amountA: "100", amountB: "250", active: true }, 1);
    expect(BigInt(order.availableA)).toBe(BigInt(order.amountA));
    expect(BigInt(order.availableB)).toBe(BigInt(order.amountB));
  });

  // MUTATION: Derive v1 status from `active` alone
  // BREAKS: cancelled orders report as filled, and the watch list fires a
  //         "your order was filled" notification for an order that was not
  test("derives a v1 order's status from active and taker", () => {
    expect(normalizeOrder({ active: true, taker: null }, 1).status).toBe(ORDER_STATUS.OPEN);
    expect(normalizeOrder({ active: false, taker: "0xabc" }, 1).status).toBe(ORDER_STATUS.FILLED);
    expect(normalizeOrder({ active: false, taker: null }, 1).status).toBe(ORDER_STATUS.CANCELED);
  });

  // MUTATION: Overwrite the v2 amounts too
  // BREAKS: partial-fill progress is erased on the version that has it
  test("leaves genuine v2 partial-fill data alone", () => {
    const order = normalizeOrder(
      {
        amountA: "100",
        amountB: "250",
        availableA: "40",
        availableB: "100",
        partialFillAllowed: true,
        status: ORDER_STATUS.PARTIALLY_FILLED,
      },
      2
    );
    expect(order.amountA).toBe("100");
    expect(order.availableA).toBe("40");
    expect(order.partialFillAllowed).toBe(true);
  });

  // MUTATION: Keep maker as the Account object
  // BREAKS: every maker cell renders "[object Object]" and the My Orders
  //         comparison against the connected wallet never matches
  test("flattens the v2 maker relation to an address", () => {
    const order = normalizeOrder(
      { maker: { id: "0xabc" }, status: ORDER_STATUS.OPEN, partialFillAllowed: false },
      2
    );
    expect(order.maker).toBe("0xabc");
  });

  // MUTATION: Take the taker from the latest fill regardless of status
  // BREAKS: a partially filled order shows a taker, implying it is finished
  test("recovers the taker only once the closing fill has landed", () => {
    const filled = normalizeOrder(
      { status: ORDER_STATUS.FILLED, fills: [{ taker: { id: "0xtaker" } }] },
      2
    );
    expect(filled.taker).toBe("0xtaker");

    const partial = normalizeOrder(
      { status: ORDER_STATUS.PARTIALLY_FILLED, fills: [{ taker: { id: "0xtaker" } }] },
      2
    );
    expect(partial.taker).toBe(null);

    const open = normalizeOrder({ status: ORDER_STATUS.OPEN, fills: [] }, 2);
    expect(open.taker).toBe(null);
  });

  // MUTATION: Keep `fills` on the order
  // MUTATION: Assume `fills` is always present
  // BREAKS: the raw relation leaks into the CSV export, and a selection that
  //         omitted `fills` throws on `.length`
  test("drops the fills relation once the taker is recovered", () => {
    const order = normalizeOrder({ status: ORDER_STATUS.FILLED, fills: [] }, 2);
    expect(order.fills).toBeUndefined();
    expect(normalizeOrder({ status: ORDER_STATUS.FILLED }, 2).taker).toBe(null);
  });

  // MUTATION: Treat a missing flag as true
  // BREAKS: an order the subgraph never vouched for offers partial fills the
  //         contract will reject with PartialFillNotAllowed
  test("a missing partialFillAllowed flag means opted out", () => {
    expect(normalizeOrder({ amountA: "1", amountB: "1" }, 2).partialFillAllowed).toBe(false);
    expect(
      normalizeOrder({ amountA: "1", amountB: "1", partialFillAllowed: "yes" }, 2)
        .partialFillAllowed
    ).toBe(false);
  });

  test("passes a missing order straight through", () => {
    expect(normalizeOrder(null, 1)).toBe(null);
    expect(normalizeOrder(undefined, 2)).toBe(undefined);
  });
});

describe("nativeEthTotal", () => {
  const NATIVE = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
  const WETH = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";

  // MUTATION: Count every leg, or only the first native one
  // BREAKS: msg.value misses the exact total and v2 reverts ETHAmountMismatch
  test("sums exactly the native-ETH legs", () => {
    expect(
      nativeEthTotal([
        { token: NATIVE, amount: 3n },
        { token: WETH, amount: 100n },
        { token: NATIVE.toLowerCase(), amount: "5" },
      ])
    ).toBe(8n);
  });

  // MUTATION: Return undefined or a Number when no leg is native
  // BREAKS: an ERC20-only call gets a bogus msg.value override attached
  test("is 0n when no leg is native ETH", () => {
    expect(nativeEthTotal([{ token: WETH, amount: 1n }])).toBe(0n);
    expect(nativeEthTotal([])).toBe(0n);
  });

  // MUTATION: Assume an array
  // BREAKS: a malformed call throws instead of carrying no value
  test("treats a non-array as no legs", () => {
    expect(nativeEthTotal(undefined)).toBe(0n);
  });
});

describe("offersEthDirectly", () => {
  const WETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
  const isWeth = (a) => a.toLowerCase() === WETH.toLowerCase();
  const USDC = "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48";

  // MUTATION: Use isNativeEth on v1
  // BREAKS: a v1 order offering WETH goes down the ERC20 path, so the wallet
  //         is asked to approve and transfer WETH it was never given
  test("v1 settles a WETH leg through msg.value", () => {
    expect(offersEthDirectly(WETH, 1, isWeth)).toBe(true);
    expect(offersEthDirectly(USDC, 1, isWeth)).toBe(false);
  });

  // MUTATION: Treat WETH as ETH on v2 as well
  // BREAKS: a v2 WETH order sends ETH in msg.value for a contract expecting
  //         an ERC20 transfer
  test("v2 settles only the native sentinel through msg.value", () => {
    expect(offersEthDirectly(NATIVE_ETH, 2, isWeth)).toBe(true);
    expect(offersEthDirectly(WETH, 2, isWeth)).toBe(false);
    expect(offersEthDirectly(USDC, 2, isWeth)).toBe(false);
  });

  // MUTATION: Call isWethFn unconditionally
  // BREAKS: TypeError when no predicate is supplied
  test("returns false rather than throwing on bad input", () => {
    expect(offersEthDirectly(null, 1, isWeth)).toBe(false);
    expect(offersEthDirectly(WETH, 1, undefined)).toBe(false);
    expect(offersEthDirectly(123, 2, isWeth)).toBe(false);
  });
});
