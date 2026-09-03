// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ISwapboard} from "./interfaces/ISwapboard.sol";
import {Semver} from "./Semver.sol";

/// @title Swapboard
/// @author Zak Cole (numbergroup.xyz) for Ethereum Community Foundation
/// @notice Trustless OTC bulletin board for ERC20 and native ETH swaps on Ethereum
/// @dev This contract implements a simple orderbook for peer-to-peer token swaps.
///
///      Key properties:
///      - No admin functions, fees, or upgrades
///      - Full fills are atomic; partial fills are opt-in via `partialFillAllowed`
///      - Partial fill size is specified as tokenA to receive (`amountA`); tokenB paid is ceiled
///      - Fee-on-transfer / mid-transfer rebase / phantom transfers are rejected on inbound
///        pulls (tokenA deposits and tokenB payments) via `_pullExactToken` / `BalanceMismatch`
///      - Native ETH uses the `0xEeee...eE` sentinel (`getEth()`)
///      - Order amounts use `uint128` (sufficient for practical sizes); originals and available
///        remaining amounts are packed separately so fill % is readable on-chain
///      - Reentrancy protected via OpenZeppelin ReentrancyGuardTransient (EIP-1153)
///
///      Security considerations:
///      - Front-running is possible on `fillOrder` / `fillOrders` (inherent to on-chain orderbooks)
///      - Rebasing tokens may cause unexpected behavior
///      - Malicious tokens can cause fund loss - users must verify token contracts
///      - Outbound fee-on-transfer / mid-transfer rebase on maker payout remains possible after an
///        exact tokenB pull
///      - ETH is sent with `Address.sendValue` (forwards all gas) so contract recipients
///        can run `receive`/`fallback`; always after state updates (CEI)
///      - Floor/ceil rounding on partial fills may leave tokenA dust in escrow; refunding that dust
///        is not worth the gas. It can later benefit a user who rounds favorably on another
///        fill where that dust token is tokenB
///
/// @custom:security-contact zak@numbergroup.xyz
contract Swapboard is ISwapboard, Semver, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;
    using Address for address payable;

    /// @notice Canonical placeholder address representing native ETH
    address private constant _ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice One fill leg after validation/quote (internal batch settlement)
    /// @param maker Address that receives tokenB for this leg
    /// @param tokenA Address of the token paid out to the taker
    /// @param amountA Amount of tokenA transferred to the taker
    /// @param tokenB Address of the token pulled from the taker
    /// @param amountB Amount of tokenB paid to the maker (ceiled proportion)
    struct FillLeg {
        address maker;
        address tokenA;
        uint256 amountA;
        address tokenB;
        uint256 amountB;
    }

    /// @notice Counter for generating unique order IDs
    /// @dev Starts at 0, increments by 1 for each new order
    uint256 private _nextOrderId;

    /// @notice Mapping from order ID to Order struct
    /// @dev Non-existent orders return default struct with maker=address(0) and active=false
    mapping(uint256 orderId => Order order) private _orders;

    /// @notice Initializes Swapboard
    constructor() Semver(2, 0, 0) {}

    /// @inheritdoc ISwapboard
    /// @dev Token addresses are identity-based. Aliased or rebranded tokens at different
    ///      addresses are treated as distinct tokens. Users must verify token addresses.
    function createOrder(
        CreateOrderParams calldata order
    ) external payable nonReentrant returns (uint256) {
        address tokenA = order.tokenA;
        uint128 amountA = order.amountA;
        _validateCreateOrder(tokenA, amountA, order.tokenB, order.amountB);

        uint256 ethAmount = tokenA == _ETH ? uint256(amountA) : 0;
        if (msg.value != ethAmount) {
            revert ETHAmountMismatch(ethAmount, msg.value);
        }
        if (tokenA != _ETH) {
            _pullExactToken(tokenA, amountA);
        }

        return _storeOrder(order);
    }

    /// @inheritdoc ISwapboard
    function createOrders(
        CreateOrderParams[] calldata orders
    ) external payable nonReentrant returns (uint256[] memory) {
        return _createOrders(orders);
    }

    /// @inheritdoc ISwapboard
    /// @dev Inbound tokenB pulls use `_pullExactToken` and reject fee-on-transfer / mid-transfer
    ///      rebase / phantom transfers via `BalanceMismatch`. Residual risk is fee-on-transfer /
    ///      mid-transfer rebase only on the outbound `transfer` to the maker after an exact pull.
    ///      tokenB in uses ceil division so the taker never underpays for the requested tokenA.
    ///      Residual tokenA dust (when amountB is exhausted first) is not refunded (not worth the
    ///      gas); it can be picked up by any user that rounds favorably on another order where the
    ///      dust token is tokenB.
    function fillOrder(
        uint256 orderId,
        uint128 amountA,
        uint128 minAmountB,
        uint256 deadline
    ) external payable nonReentrant {
        if (deadline != 0 && block.timestamp > deadline) {
            revert DeadlineExpired();
        }
        if (amountA == 0) {
            revert ZeroAmount();
        }

        FillLeg[] memory legs = new FillLeg[](1);
        legs[0] = _applyOneFillEffect(orderId, amountA, minAmountB);
        _settleFills(legs);
    }

    /// @inheritdoc ISwapboard
    function fillOrders(
        FillOrderParams[] calldata fills,
        uint256 deadline
    ) external payable nonReentrant {
        _fillOrders(fills, deadline);
    }

    /// @inheritdoc ISwapboard
    function cancelOrder(
        uint256 orderId
    ) external nonReentrant {
        Order memory cached = _requireActiveOrder(orderId);
        if (msg.sender != cached.maker) {
            revert NotMaker(orderId, msg.sender, cached.maker);
        }

        address tokenA = cached.tokenA;
        uint256 amountA = cached.availableA;

        delete _orders[orderId];
        emit OrderCanceled({orderId: orderId});

        if (tokenA == _ETH) {
            _sendAggregated(new address[](0), new uint256[](0), amountA, msg.sender);
        } else {
            address[] memory tokens = new address[](1);
            uint256[] memory amounts = new uint256[](1);
            tokens[0] = tokenA;
            amounts[0] = amountA;
            _sendAggregated(tokens, amounts, 0, msg.sender);
        }
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
    ///      `NoChange` when both remainings already match on-chain.
    /// @param orderId The unique identifier of the order to modify
    /// @param previousAmounts Expected current amounts from the caller's snapshot (race protection)
    /// @param updatedOrder Desired remaining amounts
    function modifyOrder(
        uint256 orderId,
        OrderAmounts calldata previousAmounts,
        ModifyOrderParams calldata updatedOrder
    ) external payable nonReentrant {
        Order storage order = _requireActiveOrder(orderId);
        Order memory cached = order;

        if (msg.sender != cached.maker) {
            revert NotMaker(orderId, msg.sender, cached.maker);
        }

        if (
            previousAmounts.amountA != cached.amountA || previousAmounts.amountB != cached.amountB
                || previousAmounts.availableA != cached.availableA || previousAmounts.availableB != cached.availableB
        ) {
            revert OrderStateMismatch(
                orderId,
                previousAmounts.amountA,
                previousAmounts.amountB,
                previousAmounts.availableA,
                previousAmounts.availableB,
                cached.amountA,
                cached.amountB,
                cached.availableA,
                cached.availableB
            );
        }

        uint128 newAvailableA = updatedOrder.availableA;
        uint128 newAvailableB = updatedOrder.availableB;
        if (newAvailableA == 0 || newAvailableB == 0) {
            revert ZeroAmount();
        }
        if (newAvailableA == cached.availableA && newAvailableB == cached.availableB) {
            revert NoChange();
        }

        (uint256 ethTopUp, uint256 ethRefund) =
            _adjustTokenAEscrow(cached.tokenA, cached.availableA, newAvailableA, cached.maker);

        if (msg.value != ethTopUp) {
            revert ETHAmountMismatch(ethTopUp, msg.value);
        }

        // Reset totals to the new remainings (filled history is not preserved in amount fields).
        order.amountA = newAvailableA;
        order.amountB = newAvailableB;
        order.availableA = newAvailableA;
        order.availableB = newAvailableB;

        emit OrderModified(orderId, newAvailableA, newAvailableB);

        if (ethRefund > 0) {
            // Forward all gas so maker contracts can execute receive/fallback.
            payable(cached.maker).sendValue(ethRefund);
        }
    }

    /// @inheritdoc ISwapboard
    function setPartialFillAllowed(
        uint256 orderId,
        bool partialFillAllowed
    ) external nonReentrant {
        Order storage order = _requireActiveOrder(orderId);
        address maker = order.maker;
        bool currentPartialFillAllowed = order.partialFillAllowed;

        if (msg.sender != maker) {
            revert NotMaker(orderId, msg.sender, maker);
        }
        if (partialFillAllowed == currentPartialFillAllowed) {
            revert NoChange();
        }

        order.partialFillAllowed = partialFillAllowed;

        emit OrderPartialFillUpdated(orderId, partialFillAllowed);
    }

    /// @notice Adjusts tokenA escrow when `availableA` changes due to an order modification
    /// @dev ETH refund is returned instead of sent immediately so storage can be updated first (CEI).
    /// @param tokenA The tokenA held in escrow (token addresses are immutable for the order's lifetime)
    /// @param oldAvailableA Previous remaining `availableA`
    /// @param newAvailableA Updated remaining `availableA`
    /// @param maker Maker receiving any tokenA refund
    /// @return ethTopUp ETH top-up amount required (0 when tokenA is ERC20 or no top-up needed)
    /// @return ethRefund ETH refund amount owed to maker (0 when tokenA is ERC20 or no refund needed)
    function _adjustTokenAEscrow(
        address tokenA,
        uint128 oldAvailableA,
        uint128 newAvailableA,
        address maker
    ) private returns (uint256 ethTopUp, uint256 ethRefund) {
        if (newAvailableA > oldAvailableA) {
            // Unchecked is safe: branch proves newAvailableA > oldAvailableA.
            uint256 delta;
            unchecked {
                delta = uint256(newAvailableA - oldAvailableA);
            }
            if (tokenA == _ETH) {
                ethTopUp = delta;
            } else {
                _pullExactToken(tokenA, delta);
            }
        } else if (newAvailableA < oldAvailableA) {
            // Unchecked is safe: branch proves oldAvailableA > newAvailableA.
            uint256 refund;
            unchecked {
                refund = uint256(oldAvailableA - newAvailableA);
            }
            if (tokenA == _ETH) {
                ethRefund = refund;
            } else {
                IERC20(tokenA).safeTransfer(maker, refund);
            }
        }
    }

    /// @inheritdoc ISwapboard
    function getEth() external pure returns (address) {
        return _ETH;
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
        return _orders[orderId].active;
    }

    /// @notice Reverts unless the order exists and is active
    /// @param orderId Order to load
    /// @return order Storage pointer to the active order
    function _requireActiveOrder(
        uint256 orderId
    ) private view returns (Order storage) {
        Order storage order = _orders[orderId];
        (address maker, bool active) = (order.maker, order.active);
        if (maker == address(0)) {
            revert OrderNotFound(orderId);
        }
        if (!active) {
            revert OrderNotActive(orderId);
        }

        return order;
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
    ) private view {
        if (tokenA == address(0) || tokenB == address(0)) {
            revert ZeroAddress();
        }
        if (amountA == 0 || amountB == 0) {
            revert ZeroAmount();
        }
        if (tokenA == tokenB) {
            revert SameToken();
        }

        if (tokenA != _ETH && tokenA.code.length == 0) {
            revert NotAContract(tokenA);
        }
        if (tokenB != _ETH && tokenB.code.length == 0) {
            revert NotAContract(tokenB);
        }
    }

    /// @notice Creates orders after aggregating ERC20 pulls and exact ETH payment
    /// @param orders Order creation arguments
    /// @return orderIds Identifiers assigned to each created order
    function _createOrders(
        CreateOrderParams[] calldata orders
    ) private returns (uint256[] memory) {
        uint256 length = orders.length;
        if (length == 0) {
            revert ZeroAmount();
        }

        _validateCreateOrders(orders);

        (address[] memory tokens, uint256[] memory amounts) = _collectDepositAssets(orders);
        (address[] memory uniqueTokens, uint256[] memory uniqueAmounts, uint256 ethAmount) =
            _aggregateTokenAmounts(tokens, amounts);
        if (msg.value != ethAmount) {
            revert ETHAmountMismatch(ethAmount, msg.value);
        }

        _pullAggregatedTokens(uniqueTokens, uniqueAmounts);
        return _storeOrders(orders);
    }

    /// @notice Validates every order in a create batch
    /// @param orders Order creation arguments
    function _validateCreateOrders(
        CreateOrderParams[] calldata orders
    ) private view {
        uint256 length = orders.length;
        for (uint256 i = 0; i < length; ++i) {
            CreateOrderParams calldata params = orders[i];

            _validateCreateOrder(params.tokenA, params.amountA, params.tokenB, params.amountB);
        }
    }

    /// @notice Collects tokenA/amountA pairs to aggregate into escrow pulls
    /// @param orders Order creation arguments
    /// @return tokens tokenA for each order
    /// @return amounts amountA for each order
    function _collectDepositAssets(
        CreateOrderParams[] calldata orders
    ) private pure returns (address[] memory tokens, uint256[] memory amounts) {
        uint256 length = orders.length;
        tokens = new address[](length);
        amounts = new uint256[](length);
        for (uint256 i = 0; i < length; ++i) {
            CreateOrderParams calldata params = orders[i];
            tokens[i] = params.tokenA;
            amounts[i] = params.amountA;
        }
    }

    /// @notice Aggregates per-token deposit amounts and sums native ETH
    /// @dev ETH sentinel amounts are returned separately and omitted from `uniqueTokens`.
    /// @param tokens Deposit token for each order (tokenA)
    /// @param amounts Deposit amount for each order (amountA)
    /// @return uniqueTokens Distinct ERC20 tokens in first-seen order
    /// @return uniqueAmounts Summed deposit for each unique ERC20
    /// @return ethAmount Summed native ETH to escrow (0 if none)
    function _aggregateTokenAmounts(
        address[] memory tokens,
        uint256[] memory amounts
    ) private pure returns (address[] memory uniqueTokens, uint256[] memory uniqueAmounts, uint256 ethAmount) {
        uint256 length = tokens.length;
        address[] memory stackedTokens = new address[](length);
        uint256[] memory stackedAmounts = new uint256[](length);
        uint256 uniqueCount = 0;

        for (uint256 i = 0; i < length; ++i) {
            address token = tokens[i];
            uint256 amount = amounts[i];
            if (token == _ETH) {
                ethAmount += amount;

                continue;
            }

            uint256 existing = _indexOfToken(stackedTokens, uniqueCount, token);
            if (existing == uniqueCount) {
                stackedTokens[uniqueCount] = token;
                stackedAmounts[uniqueCount] = amount;

                ++uniqueCount;
            } else {
                stackedAmounts[existing] += amount;
            }
        }

        uniqueTokens = new address[](uniqueCount);
        uniqueAmounts = new uint256[](uniqueCount);

        for (uint256 j = 0; j < uniqueCount; ++j) {
            uniqueTokens[j] = stackedTokens[j];
            uniqueAmounts[j] = stackedAmounts[j];
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
    /// @param tokens Unique ERC20 tokens
    /// @param amounts Aggregated amount per token
    function _pullAggregatedTokens(
        address[] memory tokens,
        uint256[] memory amounts
    ) private {
        uint256 length = tokens.length;
        for (uint256 i = 0; i < length; ++i) {
            _pullExactToken(tokens[i], amounts[i]);
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

        bool partialFillAllowed = params.partialFillAllowed;
        address tokenA = params.tokenA;
        address tokenB = params.tokenB;
        uint128 amountA = params.amountA;
        uint128 amountB = params.amountB;

        _orders[orderId] = Order({
            maker: msg.sender,
            active: true,
            partialFillAllowed: partialFillAllowed,
            tokenA: tokenA,
            tokenB: tokenB,
            amountA: amountA,
            amountB: amountB,
            availableA: amountA,
            availableB: amountB
        });

        emit OrderCreated({
            orderId: orderId,
            maker: msg.sender,
            tokenA: tokenA,
            amountA: amountA,
            tokenB: tokenB,
            amountB: amountB,
            partialFillAllowed: partialFillAllowed
        });

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
            CreateOrderParams calldata params = orders[i];

            // Unchecked is safe: wrapping `_nextOrderId` would require 2^256 orders;
            // `i < length` and `_nextOrderId = nextId + length` below share that bound.
            uint256 orderId;
            unchecked {
                orderId = nextId + i;
            }
            orderIds[i] = orderId;

            bool partialFillAllowed = params.partialFillAllowed;
            address tokenA = params.tokenA;
            address tokenB = params.tokenB;
            uint128 amountA = params.amountA;
            uint128 amountB = params.amountB;

            // forge-lint: disable-next-item(costly-loop)
            _orders[orderId] = Order({
                maker: msg.sender,
                active: true,
                partialFillAllowed: partialFillAllowed,
                tokenA: tokenA,
                tokenB: tokenB,
                amountA: amountA,
                amountB: amountB,
                availableA: amountA,
                availableB: amountB
            });

            emit OrderCreated({
                orderId: orderId,
                maker: msg.sender,
                tokenA: tokenA,
                amountA: amountA,
                tokenB: tokenB,
                amountB: amountB,
                partialFillAllowed: partialFillAllowed
            });
        }

        // Unchecked is safe: wrapping `_nextOrderId` would require 2^256 orders.
        unchecked {
            _nextOrderId = nextId + length;
        }

        return orderIds;
    }

    /// @notice Quotes the ceiled tokenB payment for an active order
    /// @dev Ceil division benefits escrow/maker. Residual tokenA dust is not refunded.
    ///      Intermediate math widens to uint256; both factors are uint128 so the product fits.
    /// @param order Order to quote (must already be active)
    /// @param orderId Order id for error payloads
    /// @param amountA Requested tokenA out
    /// @return maker Order maker
    /// @return tokenA Sold asset
    /// @return tokenB Payment asset
    /// @return amountBIn Ceiled tokenB the taker must pay
    function _quoteFill(
        Order memory order,
        uint256 orderId,
        uint128 amountA
    ) private pure returns (address maker, address tokenA, address tokenB, uint128 amountBIn) {
        maker = order.maker;
        tokenA = order.tokenA;
        tokenB = order.tokenB;
        bool partialFillAllowed = order.partialFillAllowed;
        uint128 availableA = order.availableA;
        uint128 availableB = order.availableB;

        if (amountA > availableA) {
            revert FillAmountTooHigh(orderId, amountA, availableA);
        }
        if (!partialFillAllowed && amountA != availableA) {
            revert PartialFillNotAllowed(orderId);
        }

        if (amountA == availableA) {
            amountBIn = availableB;
        } else {
            // Unchecked is safe: else branch implies amountA < availableA so availableA >= 1;
            // product of two uint128 values always fits in uint256; ceil result is <= availableB.
            uint256 quotedB;
            unchecked {
                quotedB = (uint256(amountA) * uint256(availableB) + uint256(availableA) - 1) / uint256(availableA);
            }
            // forge-lint: disable-next-line(unsafe-typecast)
            amountBIn = uint128(quotedB);
        }
        if (amountBIn == 0) {
            revert ZeroAmount();
        }
    }

    /// @notice Fills orders after aggregating tokenB pulls and tokenA/tokenB payouts
    /// @param fills Fill arguments in execution order
    /// @param deadline Unix timestamp after which the batch reverts (0 = no deadline)
    function _fillOrders(
        FillOrderParams[] calldata fills,
        uint256 deadline
    ) private {
        if (deadline != 0 && block.timestamp > deadline) {
            revert DeadlineExpired();
        }

        uint256 length = fills.length;
        if (length == 0) {
            revert ZeroAmount();
        }

        _settleFills(_applyFillEffects(fills));
    }

    /// @notice Validates one fill, updates order storage, emits `OrderFilled`, and returns the leg
    /// @param orderId Order to fill
    /// @param amountA Requested tokenA out
    /// @param minAmountB Minimum tokenB payment declared by the taker
    /// @return leg Settled fill leg
    function _applyOneFillEffect(
        uint256 orderId,
        uint128 amountA,
        uint128 minAmountB
    ) private returns (FillLeg memory) {
        Order storage order = _requireActiveOrder(orderId);
        Order memory cached = order;
        (address maker, address tokenA, address tokenB, uint128 amountBIn) = _quoteFill(cached, orderId, amountA);

        if (amountBIn < minAmountB) {
            revert FillAmountMismatch(orderId, amountBIn, minAmountB);
        }

        // Unchecked is safe: _quoteFill ensures amountA <= availableA and
        // amountBIn <= availableB (exact remaining or ceiled proportion).
        uint128 remainingA;
        uint128 remainingB;
        unchecked {
            remainingA = cached.availableA - amountA;
            remainingB = cached.availableB - amountBIn;
        }
        order.availableA = remainingA;
        order.availableB = remainingB;
        if (remainingA == 0 || remainingB == 0) {
            order.active = false;
        }

        emit OrderFilled({orderId: orderId, taker: msg.sender, amountA: amountA, amountB: amountBIn});

        return FillLeg({maker: maker, tokenA: tokenA, amountA: amountA, tokenB: tokenB, amountB: amountBIn});
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
            if (fill.amountA == 0) {
                revert ZeroAmount();
            }

            legs[i] = _applyOneFillEffect(fill.orderId, fill.amountA, fill.minAmountB);
        }

        return legs;
    }

    /// @notice Pulls aggregated tokenB and pays makers/taker for settled fill legs
    /// @param legs Settled fill legs
    function _settleFills(
        FillLeg[] memory legs
    ) private {
        uint256 length = legs.length;
        address[] memory makers = new address[](length);
        address[] memory tokenAs = new address[](length);
        uint256[] memory amountAs = new uint256[](length);
        address[] memory tokenBs = new address[](length);
        uint256[] memory amountBs = new uint256[](length);

        for (uint256 i = 0; i < length; ++i) {
            FillLeg memory leg = legs[i];
            makers[i] = leg.maker;
            tokenAs[i] = leg.tokenA;
            amountAs[i] = leg.amountA;
            tokenBs[i] = leg.tokenB;
            amountBs[i] = leg.amountB;
        }

        (address[] memory uniqueTokenB, uint256[] memory uniqueAmountB, uint256 ethIn) =
            _aggregateTokenAmounts(tokenBs, amountBs);
        if (msg.value != ethIn) {
            revert ETHAmountMismatch(ethIn, msg.value);
        }

        _pullAggregatedTokens(uniqueTokenB, uniqueAmountB);
        _payMakersAggregated(makers, tokenBs, amountBs);
        _payTakerAggregated(tokenAs, amountAs);
    }

    /// @notice Pays makers their aggregated tokenB (ERC20 and/or ETH)
    /// @param makers Maker for each fill leg
    /// @param tokens tokenB for each fill leg
    /// @param amounts tokenB amount for each fill leg
    function _payMakersAggregated(
        address[] memory makers,
        address[] memory tokens,
        uint256[] memory amounts
    ) private {
        (address[] memory ethMakers, uint256[] memory ethAmounts, uint256 ethCount) =
            _aggregateEthByRecipient(makers, tokens, amounts);
        for (uint256 i = 0; i < ethCount; ++i) {
            // Forward all gas so maker contracts can execute receive/fallback.
            payable(ethMakers[i]).sendValue(ethAmounts[i]);
        }

        (
            address[] memory recipients,
            address[] memory uniqueTokens,
            uint256[] memory uniqueAmounts,
            uint256 uniqueCount
        ) = _aggregateRecipientTokenAmounts(makers, tokens, amounts);
        for (uint256 j = 0; j < uniqueCount; ++j) {
            IERC20(uniqueTokens[j]).safeTransfer(recipients[j], uniqueAmounts[j]);
        }
    }

    /// @notice Pays the taker aggregated tokenA out of escrow (ERC20 and/or ETH)
    /// @param tokens tokenA for each fill leg
    /// @param amounts tokenA amount for each fill leg
    function _payTakerAggregated(
        address[] memory tokens,
        uint256[] memory amounts
    ) private {
        (address[] memory uniqueTokens, uint256[] memory uniqueAmounts, uint256 ethOut) =
            _aggregateTokenAmounts(tokens, amounts);
        _sendAggregated(uniqueTokens, uniqueAmounts, ethOut, msg.sender);
    }

    /// @notice Sends aggregated ERC20 and optional ETH to one recipient
    /// @param tokens Unique ERC20 tokens
    /// @param amounts Aggregated amount per token
    /// @param ethAmount Native ETH to send (0 if none)
    /// @param recipient Token/ETH recipient
    function _sendAggregated(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256 ethAmount,
        address recipient
    ) private {
        if (ethAmount > 0) {
            // Forward all gas so recipient contracts can execute receive/fallback.
            payable(recipient).sendValue(ethAmount);
        }

        uint256 length = tokens.length;
        for (uint256 i = 0; i < length; ++i) {
            IERC20(tokens[i]).safeTransfer(recipient, amounts[i]);
        }
    }

    /// @notice Aggregates ETH amounts by recipient; skips non-ETH tokens
    /// @param recipients Recipient for each leg
    /// @param tokens Token for each leg
    /// @param amounts Amount for each leg
    /// @return ethRecipients Distinct ETH recipients in first-seen order
    /// @return ethAmounts Summed ETH per recipient
    /// @return ethCount Number of populated ETH recipients
    function _aggregateEthByRecipient(
        address[] memory recipients,
        address[] memory tokens,
        uint256[] memory amounts
    ) private pure returns (address[] memory ethRecipients, uint256[] memory ethAmounts, uint256 ethCount) {
        uint256 length = recipients.length;
        ethRecipients = new address[](length);
        ethAmounts = new uint256[](length);
        ethCount = 0;

        for (uint256 i = 0; i < length; ++i) {
            if (tokens[i] != _ETH) {
                continue;
            }

            uint256 existing = _indexOfToken(ethRecipients, ethCount, recipients[i]);
            if (existing == ethCount) {
                ethRecipients[ethCount] = recipients[i];
                ethAmounts[ethCount] = amounts[i];

                ++ethCount;
            } else {
                ethAmounts[existing] += amounts[i];
            }
        }
    }

    /// @notice Aggregates ERC20 amounts by (recipient, token); skips ETH
    /// @param recipients Recipient for each leg
    /// @param tokens Token for each leg
    /// @param amounts Amount for each leg
    /// @return uniqueRecipients Recipient for each unique pair
    /// @return uniqueTokens Token for each unique pair
    /// @return uniqueAmounts Summed amount for each unique pair
    /// @return uniqueCount Number of unique (recipient, token) pairs
    function _aggregateRecipientTokenAmounts(
        address[] memory recipients,
        address[] memory tokens,
        uint256[] memory amounts
    )
        private
        pure
        returns (
            address[] memory uniqueRecipients,
            address[] memory uniqueTokens,
            uint256[] memory uniqueAmounts,
            uint256 uniqueCount
        )
    {
        uint256 length = recipients.length;
        uniqueRecipients = new address[](length);
        uniqueTokens = new address[](length);
        uniqueAmounts = new uint256[](length);
        uniqueCount = 0;

        for (uint256 i = 0; i < length; ++i) {
            address token = tokens[i];
            if (token == _ETH) {
                continue;
            }

            uint256 existing =
                _indexOfRecipientToken(uniqueRecipients, uniqueTokens, uniqueCount, recipients[i], token);
            if (existing == uniqueCount) {
                uniqueRecipients[uniqueCount] = recipients[i];
                uniqueTokens[uniqueCount] = token;
                uniqueAmounts[uniqueCount] = amounts[i];

                ++uniqueCount;
            } else {
                uniqueAmounts[existing] += amounts[i];
            }
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

    /// @notice Cancels orders after aggregating ERC20 and ETH refunds to the maker
    /// @param orderIds Order identifiers to cancel
    function _cancelOrders(
        uint256[] calldata orderIds
    ) private {
        uint256 length = orderIds.length;
        if (length == 0) {
            revert ZeroAmount();
        }

        _validateCancelOrders(orderIds);

        (address[] memory tokens, uint256[] memory amounts) = _collectCancelAssets(orderIds);
        (address[] memory uniqueTokens, uint256[] memory uniqueAmounts, uint256 ethAmount) =
            _aggregateTokenAmounts(tokens, amounts);

        _deleteCanceledOrders(orderIds);
        _sendAggregated(uniqueTokens, uniqueAmounts, ethAmount, msg.sender);
    }

    /// @notice Validates every order in a cancel batch
    /// @param orderIds Order identifiers to cancel
    function _validateCancelOrders(
        uint256[] calldata orderIds
    ) private view {
        uint256 length = orderIds.length;
        for (uint256 i = 0; i < length; ++i) {
            uint256 orderId = orderIds[i];
            for (uint256 j = i + 1; j < length; ++j) {
                if (orderIds[j] == orderId) {
                    revert DuplicateOrderId(orderId);
                }
            }

            Order storage order = _requireActiveOrder(orderId);
            address maker = order.maker;
            if (msg.sender != maker) {
                revert NotMaker(orderId, msg.sender, maker);
            }
        }
    }

    /// @notice Collects tokenA/availableA pairs to aggregate into maker refunds
    /// @param orderIds Order identifiers to cancel
    /// @return tokens tokenA for each order
    /// @return amounts availableA for each order
    function _collectCancelAssets(
        uint256[] calldata orderIds
    ) private view returns (address[] memory tokens, uint256[] memory amounts) {
        uint256 length = orderIds.length;
        tokens = new address[](length);
        amounts = new uint256[](length);
        for (uint256 i = 0; i < length; ++i) {
            Order storage order = _orders[orderIds[i]];
            (address tokenA, uint128 availableA) = (order.tokenA, order.availableA);
            tokens[i] = tokenA;
            amounts[i] = availableA;
        }
    }

    /// @notice Deletes canceled orders and emits `OrderCanceled`
    /// @param orderIds Order identifiers to cancel
    function _deleteCanceledOrders(
        uint256[] calldata orderIds
    ) private {
        uint256 length = orderIds.length;
        for (uint256 i = 0; i < length; ++i) {
            uint256 orderId = orderIds[i];
            // forge-lint: disable-next-line(costly-loop)
            delete _orders[orderId];

            emit OrderCanceled({orderId: orderId});
        }
    }

    /// @notice Pulls an exact ERC20 amount into escrow, rejecting fee-on-transfer / mid-transfer
    ///         rebase / phantom transfers
    /// @param token ERC20 token to pull from the caller
    /// @param amount Expected amount received
    function _pullExactToken(
        address token,
        uint256 amount
    ) private {
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 balanceAfter = IERC20(token).balanceOf(address(this));

        // Detect fee-on-transfer / mid-transfer rebase / phantom by comparing received to expected
        // Using unchecked is safe: balanceAfter >= balanceBefore after successful transfer
        unchecked {
            uint256 received = balanceAfter - balanceBefore;
            if (received != amount) {
                revert BalanceMismatch(amount, received);
            }
        }
    }
}
