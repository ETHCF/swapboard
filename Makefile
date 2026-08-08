.PHONY: all build build-contracts test test-contracts test-e2e clean install fmt fmt-check lint coverage

all: build test

# Install dependencies
install:
	cd contracts && forge install
	cd subgraph && pnpm install
	cd e2e && pnpm install
	cd frontend && pnpm install

# Build all
build: lint build-contracts
	cd subgraph && pnpm build

# Build contracts only
build-contracts:
	cd contracts && forge build --sizes

# Run unit/integration tests (no full Docker e2e stack)
test:
	cd contracts && forge test -vvv
	cd subgraph && pnpm test

# Run contract tests only
test-contracts:
	cd contracts && forge test -vvv

# Full stack e2e (Docker: anvil + graph-node + deploy + tests + teardown)
test-e2e:
	cd e2e && pnpm e2e

# Run contract tests with coverage (src only; mocks/tests excluded from report)
coverage:
	cd contracts && forge coverage --report summary --report lcov --exclude-tests --no-match-coverage 'test/'

# Format code
fmt:
	cd contracts && forge fmt

# Check formatting
fmt-check:
	cd contracts && forge fmt --check

# Lint contracts (forge lint + solhint)
lint:
	cd contracts && forge lint
	cd contracts && npx --yes solhint 'src/**/*.sol' 'script/**/*.sol' 'test/**/*.sol'

# Clean build artifacts
clean:
	cd contracts && forge clean
	rm -rf subgraph/build subgraph/generated
	rm -rf e2e/node_modules/.cache

# Run local Anvil node
anvil:
	anvil --block-time 1

# Deploy to local Anvil (deploys MockWETH first, then Swapboard)
deploy-local:
	@cd contracts && \
	WETH_ADDR=$$(forge create test/mocks/MockWETH.sol:MockWETH \
		--rpc-url http://localhost:8545 \
		--private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
		--broadcast --json | jq -r '.deployedTo') && \
	echo "MockWETH deployed at: $$WETH_ADDR" && \
	WETH_ADDRESS=$$WETH_ADDR forge script script/Deploy.s.sol \
		--rpc-url http://localhost:8545 \
		--private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
		--broadcast

# Gas snapshot
snapshot:
	cd contracts && forge snapshot

# Slither analysis (requires slither installed)
slither:
	cd contracts && slither src/Swapboard.sol --config-file slither.config.json || true

# Frontend dev server
serve:
	cd frontend && npx serve . -p 3000

# Help
help:
	@echo "Available targets:"
	@echo "  install         - Install all dependencies"
	@echo "  build           - Lint, then build contracts and subgraph"
	@echo "  build-contracts - Build contracts only"
	@echo "  test            - Run contract + subgraph tests"
	@echo "  test-contracts  - Run contract tests only"
	@echo "  test-e2e        - Run full Docker e2e stack (setup + test + teardown)"
	@echo "  coverage        - Run contract tests with coverage"
	@echo "  fmt             - Format Solidity code"
	@echo "  fmt-check       - Check Solidity formatting"
	@echo "  lint            - Lint Solidity (forge lint + solhint)"
	@echo "  clean           - Clean build artifacts"
	@echo "  anvil           - Start local Anvil node"
	@echo "  deploy-local    - Deploy to local Anvil"
	@echo "  snapshot        - Generate gas snapshot"
	@echo "  slither         - Run Slither analysis"
	@echo "  serve           - Start frontend dev server"
