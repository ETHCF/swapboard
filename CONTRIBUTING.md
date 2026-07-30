# Contributing to Swapboard

## Development Setup

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Node.js](https://nodejs.org/) v20+
- [pnpm](https://pnpm.io/) v8+

### Clone and Install

```bash
git clone https://github.com/YOUR_USERNAME/swapboard.git
cd swapboard
make install
```

### Running Tests

```bash
# All tests (includes contract lint)
./test.sh

# Contract tests only
make test-contracts

# Lint (forge lint + solhint)
make lint

# Format
make fmt
```

## Code Style

### Solidity

- Follow the [Solidity Style Guide](https://docs.soliditylang.org/en/latest/style-guide.html)
- Use `make fmt` to format code
- Run `make lint` before opening a PR
- Maximum line length: 100 characters
- Use NatSpec comments for all public functions

### TypeScript

- Use strict mode
- Prefer explicit types over `any`
- Use async/await over raw promises

### JavaScript (Frontend)

- No build step - vanilla JS only
- Use strict mode (`"use strict"`)
- Prefer const/let over var
- Use meaningful variable names

## Pull Request Process

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make your changes
4. Run lint and tests (`make lint && ./test.sh`)
5. Commit with a clear message
6. Push to your fork
7. Open a Pull Request

### PR Requirements

- All tests must pass
- Code must be formatted (`make fmt` / `make fmt-check`)
- Linting must pass (`make lint`)
- Include test coverage for new features
- Update documentation if needed
- Keep commits atomic and well-described

## Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add new feature
fix: fix bug in X
docs: update README
test: add tests for Y
refactor: restructure Z
chore: update dependencies
```

## Architecture Decisions

Major changes should be discussed in an issue first. Include:
- Problem statement
- Proposed solution
- Alternative approaches considered
- Trade-offs

## Questions?

Open an issue with the `question` label.
