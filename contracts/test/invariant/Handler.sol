// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.33;

// solhint-disable use-natspec

import {Test} from "forge-std/Test.sol";
import {Swapboard} from "../../src/Swapboard.sol";
import {ISwapboard} from "../../src/interfaces/ISwapboard.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @title SwapboardHandler
/// @notice Handler contract for invariant testing of Swapboard
/// @dev Tracks ghost variables for accounting invariants
contract SwapboardHandler is Test {
    Swapboard internal _board;
    MockERC20 internal _tokenA;
    MockERC20 internal _tokenB;

    // Ghost variables for tracking state
    uint256 public ghost_totalTokenADeposited;
    uint256 public ghost_totalTokenAWithdrawn;
    uint256 public ghost_ordersCreated;
    uint256 public ghost_ordersFilled;
    uint256 public ghost_ordersCancelled;
    uint256 public ghost_activeOrders;

    // Track individual order amounts for precise accounting
    mapping(uint256 => uint256) public ghost_orderAmounts;
    mapping(uint256 => bool) public ghost_orderActive;

    // Actors
    address[] internal _actors;
    address internal _currentActor;

    // Counters for call tracking
    uint256 public calls_createOrder;
    uint256 public calls_fillOrder;
    uint256 public calls_cancelOrder;

    modifier useActor(
        uint256 actorIndexSeed
    ) {
        _currentActor = _actors[bound(actorIndexSeed, 0, _actors.length - 1)];
        vm.startPrank(_currentActor);
        _;
        vm.stopPrank();
    }

    constructor(
        Swapboard board,
        MockERC20 tokenA,
        MockERC20 tokenB
    ) {
        _board = board;
        _tokenA = tokenA;
        _tokenB = tokenB;

        // Setup actors
        _actors.push(address(0x1001));
        _actors.push(address(0x1002));
        _actors.push(address(0x1003));
        _actors.push(address(0x1004));
        _actors.push(address(0x1005));

        // Mint tokens to all actors
        for (uint256 i = 0; i < _actors.length; ++i) {
            _tokenA.mint(_actors[i], 1_000_000 ether);
            _tokenB.mint(_actors[i], 1_000_000 ether);
            vm.prank(_actors[i]);
            _tokenA.approve(address(_board), type(uint256).max);
            vm.prank(_actors[i]);
            _tokenB.approve(address(_board), type(uint256).max);
        }
    }

    /// @notice Creates a new order with bounded amounts
    function createOrder(
        uint256 actorSeed,
        uint256 amountA,
        uint256 amountB
    ) external useActor(actorSeed) {
        amountA = bound(amountA, 1, 1000 ether);
        amountB = bound(amountB, 1, 1000 ether);

        uint256 balanceBefore = _tokenA.balanceOf(_currentActor);
        if (balanceBefore < amountA) {
            return; // Skip if insufficient balance
        }

        ++calls_createOrder;

        uint256 orderId = _board.createOrder(address(_tokenA), amountA, address(_tokenB), amountB);

        ghost_totalTokenADeposited += amountA;
        ++ghost_ordersCreated;
        ++ghost_activeOrders;
        ghost_orderAmounts[orderId] = amountA;
        ghost_orderActive[orderId] = true;
    }

    /// @notice Fills an existing order
    function fillOrder(
        uint256 actorSeed,
        uint256 orderIdSeed
    ) external useActor(actorSeed) {
        uint256 nextId = _board.nextOrderId();
        if (nextId == 0) {
            return; // No orders exist
        }

        uint256 orderId = bound(orderIdSeed, 0, nextId - 1);
        ISwapboard.Order memory order = _board.getOrder(orderId);

        if (!order.active) {
            return; // Order not active
        }

        uint256 takerBalance = _tokenB.balanceOf(_currentActor);
        if (takerBalance < order.amountB) {
            return; // Insufficient balance
        }

        ++calls_fillOrder;

        _board.fillOrder(orderId, 0);

        ghost_totalTokenAWithdrawn += order.amountA;
        ++ghost_ordersFilled;
        --ghost_activeOrders;
        ghost_orderActive[orderId] = false;
    }

    /// @notice Cancels an order (only by maker)
    function cancelOrder(
        uint256 orderIdSeed
    ) external {
        uint256 nextId = _board.nextOrderId();
        if (nextId == 0) {
            return;
        }

        uint256 orderId = bound(orderIdSeed, 0, nextId - 1);
        ISwapboard.Order memory order = _board.getOrder(orderId);

        if (!order.active) {
            return;
        }

        // Only maker can cancel
        vm.prank(order.maker);
        ++calls_cancelOrder;

        _board.cancelOrder(orderId);

        ghost_totalTokenAWithdrawn += order.amountA;
        ++ghost_ordersCancelled;
        --ghost_activeOrders;
        ghost_orderActive[orderId] = false;
    }

    /// @notice View function to get contract token balance
    function getContractTokenABalance() external view returns (uint256) {
        return _tokenA.balanceOf(address(_board));
    }

    /// @notice Calculate expected contract balance from ghost vars
    function getExpectedContractBalance() external view returns (uint256) {
        return ghost_totalTokenADeposited - ghost_totalTokenAWithdrawn;
    }

    /// @notice Count active orders by iterating
    function countActiveOrders() external view returns (uint256 count) {
        uint256 nextId = _board.nextOrderId();
        for (uint256 i = 0; i < nextId; ++i) {
            if (_board.canFill(i)) {
                ++count;
            }
        }
    }

    /// @notice Get sum of all active order amounts
    function sumActiveOrderAmounts() external view returns (uint256 total) {
        uint256 nextId = _board.nextOrderId();
        for (uint256 i = 0; i < nextId; ++i) {
            ISwapboard.Order memory order = _board.getOrder(i);
            if (order.active) {
                total += order.amountA;
            }
        }
    }
}
