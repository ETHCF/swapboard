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
  calculateMarketDeviation,
  searchTokens,
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
  decodeContractError,
  parseContractError,
  validateConfig,
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
  // MUTATION: Return "$ 0" for null
  // BREAKS: Returns "$ 0" instead of "$ --"
  test("returns $ -- for null", () => {
    expect(formatUsd(null)).toBe("$ --");
  });

  // MUTATION: Return "$ NaN" for undefined (no check)
  // BREAKS: Returns "$ NaN"
  test("returns $ -- for undefined", () => {
    expect(formatUsd(undefined)).toBe("$ --");
  });

  // MUTATION: Change threshold from 1000000 to 1000
  // BREAKS: 1500 would show as "$ 1.50M"
  test("formats values >= 1M with M suffix", () => {
    expect(formatUsd(1000000)).toBe("$ 1.00M");
    expect(formatUsd(2500000)).toBe("$ 2.50M");
    expect(formatUsd(999999)).toBe("$ 999,999"); // Just under 1M
  });

  // MUTATION: Remove comma insertion regex
  // BREAKS: Returns "$ 1500" instead of "$ 1,500"
  test("formats values >= 1000 with comma separators", () => {
    expect(formatUsd(1000)).toBe("$ 1,000");
    expect(formatUsd(1500)).toBe("$ 1,500");
    expect(formatUsd(999999)).toBe("$ 999,999");
  });

  // MUTATION: Use toFixed(0) instead of toFixed(2)
  // BREAKS: Returns "$ 6" instead of "$ 5.50"
  test("formats values >= 1 with 2 decimal places", () => {
    expect(formatUsd(5.5)).toBe("$ 5.50");
    expect(formatUsd(1.0)).toBe("$ 1.00");
    expect(formatUsd(999.99)).toBe("$ 999.99");
  });

  // MUTATION: Change threshold from 0.01 to 0.001
  // BREAKS: 0.05 would show as exponential
  test("formats values >= 0.01 with 4 decimal places", () => {
    expect(formatUsd(0.01)).toBe("$ 0.0100");
    expect(formatUsd(0.05)).toBe("$ 0.0500");
    expect(formatUsd(0.0123)).toBe("$ 0.0123");
  });

  // MUTATION: Use toFixed(4) instead of toExponential(2)
  // BREAKS: Returns "$ 0.0000" instead of "$ 1.00e-6"
  test("formats values < 0.01 in scientific notation", () => {
    expect(formatUsd(0.001)).toBe("$ 1.00e-3");
    expect(formatUsd(0.000001)).toBe("$ 1.00e-6");
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

  // MUTATION: Change threshold from 60 to 30
  // BREAKS: 45 seconds ago shows "0m ago" instead of "just now"
  test("shows just now for timestamps within 60 seconds", () => {
    expect(formatTimeAgo(now - 1)).toBe("just now");
    expect(formatTimeAgo(now - 59)).toBe("just now");
    expect(formatTimeAgo(now - 60)).toBe("1m ago"); // Exactly 60 = 1m
  });

  // MUTATION: Divide by 3600 instead of 60 for minutes
  // BREAKS: 120 seconds shows "0h ago" instead of "2m ago"
  test("shows minutes for timestamps 1-59 minutes ago", () => {
    expect(formatTimeAgo(now - 60)).toBe("1m ago");
    expect(formatTimeAgo(now - 120)).toBe("2m ago");
    expect(formatTimeAgo(now - 3540)).toBe("59m ago");
  });

  // MUTATION: Change hour threshold from 86400 to 43200
  // BREAKS: 13 hours shows "1d ago" instead of "13h ago"
  test("shows hours for timestamps 1-23 hours ago", () => {
    expect(formatTimeAgo(now - 3600)).toBe("1h ago");
    expect(formatTimeAgo(now - 7200)).toBe("2h ago");
    expect(formatTimeAgo(now - 82800)).toBe("23h ago");
  });

  // MUTATION: Change day threshold from 604800 to 172800
  // BREAKS: 3 days shows formatted date instead of "3d ago"
  test("shows days for timestamps 1-6 days ago", () => {
    expect(formatTimeAgo(now - 86400)).toBe("1d ago");
    expect(formatTimeAgo(now - 172800)).toBe("2d ago");
    expect(formatTimeAgo(now - 518400)).toBe("6d ago");
  });

  // MUTATION: Continue showing "Xd ago" for all past dates
  // BREAKS: Would show "365d ago" instead of a date
  test("shows formatted date for timestamps >= 7 days ago", () => {
    const result = formatTimeAgo(now - 604800); // Exactly 7 days
    expect(result).not.toContain("ago");
    expect(result).toMatch(/\d{1,2}\/\d{1,2}\/\d{4}|\d{1,2}\.\d{1,2}\.\d{4}/); // Date format
  });

  // MUTATION: Change timestamp * 1000 to timestamp / 1000
  // BREAKS: Date would be near 1970 instead of the actual date
  test("multiplies timestamp by 1000 for Date constructor (* not /)", () => {
    // 7 days ago should show a date in the current year (or last year at boundary)
    const result = formatTimeAgo(now - 604800);
    const currentYear = new Date().getFullYear();
    const lastYear = currentYear - 1;
    // The date string should contain the current or last year, not 1970
    expect(result).toMatch(new RegExp(`(${currentYear}|${lastYear})`));
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

  // MUTATION: Ignore decimal part
  // BREAKS: "1.5" parses as 1e18 instead of 1.5e18
  test("handles decimal input correctly", () => {
    expect(parseAmount("1.5", 18)).toBe(BigInt("1500000000000000000"));
    expect(parseAmount("0.5", 6)).toBe(BigInt("500000"));
  });

  // MUTATION: Don't strip commas before parsing
  // BREAKS: Throws or returns null for "1,000"
  test("strips commas from input", () => {
    expect(parseAmount("1,000", 6)).toBe(BigInt("1000000000"));
    expect(parseAmount("1,000,000", 18)).toBe(BigInt("1000000000000000000000000"));
  });

  // MUTATION: Don't truncate excess decimals
  // BREAKS: Extra decimals cause wrong value
  test("truncates decimals exceeding token precision", () => {
    expect(parseAmount("1.1234567", 6)).toBe(BigInt("1123456")); // Truncated to 6
    expect(parseAmount("1.123456789012345678901", 18)).toBe(BigInt("1123456789012345678")); // Truncated to 18
  });

  // MUTATION: Don't pad short decimals
  // BREAKS: "1.5" with 6 decimals gives 15n instead of 1500000n
  test("pads short decimal input", () => {
    expect(parseAmount("1.5", 6)).toBe(BigInt("1500000")); // 1.5 * 10^6
    expect(parseAmount("1.1", 18)).toBe(BigInt("1100000000000000000")); // 1.1 * 10^18
  });

  // MUTATION: Don't handle leading decimal
  // BREAKS: ".5" throws or returns null
  test("handles leading decimal (.5 = 0.5)", () => {
    expect(parseAmount(".5", 18)).toBe(BigInt("500000000000000000"));
  });

  // MUTATION: Don't handle trailing decimal
  // BREAKS: "5." throws or returns null
  test("handles trailing decimal (5. = 5)", () => {
    expect(parseAmount("5.", 18)).toBe(BigInt("5000000000000000000"));
  });

  // MUTATION: Return 0n instead of null for invalid input
  // BREAKS: Invalid input returns 0n instead of null
  test("returns null for invalid input", () => {
    expect(parseAmount("abc", 18)).toBe(null);
    expect(parseAmount("", 18)).toBe(null);
    expect(parseAmount(".", 18)).toBe(null);
    expect(parseAmount(null, 18)).toBe(null);
    expect(parseAmount("1.2.3", 18)).toBe(null);
    expect(parseAmount("-1", 18)).toBe(null);
  });

  // MUTATION: Change fracPart.length > decimals to >= decimals
  // BREAKS: Decimal with exactly decimals digits would be truncated
  test("boundary: decimals at exactly token precision not truncated (> not >=)", () => {
    // 6 decimal places for 6-decimal token should work exactly
    expect(parseAmount("1.123456", 6)).toBe(BigInt("1123456"));
    // 18 decimal places for 18-decimal token should work exactly
    expect(parseAmount("1.123456789012345678", 18)).toBe(BigInt("1123456789012345678"));
  });

  // MUTATION: Remove .trim() from input cleaning
  // BREAKS: " 1.5 " would fail validation
  test("trims whitespace from input", () => {
    expect(parseAmount(" 1.5 ", 6)).toBe(BigInt("1500000"));
    expect(parseAmount("  100  ", 18)).toBe(BigInt("100000000000000000000"));
  });

  // MUTATION: Use "" instead of "0" for empty wholePart
  // BREAKS: ".5" would become "5" (missing leading zero)
  test("leading decimal defaults wholePart to 0", () => {
    expect(parseAmount(".123456", 6)).toBe(BigInt("123456"));
    expect(parseAmount(".1", 18)).toBe(BigInt("100000000000000000"));
  });

  // MUTATION: Change !str to false or change && to ||
  // BREAKS: Non-string input would pass validation
  test("type validation rejects non-string input (!str and typeof check)", () => {
    expect(parseAmount(123, 18)).toBe(null);
    expect(parseAmount(["1.5"], 18)).toBe(null);
    expect(parseAmount({}, 18)).toBe(null);
    expect(parseAmount(true, 18)).toBe(null);
  });

  // MUTATION: Change cleaned === "" to false or "Stryker was here!"
  // BREAKS: Empty string after cleaning would pass
  test("rejects empty string after cleaning", () => {
    expect(parseAmount("", 18)).toBe(null);
    expect(parseAmount("   ", 18)).toBe(null); // Whitespace only
  });

  // MUTATION: if (fracPart.length > decimals) to if (true)
  // BREAKS: All fractional parts would be truncated
  test("only truncates when fraction exceeds decimals (> not always)", () => {
    // Exact precision should not be truncated
    expect(parseAmount("1.12", 2)).toBe(BigInt("112")); // Exactly 2 decimals
    expect(parseAmount("1.1", 2)).toBe(BigInt("110")); // Less than 2 decimals, padded
    expect(parseAmount("1.123", 2)).toBe(BigInt("112")); // More than 2 decimals, truncated
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
  const orders = [
    {
      orderId: "2",
      maker: "0xbbb",
      tokenA: { symbol: "USDC" },
      tokenB: { symbol: "WETH" },
      amountA: "2000000000",
      amountB: "1000000000000000000",
      _usdValue: 2000,
      _price: 0.0005,
    },
    {
      orderId: "1",
      maker: "0xaaa",
      tokenA: { symbol: "WETH" },
      tokenB: { symbol: "USDC" },
      amountA: "1000000000000000000",
      amountB: "3500000000",
      _usdValue: 3500,
      _price: 3500,
    },
    {
      orderId: "3",
      maker: "0xccc",
      tokenA: { symbol: "DAI" },
      tokenB: { symbol: "USDT" },
      amountA: "5000000000000000000",
      amountB: "5000000",
      _usdValue: 5000,
      _price: 1,
    },
  ];

  // MUTATION: Use string comparison for orderId
  // BREAKS: "10" sorts before "2"
  test("sorts orderId numerically", () => {
    const withTen = [
      ...orders,
      {
        orderId: "10",
        maker: "",
        tokenA: { symbol: "" },
        tokenB: { symbol: "" },
        amountA: "1",
        amountB: "1",
        _usdValue: 0,
        _price: 0,
      },
    ];
    const sorted = sortOrders(withTen, "orderId", "asc");
    expect(sorted.map((o) => o.orderId)).toEqual(["1", "2", "3", "10"]);
  });

  // MUTATION: Invert asc/desc comparison
  // BREAKS: desc shows ascending order
  test("respects sort direction", () => {
    const sorted = sortOrders(orders, "orderId", "desc");
    expect(sorted[0].orderId).toBe("3");
    expect(sorted[2].orderId).toBe("1");
  });

  // MUTATION: Use Number() instead of BigInt for amounts
  // BREAKS: Large amounts overflow and sort wrong
  test("sorts amountA as BigInt (handles large values)", () => {
    const bigOrders = [
      {
        orderId: "1",
        amountA: "999999999999999999999999999",
        amountB: "1",
        tokenA: { symbol: "" },
        tokenB: { symbol: "" },
        maker: "",
        _usdValue: 0,
        _price: 0,
      },
      {
        orderId: "2",
        amountA: "1",
        amountB: "1",
        tokenA: { symbol: "" },
        tokenB: { symbol: "" },
        maker: "",
        _usdValue: 0,
        _price: 0,
      },
    ];
    const sorted = sortOrders(bigOrders, "amountA", "asc");
    expect(sorted[0].orderId).toBe("2"); // Smaller first
  });

  // MUTATION: Sort in place instead of copying
  // BREAKS: Original array is mutated
  test("does not mutate original array", () => {
    const original = orders.map((o) => o.orderId);
    sortOrders(orders, "orderId", "asc");
    expect(orders.map((o) => o.orderId)).toEqual(original);
  });

  // MUTATION: Throw for unknown column
  // BREAKS: App crashes on typo
  test("handles unknown column gracefully", () => {
    const sorted = sortOrders(orders, "nonexistent", "asc");
    expect(sorted.length).toBe(3);
  });

  // MUTATION: Don't lowercase when sorting maker
  // BREAKS: "0xAAA" sorts differently than "0xaaa"
  test("sorts maker case-insensitively", () => {
    const sorted = sortOrders(orders, "maker", "asc");
    expect(sorted[0].maker).toBe("0xaaa");
  });

  // MUTATION: Don't lowercase tokenA symbol for comparison
  // BREAKS: "DAI" sorts after "USDC" if uppercase not lowercased
  test("sorts tokenA by symbol case-insensitively", () => {
    const sorted = sortOrders(orders, "tokenA", "asc");
    expect(sorted[0].tokenA.symbol).toBe("DAI");
    expect(sorted[1].tokenA.symbol).toBe("USDC");
    expect(sorted[2].tokenA.symbol).toBe("WETH");
  });

  // MUTATION: Don't lowercase tokenB symbol for comparison
  // BREAKS: Sorts by ASCII code instead of case-insensitive
  test("sorts tokenB by symbol case-insensitively", () => {
    const sorted = sortOrders(orders, "tokenB", "asc");
    expect(sorted[0].tokenB.symbol).toBe("USDC");
    expect(sorted[1].tokenB.symbol).toBe("USDT");
    expect(sorted[2].tokenB.symbol).toBe("WETH");
  });

  // MUTATION: Use Number() instead of BigInt for amountB
  // BREAKS: Large amountB values overflow and sort incorrectly
  test("sorts amountB as BigInt (handles large values)", () => {
    const bigOrders = [
      {
        orderId: "1",
        amountA: "1",
        amountB: "999999999999999999999999999",
        tokenA: { symbol: "" },
        tokenB: { symbol: "" },
        maker: "",
        _usdValue: 0,
        _price: 0,
      },
      {
        orderId: "2",
        amountA: "1",
        amountB: "1",
        tokenA: { symbol: "" },
        tokenB: { symbol: "" },
        maker: "",
        _usdValue: 0,
        _price: 0,
      },
    ];
    const sorted = sortOrders(bigOrders, "amountB", "asc");
    expect(sorted[0].orderId).toBe("2"); // Smaller first
  });

  // MUTATION: Invert comparison result for desc direction
  // BREAKS: desc order returns wrong sequence
  test("sorts amountA descending correctly", () => {
    const bigOrders = [
      {
        orderId: "1",
        amountA: "1",
        amountB: "1",
        tokenA: { symbol: "" },
        tokenB: { symbol: "" },
        maker: "",
        _usdValue: 0,
        _price: 0,
      },
      {
        orderId: "2",
        amountA: "999999999999999999999999999",
        amountB: "1",
        tokenA: { symbol: "" },
        tokenB: { symbol: "" },
        maker: "",
        _usdValue: 0,
        _price: 0,
      },
    ];
    const sorted = sortOrders(bigOrders, "amountA", "desc");
    expect(sorted[0].orderId).toBe("2"); // Larger first in desc
    expect(sorted[1].orderId).toBe("1");
  });

  // MUTATION: Invert comparison result for desc direction
  // BREAKS: desc order returns wrong sequence
  test("sorts amountB descending correctly", () => {
    const bigOrders = [
      {
        orderId: "1",
        amountA: "1",
        amountB: "1",
        tokenA: { symbol: "" },
        tokenB: { symbol: "" },
        maker: "",
        _usdValue: 0,
        _price: 0,
      },
      {
        orderId: "2",
        amountA: "1",
        amountB: "999999999999999999999999999",
        tokenA: { symbol: "" },
        tokenB: { symbol: "" },
        maker: "",
        _usdValue: 0,
        _price: 0,
      },
    ];
    const sorted = sortOrders(bigOrders, "amountB", "desc");
    expect(sorted[0].orderId).toBe("2"); // Larger first in desc
    expect(sorted[1].orderId).toBe("1");
  });

  // MUTATION: Sort by _usdValue * -1
  // BREAKS: Order with usdValue 5000 appears before 2000 in asc
  test("sorts usdVal numerically", () => {
    const sorted = sortOrders(orders, "usdVal", "asc");
    expect(sorted[0]._usdValue).toBe(2000);
    expect(sorted[1]._usdValue).toBe(3500);
    expect(sorted[2]._usdValue).toBe(5000);
  });

  // MUTATION: Sort by _price * -1
  // BREAKS: Order with price 0.0005 appears after 3500 in asc
  test("sorts price numerically", () => {
    const sorted = sortOrders(orders, "price", "asc");
    expect(sorted[0]._price).toBe(0.0005);
    expect(sorted[1]._price).toBe(1);
    expect(sorted[2]._price).toBe(3500);
  });

  // MUTATION: Return -1 instead of 0 when values are equal
  // BREAKS: Identical orders have unstable sort order
  test("returns 0 for equal values (stable sort)", () => {
    const equalOrders = [
      {
        orderId: "1",
        maker: "0xaaa",
        tokenA: { symbol: "A" },
        tokenB: { symbol: "B" },
        amountA: "100",
        amountB: "100",
        _usdValue: 100,
        _price: 1,
      },
      {
        orderId: "2",
        maker: "0xaaa",
        tokenA: { symbol: "A" },
        tokenB: { symbol: "B" },
        amountA: "100",
        amountB: "100",
        _usdValue: 100,
        _price: 1,
      },
    ];
    const sorted = sortOrders(equalOrders, "maker", "asc");
    // With stable sort (return 0), original order is preserved
    expect(sorted[0].orderId).toBe("1");
    expect(sorted[1].orderId).toBe("2");
  });

  // MUTATION: Change aVal < bVal to aVal <= bVal in amountA
  // BREAKS: Equal amounts would incorrectly return -1 instead of falling through to return 0
  test("amountA boundary: equal values return 0 (< not <=)", () => {
    const equalAmounts = [
      {
        orderId: "1",
        amountA: "1000000000000000000",
        amountB: "1",
        tokenA: { symbol: "" },
        tokenB: { symbol: "" },
        maker: "",
        _usdValue: 0,
        _price: 0,
      },
      {
        orderId: "2",
        amountA: "1000000000000000000",
        amountB: "1",
        tokenA: { symbol: "" },
        tokenB: { symbol: "" },
        maker: "",
        _usdValue: 0,
        _price: 0,
      },
    ];
    const sorted = sortOrders(equalAmounts, "amountA", "asc");
    // Equal amounts should preserve original order (stable sort)
    expect(sorted[0].orderId).toBe("1");
    expect(sorted[1].orderId).toBe("2");
  });

  // MUTATION: Change aVal < bVal to aVal <= bVal in amountB
  // BREAKS: Equal amounts would incorrectly return -1 instead of falling through to return 0
  test("amountB boundary: equal values return 0 (< not <=)", () => {
    const equalAmounts = [
      {
        orderId: "1",
        amountA: "1",
        amountB: "1000000000000000000",
        tokenA: { symbol: "" },
        tokenB: { symbol: "" },
        maker: "",
        _usdValue: 0,
        _price: 0,
      },
      {
        orderId: "2",
        amountA: "1",
        amountB: "1000000000000000000",
        tokenA: { symbol: "" },
        tokenB: { symbol: "" },
        maker: "",
        _usdValue: 0,
        _price: 0,
      },
    ];
    const sorted = sortOrders(equalAmounts, "amountB", "asc");
    // Equal amounts should preserve original order (stable sort)
    expect(sorted[0].orderId).toBe("1");
    expect(sorted[1].orderId).toBe("2");
  });

  // MUTATION: Change aVal > bVal to aVal >= bVal in amountA
  // BREAKS: Equal amounts in desc would return 1 instead of falling through
  test("amountA boundary desc: equal values return 0 (> not >=)", () => {
    const equalAmounts = [
      {
        orderId: "1",
        amountA: "5000",
        amountB: "1",
        tokenA: { symbol: "" },
        tokenB: { symbol: "" },
        maker: "",
        _usdValue: 0,
        _price: 0,
      },
      {
        orderId: "2",
        amountA: "5000",
        amountB: "1",
        tokenA: { symbol: "" },
        tokenB: { symbol: "" },
        maker: "",
        _usdValue: 0,
        _price: 0,
      },
    ];
    const sorted = sortOrders(equalAmounts, "amountA", "desc");
    expect(sorted[0].orderId).toBe("1");
    expect(sorted[1].orderId).toBe("2");
  });

  // MUTATION: Change aVal > bVal to aVal >= bVal in amountB
  // BREAKS: Equal amounts in desc would return 1 instead of falling through
  test("amountB boundary desc: equal values return 0 (> not >=)", () => {
    const equalAmounts = [
      {
        orderId: "1",
        amountA: "1",
        amountB: "5000",
        tokenA: { symbol: "" },
        tokenB: { symbol: "" },
        maker: "",
        _usdValue: 0,
        _price: 0,
      },
      {
        orderId: "2",
        amountA: "1",
        amountB: "5000",
        tokenA: { symbol: "" },
        tokenB: { symbol: "" },
        maker: "",
        _usdValue: 0,
        _price: 0,
      },
    ];
    const sorted = sortOrders(equalAmounts, "amountB", "desc");
    expect(sorted[0].orderId).toBe("1");
    expect(sorted[1].orderId).toBe("2");
  });
});

// ============================================================================
// decodeContractError
// ============================================================================

describe("decodeContractError", () => {
  // MUTATION: Wrong selector in ERROR_SIGNATURES
  // BREAKS: Returns wrong error name
  test("maps selector 0xd92e233d to ZeroAddress", () => {
    const result = decodeContractError("0xd92e233d");
    expect(result.name).toBe("ZeroAddress");
    expect(result.message).toBe("Token address cannot be zero");
  });

  // MUTATION: Use exact string match instead of slice(0,10)
  // BREAKS: Fails when error has additional data
  test("handles selector with ABI-encoded parameters", () => {
    const result = decodeContractError("0xd92e233d0000000000000000000000001234");
    expect(result.name).toBe("ZeroAddress");
  });

  // MUTATION: Don't lowercase before lookup
  // BREAKS: Returns null for uppercase selector
  test("selector lookup is case-insensitive", () => {
    expect(decodeContractError("0xD92E233D").name).toBe("ZeroAddress");
  });

  // MUTATION: Throw for unknown selector
  // BREAKS: App crashes on unknown error
  test("returns null for unknown selector", () => {
    expect(decodeContractError("0xdeadbeef")).toBe(null);
  });

  // MUTATION: Don't type-check input
  // BREAKS: Crashes on null.slice()
  test("returns null for invalid input", () => {
    expect(decodeContractError(null)).toBe(null);
    expect(decodeContractError(123)).toBe(null);
  });

  // All known selectors
  test("decodes all known error selectors", () => {
    expect(decodeContractError("0x1f2a2005").name).toBe("ZeroAmount");
    expect(decodeContractError("0x201b580a").name).toBe("SameToken");
    expect(decodeContractError("0x8a8b41ec").name).toBe("NotAContract");
    expect(decodeContractError("0x6e65ed84").name).toBe("BalanceMismatch");
    expect(decodeContractError("0x4e90badc").name).toBe("OrderNotFound");
    expect(decodeContractError("0xd2c02610").name).toBe("OrderNotActive");
    expect(decodeContractError("0x98cd7222").name).toBe("NotMaker");
  });
});

// ============================================================================
// parseContractError
// ============================================================================

describe("parseContractError", () => {
  // MUTATION: Don't check e.data
  // BREAKS: Known contract error shows generic message
  test("extracts error from e.data", () => {
    expect(parseContractError({ data: "0xd92e233d" })).toBe("Token address cannot be zero");
  });

  // MUTATION: Don't check nested e.info.error.data
  // BREAKS: ethers.js v6 errors not decoded
  test("extracts error from e.info.error.data (ethers v6)", () => {
    expect(parseContractError({ info: { error: { data: "0x1f2a2005" } } })).toBe(
      "Amount cannot be zero"
    );
  });

  // MUTATION: Don't handle code 4001
  // BREAKS: MetaMask rejection shows raw error
  test("handles user rejection code 4001", () => {
    expect(parseContractError({ code: 4001 })).toBe("Transaction rejected by user");
  });

  // MUTATION: Only handle numeric codes
  // BREAKS: ethers string code not recognized
  test("handles ACTION_REJECTED string code", () => {
    expect(parseContractError({ code: "ACTION_REJECTED" })).toBe("Transaction rejected by user");
  });

  // MUTATION: Don't handle -32000 code
  // BREAKS: Insufficient funds shows raw RPC error
  test("handles insufficient funds code -32000", () => {
    expect(parseContractError({ code: -32000 })).toBe("Insufficient funds for transaction");
  });

  // MUTATION: Don't parse reason from message
  // BREAKS: Shows full ugly revert message
  test("extracts reason from execution reverted message", () => {
    expect(parseContractError({ message: 'execution reverted: reason="Custom error"' })).toBe(
      "Custom error"
    );
  });

  // MUTATION: Return raw revert message instead of fallback
  // BREAKS: Shows "execution reverted" instead of "Transaction would fail"
  test("returns fallback for execution reverted without reason", () => {
    expect(parseContractError({ message: "execution reverted" })).toBe("Transaction would fail");
    expect(parseContractError({ message: "call revert exception; execution reverted" })).toBe(
      "Transaction would fail"
    );
  });

  // MUTATION: Return undefined for empty error
  // BREAKS: UI shows "undefined"
  test("returns generic message for unknown error", () => {
    expect(parseContractError({})).toBe("Transaction failed");
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
