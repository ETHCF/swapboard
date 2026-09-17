.PHONY: all build build-contracts size test test-contracts test-e2e clean install fmt fmt-check lint coverage coverage-html snapshot snapshot-save snapshot-diff anvil deploy-local slither serve help

# Foundry project lives in contracts/ (repo git root is not the forge root).
# Run forge from contracts/ — `forge … --root contracts` breaks solar import resolution.
CONTRACTS := contracts
FORGE := cd $(CONTRACTS) && forge
GAS_SNAPSHOTS := $(CONTRACTS)/gas-snapshots
SNAPSHOT_COMPARE := python3 $(CONTRACTS)/scripts/compare_gas_snapshots.py

# Host port for local Anvil (e2e Docker maps 18545:8545; avoids clashes with RPC tunnels on 8545)
ANVIL_RPC_URL ?= http://localhost:18545
ANVIL_PORT ?= 18545

# Optional dated snapshot names for `make snapshot-diff A=... B=...`
A ?=
B ?=

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
	$(FORGE) build --sizes

# Show contract runtime / initcode sizes (EIP-170 margin)
size:
	$(FORGE) build --sizes

# Run unit/integration tests (no full Docker e2e stack)
test:
	$(FORGE) test -vvv
	cd subgraph && pnpm test

# Run contract tests only
test-contracts:
	$(FORGE) test -vvv

# Full stack e2e (Docker: anvil + graph-node + deploy + tests + teardown)
test-e2e:
	cd e2e && pnpm e2e

# Run contract tests with coverage (src only; mocks/tests excluded from report)
# `--ir-minimum`: coverage disables optimizer/viaIR; Swapboard needs IR to avoid stack-too-deep.
coverage:
	$(FORGE) coverage --ir-minimum --report summary --report lcov --exclude-tests --no-match-coverage 'test/' --no-match-contract GasBenchmarks

# Coverage summary + HTML report at contracts/coverage/
coverage-html: coverage
	cd $(CONTRACTS) && genhtml -o coverage lcov.info

# Format code
fmt:
	$(FORGE) fmt

# Check formatting
fmt-check:
	$(FORGE) fmt --check

# Lint contracts (fmt check + forge lint + solhint). Non-zero exit on any issues.
lint:
	$(FORGE) fmt --check
	cd $(CONTRACTS) && forge lint --deny warnings src script test
	cd $(CONTRACTS) && npx --yes solhint --max-warnings 0 'src/**/*.sol' 'script/**/*.sol' 'test/**/*.sol'

# Clean build artifacts
clean:
	$(FORGE) clean
	rm -rf subgraph/build subgraph/generated
	rm -rf e2e/node_modules/.cache

# Run local Anvil node (same host port as e2e)
anvil:
	anvil --block-time 1 --host 0.0.0.0 --port $(ANVIL_PORT)

# Deploy to local Anvil
deploy-local:
	@$(FORGE) script script/Deploy.s.sol \
		--rpc-url $(ANVIL_RPC_URL) \
		--private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
		--broadcast

# Gas snapshot: GasBenchmarks only → contracts/.gas-snapshot
snapshot:
	$(FORGE) snapshot --match-contract GasBenchmarks --snap .gas-snapshot

# Archive current .gas-snapshot as gas-snapshots/YYYY-MM-DDTHHMMSS.gas-snapshot
snapshot-save: snapshot
	@mkdir -p $(GAS_SNAPSHOTS)
	@dest="$(GAS_SNAPSHOTS)/$$(date +%Y-%m-%dT%H%M%S).gas-snapshot"; \
		cp $(CONTRACTS)/.gas-snapshot "$$dest"; \
		echo "Saved $$dest"

# Compare two snapshots as a markdown table.
# Usage: make snapshot-diff A=2026-09-01 B=2026-09-10
#    or: make snapshot-diff A=path/to/a.gas-snapshot B=path/to/b.gas-snapshot
snapshot-diff:
	@if [ -z "$(A)" ] || [ -z "$(B)" ]; then \
		echo "Usage: make snapshot-diff A=<date-or-path> B=<date-or-path>"; \
		exit 1; \
	fi
	@$(SNAPSHOT_COMPARE) "$(A)" "$(B)" "$(GAS_SNAPSHOTS)"

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
	@echo "  size            - Show contract runtime / initcode sizes"
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
	@echo "  snapshot        - Write GasBenchmarks gas → contracts/.gas-snapshot"
	@echo "  snapshot-save   - snapshot + archive to gas-snapshots/YYYY-MM-DDTHHMMSS.gas-snapshot"
	@echo "  snapshot-diff   - Compare two snapshots as a table (A=... B=...)"
	@echo "  slither         - Run Slither analysis"
	@echo "  serve           - Start frontend dev server"
