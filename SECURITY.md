# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Swapboard, please report it responsibly.

**DO NOT** create a public GitHub issue for security vulnerabilities.

Instead, please send an email to: zcole@linux.com

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

The following are out of scope:
- Known behaviors documented below
- Third-party dependencies (report to upstream)
- Theoretical attacks without proof of concept
- Social engineering attacks

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

## Known Limitations

The following are documented design decisions, not vulnerabilities:

1. **Front-running**: Inherent to on-chain orderbooks. Orders can be front-run by MEV bots.

2. **Rebasing tokens**: May cause unexpected behavior. Users should not use rebasing tokens.

3. **Fee-on-transfer tokens**: Blocked for tokenA (selling token). Allowed for tokenB at maker's risk.

4. **Malicious tokens**: The contract cannot detect malicious token implementations. Users must verify token contracts before trading.

5. **No partial fills**: Orders must be filled entirely or not at all. This is by design.

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
