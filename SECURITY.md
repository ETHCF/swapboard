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
- Known behaviors documented in `spec.md` (see "Known Behaviors" section)
- Fee-on-transfer token edge cases (documented)
- Rebasing token edge cases (documented)
- Front-running (inherent to on-chain order books)

## Response Timeline

- Acknowledgment: Within 48 hours
- Initial assessment: Within 7 days
- Resolution timeline: Depends on severity

## Severity Levels

**Critical**: Direct fund loss possible
**High**: Funds at risk under specific conditions
**Medium**: Denial of service or data integrity issues
**Low**: Minor issues with limited impact

## Bug Bounty

There is currently no formal bug bounty program. However, we may offer rewards for critical vulnerabilities at our discretion.

## Contract Immutability

Note that the deployed contract is immutable. If a critical vulnerability is found:
1. A new contract will be deployed
2. Users will be notified to migrate
3. Frontend will be updated to point to the new contract
4. The old contract remains accessible but should not be used

## Audit Status

- [ ] Internal review complete
- [ ] External audit pending
- [ ] Formal verification pending
