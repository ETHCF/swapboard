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

2. **Rebasing tokens**: Mid-transfer rebases on inbound pulls are rejected via `BalanceMismatch`. Post-deposit rebases (while tokenA sits in escrow) may leave the contract under-collateralized or lock surplus; positive rebases can strand excess. Users should not use rebasing tokens.

3. **Fee-on-transfer and phantom tokens**: Inbound fee-on-transfer, mid-transfer rebase, and phantom transfers are rejected on tokenA deposits and tokenB pulls via balance checks. Outbound fee-on-transfer or mid-transfer rebase on maker payout remains possible after an exact tokenB pull; makers may receive less than quoted `amountB`.

4. **Malicious tokens**: The contract cannot detect malicious token implementations. Tokens with blacklists, pausability, or admin mint functions can disrupt trades.

5. **No partial fills**: Orders must be filled entirely or not at all. This is by design for simplicity and gas efficiency.

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
