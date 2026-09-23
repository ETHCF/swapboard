// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ISwapboard} from "./interfaces/ISwapboard.sol";
import {ISignatureTransfer} from "./vendor/ISignatureTransfer.sol";
import {Semver} from "./Semver.sol";
import {Token, NATIVE_TOKEN, NATIVE_TOKEN_ADDRESS} from "./token/Token.sol";

/// @title Swapboard
/// @author Zak Cole (numbergroup.xyz) for Ethereum Community Foundation
/// @notice Trustless OTC bulletin board for ERC20 and native ETH swaps on Ethereum
/// @dev This contract implements a simple orderbook for peer-to-peer token swaps.
///
///      Key properties:
///      - No admin functions, fees, or upgrades
///      - Full fills are atomic; partial fills are opt-in via `partialFillAllowed`
///      - `fillOrder` sends exact tokenB (`amountB`) and receives floored tokenA, bounded by
///        `minAmountA`
///      - Fee-on-transfer / mid-transfer rebase / phantom transfers are rejected on inbound
///        tokenA deposits (`_pullExactToken`), on ERC20 tokenA paid to the taker and refunded to
///        the maker (`_transferExactTo` / `BalanceMismatch`), and on ERC20 tokenB payments to the
///        maker (`_transferExactFrom`, `_transferExactTo`), including multi-maker Permit2
///        board→maker distribution. ETH uses `msg.value` then `sendValue` and is not balance-checked
///        on the recipient, because a contract may forward the ETH it just received.
///      - The maker cannot fill their own order (`SelfFill`). A self-`transferFrom` of tokenB
///        does not increase the recipient, so supporting self-fill needed a board hop just to
///        satisfy the exact-receive check. Forbidding it keeps every fill payment a one-hop
///        pull to a distinct maker.
///      - Native ETH uses the `0xEeee...eE` sentinel (`getEth()`)
///      - EIP-2612 `permit` overloads set token allowance in the same transaction as the pull,
///        skipping the `permit` call when the existing allowance already covers the signed value
///        (a replayed signature spends the nonce but leaves the same allowance, so the pull still
///        works)
///      - Permit2 SignatureTransfer overloads pull via the canonical Permit2 contract
///      - Order amounts use `uint128` (sufficient for practical sizes); originals and available
///        remaining amounts are packed separately so fill % is readable on-chain
///      - Reentrancy protected via OpenZeppelin ReentrancyGuardTransient (EIP-1153)
///      - Token/ETH transfers go through `Token` (no-ops on amount 0; ETH via `sendValue`)
///
///      Security considerations:
///      - Front-running is possible on `fillOrder` / `fillOrders` (inherent to on-chain orderbooks)
///      - Inbound mid-transfer rebase is rejected via `BalanceMismatch`. Post-deposit rebase of
///        escrowed tokenA is not: a negative rebase can lock fill/cancel; a positive rebase can
///        strand surplus
///      - The board does not check that token addresses have code. Makers (and takers) must
///        verify token contracts before create/fill; a non-contract or malicious token can make
///        create/fill/cancel fail or cause fund loss
///      - Malicious tokens can cause fund loss - users must verify token contracts. Escrowed
///        tokenA of a given address is commingled: that token is the real custodian. Admin
///        seize/burn or a lying `transfer` can take all escrow of that token. Makers of the same
///        scam token share one pool; after a rebase they race whatever balance remains. Other
///        tokens in escrow are not affected
///      - Every ERC20 payment is verified against the recipient's balance delta, so an address that
///        does not retain the token (a vault that forwards/stakes/burns it in a transfer hook, or a
///        hooked token) reverts `BalanceMismatch`. A maker's orders are then unfillable, and a taker
///        cannot receive that tokenA. Recipients must simply hold the token.
///      - ETH is sent with `Address.sendValue` (forwards all gas) so contract recipients
///        can run `receive`/`fallback`; always after state updates (CEI)
///      - ETH always goes to `msg.sender`; no path takes a recipient override. An address that
///        reverts on receiving ETH (or self-destructs) locks itself out of native-ETH orders: as a
///        maker it can never `cancelOrder` an ETH-tokenA order, so that escrow stays here forever,
///        and its ETH-tokenB orders are unfillable; as a taker it cannot fill ETH-tokenA orders.
///        Self-inflicted and unprofitable for third parties, but it can waste counterparty gas
///      - Floor rounding on `fillOrder` may leave tokenA dust in escrow; refunding that dust is
///        not worth the gas. It can later benefit a user who rounds favorably on another fill
///        where that dust token is tokenB
///
/// @custom:security-contact zak@numbergroup.xyz
contract Swapboard is ISwapboard, Semver, ReentrancyGuardTransient {
    /// @notice Canonical Permit2 SignatureTransfer contract (immutable singleton)
    ISignatureTransfer private constant _PERMIT2 = ISignatureTransfer(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    /// @notice One fill leg after validation/quote (internal batch settlement)
    /// @param maker Address that receives tokenB for this leg
    /// @param tokenA Address of the token paid out to the taker
    /// @param amountA Amount of tokenA transferred to the taker
    /// @param tokenB Address of the token pulled from the taker
    /// @param amountB Amount of tokenB paid to the maker
    struct FillLeg {
        address maker;
        address tokenA;
        uint256 amountA;
        address tokenB;
        uint256 amountB;
    }

    /// @notice One modify leg after validation (internal batch settlement)
    /// @param tokenA Address of the escrowed asset (ETH sentinel or ERC20)
    /// @param topUp Amount of tokenA to pull from the maker (0 if none)
    /// @param refund Amount of tokenA to return to the maker (0 if none)
    struct ModifyLeg {
        address tokenA;
        uint256 topUp;
        uint256 refund;
    }

    /// @notice tokenA escrow delta between current and desired availableA
    /// @param topUp Amount to pull from the maker (0 if none)
    /// @param refund Amount to return to the maker (0 if none)
    struct EscrowADelta {
        uint256 topUp;
        uint256 refund;
    }

    /// @notice Aggregated ERC20 amounts with a separate ETH total
    /// @dev `tokens` / `amounts` may be longer than `count`; only the first `count` entries are valid
    /// @param tokens Distinct ERC20 tokens in first-seen order
    /// @param amounts Summed amount per token
    /// @param ethAmount Summed native ETH (0 if none)
    /// @param count Number of populated ERC20 entries
    struct AggregatedAmounts {
        address[] tokens;
        uint256[] amounts;
        uint256 ethAmount;
        uint256 count;
    }

    /// @notice Quote snapshot used to commit a fill
    /// @param maker Order maker
    /// @param tokenA Sold asset
    /// @param tokenB Payment asset
    /// @param amountA tokenA out for this fill
    /// @param amountB tokenB in for this fill
    /// @param availableA Pre-fill availableA
    /// @param availableB Pre-fill availableB
    struct FillQuote {
        address maker;
        address tokenA;
        address tokenB;
        uint128 amountA;
        uint128 amountB;
        uint128 availableA;
        uint128 availableB;
    }

    /// @notice Aggregated modify top-ups and refunds per unique tokenA
    /// @dev `tokens` / `topUps` / `refunds` may be longer than `count`
    /// @param tokens Distinct ERC20 tokenA values in first-seen order
    /// @param topUps Summed top-up per token
    /// @param refunds Summed refund per token
    /// @param ethTopUp Summed ETH top-up (not yet netted)
    /// @param ethRefund Summed ETH refund (not yet netted)
    /// @param count Number of populated ERC20 entries
    struct AggregatedModifyDeltas {
        address[] tokens;
        uint256[] topUps;
        uint256[] refunds;
        uint256 ethTopUp;
        uint256 ethRefund;
        uint256 count;
    }

    /// @notice Aggregated maker tokenB payouts from fill legs
    /// @param ethMakers Distinct makers receiving ETH tokenB
    /// @param ethAmounts ETH amount per maker
    /// @param ethCount Number of populated ETH maker entries
    /// @param recipients Maker recipients for ERC20 tokenB
    /// @param uniqueTokens Distinct ERC20 tokenB values (paired with recipients)
    /// @param uniqueAmounts Amount per `(maker, token)`
    /// @param uniqueCount Number of populated ERC20 entries
    struct MakerTokenBPayments {
        address[] ethMakers;
        uint256[] ethAmounts;
        uint256 ethCount;
        address[] recipients;
        address[] uniqueTokens;
        uint256[] uniqueAmounts;
        uint256 uniqueCount;
    }

    /// @notice Counter for generating unique order IDs
    /// @dev Starts at 0, increments by 1 for each new order
    uint256 private _nextOrderId;

    /// @notice Mapping from order ID to Order struct
    /// @dev Non-existent, fully filled, and cancelled orders return the default struct with
    ///      maker=address(0) (full fills and cancels `delete` storage)
    mapping(uint256 orderId => Order order) private _orders;

    /// @notice Initializes Swapboard
    constructor() Semver(2, 0, 0) {}

    /// @inheritdoc ISwapboard
    /// @dev Token addresses are identity-based. Aliased or rebranded tokens at different
    ///      addresses are treated as distinct tokens. The board does not check `code.length`;
    ///      makers must verify token addresses and implementations before creating orders.
    function createOrder(
        CreateOrderParams calldata order
    ) external payable nonReentrant returns (uint256) {
        return _createOrder(order);
    }

    /// @inheritdoc ISwapboard
    function createOrder(
        CreateOrderParams calldata order,
        Permit calldata permit
    ) external payable nonReentrant returns (uint256) {
        address tokenA = order.tokenA;
        _validateCreateOrder(tokenA, order.amountA, order.tokenB, order.amountB);
        _permit(tokenA, permit);

        return _depositAndStore(order);
    }

    /// @inheritdoc ISwapboard
    function createOrder(
        CreateOrderParams calldata order,
        Permit2Permit calldata permit
    ) external payable nonReentrant returns (uint256) {
        address tokenA = order.tokenA;
        _validateCreateOrder(tokenA, order.amountA, order.tokenB, order.amountB);
        if (permit.signature.length == 0) {
            return _depositAndStore(order);
        }

        return _depositAndStorePermit2(order, permit);
    }

    /// @inheritdoc ISwapboard
    function createOrders(
        CreateOrderParams[] calldata orders
    ) external payable nonReentrant returns (uint256[] memory) {
        return _createOrders(orders);
    }

    /// @inheritdoc ISwapboard
    function createOrders(
        CreateOrderParams[] calldata orders,
        TokenPermit[] calldata permits
    ) external payable nonReentrant returns (uint256[] memory) {
        if (permits.length == 0) {
            return _createOrders(orders);
        }

        return _createOrdersWithPermits(orders, permits);
    }

    /// @inheritdoc ISwapboard
    function createOrders(
        CreateOrderParams[] calldata orders,
        TokenPermit2[] calldata permits
    ) external payable nonReentrant returns (uint256[] memory) {
        if (permits.length == 0) {
            return _createOrders(orders);
        }

        return _createOrdersPermit2(orders, permits);
    }

    /// @inheritdoc ISwapboard
    /// @dev ERC20 tokenB is pulled directly to the maker via `_transferExactFrom`, and ERC20
    ///      tokenA is sent to the taker via `_transferExactTo`. Both reject fee-on-transfer /
    ///      mid-transfer rebase / phantom via `BalanceMismatch`. ETH uses `msg.value` then
    ///      `sendValue`.
    ///      tokenB in is the exact `amountB` the taker specified. tokenA out uses floor division
    ///      so the taker never over-receives relative to the escrow ratio. Residual tokenA dust
    ///      is not refunded.
    function fillOrder(
        uint256 orderId,
        uint128 amountB,
        uint128 minAmountA,
        uint256 deadline
    ) external payable nonReentrant {
        _fillOrder(orderId, amountB, minAmountA, deadline);
    }

    /// @inheritdoc ISwapboard
    function fillOrder(
        uint256 orderId,
        uint128 amountB,
        uint128 minAmountA,
        uint256 deadline,
        Permit calldata permit
    ) external payable nonReentrant {
        _permitAndSettleFill(_beginFill(orderId, amountB, minAmountA, deadline), permit);
    }

    /// @inheritdoc ISwapboard
    function fillOrder(
        uint256 orderId,
        uint128 amountB,
        uint128 minAmountA,
        uint256 deadline,
        Permit2Permit calldata permit
    ) external payable nonReentrant {
        _permit2AndSettleFill(_beginFill(orderId, amountB, minAmountA, deadline), permit);
    }

    /// @inheritdoc ISwapboard
    function fillOrders(
        FillOrderParams[] calldata fills,
        uint256 deadline
    ) external payable nonReentrant {
        _fillOrders(fills, deadline);
    }

    /// @inheritdoc ISwapboard
    function fillOrders(
        FillOrderParams[] calldata fills,
        uint256 deadline,
        TokenPermit[] calldata permits
    ) external payable nonReentrant {
        if (permits.length == 0) {
            _fillOrders(fills, deadline);

            return;
        }

        _fillOrdersWithPermits(fills, deadline, permits);
    }

    /// @inheritdoc ISwapboard
    function fillOrders(
        FillOrderParams[] calldata fills,
        uint256 deadline,
        TokenPermit2[] calldata permits
    ) external payable nonReentrant {
        if (permits.length == 0) {
            _fillOrders(fills, deadline);

            return;
        }

        _fillOrdersPermit2(fills, deadline, permits);
    }

    /// @inheritdoc ISwapboard
    function cancelOrder(
        uint256 orderId
    ) external nonReentrant {
        _cancelOrder(orderId);
    }

    /// @inheritdoc ISwapboard
    function cancelOrders(
        uint256[] calldata orderIds
    ) external nonReentrant {
        _cancelOrders(orderIds);
    }

    /// @notice Modifies an existing order's remaining liquidity
    /// @dev Reverts if `previousAmounts` does not match on-chain amounts to prevent concurrent-modify races.
    ///      Token addresses, maker, and `partialFillAllowed` are immutable here. Callers set desired
    ///      remaining amounts; totals are reset to those remainings. TokenA escrow is refunded or
    ///      topped-up for the availableA delta. `ZeroAmount` blocks remaining 0 — cancel instead.
    ///      `NoChange` when both remainings already match on-chain. Batch path: `modifyOrders`.
    /// @param orderId The unique identifier of the order to modify
    /// @param previousAmounts Expected current amounts from the caller's snapshot (race protection)
    /// @param updatedOrder Desired remaining amounts
    function modifyOrder(
        uint256 orderId,
        OrderAmounts calldata previousAmounts,
        ModifyOrderParams calldata updatedOrder
    ) external payable nonReentrant {
        _modifyOrder(orderId, previousAmounts, updatedOrder);
    }

    /// @inheritdoc ISwapboard
    function modifyOrder(
        uint256 orderId,
        OrderAmounts calldata previousAmounts,
        ModifyOrderParams calldata updatedOrder,
        Permit calldata permit
    ) external payable nonReentrant {
        ModifyLeg memory leg = _applyOneModifyEffect(orderId, previousAmounts, updatedOrder);
        // Non-skip permit with no top-up would burn the nonce without a pull.
        if (permit.v != 0 && leg.topUp == 0) {
            if (Token.wrap(leg.tokenA).isNative()) {
                revert PermitOnNative();
            }
            revert UnusedPermit();
        }
        _permit(leg.tokenA, permit);
        _settleModifyLeg(leg);
    }

    /// @inheritdoc ISwapboard
    function modifyOrder(
        uint256 orderId,
        OrderAmounts calldata previousAmounts,
        ModifyOrderParams calldata updatedOrder,
        Permit2Permit calldata permit
    ) external payable nonReentrant {
        ModifyLeg memory leg = _applyOneModifyEffect(orderId, previousAmounts, updatedOrder);
        _settleModifyLegPermit2(leg, permit);
    }

    /// @inheritdoc ISwapboard
    function modifyOrders(
        ModifyOrdersParams[] calldata mods
    ) external payable nonReentrant {
        _modifyOrders(mods);
    }

    /// @inheritdoc ISwapboard
    function modifyOrders(
        ModifyOrdersParams[] calldata mods,
        TokenPermit[] calldata permits
    ) external payable nonReentrant {
        if (permits.length == 0) {
            _modifyOrders(mods);

            return;
        }

        _modifyOrdersWithPermits(mods, permits);
    }

    /// @inheritdoc ISwapboard
    function modifyOrders(
        ModifyOrdersParams[] calldata mods,
        TokenPermit2[] calldata permits
    ) external payable nonReentrant {
        if (permits.length == 0) {
            _modifyOrders(mods);

            return;
        }

        _modifyOrdersPermit2(mods, permits);
    }

    /// @inheritdoc ISwapboard
    function setPartialFillAllowed(
        uint256 orderId,
        bool partialFillAllowed
    ) external nonReentrant {
        Order storage order = _orders[orderId];
        (address maker, bool currentPartialFillAllowed) = (order.maker, order.partialFillAllowed);
        if (maker == address(0)) {
            revert OrderNotFound(orderId);
        }
        _requireMaker(orderId, maker);
        if (partialFillAllowed == currentPartialFillAllowed) {
            revert NoChange();
        }

        order.partialFillAllowed = partialFillAllowed;

        emit OrderPartialFillUpdated(orderId, partialFillAllowed);
    }

    /// @inheritdoc ISwapboard
    function getEth() external pure returns (address) {
        return NATIVE_TOKEN_ADDRESS;
    }

    /// @inheritdoc ISwapboard
    function getNextOrderId() external view returns (uint256) {
        return _nextOrderId;
    }

    /// @inheritdoc ISwapboard
    function getOrder(
        uint256 orderId
    ) external view returns (Order memory) {
        return _orders[orderId];
    }

    /// @inheritdoc ISwapboard
    /// @dev Gas scales linearly with array length. Callers should limit to ~100 IDs per call.
    function getOrders(
        uint256[] calldata orderIds
    ) external view returns (Order[] memory) {
        uint256 length = orderIds.length;
        Order[] memory result = new Order[](length);

        for (uint256 i = 0; i < length; ++i) {
            result[i] = _orders[orderIds[i]];
        }

        return result;
    }

    /// @inheritdoc ISwapboard
    function canFill(
        uint256 orderId
    ) external view returns (bool) {
        return _orders[orderId].maker != address(0);
    }

    /// @notice Reverts unless the order exists
    /// @dev A stored order is always fillable: full fills and cancels `delete` it.
    /// @param orderId Order to load
    /// @return order Storage pointer to the live order
    function _requireActiveOrder(
        uint256 orderId
    ) private view returns (Order storage) {
        Order storage order = _orders[orderId];
        if (order.maker == address(0)) {
            revert OrderNotFound(orderId);
        }

        return order;
    }

    /// @notice Reverts unless the order is active and the caller is not its maker
    /// @dev Self-fill would `transferFrom` tokenB to `msg.sender`. Typical ERC20s do not change
    ///      that balance, so `BalanceMismatch` would fire even for honest tokens. Supporting it
    ///      required taker→board→maker hops. `SelfFill` keeps tokenB a single pull to a distinct
    ///      maker (Permit2 still hops through the board only when splitting one pull across makers).
    /// @param orderId Order to load for a fill
    /// @return order Storage pointer to the fillable order
    function _requireFillableOrder(
        uint256 orderId
    ) private view returns (Order storage) {
        Order storage order = _requireActiveOrder(orderId);
        if (order.maker == msg.sender) {
            revert SelfFill();
        }

        return order;
    }

    /// @notice Reverts when a non-zero deadline has already passed
    /// @param deadline Unix timestamp after which the call reverts (0 = no deadline)
    function _requireDeadline(
        uint256 deadline
    ) private view {
        if (deadline != 0 && block.timestamp > deadline) {
            revert DeadlineExpired();
        }
    }

    /// @notice Reverts when the fill amount is zero or the deadline has passed
    /// @param amount Requested fill amount
    /// @param deadline Unix timestamp after which the fill reverts (0 = no deadline)
    function _requireLiveFill(
        uint128 amount,
        uint256 deadline
    ) private view {
        _requireDeadline(deadline);
        if (amount == 0) {
            revert ZeroAmount();
        }
    }

    /// @notice Reverts on an expired deadline or empty fill batch
    /// @param deadline Unix timestamp after which the batch reverts (0 = no deadline)
    /// @param length Number of fill legs
    function _requireFillBatch(
        uint256 deadline,
        uint256 length
    ) private view {
        _requireDeadline(deadline);

        if (length == 0) {
            revert ZeroAmount();
        }
    }

    /// @notice Reverts unless `msg.sender` is the order's maker
    /// @param orderId Order being authorized
    /// @param maker Expected maker address
    function _requireMaker(
        uint256 orderId,
        address maker
    ) private view {
        if (msg.sender != maker) {
            revert NotMaker(orderId, msg.sender, maker);
        }
    }

    /// @notice Validates createOrder arguments (ETH is checked after deposit aggregation)
    /// @param tokenA Address of the asset to sell
    /// @param amountA Amount of tokenA to deposit
    /// @param tokenB Address of the asset wanted
    /// @param amountB Amount of tokenB required to fill
    function _validateCreateOrder(
        address tokenA,
        uint128 amountA,
        address tokenB,
        uint128 amountB
    ) private pure {
        if (tokenA == address(0) || tokenB == address(0)) {
            revert ZeroAddress();
        }
        if (amountA == 0 || amountB == 0) {
            revert ZeroAmount();
        }
        if (tokenA == tokenB) {
            revert SameToken();
        }
    }

    /// @notice Validates, deposits escrow, and stores one order
    /// @param order Order creation arguments
    /// @return orderId Identifier assigned to the created order
    function _createOrder(
        CreateOrderParams calldata order
    ) private returns (uint256) {
        _validateCreateOrder(order.tokenA, order.amountA, order.tokenB, order.amountB);

        return _depositAndStore(order);
    }

    /// @notice Pulls tokenA (or checks `msg.value` for ETH) and stores the order
    /// @dev Caller must already have validated create args and applied any permit.
    /// @param order Order creation arguments
    /// @return orderId Identifier assigned to the created order
    function _depositAndStore(
        CreateOrderParams calldata order
    ) private returns (uint256) {
        address tokenA = order.tokenA;
        uint128 amountA = order.amountA;

        Token token = Token.wrap(tokenA);
        if (token.isNative()) {
            _requireMsgValue(amountA);
        } else {
            _requireNoStrayEth();
            _pullExactToken(token, amountA);
        }

        return _storeOrder(order);
    }

    /// @notice Pulls tokenA via Permit2 then stores the order
    /// @param order Order creation arguments
    /// @param permit Permit2 signature for tokenA (non-empty)
    /// @return orderId Identifier assigned to the created order
    function _depositAndStorePermit2(
        CreateOrderParams calldata order,
        Permit2Permit calldata permit
    ) private returns (uint256) {
        address tokenA = order.tokenA;
        uint128 amountA = order.amountA;

        if (Token.wrap(tokenA).isNative()) {
            revert PermitOnNative();
        }
        _requireNoStrayEth();

        _pullExactViaPermit2(
            tokenA, address(this), amountA, permit.amount, permit.nonce, permit.deadline, permit.signature
        );

        return _storeOrder(order);
    }

    /// @notice Creates orders after aggregating ERC20 pulls and exact ETH payment
    /// @param orders Order creation arguments
    /// @return orderIds Identifiers assigned to each created order
    function _createOrders(
        CreateOrderParams[] calldata orders
    ) private returns (uint256[] memory) {
        if (orders.length == 0) {
            revert ZeroAmount();
        }

        _pullAggregatedTokens(_requireCreateBatchDeposits(orders));

        return _storeOrders(orders);
    }

    /// @notice Creates orders after EIP-2612 permits for every deposited ERC20
    /// @dev Unused permit entries revert `UnusedPermit` before any `permit` call.
    /// @param orders Order creation arguments
    /// @param permits EIP-2612 signatures keyed by tokenA
    /// @return orderIds Identifiers assigned to each created order
    function _createOrdersWithPermits(
        CreateOrderParams[] calldata orders,
        TokenPermit[] calldata permits
    ) private returns (uint256[] memory) {
        _validateTokenPermitBatch(permits);
        uint256 length = orders.length;
        if (length == 0) {
            revert ZeroAmount();
        }

        AggregatedAmounts memory deposits = _requireCreateBatchDeposits(orders);
        _requirePermitsUsed(permits, deposits.tokens, deposits.count);
        _applyValidatedPermits(permits);
        _pullAggregatedTokens(deposits);

        return _storeOrders(orders);
    }

    /// @notice Creates orders pulling ERC20 deposits via Permit2 where provided
    /// @param orders Order creation arguments
    /// @param permits Permit2 signatures keyed by tokenA
    /// @return orderIds Identifiers assigned to each created order
    function _createOrdersPermit2(
        CreateOrderParams[] calldata orders,
        TokenPermit2[] calldata permits
    ) private returns (uint256[] memory) {
        if (orders.length == 0) {
            revert ZeroAmount();
        }

        _validateTokenPermit2Batch(permits);
        _pullAggregatedTokensPermit2(_requireCreateBatchDeposits(orders), permits);

        return _storeOrders(orders);
    }

    /// @notice Aggregates create deposits and requires exact `msg.value` for ETH tokenA
    /// @param orders Order creation arguments
    /// @return deposits Distinct ERC20 deposits plus summed ETH
    function _requireCreateBatchDeposits(
        CreateOrderParams[] calldata orders
    ) private view returns (AggregatedAmounts memory deposits) {
        deposits = _aggregateDepositAssets(orders);
        if (msg.value != deposits.ethAmount) {
            revert ETHAmountMismatch(deposits.ethAmount, msg.value);
        }
    }

    /// @notice Validates create args and aggregates tokenA deposits (ETH summed separately)
    /// @param orders Order creation arguments
    /// @return aggregated Distinct ERC20 deposits plus summed ETH
    function _aggregateDepositAssets(
        CreateOrderParams[] calldata orders
    ) private pure returns (AggregatedAmounts memory aggregated) {
        uint256 length = orders.length;
        aggregated.tokens = new address[](length);
        aggregated.amounts = new uint256[](length);

        for (uint256 i = 0; i < length; ++i) {
            CreateOrderParams calldata params = orders[i];
            address token = params.tokenA;
            uint128 amountA = params.amountA;

            _validateCreateOrder(token, amountA, params.tokenB, params.amountB);

            uint256 amount = amountA;
            if (Token.wrap(token).isNative()) {
                aggregated.ethAmount += amount;

                continue;
            }

            uint256 existing = _indexOfToken(aggregated.tokens, aggregated.count, token);
            if (existing == aggregated.count) {
                aggregated.tokens[aggregated.count] = token;
                aggregated.amounts[aggregated.count] = amount;

                ++aggregated.count;
            } else {
                aggregated.amounts[existing] += amount;
            }
        }
    }

    /// @notice Aggregates per-token amounts and sums native ETH
    /// @dev ETH sentinel amounts are returned separately and omitted from `tokens`.
    ///      Zero amounts are harmless here; `Token.safeTransfer` / `safeTransferFrom` no-op on 0.
    /// @param tokens Deposit token for each leg
    /// @param amounts Deposit amount for each leg
    /// @return aggregated Distinct ERC20 amounts plus summed ETH
    function _aggregateTokenAmounts(
        address[] memory tokens,
        uint256[] memory amounts
    ) private pure returns (AggregatedAmounts memory aggregated) {
        uint256 length = tokens.length;
        aggregated.tokens = new address[](length);
        aggregated.amounts = new uint256[](length);

        for (uint256 i = 0; i < length; ++i) {
            address token = tokens[i];
            uint256 amount = amounts[i];
            if (Token.wrap(token).isNative()) {
                aggregated.ethAmount += amount;

                continue;
            }

            uint256 existing = _indexOfToken(aggregated.tokens, aggregated.count, token);
            if (existing == aggregated.count) {
                aggregated.tokens[aggregated.count] = token;
                aggregated.amounts[aggregated.count] = amount;

                ++aggregated.count;
            } else {
                aggregated.amounts[existing] += amount;
            }
        }
    }

    /// @notice Finds `token` in `tokens[0..length)`, or returns `length` if missing
    /// @param tokens Candidate token list
    /// @param length Number of populated entries
    /// @param token Token to look up
    /// @return index Matching index, or `length` when not found
    function _indexOfToken(
        address[] memory tokens,
        uint256 length,
        address token
    ) private pure returns (uint256) {
        for (uint256 i = 0; i < length; ++i) {
            if (tokens[i] == token) {
                return i;
            }
        }

        return length;
    }

    /// @notice Pulls each aggregated ERC20 deposit exactly once
    /// @param aggregated Distinct ERC20 amounts (ETH is ignored here; paid via msg.value)
    function _pullAggregatedTokens(
        AggregatedAmounts memory aggregated
    ) private {
        for (uint256 i = 0; i < aggregated.count; ++i) {
            _pullExactToken(Token.wrap(aggregated.tokens[i]), aggregated.amounts[i]);
        }
    }

    /// @notice Writes one created order to storage and emits `OrderCreated`
    /// @param params Order creation arguments
    /// @return orderId Identifier assigned to the order
    function _storeOrder(
        CreateOrderParams calldata params
    ) private returns (uint256) {
        uint256 orderId = _nextOrderId;

        // Unchecked is safe: wrapping `_nextOrderId` would require 2^256 orders.
        unchecked {
            _nextOrderId = orderId + 1;
        }

        _writeOrder(orderId, params);

        return orderId;
    }

    /// @notice Writes created orders to storage and emits `OrderCreated`
    /// @param orders Order creation arguments
    /// @return orderIds Identifiers assigned in input order
    function _storeOrders(
        CreateOrderParams[] calldata orders
    ) private returns (uint256[] memory) {
        uint256 length = orders.length;
        uint256[] memory orderIds = new uint256[](length);
        uint256 nextId = _nextOrderId;

        for (uint256 i = 0; i < length; ++i) {
            // Unchecked is safe: wrapping `_nextOrderId` would require 2^256 orders;
            // `i < length` and `_nextOrderId = nextId + length` below share that bound.
            uint256 orderId;
            unchecked {
                orderId = nextId + i;
            }
            orderIds[i] = orderId;

            // forge-lint: disable-next-item(costly-loop)
            _writeOrder(orderId, orders[i]);
        }

        // Unchecked is safe: wrapping `_nextOrderId` would require 2^256 orders.
        unchecked {
            _nextOrderId = nextId + length;
        }

        return orderIds;
    }

    /// @notice Packs one order into storage and emits `OrderCreated`
    /// @param orderId Identifier to assign
    /// @param params Order creation arguments
    function _writeOrder(
        uint256 orderId,
        CreateOrderParams calldata params
    ) private {
        _orders[orderId] = Order({
            maker: msg.sender,
            partialFillAllowed: params.partialFillAllowed,
            tokenA: params.tokenA,
            tokenB: params.tokenB,
            amountA: params.amountA,
            amountB: params.amountB,
            availableA: params.amountA,
            availableB: params.amountB
        });

        emit OrderCreated({
            orderId: orderId,
            maker: msg.sender,
            tokenA: params.tokenA,
            amountA: params.amountA,
            tokenB: params.tokenB,
            amountB: params.amountB,
            partialFillAllowed: params.partialFillAllowed
        });
    }

    /// @notice Quotes an exact-tokenB fill: pay `amountB`, receive floored tokenA
    /// @dev Floor division on tokenA so the taker never over-receives for the paid tokenB.
    ///      Intermediate math widens to uint256; both factors are uint128 so the product fits.
    ///      Reads only the fields needed for quoting (skips amountA/amountB originals).
    /// @param order Order to quote (must already be active)
    /// @param orderId Order id for error payloads
    /// @param amountB Exact tokenB to send
    /// @return quote Maker, tokens, fill amounts, and pre-fill availables
    function _quoteFill(
        Order storage order,
        uint256 orderId,
        uint128 amountB
    ) private view returns (FillQuote memory quote) {
        quote = _loadFillQuote(order);
        _requireFillRequest(orderId, amountB, quote.availableB, order.partialFillAllowed);

        quote.amountB = amountB;
        quote.amountA = _floorA(amountB, quote.availableA, quote.availableB);
        if (quote.amountA == 0) {
            revert ZeroAmount();
        }
    }

    /// @notice Copies maker/tokens/availables from storage into a fill quote
    /// @param order Order to quote
    /// @return quote Quote with settlement fields unset
    function _loadFillQuote(
        Order storage order
    ) private view returns (FillQuote memory quote) {
        quote.maker = order.maker;
        quote.tokenA = order.tokenA;
        quote.tokenB = order.tokenB;
        quote.availableA = order.availableA;
        quote.availableB = order.availableB;
    }

    /// @notice Reverts when a fill request exceeds remaining liquidity or violates all-or-nothing
    /// @param orderId Order id for error payloads
    /// @param requested Requested fill amount on the driving side
    /// @param remaining Remaining liquidity on that side
    /// @param partialFillAllowed Whether partial fills are allowed
    function _requireFillRequest(
        uint256 orderId,
        uint128 requested,
        uint128 remaining,
        bool partialFillAllowed
    ) private pure {
        if (requested > remaining) {
            revert FillAmountTooHigh(orderId, requested, remaining);
        }
        if (!partialFillAllowed && requested != remaining) {
            revert PartialFillNotAllowed(orderId);
        }
    }

    /// @notice Floored tokenA receive for `amountB` against remaining liquidity
    /// @dev `amountB == availableB` returns all remaining tokenA. Else branch implies
    ///      `amountB < availableB` so `availableB >= 1`; product of two uint128 values fits in
    ///      uint256; floor result is < `availableA`.
    /// @param amountB Requested tokenB in
    /// @param availableA Remaining tokenA in escrow
    /// @param availableB Remaining tokenB required
    /// @return Floored tokenA the taker receives
    function _floorA(
        uint128 amountB,
        uint128 availableA,
        uint128 availableB
    ) private pure returns (uint128) {
        if (amountB == availableB) {
            return availableA;
        }
        uint256 quotedA;
        unchecked {
            quotedA = (uint256(amountB) * uint256(availableA)) / uint256(availableB);
        }
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint128(quotedA);
    }

    /// @notice Checks deadline/amount, then applies one exact-tokenB fill effect
    /// @param orderId Order to fill
    /// @param amountB Exact tokenB to send
    /// @param minAmountA Minimum tokenA the taker will accept
    /// @param deadline Unix timestamp after which the fill reverts (0 = no deadline)
    /// @return quote Settled fill quote
    function _beginFill(
        uint256 orderId,
        uint128 amountB,
        uint128 minAmountA,
        uint256 deadline
    ) private returns (FillQuote memory quote) {
        _requireLiveFill(amountB, deadline);

        return _applyOneFillEffect(orderId, amountB, minAmountA);
    }

    /// @notice Fills one order by exact tokenB
    /// @param orderId Order to fill
    /// @param amountB Exact tokenB to send
    /// @param minAmountA Minimum tokenA the taker will accept
    /// @param deadline Unix timestamp after which the fill reverts (0 = no deadline)
    function _fillOrder(
        uint256 orderId,
        uint128 amountB,
        uint128 minAmountA,
        uint256 deadline
    ) private {
        _settleFillQuote(_beginFill(orderId, amountB, minAmountA, deadline));
    }

    /// @notice Fills orders after committing legs and settling tokenB/tokenA transfers
    /// @param fills Fill arguments in execution order
    /// @param deadline Unix timestamp after which the batch reverts (0 = no deadline)
    function _fillOrders(
        FillOrderParams[] calldata fills,
        uint256 deadline
    ) private {
        _requireFillBatch(deadline, fills.length);
        _settleFills(_applyFillEffects(fills));
    }

    /// @notice Fills orders after EIP-2612 permits for every pulled ERC20 tokenB
    /// @param fills Fill arguments in execution order
    /// @param deadline Unix timestamp after which the batch reverts (0 = no deadline)
    /// @param permits EIP-2612 signatures keyed by tokenB
    function _fillOrdersWithPermits(
        FillOrderParams[] calldata fills,
        uint256 deadline,
        TokenPermit[] calldata permits
    ) private {
        _validateTokenPermitBatch(permits);
        uint256 length = fills.length;
        _requireFillBatch(deadline, length);

        uint256[] memory orderIds = new uint256[](length);
        for (uint256 i = 0; i < length; ++i) {
            orderIds[i] = fills[i].orderId;
        }
        _requireAndApplyFillPermits(orderIds, permits);
        _fillOrders(fills, deadline);
    }

    /// @notice Requires every EIP-2612 permit matches a pulled ERC20 tokenB, then applies them
    /// @dev Caller must already have validated the permit batch.
    /// @param orderIds Orders whose tokenB may be pulled
    /// @param permits EIP-2612 signatures keyed by tokenB
    function _requireAndApplyFillPermits(
        uint256[] memory orderIds,
        TokenPermit[] calldata permits
    ) private {
        uint256 length = orderIds.length;
        address[] memory tokens = new address[](length);
        uint256 count = 0;
        for (uint256 i = 0; i < length; ++i) {
            count = _addUniqueErc20TokenB(orderIds[i], tokens, count);
        }

        _requirePermitsUsed(permits, tokens, count);
        _applyValidatedPermits(permits);
    }

    /// @notice Adds `order.tokenB` to `tokens` when it is a new ERC20
    /// @param orderId Order whose tokenB may be pulled
    /// @param tokens Distinct ERC20 tokenB values
    /// @param count Number of populated entries
    /// @return newCount Updated count
    function _addUniqueErc20TokenB(
        uint256 orderId,
        address[] memory tokens,
        uint256 count
    ) private view returns (uint256) {
        address tokenB = _requireActiveOrder(orderId).tokenB;
        if (Token.wrap(tokenB).isNative()) {
            return count;
        }
        if (_indexOfToken(tokens, count, tokenB) != count) {
            return count;
        }

        tokens[count] = tokenB;

        unchecked {
            return count + 1;
        }
    }

    /// @notice Validates one exact-tokenB fill, updates order storage, emits `OrderFilled`, and returns the quote
    /// @param orderId Order to fill
    /// @param amountB Exact tokenB to send
    /// @param minAmountA Minimum tokenA receive declared by the taker
    /// @return quote Settled fill quote
    function _applyOneFillEffect(
        uint256 orderId,
        uint128 amountB,
        uint128 minAmountA
    ) private returns (FillQuote memory quote) {
        Order storage order = _requireFillableOrder(orderId);
        quote = _quoteFill(order, orderId, amountB);

        if (quote.amountA < minAmountA) {
            revert FillAmountMismatch(orderId, quote.amountA, minAmountA);
        }

        // Unchecked is safe: _quoteFill ensures amountA <= availableA and
        // amountB <= availableB (exact remaining or floored proportion).
        _commitFill(order, orderId, quote);
    }

    /// @notice Writes remaining amounts (or deletes on exhaustion) and emits `OrderFilled`
    /// @dev Full fills `delete` the order so later reads look like `OrderNotFound` rather than an
    ///      inactive shell. Partial fills keep originals and update availables only.
    /// @param order Active order storage
    /// @param orderId Order id for the event
    /// @param quote Quoted fill amounts and pre-fill availables
    function _commitFill(
        Order storage order,
        uint256 orderId,
        FillQuote memory quote
    ) private {
        uint128 remainingA;
        uint128 remainingB;
        unchecked {
            remainingA = quote.availableA - quote.amountA;
            remainingB = quote.availableB - quote.amountB;
        }
        if (remainingA == 0 || remainingB == 0) {
            delete _orders[orderId];
        } else {
            order.availableA = remainingA;
            order.availableB = remainingB;
        }

        emit OrderFilled({orderId: orderId, taker: msg.sender, amountA: quote.amountA, amountB: quote.amountB});
    }

    /// @notice Validates one exact-tokenB fill into a batch settlement leg
    /// @param orderId Order to fill
    /// @param amountB Exact tokenB to send
    /// @param minAmountA Minimum tokenA receive declared by the taker
    /// @return leg Settled fill leg
    function _applyOneFillLeg(
        uint256 orderId,
        uint128 amountB,
        uint128 minAmountA
    ) private returns (FillLeg memory) {
        return _fillLegFromQuote(_applyOneFillEffect(orderId, amountB, minAmountA));
    }

    /// @notice Packs a settled fill quote into a batch transfer leg
    /// @param quote Settled fill quote
    /// @return leg Maker/token/amount fields for settlement
    function _fillLegFromQuote(
        FillQuote memory quote
    ) private pure returns (FillLeg memory) {
        return FillLeg({
            maker: quote.maker,
            tokenA: quote.tokenA,
            amountA: quote.amountA,
            tokenB: quote.tokenB,
            amountB: quote.amountB
        });
    }

    /// @notice Validates fills, updates order storage, and collects transfer legs
    /// @dev Same `orderId` may appear more than once; later legs see reduced available amounts.
    /// @param fills Fill arguments in execution order
    /// @return legs Settled fill legs in input order
    function _applyFillEffects(
        FillOrderParams[] calldata fills
    ) private returns (FillLeg[] memory) {
        uint256 length = fills.length;
        FillLeg[] memory legs = new FillLeg[](length);

        for (uint256 i = 0; i < length; ++i) {
            FillOrderParams calldata fill = fills[i];
            if (fill.amountB == 0) {
                revert ZeroAmount();
            }

            legs[i] = _applyOneFillLeg(fill.orderId, fill.amountB, fill.minAmountA);
        }

        return legs;
    }

    /// @notice Permits tokenB then pays maker tokenB and taker tokenA
    /// @param quote Settled fill quote
    /// @param permit EIP-2612 payload for `quote.tokenB` (`v == 0` skips)
    function _permitAndSettleFill(
        FillQuote memory quote,
        Permit calldata permit
    ) private {
        _permit(quote.tokenB, permit);
        _settleFillQuote(quote);
    }

    /// @notice Pulls tokenB via Permit2 (or classic skip) then pays taker tokenA
    /// @param quote Settled fill quote
    /// @param permit Permit2 payload for `quote.tokenB` (empty signature skips)
    function _permit2AndSettleFill(
        FillQuote memory quote,
        Permit2Permit calldata permit
    ) private {
        _payFillTokenBPermit2(quote, permit);
        _payTakerTokenA(quote);
    }

    /// @notice Pays maker tokenB and taker tokenA for a single settled fill quote
    /// @dev ERC20 tokenB goes taker → maker directly; ETH tokenB uses msg.value then sendValue.
    /// @param quote Settled fill quote
    function _settleFillQuote(
        FillQuote memory quote
    ) private {
        _payFillTokenB(quote);
        _payTakerTokenA(quote);
    }

    /// @notice Pays the taker tokenA for a settled single-fill quote
    /// @dev ERC20 tokenA must increase the taker's balance by exactly `amountA` (`BalanceMismatch`).
    ///      Native ETH is sent with `sendValue` and is not balance-checked.
    /// @param quote Settled fill quote
    function _payTakerTokenA(
        FillQuote memory quote
    ) private {
        Token tokenA = Token.wrap(quote.tokenA);
        if (tokenA.isNative()) {
            tokenA.safeTransfer(msg.sender, quote.amountA);

            return;
        }

        _transferExactTo(tokenA, msg.sender, quote.amountA);
    }

    /// @notice Collects tokenB for a single fill (classic allowance / msg.value)
    /// @param quote Settled fill quote
    function _payFillTokenB(
        FillQuote memory quote
    ) private {
        Token tokenB = Token.wrap(quote.tokenB);
        if (tokenB.isNative()) {
            _payNativeFillTokenB(tokenB, quote.maker, quote.amountB);

            return;
        }

        _requireNoStrayEth();
        _transferExactFrom(tokenB, quote.maker, quote.amountB);
    }

    /// @notice Collects tokenB for a single fill via Permit2 (empty signature = classic)
    /// @param quote Settled fill quote
    /// @param permit Permit2 payload for `quote.tokenB`
    function _payFillTokenBPermit2(
        FillQuote memory quote,
        Permit2Permit calldata permit
    ) private {
        Token tokenB = Token.wrap(quote.tokenB);
        if (tokenB.isNative()) {
            if (permit.signature.length != 0) {
                revert PermitOnNative();
            }
            _payNativeFillTokenB(tokenB, quote.maker, quote.amountB);

            return;
        }

        _requireNoStrayEth();
        if (permit.signature.length == 0) {
            _transferExactFrom(tokenB, quote.maker, quote.amountB);

            return;
        }

        _pullExactViaPermit2(
            quote.tokenB, quote.maker, quote.amountB, permit.amount, permit.nonce, permit.deadline, permit.signature
        );
    }

    /// @notice Forwards native tokenB from `msg.value` to the maker
    /// @param tokenB Native ETH sentinel
    /// @param maker Order maker
    /// @param amountB Exact ETH amount required
    function _payNativeFillTokenB(
        Token tokenB,
        address maker,
        uint256 amountB
    ) private {
        _requireMsgValue(amountB);
        tokenB.safeTransfer(maker, amountB);
    }

    /// @notice Reverts when `msg.value` is not exactly `expected`
    /// @param expected Required ETH amount (0 for ERC20-only calls)
    function _requireMsgValue(
        uint256 expected
    ) private view {
        if (msg.value != expected) {
            revert ETHAmountMismatch(expected, msg.value);
        }
    }

    /// @notice Reverts when ERC20 fills are called with a non-zero `msg.value`
    function _requireNoStrayEth() private view {
        _requireMsgValue(0);
    }

    /// @notice Fills orders via Permit2 for ERC20 tokenB where provided
    /// @param fills Fill arguments in execution order
    /// @param deadline Unix timestamp after which the batch reverts (0 = no deadline)
    /// @param permits Permit2 signatures keyed by tokenB
    function _fillOrdersPermit2(
        FillOrderParams[] calldata fills,
        uint256 deadline,
        TokenPermit2[] calldata permits
    ) private {
        uint256 length = fills.length;
        _requireFillBatch(deadline, length);
        _validateTokenPermit2Batch(permits);
        _settleFillsPermit2(_applyFillEffects(fills), permits);
    }

    /// @notice Pays makers/taker for settled fill legs (ERC20 tokenB direct to makers)
    /// @param legs Settled fill legs
    function _settleFills(
        FillLeg[] memory legs
    ) private {
        _settleFillsPermit2(legs, _emptyTokenPermit2());
    }

    /// @notice Pays makers/taker using Permit2 for ERC20 tokenB totals pulled to this contract
    /// @dev Per distinct ERC20 with a Permit2 entry, the total across makers is pulled here once,
    ///      then distributed. Tokens without an entry use classic direct-to-maker pulls.
    /// @param legs Settled fill legs
    /// @param permits Permit2 signatures keyed by tokenB
    function _settleFillsPermit2(
        FillLeg[] memory legs,
        TokenPermit2[] memory permits
    ) private {
        _requireFillMsgValue(legs);
        _payMakersFromLegsPermit2(legs, permits);
        _payTakerFromLegs(legs);
    }

    /// @notice Requires `msg.value` equals total native tokenB across fill legs
    /// @param legs Settled fill legs
    function _requireFillMsgValue(
        FillLeg[] memory legs
    ) private view {
        uint256 ethAmount = _sumFillEthTokenB(legs);
        if (msg.value != ethAmount) {
            revert ETHAmountMismatch(ethAmount, msg.value);
        }
    }

    /// @notice Sums native tokenB amounts across fill legs
    /// @param legs Settled fill legs
    /// @return ethAmount Total ETH the taker must send
    function _sumFillEthTokenB(
        FillLeg[] memory legs
    ) private pure returns (uint256 ethAmount) {
        uint256 length = legs.length;
        for (uint256 i = 0; i < length; ++i) {
            FillLeg memory leg = legs[i];
            if (Token.wrap(leg.tokenB).isNative()) {
                ethAmount += leg.amountB;
            }
        }
    }

    /// @notice Pays makers tokenB using Permit2 totals to this contract where provided
    /// @param legs Settled fill legs
    /// @param permits Permit2 signatures keyed by tokenB
    function _payMakersFromLegsPermit2(
        FillLeg[] memory legs,
        TokenPermit2[] memory permits
    ) private {
        MakerTokenBPayments memory payments = _aggregateMakerTokenB(legs);
        _sendMakerEthTokenB(payments);
        _pullAndDistributePermit2TokenB(
            payments.recipients, payments.uniqueTokens, payments.uniqueAmounts, payments.uniqueCount, permits
        );
    }

    /// @notice Aggregates ETH and ERC20 tokenB payouts to makers from fill legs
    /// @param legs Settled fill legs
    /// @return payments Aggregated maker tokenB destinations and amounts
    function _aggregateMakerTokenB(
        FillLeg[] memory legs
    ) private pure returns (MakerTokenBPayments memory payments) {
        uint256 length = legs.length;
        payments.ethMakers = new address[](length);
        payments.ethAmounts = new uint256[](length);
        payments.recipients = new address[](length);
        payments.uniqueTokens = new address[](length);
        payments.uniqueAmounts = new uint256[](length);

        for (uint256 i = 0; i < length; ++i) {
            FillLeg memory leg = legs[i];
            address token = leg.tokenB;
            uint256 amount = leg.amountB;
            address maker = leg.maker;
            if (Token.wrap(token).isNative()) {
                uint256 existingEth = _indexOfToken(payments.ethMakers, payments.ethCount, maker);
                if (existingEth == payments.ethCount) {
                    payments.ethMakers[payments.ethCount] = maker;
                    payments.ethAmounts[payments.ethCount] = amount;
                    ++payments.ethCount;
                } else {
                    payments.ethAmounts[existingEth] += amount;
                }
                continue;
            }

            uint256 existing =
                _indexOfRecipientToken(payments.recipients, payments.uniqueTokens, payments.uniqueCount, maker, token);
            if (existing == payments.uniqueCount) {
                payments.recipients[payments.uniqueCount] = maker;
                payments.uniqueTokens[payments.uniqueCount] = token;
                payments.uniqueAmounts[payments.uniqueCount] = amount;
                ++payments.uniqueCount;
            } else {
                payments.uniqueAmounts[existing] += amount;
            }
        }
    }

    /// @notice Forwards aggregated ETH tokenB to makers
    /// @param payments Aggregated maker tokenB payouts
    function _sendMakerEthTokenB(
        MakerTokenBPayments memory payments
    ) private {
        for (uint256 j = 0; j < payments.ethCount; ++j) {
            NATIVE_TOKEN.safeTransfer(payments.ethMakers[j], payments.ethAmounts[j]);
        }
    }

    /// @notice Pulls Permit2 tokenB totals, then pays makers; classic pull otherwise
    /// @dev Single-recipient Permit2 pulls go straight to that maker. Multi-maker totals for the
    ///      same token pull to this contract once, then `_transferExactTo` each maker.
    /// @param recipients Maker recipients for ERC20 tokenB
    /// @param uniqueTokens Distinct ERC20 tokenB values
    /// @param uniqueAmounts Amount per `(maker, token)`
    /// @param uniqueCount Number of populated ERC20 entries
    /// @param permits Permit2 signatures keyed by tokenB
    function _pullAndDistributePermit2TokenB(
        address[] memory recipients,
        address[] memory uniqueTokens,
        uint256[] memory uniqueAmounts,
        uint256 uniqueCount,
        TokenPermit2[] memory permits
    ) private {
        uint256 permitLength = permits.length;
        uint256[] memory boardTotals = new uint256[](permitLength);
        address[] memory soleRecipient = new address[](permitLength);
        uint256[] memory recipientCounts = new uint256[](permitLength);
        uint256[] memory permitIndexByUnique = new uint256[](uniqueCount);

        uint256 usedBits = _accumulatePermit2TokenB(
            recipients,
            uniqueTokens,
            uniqueAmounts,
            uniqueCount,
            permits,
            boardTotals,
            soleRecipient,
            recipientCounts,
            permitIndexByUnique
        );
        _requireAllPermit2BitsUsed(usedBits, permitLength);
        _executePermit2TokenBPulls(permits, boardTotals, soleRecipient, recipientCounts);
        _distributeMultiMakerPermit2TokenB(
            recipients, uniqueTokens, uniqueAmounts, uniqueCount, permitIndexByUnique, recipientCounts, permitLength
        );
    }

    /// @notice Classic-pulls unmarked tokenB legs and aggregates Permit2 totals / recipient counts
    /// @param recipients Maker recipients for ERC20 tokenB
    /// @param uniqueTokens Distinct ERC20 tokenB values
    /// @param uniqueAmounts Amount per `(maker, token)`
    /// @param uniqueCount Number of populated ERC20 entries
    /// @param permits Permit2 signatures keyed by tokenB
    /// @param boardTotals Out: aggregated Permit2 pull amounts by permit index
    /// @param soleRecipient Out: first maker for each permit index
    /// @param recipientCounts Out: number of unique makers per permit index
    /// @param permitIndexByUnique Out: permit index (or `permits.length`) per unique leg
    /// @return usedBits Bitmap of Permit2 entries that matched a unique leg
    function _accumulatePermit2TokenB(
        address[] memory recipients,
        address[] memory uniqueTokens,
        uint256[] memory uniqueAmounts,
        uint256 uniqueCount,
        TokenPermit2[] memory permits,
        uint256[] memory boardTotals,
        address[] memory soleRecipient,
        uint256[] memory recipientCounts,
        uint256[] memory permitIndexByUnique
    ) private returns (uint256 usedBits) {
        uint256 permitLength = permits.length;
        for (uint256 k = 0; k < uniqueCount; ++k) {
            address token = uniqueTokens[k];
            uint256 permitIndex = _indexOfTokenPermit2(permits, token);
            permitIndexByUnique[k] = permitIndex;
            if (permitIndex == permitLength) {
                _transferExactFrom(Token.wrap(token), recipients[k], uniqueAmounts[k]);
                continue;
            }

            usedBits |= uint256(1) << permitIndex;
            boardTotals[permitIndex] += uniqueAmounts[k];

            uint256 priorCount = recipientCounts[permitIndex];
            if (priorCount == 0) {
                soleRecipient[permitIndex] = recipients[k];
            }
            unchecked {
                recipientCounts[permitIndex] = priorCount + 1;
            }
        }
    }

    /// @notice Executes Permit2 pulls: direct to sole maker, or to this contract for multi-maker
    /// @param permits Permit2 signatures keyed by tokenB
    /// @param boardTotals Aggregated Permit2 pull amounts by permit index
    /// @param soleRecipient First maker for each permit index
    /// @param recipientCounts Number of unique makers per permit index
    function _executePermit2TokenBPulls(
        TokenPermit2[] memory permits,
        uint256[] memory boardTotals,
        address[] memory soleRecipient,
        uint256[] memory recipientCounts
    ) private {
        uint256 permitLength = permits.length;
        for (uint256 p = 0; p < permitLength; ++p) {
            TokenPermit2 memory permit = permits[p];
            uint256 total = boardTotals[p];
            if (recipientCounts[p] == 1) {
                _pullExactViaPermit2(
                    permit.token,
                    soleRecipient[p],
                    total,
                    permit.amount,
                    permit.nonce,
                    permit.deadline,
                    permit.signature
                );
                continue;
            }

            _pullExactViaPermit2(
                permit.token, address(this), total, permit.amount, permit.nonce, permit.deadline, permit.signature
            );
        }
    }

    /// @notice Pays multi-maker Permit2 tokenB from board balances after the aggregated pull
    /// @dev Each maker hop uses `_transferExactTo` (`BalanceMismatch` if outbound FOT / phantom).
    /// @param recipients Maker recipients for ERC20 tokenB
    /// @param uniqueTokens Distinct ERC20 tokenB values
    /// @param uniqueAmounts Amount per `(maker, token)`
    /// @param uniqueCount Number of populated ERC20 entries
    /// @param permitIndexByUnique Permit index (or `permitLength`) per unique leg
    /// @param recipientCounts Number of unique makers per permit index
    /// @param permitLength Number of Permit2 entries
    function _distributeMultiMakerPermit2TokenB(
        address[] memory recipients,
        address[] memory uniqueTokens,
        uint256[] memory uniqueAmounts,
        uint256 uniqueCount,
        uint256[] memory permitIndexByUnique,
        uint256[] memory recipientCounts,
        uint256 permitLength
    ) private {
        for (uint256 m = 0; m < uniqueCount; ++m) {
            uint256 permitIndex = permitIndexByUnique[m];
            if (permitIndex == permitLength || recipientCounts[permitIndex] == 1) {
                continue;
            }
            _transferExactTo(Token.wrap(uniqueTokens[m]), recipients[m], uniqueAmounts[m]);
        }
    }

    /// @notice Pays the taker aggregated tokenA from fill legs
    /// @param legs Settled fill legs
    function _payTakerFromLegs(
        FillLeg[] memory legs
    ) private {
        uint256 length = legs.length;
        AggregatedAmounts memory payouts;
        payouts.tokens = new address[](length);
        payouts.amounts = new uint256[](length);

        for (uint256 i = 0; i < length; ++i) {
            FillLeg memory leg = legs[i];
            address token = leg.tokenA;
            uint256 amount = leg.amountA;
            if (Token.wrap(token).isNative()) {
                payouts.ethAmount += amount;

                continue;
            }

            uint256 existing = _indexOfToken(payouts.tokens, payouts.count, token);
            if (existing == payouts.count) {
                payouts.tokens[payouts.count] = token;
                payouts.amounts[payouts.count] = amount;

                ++payouts.count;
            } else {
                payouts.amounts[existing] += amount;
            }
        }

        _sendAggregated(payouts, msg.sender);
    }

    /// @notice Sends aggregated ERC20 and optional ETH to one recipient
    /// @dev ERC20 transfers must increase `recipient` by exactly the aggregated amount
    ///      (`BalanceMismatch`). ETH uses `sendValue` and is not balance-checked.
    ///      `Token.safeTransfer` no-ops on amount 0 (some ERC20s revert on zero-value transfers).
    /// @param aggregated Distinct ERC20 amounts plus optional ETH
    /// @param recipient Token/ETH recipient
    function _sendAggregated(
        AggregatedAmounts memory aggregated,
        address recipient
    ) private {
        if (aggregated.ethAmount != 0) {
            NATIVE_TOKEN.safeTransfer(recipient, aggregated.ethAmount);
        }

        for (uint256 i = 0; i < aggregated.count; ++i) {
            _transferExactTo(Token.wrap(aggregated.tokens[i]), recipient, aggregated.amounts[i]);
        }
    }

    /// @notice Finds `(recipient, token)` in parallel arrays, or returns `length` if missing
    /// @param recipients Candidate recipient list
    /// @param tokens Candidate token list
    /// @param length Number of populated entries
    /// @param recipient Recipient to look up
    /// @param token Token to look up
    /// @return index Matching index, or `length` when not found
    function _indexOfRecipientToken(
        address[] memory recipients,
        address[] memory tokens,
        uint256 length,
        address recipient,
        address token
    ) private pure returns (uint256) {
        for (uint256 i = 0; i < length; ++i) {
            if (recipients[i] == recipient && tokens[i] == token) {
                return i;
            }
        }

        return length;
    }

    /// @notice Modifies one order's remaining liquidity
    /// @param orderId Order to modify
    /// @param previousAmounts Expected on-chain amounts from the caller's snapshot
    /// @param updatedOrder Desired remaining amounts
    function _modifyOrder(
        uint256 orderId,
        OrderAmounts calldata previousAmounts,
        ModifyOrderParams calldata updatedOrder
    ) private {
        _settleModifyLeg(_applyOneModifyEffect(orderId, previousAmounts, updatedOrder));
    }

    /// @notice Modifies orders after validating duplicates and aggregating escrow deltas
    /// @param mods Modify arguments in execution order
    function _modifyOrders(
        ModifyOrdersParams[] calldata mods
    ) private {
        if (mods.length == 0) {
            revert ZeroAmount();
        }

        _validateModifyOrders(mods);
        _settleModifyLegs(_applyModifyEffects(mods));
    }

    /// @notice Modifies orders after EIP-2612 permits for every net ERC20 top-up
    /// @param mods Modify arguments in execution order
    /// @param permits EIP-2612 signatures keyed by tokenA
    function _modifyOrdersWithPermits(
        ModifyOrdersParams[] calldata mods,
        TokenPermit[] calldata permits
    ) private {
        _validateTokenPermitBatch(permits);
        uint256 length = mods.length;
        if (length == 0) {
            revert ZeroAmount();
        }

        _validateModifyOrders(mods);
        (address[] memory tokens, uint256 count) = _previewNetErc20TopUpTokens(mods);
        _requirePermitsUsed(permits, tokens, count);
        _applyValidatedPermits(permits);

        _settleModifyLegs(_applyModifyEffects(mods));
    }

    /// @notice Applies every modify effect into settlement legs
    /// @param mods Modify arguments in execution order
    /// @return legs Escrow top-up / refund for each mod
    function _applyModifyEffects(
        ModifyOrdersParams[] calldata mods
    ) private returns (ModifyLeg[] memory legs) {
        uint256 length = mods.length;
        legs = new ModifyLeg[](length);
        for (uint256 i = 0; i < length; ++i) {
            ModifyOrdersParams calldata mod = mods[i];
            legs[i] = _applyOneModifyEffect(mod.orderId, mod.previousAmounts, mod.updatedOrder);
        }
    }

    /// @notice Distinct ERC20 tokenA values that would have a net top-up (no storage writes)
    /// @param mods Modify arguments in execution order
    /// @return tokens Tokens that will be pulled
    /// @return count Number of populated entries
    function _previewNetErc20TopUpTokens(
        ModifyOrdersParams[] calldata mods
    ) private view returns (address[] memory tokens, uint256 count) {
        uint256 length = mods.length;
        AggregatedModifyDeltas memory deltas;
        deltas.tokens = new address[](length);
        deltas.topUps = new uint256[](length);
        deltas.refunds = new uint256[](length);

        for (uint256 i = 0; i < length; ++i) {
            ModifyOrdersParams calldata mod = mods[i];
            Order storage order = _requireActiveOrder(mod.orderId);
            address tokenA = order.tokenA;
            if (Token.wrap(tokenA).isNative()) {
                continue;
            }

            EscrowADelta memory delta = _escrowADelta(mod.updatedOrder.availableA, order.availableA);
            uint256 existing = _indexOfToken(deltas.tokens, deltas.count, tokenA);
            if (existing == deltas.count) {
                deltas.tokens[deltas.count] = tokenA;
                deltas.topUps[deltas.count] = delta.topUp;
                deltas.refunds[deltas.count] = delta.refund;
                unchecked {
                    ++deltas.count;
                }
            } else {
                deltas.topUps[existing] += delta.topUp;
                deltas.refunds[existing] += delta.refund;
            }
        }

        return _netErc20TopUpTokens(deltas);
    }

    /// @notice Distinct ERC20 tokenA values with a net modify top-up
    /// @param deltas Aggregated modify deltas
    /// @return tokens Tokens that will be pulled
    /// @return count Number of populated entries
    function _netErc20TopUpTokens(
        AggregatedModifyDeltas memory deltas
    ) private pure returns (address[] memory tokens, uint256 count) {
        tokens = new address[](deltas.count);
        for (uint256 i = 0; i < deltas.count; ++i) {
            if (deltas.topUps[i] > deltas.refunds[i]) {
                tokens[count] = deltas.tokens[i];
                unchecked {
                    ++count;
                }
            }
        }
    }

    /// @notice Validates every order in a modify batch for duplicate IDs
    /// @param mods Modify arguments to check
    function _validateModifyOrders(
        ModifyOrdersParams[] calldata mods
    ) private pure {
        uint256 length = mods.length;
        uint256[] memory orderIds = new uint256[](length);
        for (uint256 i = 0; i < length; ++i) {
            orderIds[i] = mods[i].orderId;
        }
        _requireUniqueOrderIds(orderIds);
    }

    /// @notice Reverts when any order id appears more than once
    /// @param orderIds Identifiers to check
    function _requireUniqueOrderIds(
        uint256[] memory orderIds
    ) private pure {
        uint256 length = orderIds.length;
        for (uint256 i = 0; i < length; ++i) {
            uint256 orderId = orderIds[i];
            for (uint256 j = i + 1; j < length; ++j) {
                if (orderIds[j] == orderId) {
                    revert DuplicateOrderId(orderId);
                }
            }
        }
    }

    /// @notice Validates one modify, updates order storage, emits `OrderModified`, and returns the leg
    /// @param orderId Order to modify
    /// @param previousAmounts Expected on-chain amounts from the caller's snapshot
    /// @param updatedOrder Desired remaining amounts
    /// @return leg Escrow top-up / refund for settlement
    function _applyOneModifyEffect(
        uint256 orderId,
        OrderAmounts calldata previousAmounts,
        ModifyOrderParams calldata updatedOrder
    ) private returns (ModifyLeg memory) {
        Order storage order = _requireActiveOrder(orderId);

        address maker = order.maker;
        address tokenA = order.tokenA;
        _requireMaker(orderId, maker);

        uint128 amountA = order.amountA;
        uint128 amountB = order.amountB;
        uint128 availableA = order.availableA;
        uint128 availableB = order.availableB;
        _requireOrderAmountsMatch(orderId, previousAmounts, amountA, amountB, availableA, availableB);

        uint128 newAvailableA = updatedOrder.availableA;
        uint128 newAvailableB = updatedOrder.availableB;
        if (newAvailableA == 0 || newAvailableB == 0) {
            revert ZeroAmount();
        }
        if (newAvailableA == availableA && newAvailableB == availableB) {
            revert NoChange();
        }

        EscrowADelta memory delta = _escrowADelta(newAvailableA, availableA);

        // Reset totals to the new remainings (filled history is not preserved in amount fields).
        order.amountA = newAvailableA;
        order.amountB = newAvailableB;
        order.availableA = newAvailableA;
        order.availableB = newAvailableB;

        emit OrderModified(orderId, newAvailableA, newAvailableB);

        return ModifyLeg({tokenA: tokenA, topUp: delta.topUp, refund: delta.refund});
    }

    /// @notice Reverts when live amounts differ from the caller's previousAmounts snapshot
    /// @param orderId Order id for the error payload
    /// @param previousAmounts Expected amounts from the caller
    /// @param amountA Live `amountA`
    /// @param amountB Live `amountB`
    /// @param availableA Live `availableA`
    /// @param availableB Live `availableB`
    function _requireOrderAmountsMatch(
        uint256 orderId,
        OrderAmounts calldata previousAmounts,
        uint128 amountA,
        uint128 amountB,
        uint128 availableA,
        uint128 availableB
    ) private pure {
        if (
            previousAmounts.amountA != amountA || previousAmounts.amountB != amountB
                || previousAmounts.availableA != availableA || previousAmounts.availableB != availableB
        ) {
            revert OrderStateMismatch(orderId);
        }
    }

    /// @notice Computes tokenA escrow top-up or refund between new and current availableA
    /// @param newAvailableA Desired remaining tokenA
    /// @param availableA Current remaining tokenA
    /// @return delta Top-up and/or refund amounts
    function _escrowADelta(
        uint128 newAvailableA,
        uint128 availableA
    ) private pure returns (EscrowADelta memory delta) {
        if (newAvailableA > availableA) {
            // Unchecked is safe: branch proves newAvailableA > availableA.
            unchecked {
                delta.topUp = uint256(newAvailableA - availableA);
            }
        } else if (newAvailableA < availableA) {
            // Unchecked is safe: branch proves availableA > newAvailableA.
            unchecked {
                delta.refund = uint256(availableA - newAvailableA);
            }
        }
    }

    /// @notice Settles one modify leg's escrow top-up or refund
    /// @param leg Escrow delta for a single order
    function _settleModifyLeg(
        ModifyLeg memory leg
    ) private {
        Token token = Token.wrap(leg.tokenA);
        if (token.isNative()) {
            _settleModifyLegNative(token, leg.topUp, leg.refund);

            return;
        }

        _requireNoStrayEth();
        if (leg.topUp != 0) {
            _pullExactToken(token, leg.topUp);
        } else if (leg.refund != 0) {
            _transferExactTo(token, msg.sender, leg.refund);
        }
    }

    /// @notice Settles one modify leg using Permit2 for an ERC20 top-up when provided
    /// @param leg Escrow delta for a single order
    /// @param permit Permit2 payload for tokenA (empty signature skips)
    function _settleModifyLegPermit2(
        ModifyLeg memory leg,
        Permit2Permit calldata permit
    ) private {
        Token token = Token.wrap(leg.tokenA);
        if (token.isNative()) {
            if (permit.signature.length != 0) {
                revert PermitOnNative();
            }
            _settleModifyLegNative(token, leg.topUp, leg.refund);

            return;
        }

        _requireNoStrayEth();
        if (leg.topUp != 0) {
            if (permit.signature.length == 0) {
                _pullExactToken(token, leg.topUp);
            } else {
                _pullExactViaPermit2(
                    leg.tokenA,
                    address(this),
                    leg.topUp,
                    permit.amount,
                    permit.nonce,
                    permit.deadline,
                    permit.signature
                );
            }
        } else if (leg.refund != 0) {
            if (permit.signature.length != 0) {
                revert UnusedPermit2();
            }
            _transferExactTo(token, msg.sender, leg.refund);
        }
    }

    /// @notice Settles a native-tokenA modify: exact `msg.value` top-up, optional refund
    /// @param token Native ETH sentinel
    /// @param topUp Required `msg.value`
    /// @param refund ETH to return to the maker (if any)
    function _settleModifyLegNative(
        Token token,
        uint256 topUp,
        uint256 refund
    ) private {
        _requireMsgValue(topUp);
        if (refund != 0) {
            token.safeTransfer(msg.sender, refund);
        }
    }

    /// @notice Modifies orders pulling net ERC20 top-ups via Permit2 where provided
    /// @param mods Modify arguments in execution order
    /// @param permits Permit2 signatures keyed by tokenA
    function _modifyOrdersPermit2(
        ModifyOrdersParams[] calldata mods,
        TokenPermit2[] calldata permits
    ) private {
        if (mods.length == 0) {
            revert ZeroAmount();
        }

        _validateTokenPermit2Batch(permits);
        _validateModifyOrders(mods);
        _settleModifyLegsPermit2(_applyModifyEffects(mods), permits);
    }

    /// @notice Settles modify legs with Permit2 for net ERC20 top-ups where provided
    /// @param legs Settled modify legs
    /// @param permits Permit2 signatures keyed by tokenA
    function _settleModifyLegsPermit2(
        ModifyLeg[] memory legs,
        TokenPermit2[] memory permits
    ) private {
        AggregatedModifyDeltas memory deltas = _aggregateModifyLegs(legs);
        uint256 ethRefund = _requireModifyMsgValue(deltas);
        _pullModifyTopUpsPermit2(deltas, permits);
        _refundModifyEth(ethRefund);
    }

    /// @notice Nets ETH modify top-up against refund into a single direction
    /// @param ethTopUp Gross ETH top-up
    /// @param ethRefund Gross ETH refund
    /// @return netTopUp Net ETH the maker must send
    /// @return netRefund Net ETH to return to the maker
    function _netEthModifyDeltas(
        uint256 ethTopUp,
        uint256 ethRefund
    ) private pure returns (uint256 netTopUp, uint256 netRefund) {
        if (ethTopUp > ethRefund) {
            unchecked {
                netTopUp = ethTopUp - ethRefund;
            }
        } else {
            unchecked {
                netRefund = ethRefund - ethTopUp;
            }
        }
    }

    /// @notice Nets ETH modify deltas and requires `msg.value` equals the net top-up
    /// @param deltas Aggregated modify deltas
    /// @return ethRefund Net ETH to return to the maker after pulls
    function _requireModifyMsgValue(
        AggregatedModifyDeltas memory deltas
    ) private view returns (uint256 ethRefund) {
        uint256 ethTopUp;
        (ethTopUp, ethRefund) = _netEthModifyDeltas(deltas.ethTopUp, deltas.ethRefund);
        if (msg.value != ethTopUp) {
            revert ETHAmountMismatch(ethTopUp, msg.value);
        }
    }

    /// @notice Refunds net ETH after a modify settle, if any
    /// @param ethRefund Net ETH to return to the maker
    function _refundModifyEth(
        uint256 ethRefund
    ) private {
        if (ethRefund != 0) {
            NATIVE_TOKEN.safeTransfer(msg.sender, ethRefund);
        }
    }

    /// @notice Pulls net ERC20 modify top-ups via Permit2 where provided
    /// @param deltas Aggregated modify deltas
    /// @param permits Permit2 signatures keyed by tokenA
    function _pullModifyTopUpsPermit2(
        AggregatedModifyDeltas memory deltas,
        TokenPermit2[] memory permits
    ) private {
        uint256 permitLength = permits.length;
        uint256 usedBits = 0;

        for (uint256 i = 0; i < deltas.count; ++i) {
            uint256 topUp = deltas.topUps[i];
            uint256 refund = deltas.refunds[i];
            address tokenAddr = deltas.tokens[i];
            Token token = Token.wrap(tokenAddr);
            if (topUp > refund) {
                uint256 net;
                unchecked {
                    net = topUp - refund;
                }
                uint256 permitIndex = _indexOfTokenPermit2(permits, tokenAddr);
                if (permitIndex == permitLength) {
                    _pullExactToken(token, net);
                } else {
                    usedBits |= uint256(1) << permitIndex;
                    TokenPermit2 memory permit = permits[permitIndex];
                    _pullExactViaPermit2(
                        tokenAddr, address(this), net, permit.amount, permit.nonce, permit.deadline, permit.signature
                    );
                }
            } else if (refund > topUp) {
                uint256 netRefund;
                unchecked {
                    netRefund = refund - topUp;
                }
                _transferExactTo(token, msg.sender, netRefund);
            }
        }

        _requireAllPermit2BitsUsed(usedBits, permitLength);
    }

    /// @notice Settles modify legs after netting same-token top-ups against refunds
    /// @dev Per unique tokenA (and ETH), only the net delta is pulled or sent — equal opposing
    ///      flows cancel and produce no transfer. `msg.value` must equal the net ETH top-up.
    /// @param legs Settled modify legs
    function _settleModifyLegs(
        ModifyLeg[] memory legs
    ) private {
        _settleModifyLegsPermit2(legs, _emptyTokenPermit2());
    }

    /// @notice Aggregates modify-leg top-ups and refunds per unique ERC20 (ETH returned separately)
    /// @param legs Per-order escrow deltas
    /// @return deltas Distinct ERC20 top-ups/refunds plus ETH totals
    function _aggregateModifyLegs(
        ModifyLeg[] memory legs
    ) private pure returns (AggregatedModifyDeltas memory deltas) {
        uint256 length = legs.length;
        deltas.tokens = new address[](length);
        deltas.topUps = new uint256[](length);
        deltas.refunds = new uint256[](length);

        for (uint256 i = 0; i < length; ++i) {
            ModifyLeg memory leg = legs[i];
            address token = leg.tokenA;
            uint256 topUp = leg.topUp;
            uint256 refund = leg.refund;
            if (topUp == 0 && refund == 0) {
                continue;
            }
            if (Token.wrap(token).isNative()) {
                deltas.ethTopUp += topUp;
                deltas.ethRefund += refund;

                continue;
            }

            uint256 existing = _indexOfToken(deltas.tokens, deltas.count, token);
            if (existing == deltas.count) {
                deltas.tokens[deltas.count] = token;
                deltas.topUps[deltas.count] = topUp;
                deltas.refunds[deltas.count] = refund;

                ++deltas.count;
            } else {
                deltas.topUps[existing] += topUp;
                deltas.refunds[existing] += refund;
            }
        }
    }

    /// @notice Cancels one order and refunds remaining tokenA to the maker
    /// @param orderId Order to cancel
    function _cancelOrder(
        uint256 orderId
    ) private {
        Order storage order = _requireActiveOrder(orderId);
        _requireMaker(orderId, order.maker);

        address tokenA = order.tokenA;
        uint256 amountA = order.availableA;

        delete _orders[orderId];
        emit OrderCanceled({orderId: orderId});

        Token token = Token.wrap(tokenA);
        if (token.isNative()) {
            token.safeTransfer(msg.sender, amountA);

            return;
        }

        _transferExactTo(token, msg.sender, amountA);
    }

    /// @notice Cancels orders after aggregating ERC20 and ETH refunds to the maker
    /// @param orderIds Order identifiers to cancel
    function _cancelOrders(
        uint256[] calldata orderIds
    ) private {
        uint256 length = orderIds.length;
        if (length == 0) {
            revert ZeroAmount();
        }

        address[] memory tokens = new address[](length);
        uint256[] memory amounts = new uint256[](length);
        uint256[] memory ids = new uint256[](length);

        for (uint256 i = 0; i < length; ++i) {
            ids[i] = orderIds[i];
        }
        _requireUniqueOrderIds(ids);

        for (uint256 i = 0; i < length; ++i) {
            uint256 orderId = ids[i];
            Order storage order = _requireActiveOrder(orderId);
            _requireMaker(orderId, order.maker);
            tokens[i] = order.tokenA;
            amounts[i] = order.availableA;
        }

        AggregatedAmounts memory refunds = _aggregateTokenAmounts(tokens, amounts);

        for (uint256 k = 0; k < length; ++k) {
            uint256 orderId = ids[k];
            // forge-lint: disable-next-line(costly-loop)
            delete _orders[orderId];

            emit OrderCanceled({orderId: orderId});
        }

        _sendAggregated(refunds, msg.sender);
    }

    /// @notice Applies an EIP-2612 permit for `token` from `msg.sender` to this contract
    /// @dev `v == 0` is a no-op (other fields are not read). Native ETH with `v != 0` reverts
    ///      `PermitOnNative`. A permit whose `value` is already covered by the current allowance
    ///      is also a no-op (see `_callPermit`).
    /// @param token Token to permit
    /// @param permit Signature payload
    function _permit(
        address token,
        Permit calldata permit
    ) private {
        uint8 v = permit.v;
        if (v == 0) {
            return;
        }

        _callPermit(token, permit.value, permit.deadline, v, permit.r, permit.s);
    }

    /// @notice Calls token `permit` after native-ETH check. Caller must ensure `v != 0`.
    /// @dev No-ops when the board's allowance from `msg.sender` already covers `value`. EIP-2612
    ///      nonces are single-use and the signature is not bound to a submitter, so anyone can
    ///      replay it first: the allowance ends up the same but the nonce is spent, and calling
    ///      `permit` again with a spent nonce reverts on the signature check. Skipping the
    ///      redundant call keeps the pull working instead of bricking every permit overload for
    ///      that signature, and saves the call when a plain `approve` already covers the pull.
    /// @param token Token to permit
    /// @param value Signed allowance
    /// @param deadline Permit deadline
    /// @param v Signature v
    /// @param r Signature r
    /// @param s Signature s
    function _callPermit(
        address token,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) private {
        Token wrapped = Token.wrap(token);
        if (wrapped.isNative()) {
            revert PermitOnNative();
        }

        if (wrapped.allowance(msg.sender, address(this)) < value) {
            // forge-lint: disable-next-line(reentrancy-no-eth)
            IERC20Permit(token).permit(msg.sender, address(this), value, deadline, v, r, s);
        }
    }

    /// @notice Validates a batch of EIP-2612 permits: non-zero v, no zero/native/duplicate tokens
    /// @param permits Permits keyed by token
    function _validateTokenPermitBatch(
        TokenPermit[] calldata permits
    ) private pure {
        uint256 length = permits.length;
        for (uint256 i = 0; i < length; ++i) {
            TokenPermit calldata p = permits[i];
            address token = p.token;
            if (token == address(0)) {
                revert ZeroAddress();
            }
            if (p.v == 0) {
                revert InvalidPermit();
            }
            if (Token.wrap(token).isNative()) {
                revert PermitOnNative();
            }

            for (uint256 j = i + 1; j < length; ++j) {
                if (permits[j].token == token) {
                    revert DuplicatePermitToken(token);
                }
            }
        }
    }

    /// @notice Reverts unless every EIP-2612 batch entry matches a pulled ERC20
    /// @param permits Permits keyed by token
    /// @param pulledTokens Distinct ERC20 tokens that will be pulled
    /// @param pulledCount Number of populated pull tokens
    function _requirePermitsUsed(
        TokenPermit[] calldata permits,
        address[] memory pulledTokens,
        uint256 pulledCount
    ) private pure {
        uint256 length = permits.length;
        for (uint256 i = 0; i < length; ++i) {
            if (_indexOfToken(pulledTokens, pulledCount, permits[i].token) == pulledCount) {
                revert UnusedPermit();
            }
        }
    }

    /// @notice Calls `permit` for a batch already validated by `_validateTokenPermitBatch`
    /// @param permits Permits keyed by token
    function _applyValidatedPermits(
        TokenPermit[] calldata permits
    ) private {
        uint256 length = permits.length;
        for (uint256 i = 0; i < length; ++i) {
            TokenPermit calldata p = permits[i];
            _callPermit(p.token, p.value, p.deadline, p.v, p.r, p.s);
        }
    }

    /// @notice Validates a Permit2 batch: non-empty signatures, no zero/native/duplicate tokens
    /// @dev More than 256 entries revert `TooManyPermit2`. Empty signatures revert `InvalidPermit2`.
    /// @param permits Permit2 signatures keyed by token
    function _validateTokenPermit2Batch(
        TokenPermit2[] calldata permits
    ) private pure {
        uint256 length = permits.length;
        // Usage bitmaps are a single `uint256` (max 256 entries).
        if (length > 256) {
            revert TooManyPermit2();
        }

        for (uint256 i = 0; i < length; ++i) {
            TokenPermit2 calldata p = permits[i];
            address token = p.token;
            if (token == address(0)) {
                revert ZeroAddress();
            }
            if (p.signature.length == 0) {
                revert InvalidPermit2();
            }
            if (Token.wrap(token).isNative()) {
                revert PermitOnNative();
            }

            for (uint256 j = i + 1; j < length; ++j) {
                if (permits[j].token == token) {
                    revert DuplicatePermitToken(token);
                }
            }
        }
    }

    /// @notice Empty Permit2 batch used by classic settle paths
    /// @return permits Zero-length memory array
    function _emptyTokenPermit2() private pure returns (TokenPermit2[] memory) {
        return new TokenPermit2[](0);
    }

    /// @notice Finds `token` in a Permit2 batch, or returns `permits.length` if missing
    /// @param permits Permit2 signatures
    /// @param token Token to look up
    /// @return index Matching index, or `permits.length` when not found
    function _indexOfTokenPermit2(
        TokenPermit2[] memory permits,
        address token
    ) private pure returns (uint256) {
        uint256 length = permits.length;
        for (uint256 i = 0; i < length; ++i) {
            if (permits[i].token == token) {
                return i;
            }
        }

        return length;
    }

    /// @notice Pulls aggregated ERC20 deposits via Permit2 where provided
    /// @dev Every Permit2 entry must match a deposited token. Tokens without an entry use classic pull.
    /// @param aggregated Distinct ERC20 amounts (ETH is ignored here; paid via msg.value)
    /// @param permits Permit2 signatures keyed by token
    function _pullAggregatedTokensPermit2(
        AggregatedAmounts memory aggregated,
        TokenPermit2[] memory permits
    ) private {
        uint256 permitLength = permits.length;
        uint256 usedBits = 0;
        uint256[] memory permitIndexByDeposit = new uint256[](aggregated.count);

        for (uint256 i = 0; i < aggregated.count; ++i) {
            uint256 permitIndex = _indexOfTokenPermit2(permits, aggregated.tokens[i]);
            permitIndexByDeposit[i] = permitIndex;
            if (permitIndex != permitLength) {
                usedBits |= uint256(1) << permitIndex;
            }
        }
        _requireAllPermit2BitsUsed(usedBits, permitLength);

        for (uint256 k = 0; k < aggregated.count; ++k) {
            address token = aggregated.tokens[k];
            uint256 amount = aggregated.amounts[k];
            uint256 permitIndex = permitIndexByDeposit[k];
            if (permitIndex == permitLength) {
                _pullExactToken(Token.wrap(token), amount);
                continue;
            }

            TokenPermit2 memory permit = permits[permitIndex];
            _pullExactViaPermit2(
                token, address(this), amount, permit.amount, permit.nonce, permit.deadline, permit.signature
            );
        }
    }

    /// @notice Reverts unless every Permit2 batch bit in `[0, length)` is set
    /// @dev Unused entries revert `UnusedPermit2`.
    /// @param usedBits Bitmap of used permit indices
    /// @param length Number of Permit2 entries
    function _requireAllPermit2BitsUsed(
        uint256 usedBits,
        uint256 length
    ) private pure {
        // Mask with the low `length` bits set. Built by right-shifting because `1 << 256` is not
        // representable; `length == 0` shifts by 256 and yields the empty mask.
        uint256 mask = type(uint256).max >> (256 - length);
        if (usedBits != mask) {
            revert UnusedPermit2();
        }
    }

    /// @notice Pulls an exact ERC20 amount via Permit2 SignatureTransfer with BalanceMismatch check
    /// @param token ERC20 token address
    /// @param to Recipient of the pulled tokens
    /// @param requestedAmount Exact amount to pull
    /// @param permittedAmount Max amount signed in Permit2 `TokenPermissions`
    /// @param nonce Permit2 unordered nonce
    /// @param deadline Permit2 signature deadline
    /// @param signature EIP-712 Permit2 signature
    function _pullExactViaPermit2(
        address token,
        address to,
        uint256 requestedAmount,
        uint256 permittedAmount,
        uint256 nonce,
        uint256 deadline,
        bytes memory signature
    ) private {
        Token wrapped = Token.wrap(token);
        uint256 balanceBefore = wrapped.balanceOf(to);

        ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: token, amount: permittedAmount}),
            nonce: nonce,
            deadline: deadline
        });
        ISignatureTransfer.SignatureTransferDetails memory details =
            ISignatureTransfer.SignatureTransferDetails({to: to, requestedAmount: requestedAmount});

        _PERMIT2.permitTransferFrom(permit, details, msg.sender, signature);

        _requireExactReceived(wrapped, to, balanceBefore, requestedAmount);
    }

    /// @notice Pulls an exact ERC20 amount into escrow, rejecting fee-on-transfer / mid-transfer
    ///         rebase / phantom transfers
    /// @dev `Token.safeTransferFrom` no-ops when `amount == 0` and reverts `TransferFromOnNative` for the ETH sentinel.
    /// @param token ERC20 token to pull from the caller
    /// @param amount Expected amount received
    function _pullExactToken(
        Token token,
        uint256 amount
    ) private {
        _transferExactFrom(token, address(this), amount);
    }

    /// @notice `transfer` to `to` and require `to`'s balance rises by exactly `amount`
    /// @param token ERC20 token to send
    /// @param to Recipient
    /// @param amount Expected amount received by `to`
    function _transferExactTo(
        Token token,
        address to,
        uint256 amount
    ) private {
        uint256 balanceBefore = token.balanceOf(to);
        token.safeTransfer(to, amount);
        _requireExactReceived(token, to, balanceBefore, amount);
    }

    /// @notice `transferFrom` caller → `to` and require `to`'s balance rises by exactly `amount`
    /// @param token ERC20 token to pull
    /// @param to Recipient
    /// @param amount Expected amount received by `to`
    function _transferExactFrom(
        Token token,
        address to,
        uint256 amount
    ) private {
        uint256 balanceBefore = token.balanceOf(to);
        token.safeTransferFrom(msg.sender, to, amount);
        _requireExactReceived(token, to, balanceBefore, amount);
    }

    /// @notice Requires `to`'s token balance rose by exactly `expected` since `balanceBefore`
    /// @param token ERC20 token
    /// @param to Account whose balance is checked
    /// @param balanceBefore Balance snapshot before the transfer
    /// @param expected Expected received amount
    function _requireExactReceived(
        Token token,
        address to,
        uint256 balanceBefore,
        uint256 expected
    ) private view {
        uint256 balanceAfter = token.balanceOf(to);
        // Detect fee-on-transfer / mid-transfer rebase / phantom by comparing received to expected.
        // Unchecked is safe: balanceAfter >= balanceBefore after successful transfer.
        unchecked {
            uint256 received = balanceAfter - balanceBefore;
            if (received != expected) {
                revert BalanceMismatch(expected, received);
            }
        }
    }
}
