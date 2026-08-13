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
///      - Fee-on-transfer tokens are rejected for tokenA (selling token)
///      - Native ETH uses the `0xEeee...eE` sentinel (`getEth()`)
///      - Order amounts use `uint128` (sufficient for practical sizes); originals and available
///        remaining amounts are packed separately so fill % is readable on-chain
///      - Reentrancy protected via OpenZeppelin ReentrancyGuardTransient (EIP-1153)
///
///      Security considerations:
///      - Front-running is possible on fillOrder (inherent to on-chain orderbooks)
///      - Rebasing tokens may cause unexpected behavior
///      - Malicious tokens can cause fund loss - users must verify token contracts
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
        address tokenA,
        uint128 amountA,
        address tokenB,
        uint128 amountB,
        bool partialFillAllowed
    ) external payable nonReentrant returns (uint256 orderId) {
        _validateCreateOrder(tokenA, amountA, tokenB, amountB);

        if (tokenA != _ETH) {
            _pullExactToken(tokenA, amountA);
        }

        unchecked {
            orderId = _nextOrderId;

            ++_nextOrderId;
        }

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

    /// @inheritdoc ISwapboard
    /// @dev Fee-on-transfer tokenB: maker receives less than amountB. This is maker's risk.
    ///      tokenB in uses ceil division so the taker never underpays for the requested tokenA.
    ///      Residual tokenA dust (when amountB is exhausted first) is not refunded (not worth the
    ///      gas); it can be picked up by any user that rounds favorably on another order where
    ///      the dust token is tokenB.
    function fillOrder(
        uint256 orderId,
        uint128 amountA,
        uint256 deadline
    ) external payable nonReentrant {
        if (deadline != 0 && block.timestamp > deadline) {
            revert DeadlineExpired();
        }
        if (amountA == 0) {
            revert ZeroAmount();
        }

        Order storage order = _orders[orderId];
        (address maker, address tokenA, address tokenB, uint128 amountBIn) =
            _validateAndQuoteFill(order, orderId, amountA);

        uint256 requiredEth = tokenB == _ETH ? amountBIn : 0;
        if (msg.value != requiredEth) {
            revert ETHAmountMismatch(requiredEth, msg.value);
        }

        _applyFillEffects(order, amountA, amountBIn);
        _transferFill(maker, tokenA, tokenB, amountA, amountBIn);

        emit OrderFilled({orderId: orderId, taker: msg.sender, amountA: amountA, amountB: amountBIn});
    }

    /// @inheritdoc ISwapboard
    function cancelOrder(
        uint256 orderId
    ) external nonReentrant {
        Order storage order = _orders[orderId];

        (address maker, bool active, address tokenA, uint128 availableA) =
            (order.maker, order.active, order.tokenA, order.availableA);
        if (maker == address(0)) {
            revert OrderNotFound(orderId);
        }
        if (!active) {
            revert OrderNotActive(orderId);
        }
        if (msg.sender != maker) {
            revert NotMaker(orderId, msg.sender, maker);
        }

        order.active = false;
        order.availableA = 0;
        order.availableB = 0;

        if (tokenA == _ETH) {
            // Forward all gas so maker contracts can execute receive/fallback.
            payable(maker).sendValue(availableA);
        } else {
            IERC20(tokenA).safeTransfer(maker, availableA);
        }

        emit OrderCanceled({orderId: orderId});
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
        Order[] memory result = new Order[](orderIds.length);

        for (uint256 i; i < orderIds.length;) {
            result[i] = _orders[orderIds[i]];
            unchecked {
                ++i;
            }
        }

        return result;
    }

    /// @inheritdoc ISwapboard
    function canFill(
        uint256 orderId
    ) external view returns (bool) {
        return _orders[orderId].active;
    }

    /// @notice Validates createOrder arguments and exact ETH payment
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

        bool tokenAIsEth = tokenA == _ETH;
        bool tokenBIsEth = tokenB == _ETH;

        if (!tokenAIsEth && tokenA.code.length == 0) {
            revert NotAContract(tokenA);
        }
        if (!tokenBIsEth && tokenB.code.length == 0) {
            revert NotAContract(tokenB);
        }

        uint256 requiredEth = tokenAIsEth ? amountA : 0;
        if (msg.value != requiredEth) {
            revert ETHAmountMismatch(requiredEth, msg.value);
        }
    }

    /// @notice Validates a fill and quotes the ceiled tokenB payment
    /// @dev Ceil division benefits escrow/maker. Residual tokenA dust is not refunded.
    ///      Intermediate math widens to uint256; both factors are uint128 so the product fits.
    /// @param order Order storage slot to read
    /// @param orderId Order id for error payloads
    /// @param amountA Requested tokenA out
    /// @return maker Order maker
    /// @return tokenA Sold asset
    /// @return tokenB Payment asset
    /// @return amountBIn Ceiled tokenB the taker must pay
    function _validateAndQuoteFill(
        Order storage order,
        uint256 orderId,
        uint128 amountA
    ) private view returns (address maker, address tokenA, address tokenB, uint128 amountBIn) {
        maker = order.maker;
        if (maker == address(0)) {
            revert OrderNotFound(orderId);
        }
        if (!order.active) {
            revert OrderNotActive(orderId);
        }

        uint128 availableA = order.availableA;
        if (amountA > availableA) {
            revert FillAmountTooHigh(orderId, amountA, availableA);
        }
        if (!order.partialFillAllowed && amountA != availableA) {
            revert PartialFillNotAllowed(orderId);
        }

        tokenA = order.tokenA;
        tokenB = order.tokenB;
        uint128 availableB = order.availableB;
        // Product of two uint128 values always fits in uint256; ceil result is <= availableB.
        // forge-lint: disable-next-line(unsafe-typecast)
        amountBIn = amountA == availableA
            ? availableB
            : uint128((uint256(amountA) * uint256(availableB) + uint256(availableA) - 1) / uint256(availableA));
        if (amountBIn == 0) {
            revert ZeroAmount();
        }
    }

    /// @notice Applies fill accounting effects before transfers (CEI)
    /// @dev Decrements available amounts only; original `amountA`/`amountB` stay fixed for fill %.
    /// @param order Order storage slot to update
    /// @param amountA tokenA sent to the taker
    /// @param amountBIn tokenB paid by the taker
    function _applyFillEffects(
        Order storage order,
        uint128 amountA,
        uint128 amountBIn
    ) private {
        unchecked {
            order.availableA -= amountA;
            order.availableB -= amountBIn;
        }
        if (order.availableA == 0 || order.availableB == 0) {
            order.active = false;
        }
    }

    /// @notice Moves tokenB from taker to maker and tokenA from escrow to taker
    /// @param maker Order maker receiving tokenB
    /// @param tokenA Sold asset (possibly ETH sentinel)
    /// @param tokenB Payment asset (possibly ETH sentinel)
    /// @param amountA tokenA amount to send to the taker
    /// @param amountBIn tokenB amount to take from the taker
    function _transferFill(
        address maker,
        address tokenA,
        address tokenB,
        uint128 amountA,
        uint128 amountBIn
    ) private {
        if (tokenB == _ETH) {
            // Forward all gas so maker contracts can execute receive/fallback.
            payable(maker).sendValue(amountBIn);
        } else {
            // Note: If tokenB is fee-on-transfer, maker receives less than amountB
            IERC20(tokenB).safeTransferFrom(msg.sender, maker, amountBIn);
        }

        if (tokenA == _ETH) {
            // Forward all gas so taker contracts can execute receive/fallback.
            payable(msg.sender).sendValue(amountA);
        } else {
            IERC20(tokenA).safeTransfer(msg.sender, amountA);
        }
    }

    /// @notice Pulls an exact ERC20 amount into escrow, rejecting fee-on-transfer
    /// @param token ERC20 token to pull from the caller
    /// @param amount Expected amount received
    function _pullExactToken(
        address token,
        uint256 amount
    ) private {
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 balanceAfter = IERC20(token).balanceOf(address(this));

        // Detect fee-on-transfer tokens by comparing received amount to expected
        // Using unchecked is safe: balanceAfter >= balanceBefore after successful transfer
        unchecked {
            uint256 received = balanceAfter - balanceBefore;
            if (received != amount) {
                revert BalanceMismatch(amount, received);
            }
        }
    }
}
