// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ISwapboard} from "./interfaces/ISwapboard.sol";
import {IWETH} from "./interfaces/IWETH.sol";

/// @title Swapboard
/// @author Zak Cole (numbergroup.xyz) for Ethereum Community Foundation
/// @custom:coauthor z0r0z (zfi.wei) for Ethereum and the onchain traders
/// @notice Trustless OTC bulletin board for ERC20 token swaps on Ethereum
/// @dev This contract implements a simple orderbook for peer-to-peer token swaps.
///
///      Key properties:
///      - No admin functions, fees, or upgrades
///      - Orders support full fills (default) or partial fills (opt-in at creation)
///      - Partial fill math uses OpenZeppelin Math.mulDiv for overflow-safe
///        proportional computation; rounding always favors the maker
///      - Fee-on-transfer tokens are rejected for tokenA on deposit (selling token)
///      - Reentrancy protected via OpenZeppelin ReentrancyGuardTransient (EIP-1153)
///
///      Security considerations:
///      - Front-running is possible on fill functions (inherent to on-chain orderbooks)
///      - Rebasing tokens may cause unexpected behavior
///      - Malicious tokens can cause fund loss - users must verify token contracts
///
/// @custom:security-contact zak@numbergroup.xyz
contract Swapboard is ISwapboard, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;

    /// @notice Canonical WETH address for this deployment
    address public immutable weth;

    /// @notice Counter for generating unique order IDs
    /// @dev Starts at 0, increments by 1 for each new order
    uint256 public nextOrderId;

    /// @notice Mapping from order ID to Order struct
    /// @dev Non-existent orders return default struct with maker=address(0) and active=false
    mapping(uint256 orderId => Order order) public orders;

    constructor(
        address _weth
    ) payable {
        if (_weth == address(0)) revert ZeroAddress();
        if (_weth.code.length == 0) revert NotAContract(_weth);
        weth = _weth;
    }

    /// @notice Accept ETH only from WETH contract (for withdraw callbacks)
    receive() external payable {
        if (msg.sender != weth) revert NotWETH(weth, msg.sender);
    }

    /// @dev Validates an order and computes fill amounts. Updates storage for both
    ///      full and partial fills. fillAmountB == 0 means "fill entire order".
    function _computeFill(
        Order storage order,
        uint256 orderId,
        uint256 fillAmountB
    )
        internal
        returns (address maker, uint256 transferAmountA, uint256 transferAmountB, bool fullFill)
    {
        bool active;
        (maker, active) = (order.maker, order.active);
        if (maker == address(0)) revert OrderNotFound(orderId);
        if (!active) revert OrderNotActive(orderId);

        uint256 amountA = order.amountA;
        uint256 amountB = order.amountB;

        // Full fill: fillAmountB is 0 (meaning "all") or covers the remainder
        if (fillAmountB == 0 || fillAmountB >= amountB) {
            order.active = false;
            order.amountA = 0;
            order.amountB = 0;
            return (maker, amountA, amountB, true);
        }

        // Partial fill
        if (!order.partialFill) revert PartialFillNotAllowed(orderId);

        // Rounds down, favoring maker; overflow-safe via 512-bit intermediate
        transferAmountA = Math.mulDiv(fillAmountB, amountA, amountB);
        if (transferAmountA == 0) revert ZeroFillAmount();

        order.amountA = amountA - transferAmountA;
        order.amountB = amountB - fillAmountB;

        return (maker, transferAmountA, fillAmountB, false);
    }

    /// @dev Internal create logic shared by createOrder and createOrders.
    function _createOrder(
        address tokenA,
        uint256 amountA,
        address tokenB,
        uint256 amountB,
        bool partialFill
    ) internal returns (uint256 orderId) {
        if (tokenA == address(0)) revert ZeroAddress();
        if (tokenB == address(0)) revert ZeroAddress();
        if (amountA == 0) revert ZeroAmount();
        if (amountB == 0) revert ZeroAmount();
        if (tokenA == tokenB) revert SameToken();
        if (tokenA.code.length == 0) revert NotAContract(tokenA);
        if (tokenB.code.length == 0) revert NotAContract(tokenB);

        uint256 balanceBefore = IERC20(tokenA).balanceOf(address(this));
        IERC20(tokenA).safeTransferFrom(msg.sender, address(this), amountA);
        uint256 balanceAfter = IERC20(tokenA).balanceOf(address(this));

        // Detect fee-on-transfer tokens by comparing received amount to expected
        // Using unchecked is safe: balanceAfter >= balanceBefore after successful transfer
        unchecked {
            uint256 received = balanceAfter - balanceBefore;
            if (received != amountA) {
                revert BalanceMismatch(amountA, received);
            }
        }

        orderId = _storeOrder(msg.sender, tokenA, amountA, tokenB, amountB, partialFill);
    }

    /// @dev Writes order to storage, emits event, and returns the new order ID.
    function _storeOrder(
        address maker,
        address tokenA,
        uint256 amountA,
        address tokenB,
        uint256 amountB,
        bool partialFill
    ) internal returns (uint256 orderId) {
        unchecked {
            orderId = nextOrderId++;
        }

        orders[orderId] = Order({
            maker: maker,
            active: true,
            partialFill: partialFill,
            tokenA: tokenA,
            amountA: amountA,
            tokenB: tokenB,
            amountB: amountB
        });

        emit OrderCreated(orderId, maker, tokenA, amountA, tokenB, amountB, partialFill);
    }

    /// @inheritdoc ISwapboard
    /// @dev Token addresses are identity-based. Aliased or rebranded tokens at different
    ///      addresses are treated as distinct tokens. Users must verify token addresses.
    function createOrder(
        address tokenA,
        uint256 amountA,
        address tokenB,
        uint256 amountB,
        bool partialFill
    ) external nonReentrant returns (uint256 orderId) {
        orderId = _createOrder(tokenA, amountA, tokenB, amountB, partialFill);
    }

    /// @inheritdoc ISwapboard
    /// @dev Gas scales linearly with array length.
    function createOrders(
        CreateOrderParams[] calldata params
    ) external nonReentrant returns (uint256[] memory orderIds) {
        orderIds = new uint256[](params.length);
        for (uint256 i; i < params.length; ++i) {
            orderIds[i] = _createOrder(
                params[i].tokenA,
                params[i].amountA,
                params[i].tokenB,
                params[i].amountB,
                params[i].partialFill
            );
        }
    }

    /// @inheritdoc ISwapboard
    /// @dev Token addresses are identity-based. Aliased or rebranded tokens at different
    ///      addresses are treated as distinct tokens. Users must verify token addresses.
    function createOrderWithEth(
        address tokenB,
        uint256 amountB,
        bool partialFill
    ) external payable nonReentrant returns (uint256 orderId) {
        if (msg.value == 0) revert ZeroETH();
        if (tokenB == address(0)) revert ZeroAddress();
        if (amountB == 0) revert ZeroAmount();
        if (tokenB == weth) revert SameToken();
        if (tokenB.code.length == 0) revert NotAContract(tokenB);

        IWETH(weth).deposit{value: msg.value}();

        orderId = _storeOrder(msg.sender, weth, msg.value, tokenB, amountB, partialFill);
    }

    /// @dev Emits the appropriate fill event (full or partial).
    function _emitFillEvent(
        uint256 orderId,
        address taker,
        address maker,
        address tokenA,
        address tokenB,
        uint256 transferAmountA,
        uint256 transferAmountB,
        uint256 remainingAmountA,
        uint256 remainingAmountB,
        bool fullFill
    ) internal {
        if (fullFill) {
            emit OrderFilled(
                orderId, taker, maker, tokenA, transferAmountA, tokenB, transferAmountB
            );
        } else {
            emit OrderPartiallyFilled(
                orderId,
                taker,
                maker,
                tokenA,
                transferAmountA,
                tokenB,
                transferAmountB,
                remainingAmountA,
                remainingAmountB
            );
        }
    }

    /// @dev Internal fill logic shared by fillOrder and fillOrders.
    ///      Fee-on-transfer tokenB: maker receives less than expected. This is maker's risk.
    function _fillOrder(
        uint256 orderId,
        uint256 fillAmountB
    ) internal {
        Order storage order = orders[orderId];

        (address maker, uint256 transferAmountA, uint256 transferAmountB, bool fullFill) =
            _computeFill(order, orderId, fillAmountB);

        address tokenA = order.tokenA;
        address tokenB = order.tokenB;

        // Transfer tokenB from taker to maker
        IERC20(tokenB).safeTransferFrom(msg.sender, maker, transferAmountB);

        // Transfer tokenA from contract to taker
        IERC20(tokenA).safeTransfer(msg.sender, transferAmountA);

        _emitFillEvent(
            orderId,
            msg.sender,
            maker,
            tokenA,
            tokenB,
            transferAmountA,
            transferAmountB,
            order.amountA,
            order.amountB,
            fullFill
        );
    }

    /// @inheritdoc ISwapboard
    function fillOrder(
        uint256 orderId,
        uint256 deadline,
        uint256 fillAmountB
    ) external nonReentrant {
        if (deadline != 0 && block.timestamp > deadline) revert DeadlineExpired();
        _fillOrder(orderId, fillAmountB);
    }

    /// @inheritdoc ISwapboard
    /// @dev Fills are atomic — if any fill reverts, the entire batch reverts.
    ///      Gas scales linearly with array length.
    function fillOrders(
        uint256[] calldata orderIds,
        uint256 deadline,
        uint256[] calldata fillAmountsB
    ) external nonReentrant {
        if (deadline != 0 && block.timestamp > deadline) revert DeadlineExpired();
        if (orderIds.length != fillAmountsB.length) revert LengthMismatch();

        for (uint256 i; i < orderIds.length; ++i) {
            _fillOrder(orderIds[i], fillAmountsB[i]);
        }
    }

    /// @inheritdoc ISwapboard
    /// @dev Only skips inactive/nonexistent orders — every other revert path aborts
    ///      the batch. See ISwapboard for the full list.
    function tryFillOrders(
        uint256[] calldata orderIds,
        uint256 deadline,
        uint256[] calldata fillAmountsB
    ) external nonReentrant returns (bool[] memory filled) {
        if (deadline != 0 && block.timestamp > deadline) revert DeadlineExpired();
        if (orderIds.length != fillAmountsB.length) revert LengthMismatch();

        filled = new bool[](orderIds.length);
        for (uint256 i; i < orderIds.length; ++i) {
            if (orders[orderIds[i]].active) {
                _fillOrder(orderIds[i], fillAmountsB[i]);
                filled[i] = true;
            }
        }
    }

    /// @inheritdoc ISwapboard
    function fillOrderWithEth(
        uint256 orderId,
        uint256 deadline
    ) external payable nonReentrant {
        if (deadline != 0 && block.timestamp > deadline) revert DeadlineExpired();

        if (msg.value == 0) revert ZeroETH();

        Order storage order = orders[orderId];
        if (order.maker == address(0)) revert OrderNotFound(orderId);
        if (!order.active) revert OrderNotActive(orderId);
        if (order.tokenB != weth) revert NotWETH(weth, order.tokenB);
        if (msg.value > order.amountB) revert ETHAmountMismatch(order.amountB, msg.value);
        // Defensive: fail early before _computeFill, since msg.value is payment, not a sentinel
        if (msg.value < order.amountB && !order.partialFill) revert PartialFillNotAllowed(orderId);

        (address maker, uint256 transferAmountA, uint256 transferAmountB, bool fullFill) =
            _computeFill(order, orderId, msg.value);

        address tokenA = order.tokenA;

        // Wrap ETH to WETH and transfer to maker
        IWETH(weth).deposit{value: msg.value}();
        IERC20(weth).safeTransfer(maker, transferAmountB);

        // Transfer tokenA from contract to taker
        IERC20(tokenA).safeTransfer(msg.sender, transferAmountA);

        _emitFillEvent(
            orderId,
            msg.sender,
            maker,
            tokenA,
            weth,
            transferAmountA,
            transferAmountB,
            order.amountA,
            order.amountB,
            fullFill
        );
    }

    /// @inheritdoc ISwapboard
    function fillOrderUnwrap(
        uint256 orderId,
        uint256 deadline,
        uint256 fillAmountB
    ) external nonReentrant {
        if (deadline != 0 && block.timestamp > deadline) revert DeadlineExpired();

        Order storage order = orders[orderId];
        if (order.maker == address(0)) revert OrderNotFound(orderId);
        if (!order.active) revert OrderNotActive(orderId);
        if (order.tokenA != weth) revert NotWETH(weth, order.tokenA);

        (address maker, uint256 transferAmountA, uint256 transferAmountB, bool fullFill) =
            _computeFill(order, orderId, fillAmountB);

        address tokenB = order.tokenB;

        // Transfer tokenB from taker to maker
        IERC20(tokenB).safeTransferFrom(msg.sender, maker, transferAmountB);

        // Unwrap WETH and transfer ETH to taker
        IWETH(weth).withdraw(transferAmountA);

        bool success;
        assembly {
            success := call(gas(), caller(), transferAmountA, 0, 0, 0, 0)
        }
        if (!success) revert ETHTransferFailed(msg.sender);

        _emitFillEvent(
            orderId,
            msg.sender,
            maker,
            weth,
            tokenB,
            transferAmountA,
            transferAmountB,
            order.amountA,
            order.amountB,
            fullFill
        );
    }

    /// @dev Internal cancel logic shared by cancelOrder and cancelOrders.
    function _cancelOrder(
        uint256 orderId
    ) internal {
        Order storage order = orders[orderId];

        (address maker, bool active) = (order.maker, order.active);
        if (maker == address(0)) revert OrderNotFound(orderId);
        if (!active) revert OrderNotActive(orderId);
        if (msg.sender != maker) revert NotMaker(orderId, msg.sender, maker);

        address tokenA = order.tokenA;
        uint256 amountA = order.amountA;

        order.active = false;
        order.amountA = 0;
        order.amountB = 0;

        IERC20(tokenA).safeTransfer(maker, amountA);

        emit OrderCanceled(orderId, maker, tokenA, amountA);
    }

    /// @inheritdoc ISwapboard
    function cancelOrder(
        uint256 orderId
    ) external nonReentrant {
        _cancelOrder(orderId);
    }

    /// @inheritdoc ISwapboard
    /// @dev Atomic: if any cancellation reverts, the entire batch reverts.
    ///      Gas scales linearly with array length.
    function cancelOrders(
        uint256[] calldata orderIds
    ) external nonReentrant {
        for (uint256 i; i < orderIds.length; ++i) {
            _cancelOrder(orderIds[i]);
        }
    }

    /// @dev Internal cancel-and-unwrap logic shared by cancelOrderUnwrap and cancelOrdersUnwrap.
    function _cancelOrderUnwrap(
        uint256 orderId
    ) internal {
        Order storage order = orders[orderId];

        (address maker, bool active) = (order.maker, order.active);
        if (maker == address(0)) revert OrderNotFound(orderId);
        if (!active) revert OrderNotActive(orderId);
        if (msg.sender != maker) revert NotMaker(orderId, msg.sender, maker);
        if (order.tokenA != weth) revert NotWETH(weth, order.tokenA);

        uint256 amountA = order.amountA;

        order.active = false;
        order.amountA = 0;
        order.amountB = 0;

        IWETH(weth).withdraw(amountA);

        bool success;
        assembly {
            success := call(gas(), maker, amountA, 0, 0, 0, 0)
        }
        if (!success) revert ETHTransferFailed(maker);

        emit OrderCanceled(orderId, maker, weth, amountA);
    }

    /// @inheritdoc ISwapboard
    function cancelOrderUnwrap(
        uint256 orderId
    ) external nonReentrant {
        _cancelOrderUnwrap(orderId);
    }

    /// @inheritdoc ISwapboard
    /// @dev Atomic: if any cancellation reverts, the entire batch reverts.
    ///      Gas scales linearly with array length.
    function cancelOrdersUnwrap(
        uint256[] calldata orderIds
    ) external nonReentrant {
        for (uint256 i; i < orderIds.length; ++i) {
            _cancelOrderUnwrap(orderIds[i]);
        }
    }

    /// @inheritdoc ISwapboard
    function getOrder(
        uint256 orderId
    ) external view returns (Order memory) {
        return orders[orderId];
    }

    /// @inheritdoc ISwapboard
    /// @dev Gas scales linearly with array length. Callers should limit to ~100 IDs per call.
    function getOrders(
        uint256[] calldata orderIds
    ) external view returns (Order[] memory result) {
        result = new Order[](orderIds.length);
        for (uint256 i; i < orderIds.length; ++i) {
            result[i] = orders[orderIds[i]];
        }
    }

    /// @inheritdoc ISwapboard
    function canFill(
        uint256 orderId
    ) external view returns (bool) {
        return orders[orderId].active;
    }
}
