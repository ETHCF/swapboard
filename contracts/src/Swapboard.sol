// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.33;

import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwapboard} from "./interfaces/ISwapboard.sol";
import {IWETH} from "./interfaces/IWETH.sol";

/// @title Swapboard
/// @author Zak Cole (numbergroup.xyz) for Ethereum Community Foundation
/// @notice Trustless OTC bulletin board for ERC20 token swaps on Ethereum
/// @dev This contract implements a simple orderbook for peer-to-peer token swaps.
///
///      Key properties:
///      - No admin functions, fees, or upgrades
///      - Orders are filled atomically (all-or-nothing)
///      - Fee-on-transfer tokens are rejected for tokenA (selling token)
///      - Reentrancy protected via OpenZeppelin ReentrancyGuardTransient (EIP-1153)
///
///      Security considerations:
///      - Front-running is possible on fillOrder (inherent to on-chain orderbooks)
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
    ) {
        if (_weth == address(0)) revert ZeroAddress();
        if (_weth.code.length == 0) revert NotAContract(_weth);
        weth = _weth;
    }

    /// @notice Accept ETH only from WETH contract (for withdraw callbacks)
    receive() external payable {
        if (msg.sender != weth) revert NotWETH(weth, msg.sender);
    }

    /// @inheritdoc ISwapboard
    /// @dev Token addresses are identity-based. Aliased or rebranded tokens at different
    ///      addresses are treated as distinct tokens. Users must verify token addresses.
    function createOrder(
        address tokenA,
        uint256 amountA,
        address tokenB,
        uint256 amountB
    ) external nonReentrant returns (uint256 orderId) {
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
            orderId = nextOrderId++;
        }

        orders[orderId] = Order({
            maker: msg.sender,
            tokenA: tokenA,
            amountA: amountA,
            tokenB: tokenB,
            amountB: amountB,
            active: true
        });

        emit OrderCreated(orderId, msg.sender, tokenA, amountA, tokenB, amountB);
    }

    /// @inheritdoc ISwapboard
    /// @dev Fee-on-transfer tokenB: maker receives less than amountB. This is maker's risk.
    function fillOrder(
        uint256 orderId,
        uint256 deadline
    ) external nonReentrant {
        if (deadline != 0 && block.timestamp > deadline) revert DeadlineExpired();

        Order storage order = orders[orderId];

        address maker = order.maker;
        if (maker == address(0)) revert OrderNotFound(orderId);
        if (!order.active) revert OrderNotActive(orderId);

        order.active = false;

        // Transfer tokenB from taker to maker
        // Note: If tokenB is fee-on-transfer, maker receives less than amountB
        IERC20(order.tokenB).safeTransferFrom(msg.sender, maker, order.amountB);

        // Transfer tokenA from contract to taker
        IERC20(order.tokenA).safeTransfer(msg.sender, order.amountA);

        emit OrderFilled(orderId, msg.sender);
    }

    /// @inheritdoc ISwapboard
    function cancelOrder(
        uint256 orderId
    ) external nonReentrant {
        Order storage order = orders[orderId];

        address maker = order.maker;
        if (maker == address(0)) revert OrderNotFound(orderId);
        if (!order.active) revert OrderNotActive(orderId);
        if (msg.sender != maker) revert NotMaker(orderId, msg.sender, maker);

        order.active = false;

        IERC20(order.tokenA).safeTransfer(maker, order.amountA);

        emit OrderCanceled(orderId);
    }

    /// @inheritdoc ISwapboard
    /// @dev Token addresses are identity-based. Aliased or rebranded tokens at different
    ///      addresses are treated as distinct tokens. Users must verify token addresses.
    function createOrderWithEth(
        address tokenB,
        uint256 amountB
    ) external payable nonReentrant returns (uint256 orderId) {
        if (msg.value == 0) revert ZeroETH();
        if (tokenB == address(0)) revert ZeroAddress();
        if (amountB == 0) revert ZeroAmount();
        if (tokenB == weth) revert SameToken();
        if (tokenB.code.length == 0) revert NotAContract(tokenB);

        IWETH(weth).deposit{value: msg.value}();

        unchecked {
            orderId = nextOrderId++;
        }

        orders[orderId] = Order({
            maker: msg.sender,
            tokenA: weth,
            amountA: msg.value,
            tokenB: tokenB,
            amountB: amountB,
            active: true
        });

        emit OrderCreated(orderId, msg.sender, weth, msg.value, tokenB, amountB);
    }

    /// @inheritdoc ISwapboard
    function fillOrderWithEth(
        uint256 orderId,
        uint256 deadline
    ) external payable nonReentrant {
        if (deadline != 0 && block.timestamp > deadline) revert DeadlineExpired();

        Order storage order = orders[orderId];

        address maker = order.maker;
        if (maker == address(0)) revert OrderNotFound(orderId);
        if (!order.active) revert OrderNotActive(orderId);

        uint256 amountB = order.amountB;

        if (order.tokenB != weth) revert NotWETH(weth, order.tokenB);
        if (msg.value != amountB) revert ETHAmountMismatch(amountB, msg.value);

        order.active = false;

        IWETH(weth).deposit{value: msg.value}();
        IERC20(weth).safeTransfer(maker, amountB);

        IERC20(order.tokenA).safeTransfer(msg.sender, order.amountA);

        emit OrderFilled(orderId, msg.sender);
    }

    /// @inheritdoc ISwapboard
    function cancelOrderUnwrap(
        uint256 orderId
    ) external nonReentrant {
        Order storage order = orders[orderId];

        address maker = order.maker;
        if (maker == address(0)) revert OrderNotFound(orderId);
        if (!order.active) revert OrderNotActive(orderId);
        if (msg.sender != maker) revert NotMaker(orderId, msg.sender, maker);
        if (order.tokenA != weth) revert NotWETH(weth, order.tokenA);

        uint256 amountA = order.amountA;

        order.active = false;

        IWETH(weth).withdraw(amountA);

        bool success;
        assembly {
            success := call(gas(), maker, amountA, 0, 0, 0, 0)
        }
        if (!success) revert ETHTransferFailed(maker);

        emit OrderCanceled(orderId);
    }

    /// @inheritdoc ISwapboard
    function fillOrderUnwrap(
        uint256 orderId,
        uint256 deadline
    ) external nonReentrant {
        if (deadline != 0 && block.timestamp > deadline) revert DeadlineExpired();

        Order storage order = orders[orderId];

        address maker = order.maker;
        if (maker == address(0)) revert OrderNotFound(orderId);
        if (!order.active) revert OrderNotActive(orderId);
        if (order.tokenA != weth) revert NotWETH(weth, order.tokenA);

        uint256 amountA = order.amountA;

        order.active = false;

        IERC20(order.tokenB).safeTransferFrom(msg.sender, maker, order.amountB);

        IWETH(weth).withdraw(amountA);

        bool success;
        assembly {
            success := call(gas(), caller(), amountA, 0, 0, 0, 0)
        }
        if (!success) revert ETHTransferFailed(msg.sender);

        emit OrderFilled(orderId, msg.sender);
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
        for (uint256 i; i < orderIds.length;) {
            result[i] = orders[orderIds[i]];
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc ISwapboard
    function canFill(
        uint256 orderId
    ) external view returns (bool) {
        return orders[orderId].active;
    }
}
