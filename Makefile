.PHONY: all build test clean install fmt lint

all: build test

# Install dependencies
install:
	cd contracts && forge install
	cd subgraph && pnpm install
	cd e2e && pnpm install

# Build all
build:
	cd contracts && forge build
	cd subgraph && pnpm build

# Run all tests
test:
	cd contracts && forge test -vvv
	cd subgraph && pnpm test
	cd e2e && pnpm test

# Run contract tests with coverage
coverage:
	cd contracts && forge coverage --report lcov

# Format code
fmt:
	cd contracts && forge fmt

# Check formatting
fmt-check:
	cd contracts && forge fmt --check

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
	@echo "  install      - Install all dependencies"
	@echo "  build        - Build contracts and subgraph"
	@echo "  test         - Run all tests"
	@echo "  coverage     - Run contract tests with coverage"
	@echo "  fmt          - Format Solidity code"
	@echo "  fmt-check    - Check Solidity formatting"
	@echo "  clean        - Clean build artifacts"
	@echo "  anvil        - Start local Anvil node"
	@echo "  deploy-local - Deploy to local Anvil"
	@echo "  snapshot     - Generate gas snapshot"
	@echo "  slither      - Run Slither analysis"
	@echo "  serve        - Start frontend dev server"
