# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Swapboard, please report it responsibly.

**DO NOT** create a public GitHub issue for security vulnerabilities.

Instead, please send an email to: <zak@numbergroup.xyz>

Include:

- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

## Scope

The following are in scope:

- Smart contract vulnerabilities in `contracts/src/`
- Frontend vulnerabilities that could lead to fund loss
- Subgraph data integrity issues

The following are explicitly out of scope:

- Known behaviors documented in "Trust Assumptions" and "Known Limitations" sections
- Third-party dependencies (OpenZeppelin, ethers.js) - report to upstream maintainers
- Theoretical attacks without proof of concept or economic viability analysis
- Social engineering, phishing, or UI spoofing attacks
- Issues requiring compromised private keys
- Network-level attacks (eclipse attacks, BGP hijacking)
- Vulnerabilities in the testnet deployment or test tokens (TestToken.sol)
- Frontend issues that do not lead to fund loss (cosmetic bugs, UX issues)
- Subgraph indexing delays or temporary data inconsistencies
- Gas optimization suggestions (unless they enable griefing attacks)

## Response Timeline

| Phase | Timeframe |
| ------- | ----------- |
| Acknowledgment | 48 hours |
| Initial assessment | 7 days |
| Resolution | Varies by severity |
| Public disclosure | After fix deployed |

## Severity Levels

| Severity | Description | Example |
| ---------- | ------------- | --------- |
| Critical | Direct fund loss possible | Reentrancy, unauthorized withdrawals |
| High | Funds at risk under conditions | Denial of service, griefing |
| Medium | Data integrity issues | State inconsistency, UI manipulation |
| Low | Minor issues | Gas inefficiencies, cosmetic bugs |

## Trust Assumptions

The contract operates under these assumptions:

1. **Token contracts are benign**: The contract trusts that ERC20 tokens behave correctly. Malicious tokens (e.g., tokens with transfer hooks, blacklists, or admin functions) can cause unexpected behavior or fund loss.

2. **Users verify tokens**: The board does **not** check that token addresses have code. An EOA or empty address used as a token can make create, fill, or cancel fail. Makers must verify tokenA and tokenB before creating orders; takers must verify before filling. A malicious token can also cause fund loss.

3. **Block timestamps are accurate**: Order creation time relies on block timestamps, which miners can manipulate within ~15 seconds.

4. **No oracle dependency**: The contract has no price feeds. Users set their own prices and are responsible for fair pricing.

5. **Immutable deployment**: The contract cannot be upgraded or paused. Critical bugs require migration to a new contract.

## Known Limitations

The following are documented design decisions, not vulnerabilities:

1. **Front-running**: Inherent to on-chain orderbooks. Orders can be front-run by MEV bots. Users should consider using private mempools for large orders.

2. **Rebasing tokens**: Inbound mid-transfer rebases are rejected via `BalanceMismatch`. Post-deposit rebases (while tokenA sits in escrow) are not: a negative rebase can leave the contract under-collateralized so fill and cancel fail; a positive rebase can strand surplus that fills do not pay out. Users should not use rebasing tokens. See `contracts/test/security-research/`.

3. **No self-fill**: The maker cannot fill their own order (`SelfFill`). Typical ERC20 `transferFrom(self, self)` does not increase the recipient, so an exact-receive check would revert even for honest tokens. Supporting self-fill required routing tokenB through the board then back to the maker. Banning it keeps every fill payment a single pull to a distinct counterparty. Multi-maker Permit2 still hops through the board to split one pull across makers.

4. **Malicious tokenA is the real custodian of its escrow**: All orders selling the same ERC20 share one board balance of that token. Swapboard only tracks nominal `availableA`; it cannot stop the token from seizing, burning, or lying about that balance. Admin seize/burn or a lying `transfer` can take all escrow of that address. Makers of the same scam token therefore share one pool; after a rebase they race whatever balance remains. Other tokens in escrow are not affected. Blacklists, pausability, and admin mint can also disrupt fill/cancel. Users must verify token contracts.

5. **Partial fills are opt-in**: Orders default to all-or-nothing. Makers can allow partial fills at create or later via `setPartialFillAllowed`. Partial `fillOrder` floors tokenA. Rounding dust stays in escrow until a later fill or cancel.

6. **No expiration**: Orders remain active until filled or cancelled. There is no automatic expiration mechanism.

7. **ETH goes to `msg.sender`, so an address that rejects ETH can lock itself out**: There is no recipient override on any path (`cancelOrder`, fills, and modify refunds all pay `msg.sender` via `Address.sendValue`). A maker that is a contract reverting in `receive`/`fallback` (by design, after an upgrade, or once self-destructed) can never cancel an ETH-tokenA order, and that escrow stays in the contract forever; their ETH-tokenB orders are also unfillable because the taker's payment to them reverts. Likewise a taker that cannot accept ETH cannot fill ETH-tokenA orders. This is self-inflicted and no third party profits from it, but counterparties can waste gas discovering it. Use an EOA or a contract that accepts ETH for orders involving native ETH.

8. **Recipients must be able to hold the ERC20 they are paid**: Every ERC20 transfer out of the board (tokenA to the taker, tokenA refunds to the maker, tokenB to the maker) is verified against the recipient's balance delta and reverts `BalanceMismatch` when it does not match. An outbound fee-on-transfer or a recipient that forwards, stakes, or burns the token in a transfer hook therefore reverts the whole call, and the escrow stays. ETH is not balance-checked: `sendValue` already reverts when the recipient rejects it, and a contract may forward ETH it just received.

9. **Gas costs**: Users pay gas for all operations. Failed transactions (e.g., insufficient allowance) still cost gas.

## Bug Bounty

There is currently no formal bug bounty program. However, we may offer rewards for critical vulnerabilities at our discretion.

## Contract Immutability

The deployed contract is immutable. If a critical vulnerability is found:

1. A new contract will be deployed
2. Users will be notified to migrate
3. Frontend will be updated to point to the new contract
4. The old contract remains accessible but should not be used

## Security Tools

The codebase is continuously scanned with:

- **Slither**: Static analysis in CI pipeline
- **Forge coverage**: Test coverage reporting
- **Invariant testing**: Property-based testing with 8 invariants
- **Fuzz testing**: Input fuzzing on all public functions

## Audit Status

| Status | Item |
| -------- | ------ |
| Complete | Internal review |
| Complete | Slither analysis |
| Complete | Invariant test suite |
| Pending | External audit |
| Pending | Formal verification |
