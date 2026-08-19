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
  parseAmount,
  getCachedPrice,
  getTokenPrice,
  fetchPrices,
  coinGeckoUrl,
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
  chunkArray,
  resolveSelectionMode,
  isSamePair,
  canSelectOrder,
  getShiftRangeIds,
  computeReceiveFromFill,
  computeFillFromReceive,
  summarizeFillBatch,
  VERSION_STORAGE_KEY,
  DEFAULT_VERSION,
  SUPPORTED_VERSIONS,
  VERSION_CAPS,
  parseVersion,
  resolveVersion,
  capsFor,
  orderQueryFields,
  normalizeOrder,
  offersEthDirectly,
} = require("./lib");

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

  // MUTATION: Use toFixed(4) instead of toExponential(2)
  // BREAKS: Returns "$0.0000" instead of "$1.00e-6"
  test("formats values < 0.01 in scientific notation", () => {
    expect(formatUsd(0.001)).toBe("$1.00e-3");
    expect(formatUsd(0.000001)).toBe("$1.00e-6");
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
  // BREAKS: Returns "0.000000" instead of "1.00e-5"
  test("uses scientific notation for values < 0.0001", () => {
    expect(formatRatio(0.00001)).toBe("1.00e-5");
    expect(formatRatio(0.000000018)).toBe("1.80e-8");
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
    const cache = new Map();
    const exactlyExpired = { usd: 3500, fetchedAt: Date.now() - 60001 };
    cache.set("weth", exactlyExpired);
    expect(getCachedPrice("weth", cache, 60000)).toBe(null);
  });

  // MUTATION: Change > to >= in TTL check
  // BREAKS: Entry at exactly TTL is incorrectly expired
  test("TTL boundary: valid at exactly TTL (> not >=)", () => {
    const cache = new Map();
    const exactlyAtTTL = { usd: 3500, fetchedAt: Date.now() - 60000 };
    cache.set("weth", exactlyAtTTL);
    expect(getCachedPrice("weth", cache, 60000)).toBe(exactlyAtTTL);
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
      amountA: "1000000000000000000", // 1 token
      amountB: "2500000000000000000", // 2.5 tokens
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
      amountA: "1000000000000000000",
      amountB: "1500000000000000000",
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
      amountA: "1000000000000000000",
      amountB: "2000000000000000000", // Exact market rate
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
      amountA: "1000000000000000000",
      amountB: "2000000000000000000",
    };
    expect(calculateMarketDeviation(order, mockGetPrice)).toBe(null);
  });

  // MUTATION: Don't check for zero price
  // BREAKS: Division by zero gives Infinity
  test("returns null when price is zero", () => {
    const order = {
      tokenA: { address: "0xtoken_a", decimals: 18 },
      tokenB: { address: "0xtoken_zero", decimals: 18 },
      amountA: "1000000000000000000",
      amountB: "2000000000000000000",
    };
    expect(calculateMarketDeviation(order, mockGetPrice)).toBe(null);
  });

  // MUTATION: Don't check for zero amount
  // BREAKS: Division by zero
  test("returns null when amount is zero", () => {
    const order = {
      tokenA: { address: "0xtoken_a", decimals: 18 },
      tokenB: { address: "0xtoken_b", decimals: 18 },
      amountA: "0",
      amountB: "2000000000000000000",
    };
    expect(calculateMarketDeviation(order, mockGetPrice)).toBe(null);
  });

  // MUTATION: Don't check for amountB === 0n
  // BREAKS: Division by zero or wrong calculation
  test("returns null when amountB is zero", () => {
    const order = {
      tokenA: { address: "0xtoken_a", decimals: 18 },
      tokenB: { address: "0xtoken_b", decimals: 18 },
      amountA: "1000000000000000000",
      amountB: "0",
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
      amountA: "1000000000000000000",
      amountB: "2000000000000000000",
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
      amountA: "1000000000000000000", // 1 token
      amountB: "2012000000000000000", // 2.012 tokens = 0.6% above market
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
      amountA: "1000000000000000000",
      amountB: "2008000000000000000", // 2.008 tokens = 0.4% above market
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
      amountA: "1000000000000000000",
      amountB: "2000000000000000000", // Exact market rate
    };
    const result = calculateMarketDeviation(order, mockGetPrice);
    expect(result.deviation).toBeCloseTo(0, 1);
    expect(result.label).toBe("~market");
  });

  // MUTATION: Change humanAmountB / humanAmountA to * humanAmountA
  // BREAKS: Order rate calculation would be wrong (multiplication instead of division)
  test("calculates order rate as amountB / amountA (division not multiplication)", () => {
    // Market rate = 100/50 = 2
    // With division: orderRate = 4/2 = 2 (matches market, ~market)
    // With multiplication: orderRate = 4*2 = 8 (huge deviation)
    const order = {
      tokenA: { address: "0xtoken_a", decimals: 18 },
      tokenB: { address: "0xtoken_b", decimals: 18 },
      amountA: "2000000000000000000", // 2 tokens
      amountB: "4000000000000000000", // 4 tokens (rate = 2)
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
// priceRatio
// ============================================================================

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
  // MUTATION: Return "Filled" for an active order
  // BREAKS: Open orders show as filled and fire spurious watch notifications
  test("an active order is Open", () => {
    expect(orderStatus({ active: true, taker: null })).toBe("Open");
  });

  // MUTATION: Check `active` only
  // BREAKS: Filled and cancelled orders become indistinguishable
  test("an inactive order with a taker is Filled", () => {
    expect(orderStatus({ active: false, taker: "0xabc" })).toBe("Filled");
  });

  test("an inactive order with no taker is Cancelled", () => {
    expect(orderStatus({ active: false, taker: null })).toBe("Cancelled");
    expect(orderStatus({ active: false, taker: "" })).toBe("Cancelled");
  });

  // MUTATION: Test `taker` before `active`
  // BREAKS: An active order that already has a taker recorded reads as Filled
  test("active wins over a recorded taker", () => {
    expect(orderStatus({ active: true, taker: "0xabc" })).toBe("Open");
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
    watchOrder(
      { orderId: "1", active: true, taker: null, tokenA: { symbol: "A" }, tokenB: { symbol: "B" } },
      localStorage
    );
    expect(getWatchedOrders(localStorage)["1"].status).toBe("Open");

    watchOrder(
      {
        orderId: "2",
        active: false,
        taker: "0x123",
        tokenA: { symbol: "A" },
        tokenB: { symbol: "B" },
      },
      localStorage
    );
    expect(getWatchedOrders(localStorage)["2"].status).toBe("Filled");

    watchOrder(
      {
        orderId: "3",
        active: false,
        taker: null,
        tokenA: { symbol: "A" },
        tokenB: { symbol: "B" },
      },
      localStorage
    );
    expect(getWatchedOrders(localStorage)["3"].status).toBe("Cancelled");
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
  ];
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
  });

  // MUTATION: Omit DeadlineExpired from the table
  // BREAKS: A fill that sat too long in the mempool reports a generic failure
  test("recognizes DeadlineExpired", () => {
    expect(decodeContractError("0x1ab7da6b")).toEqual({
      name: "DeadlineExpired",
      message: "Transaction deadline passed. Please try again.",
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
  return Object.assign(
    {
      orderId: "1",
      maker: OTHER,
      active: true,
      amountA: "1000",
      amountB: "2000",
      tokenA: { address: "0xAAA0000000000000000000000000000000000001", symbol: "A", decimals: 18 },
      tokenB: { address: "0xBBB0000000000000000000000000000000000002", symbol: "B", decimals: 18 },
    },
    overrides
  );
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

describe("computeReceiveFromFill", () => {
  const order = { amountA: "1000", amountB: "2000" };

  // MUTATION: Round up instead of down
  // BREAKS: Taker receives more than the maker priced, and the fill reverts
  test("rounds down in the maker's favour", () => {
    // 3 * 1000 / 2000 = 1.5 -> 1
    expect(computeReceiveFromFill(order, 3n)).toBe(1n);
  });

  test("scales proportionally", () => {
    expect(computeReceiveFromFill(order, 1000n)).toBe(500n);
  });

  // MUTATION: Return a scaled value past the remainder
  // BREAKS: UI promises more than the order holds
  test("caps at the full remaining amount", () => {
    expect(computeReceiveFromFill(order, 2000n)).toBe(1000n);
    expect(computeReceiveFromFill(order, 9999n)).toBe(1000n);
  });

  test("returns zero for a zero or negative fill", () => {
    expect(computeReceiveFromFill(order, 0n)).toBe(0n);
    expect(computeReceiveFromFill(order, -5n)).toBe(0n);
  });

  // MUTATION: Divide without guarding
  // BREAKS: Division by zero on a fully filled order
  test("returns zero when nothing is wanted", () => {
    expect(computeReceiveFromFill({ amountA: "1000", amountB: "0" }, 100n)).toBe(0n);
  });
});

describe("computeFillFromReceive", () => {
  const order = { amountA: "1000", amountB: "2000" };

  test("inverts an exact proportion", () => {
    expect(computeFillFromReceive(order, 500n)).toEqual({
      fillAmountB: 1000n,
      actualAmountA: 500n,
    });
  });

  // MUTATION: Round the payment down
  // BREAKS: Taker receives less than they asked for
  test("rounds the payment up so the receive target is met", () => {
    // want 1 of 1000 for 2000 -> 2 exactly; want 1 at 3:2 needs rounding up
    const odd = { amountA: "3", amountB: "2" };
    const result = computeFillFromReceive(odd, 1n);
    expect(result.fillAmountB).toBe(1n);
    expect(result.actualAmountA).toBe(1n);
  });

  // MUTATION: Let the payment exceed the order
  // BREAKS: Overpayment on a full fill
  test("caps at the full order when asking for everything or more", () => {
    expect(computeFillFromReceive(order, 1000n)).toEqual({
      fillAmountB: 2000n,
      actualAmountA: 1000n,
    });
    expect(computeFillFromReceive(order, 5000n)).toEqual({
      fillAmountB: 2000n,
      actualAmountA: 1000n,
    });
  });

  test("returns zero for a zero or negative request", () => {
    expect(computeFillFromReceive(order, 0n)).toEqual({ fillAmountB: 0n, actualAmountA: 0n });
    expect(computeFillFromReceive(order, -1n)).toEqual({ fillAmountB: 0n, actualAmountA: 0n });
  });

  test("returns zero on an empty order", () => {
    expect(computeFillFromReceive({ amountA: "0", amountB: "0" }, 10n)).toEqual({
      fillAmountB: 0n,
      actualAmountA: 0n,
    });
  });

  // MUTATION: Report the requested amount rather than the contract's
  // BREAKS: Confirmation shows an amount the contract won't deliver
  test("reports what the contract will actually transfer", () => {
    const result = computeFillFromReceive({ amountA: "1000", amountB: "3" }, 500n);
    expect(result.actualAmountA).toBe(
      computeReceiveFromFill({ amountA: "1000", amountB: "3" }, result.fillAmountB)
    );
  });
});

describe("summarizeFillBatch", () => {
  const pair = {
    tokenA: { address: "0xA", symbol: "A", decimals: 18 },
    tokenB: { address: "0xB", symbol: "B", decimals: 18 },
  };
  const batch = [
    Object.assign({ amountA: "1000000000000000000", amountB: "2000000000000000000" }, pair),
    Object.assign({ amountA: "3000000000000000000", amountB: "6000000000000000000" }, pair),
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
        amountA: "1000000000000000000", // 1.0 (18dp)
        amountB: "3000000", // 3.0 (6dp)
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
    const empty = [Object.assign({ amountA: "0", amountB: "100" }, pair)];
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
    expect(resolveVersion({ search: "%", stored: "2" }).version).toBe(2);
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

  // MUTATION: Enable gasEstimate/subgraphPolling on v2
  // BREAKS: gas estimation encodes against an ABI with no deployment behind
  //         it, and polling waits out its full timeout on every transaction
  test("v1 alone can estimate gas and poll the subgraph", () => {
    expect(capsFor(1).gasEstimate).toBe(true);
    expect(capsFor(1).subgraphPolling).toBe(true);
    expect(capsFor(2).gasEstimate).toBe(false);
    expect(capsFor(2).subgraphPolling).toBe(false);
  });

  // MUTATION: Mark v2 live
  // BREAKS: the UI would present simulated transactions as real ones
  test("only v1 is live", () => {
    expect(capsFor(1).live).toBe(true);
    expect(capsFor(2).live).toBe(false);
  });

  // MUTATION: Return undefined for an unknown version
  // BREAKS: every `CAPS.x` read throws instead of degrading to v1
  test("falls back to the default version's capabilities", () => {
    expect(capsFor(99)).toBe(VERSION_CAPS[DEFAULT_VERSION]);
    expect(capsFor(undefined)).toBe(VERSION_CAPS[DEFAULT_VERSION]);
  });
});

describe("orderQueryFields", () => {
  // MUTATION: Include partialFill in the v1 field list
  // BREAKS: the deployed subgraph errors on the unknown field and returns no
  //         orders at all — GraphQL rejects the whole query, not just the field
  test("omits every v2-only field on v1", () => {
    const fields = orderQueryFields(1);
    expect(fields).not.toContain("partialFill");
    expect(fields).not.toContain("originalAmountA");
    expect(fields).not.toContain("originalAmountB");
  });

  // MUTATION: Drop a v2 field
  // BREAKS: partial-fill progress silently stops rendering on v2
  test("requests the v2-only fields on v2", () => {
    const fields = orderQueryFields(2);
    expect(fields).toContain("partialFill");
    expect(fields).toContain("originalAmountA");
    expect(fields).toContain("originalAmountB");
  });

  // MUTATION: Drop a shared field from one branch
  // BREAKS: a column renders blank in exactly one version
  test("both versions request every shared field", () => {
    const shared = [
      "orderId",
      "maker",
      "amountA",
      "amountB",
      "active",
      "taker",
      "createdAt",
      "filledAt",
    ];
    for (const field of shared) {
      expect(orderQueryFields(1)).toContain(field);
      expect(orderQueryFields(2)).toContain(field);
    }
  });

  test("v1 asks for strictly fewer fields", () => {
    expect(orderQueryFields(1).length).toBe(8);
    expect(orderQueryFields(2).length).toBe(11);
  });
});

describe("normalizeOrder", () => {
  // MUTATION: Leave originalAmount undefined on v1
  // BREAKS: buildAmountCell calls BigInt(undefined) and throws mid-render
  test("backfills the v2 fields a v1 subgraph never returns", () => {
    const order = normalizeOrder({ amountA: "100", amountB: "250" }, 1);
    expect(order.originalAmountA).toBe("100");
    expect(order.originalAmountB).toBe("250");
    expect(order.partialFill).toBe(false);
  });

  // MUTATION: Set original to something other than the remaining amount
  // BREAKS: every v1 order renders a bogus "of X left" partial-fill hint,
  //         since that hint shows exactly when original > remaining
  test("a v1 order reads as untouched, never partly filled", () => {
    const order = normalizeOrder({ amountA: "100", amountB: "250" }, 1);
    expect(BigInt(order.originalAmountA)).toBe(BigInt(order.amountA));
    expect(BigInt(order.originalAmountB)).toBe(BigInt(order.amountB));
  });

  // MUTATION: Overwrite the v2 amounts too
  // BREAKS: partial-fill progress is erased on the version that has it
  test("leaves genuine v2 partial-fill data alone", () => {
    const order = normalizeOrder(
      {
        amountA: "40",
        amountB: "100",
        originalAmountA: "100",
        originalAmountB: "250",
        partialFill: true,
      },
      2
    );
    expect(order.originalAmountA).toBe("100");
    expect(order.amountA).toBe("40");
    expect(order.partialFill).toBe(true);
  });

  // MUTATION: Treat a missing flag as true
  // BREAKS: an order the subgraph never vouched for offers partial fills the
  //         contract will reject
  test("a missing partialFill flag means opted out", () => {
    expect(normalizeOrder({ amountA: "1", amountB: "1" }, 2).partialFill).toBe(false);
    expect(normalizeOrder({ amountA: "1", amountB: "1", partialFill: "yes" }, 2).partialFill).toBe(
      false
    );
  });

  test("passes a missing order straight through", () => {
    expect(normalizeOrder(null, 1)).toBe(null);
    expect(normalizeOrder(undefined, 2)).toBe(undefined);
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
