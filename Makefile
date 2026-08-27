.PHONY: all build build-contracts test test-contracts test-e2e clean install fmt fmt-check lint coverage coverage-html snapshot snapshot-gas anvil deploy-local slither serve help

# Foundry project lives in contracts/ (repo git root is not the forge root).
CONTRACTS := contracts
# --root must follow the subcommand (e.g. `forge test --root contracts`).
FORGE_ROOT := --root $(CONTRACTS)

# Host port for local Anvil (e2e Docker maps 18545:8545; avoids clashes with RPC tunnels on 8545)
ANVIL_RPC_URL ?= http://localhost:18545
ANVIL_PORT ?= 18545

all: build test

# Install dependencies
install:
	cd $(CONTRACTS) && forge install
	cd subgraph && pnpm install
	cd e2e && pnpm install
	cd frontend && pnpm install

# Build all
build: lint build-contracts
	cd subgraph && pnpm build

# Build contracts only
build-contracts:
	forge build $(FORGE_ROOT) --sizes

# Run unit/integration tests (no full Docker e2e stack)
test:
	forge test $(FORGE_ROOT) -vvv
	cd subgraph && pnpm test

# Run contract tests only
test-contracts:
	forge test $(FORGE_ROOT) -vvv

# Full stack e2e (Docker: anvil + graph-node + deploy + tests + teardown)
test-e2e:
	cd e2e && pnpm e2e

# Run contract tests with coverage (src only; mocks/tests excluded from report)
coverage:
	forge coverage $(FORGE_ROOT) --report summary --report lcov --exclude-tests --no-match-coverage 'test/'

# Coverage summary + HTML report at contracts/coverage/
coverage-html: coverage
	cd $(CONTRACTS) && genhtml -o coverage lcov.info

# Format code
fmt:
	forge fmt $(FORGE_ROOT)

# Check formatting
fmt-check:
	forge fmt $(FORGE_ROOT) --check

# Lint contracts (fmt check + forge lint + solhint). Non-zero exit on any issues.
lint:
	forge fmt $(FORGE_ROOT) --check
	cd $(CONTRACTS) && forge lint --deny warnings src script test
	cd $(CONTRACTS) && npx --yes solhint --max-warnings 0 'src/**/*.sol' 'script/**/*.sol' 'test/**/*.sol'

# Clean build artifacts
clean:
	forge clean $(FORGE_ROOT)
	rm -rf subgraph/build subgraph/generated
	rm -rf e2e/node_modules/.cache

# Run local Anvil node (same host port as e2e)
anvil:
	anvil --block-time 1 --host 0.0.0.0 --port $(ANVIL_PORT)

# Deploy to local Anvil
deploy-local:
	@forge script $(FORGE_ROOT) script/Deploy.s.sol \
		--rpc-url $(ANVIL_RPC_URL) \
		--private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
		--broadcast

# Gas snapshot (full suite). Use snapshot-gas for the dedicated GasBenchmarks suite only.
snapshot:
	forge snapshot $(FORGE_ROOT)

# Fast gas snapshot for GasBenchmarks.t.sol only
snapshot-gas:
	forge snapshot $(FORGE_ROOT) --match-contract GasBenchmarks

# Slither analysis (requires slither installed)
slither:
	cd $(CONTRACTS) && slither src/Swapboard.sol --config-file slither.config.json || true

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
	@echo "  coverage-html   - Coverage + HTML report (contracts/coverage/)"
	@echo "  fmt             - Format Solidity code"
	@echo "  fmt-check       - Check Solidity formatting"
	@echo "  lint            - Check fmt + forge lint + solhint"
	@echo "  clean           - Clean build artifacts"
	@echo "  anvil           - Start local Anvil on port $(ANVIL_PORT)"
	@echo "  deploy-local    - Deploy to local Anvil ($(ANVIL_RPC_URL))"
	@echo "  snapshot        - Gas snapshot (full test suite)"
	@echo "  snapshot-gas    - Gas snapshot (GasBenchmarks only)"
	@echo "  slither         - Run Slither analysis"
	@echo "  serve           - Start frontend dev server"
