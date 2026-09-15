# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Swapboard, please report it responsibly.

**DO NOT** create a public GitHub issue for security vulnerabilities.

Instead, please send an email to: zak@numbergroup.xyz

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
|-------|-----------|
| Acknowledgment | 48 hours |
| Initial assessment | 7 days |
| Resolution | Varies by severity |
| Public disclosure | After fix deployed |

## Severity Levels

| Severity | Description | Example |
|----------|-------------|---------|
| Critical | Direct fund loss possible | Reentrancy, unauthorized withdrawals |
| High | Funds at risk under conditions | Denial of service, griefing |
| Medium | Data integrity issues | State inconsistency, UI manipulation |
| Low | Minor issues | Gas inefficiencies, cosmetic bugs |

## Trust Assumptions

The contract operates under these assumptions:

1. **Token contracts are benign**: The contract trusts that ERC20 tokens behave correctly. Malicious tokens (e.g., tokens with transfer hooks, blacklists, or admin functions) can cause unexpected behavior or fund loss.

2. **Users verify tokens**: Users are responsible for verifying token contract addresses and implementations before trading.

3. **Block timestamps are accurate**: Order creation time relies on block timestamps, which miners can manipulate within ~15 seconds.

4. **No oracle dependency**: The contract has no price feeds. Users set their own prices and are responsible for fair pricing.

5. **Immutable deployment**: The contract cannot be upgraded or paused. Critical bugs require migration to a new contract.

## Known Limitations

The following are documented design decisions, not vulnerabilities:

1. **Front-running**: Inherent to on-chain orderbooks. Orders can be front-run by MEV bots. Users should consider using private mempools for large orders.

2. **Rebasing tokens**: Inbound mid-transfer rebases are rejected via `BalanceMismatch`. Post-deposit rebases (while tokenA sits in escrow) are not: a negative rebase can leave the contract under-collateralized so fill and cancel fail; a positive rebase can strand surplus that fills do not pay out. Users should not use rebasing tokens. See `contracts/test/security-research/`.

3. **Outbound fee-on-transfer**: After escrow release, tokenA is sent with `transfer` and is not balance-checked, so outbound-only fee-on-transfer or mid-transfer rebase on that hop can short the taker. ERC20 tokenB payments to the maker (including self-fill and multi-maker Permit2 board hops) exact-check the recipient and revert `BalanceMismatch`. See `contracts/test/security-research/`.

4. **Malicious tokens**: The contract cannot detect malicious token implementations. Tokens with blacklists, pausability, or admin mint functions can disrupt trades.

5. **Partial fills are opt-in**: Orders default to all-or-nothing. Makers can allow partial fills at create or later via `setPartialFillAllowed`. Partial `fillOrder` floors tokenA; `fillOrderPaying` ceils tokenB. Rounding dust stays in escrow until a later fill or cancel.

6. **No expiration**: Orders remain active until filled or cancelled. There is no automatic expiration mechanism.

7. **Gas costs**: Users pay gas for all operations. Failed transactions (e.g., insufficient allowance) still cost gas.

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
|--------|------|
| Complete | Internal review |
| Complete | Slither analysis |
| Complete | Invariant test suite |
| Pending | External audit |
| Pending | Formal verification |
