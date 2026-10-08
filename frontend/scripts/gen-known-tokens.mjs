#!/usr/bin/env node
/**
 * Regenerates frontend/known-tokens.js from the public token lists in SOURCES.
 *
 *   node frontend/scripts/gen-known-tokens.mjs
 *
 * Every list is merged into one {chainId: {address: info}} index. Where two lists
 * describe the same address the earlier source in SOURCES wins, so order them by
 * how much their metadata is trusted. An entry with no chainId of its own takes the
 * source's `defaultChainId` -- the Trust Wallet list is per-chain and leaves it off
 * most entries. A source with inline `tokens` instead of a `url` is maintained here
 * by hand.
 */

import { writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const FRONTEND = join(dirname(fileURLToPath(import.meta.url)), "..");
const OUT = join(FRONTEND, "known-tokens.js");

const SOURCES = [
  {
    // The two tokens contracts/script/Seed.s.sol deploys and posts orders for. No
    // public list covers Sepolia, so without these every order there is "unknown".
    // Metadata read back from the deployed contracts.
    name: "Swapboard",
    tokens: [
      {
        chainId: 11155111,
        address: "0xcb650b2bcf7437af4e806fbff2dcd4109c4ccdff",
        symbol: "SMKA",
        name: "Swapboard Smoke A",
        decimals: 18,
      },
      {
        chainId: 11155111,
        address: "0x8125d46e9b27914d112ce6271fe4a7e4f977cfde",
        symbol: "SMKB",
        name: "Swapboard Smoke B",
        decimals: 6,
      },
    ],
  },
  { name: "CoinGecko", url: "https://tokens.coingecko.com/uniswap/all.json" },
  {
    name: "Trust Wallet",
    url: "https://raw.githubusercontent.com/trustwallet/assets/refs/heads/master/blockchains/ethereum/tokenlist.json",
    defaultChainId: 1,
  },
];

const ADDRESS_RE = /^0x[0-9a-fA-F]{40}$/;

async function fetchList(source) {
  if (source.tokens) return source.tokens;
  const res = await fetch(source.url);
  if (!res.ok) throw new Error(`${source.name}: HTTP ${res.status} from ${source.url}`);
  const data = await res.json();
  if (!Array.isArray(data.tokens)) throw new Error(`${source.name}: no tokens array`);
  return data.tokens;
}

function merge(lists) {
  const chains = {};
  const counts = {};
  for (const { source, tokens } of lists) {
    let added = 0;
    for (const t of tokens) {
      const chainId = t.chainId ?? source.defaultChainId;
      if (!Number.isInteger(chainId) || typeof t.address !== "string") continue;
      if (!ADDRESS_RE.test(t.address)) continue;
      const address = t.address.toLowerCase();
      const section = (chains[chainId] ||= {});
      if (section[address]) continue;
      section[address] = { symbol: String(t.symbol), name: String(t.name), decimals: t.decimals };
      added++;
    }
    counts[source.name] = added;
  }
  return { chains, counts };
}

function render(chains, counts) {
  const today = new Date().toISOString().slice(0, 10);
  const distribution = Object.fromEntries(
    Object.entries(chains).map(([id, tokens]) => [id, Object.keys(tokens).length])
  );
  const sourceLines = SOURCES.map(
    (s) =>
      ` *   ${s.name.padEnd(13)} ${s.url || "hand-maintained in the generator"}\n` +
      ` *   ${"".padEnd(13)} (${counts[s.name]} new addresses)`
  ).join("\n");

  // Sorted so a regeneration diffs by what actually changed.
  const body = Object.keys(chains)
    .sort((a, b) => Number(a) - Number(b))
    .map((id) => {
      const entries = Object.keys(chains[id])
        .sort()
        .map((addr) => {
          const { symbol, name, decimals } = chains[id][addr];
          const info = `{ symbol: ${JSON.stringify(symbol)}, name: ${JSON.stringify(name)}, decimals: ${decimals} }`;
          return `        ${JSON.stringify(addr)}: ${info},`;
        })
        .join("\n");
      return `      ${id}: {\n${entries}\n      },`;
    })
    .join("\n");

  return `/**
 * @fileoverview Generated "known token" registry, keyed by chain then address.
 * @description Tokens that appear on a public token list. An order whose token is
 *              not in here gets an "unknown token" warning in the UI. Consumed via
 *              lib.js (knownTokenInfo / isKnownToken); do not read this map directly.
 * @license AGPL-3.0-only
 *
 * GENERATED FILE - DO NOT EDIT BY HAND.
 *
 * Regenerate with scripts/gen-known-tokens.mjs.
 *
 * Sources, fetched ${today}, earlier source wins on a conflict:
${sourceLines}
 *
 * Being listed is not an endorsement: it only means the address is the one these
 * lists associate with that symbol, which is what an impersonating token gets wrong.
 *
 * Distribution: ${JSON.stringify(distribution)}
 *
 * Shape: {GENERATED, CHAINS: {"<chainId>": {"<address>": {symbol, name, decimals}}}}.
 * A chain with no section has no known tokens at all.
 */

(function (root, factory) {
  const data = factory();
  if (typeof module !== "undefined" && module.exports) {
    module.exports = data;
  } else {
    root.SwapboardKnownTokens = data;
  }
})(typeof self !== "undefined" ? self : this, function () {
  return {
    GENERATED: ${JSON.stringify(today)},
    CHAINS: {
${body}
    },
  };
});
`;
}

const lists = await Promise.all(
  SOURCES.map(async (source) => ({ source, tokens: await fetchList(source) }))
);
const { chains, counts } = merge(lists);
// One entry per line rather than prettier's five; known-tokens.js is in .prettierignore.
await writeFile(OUT, render(chains, counts));
console.log(`wrote ${OUT}`, counts);
