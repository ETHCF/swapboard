// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {Swapboard} from "../../src/Swapboard.sol";
import {ISwapboard} from "../../src/interfaces/ISwapboard.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @title SwapboardHandler
/// @notice Handler contract for invariant testing of Swapboard
/// @dev Tracks ghost variables for accounting invariants
contract SwapboardHandler is Test {
    Swapboard public board;
    MockERC20 public tokenA;
    MockERC20 public tokenB;

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
    address[] public actors;
    address internal currentActor;

    // Counters for call tracking
    uint256 public calls_createOrder;
    uint256 public calls_fillOrder;
    uint256 public calls_cancelOrder;

    modifier useActor(
        uint256 actorIndexSeed
    ) {
        currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    constructor(
        Swapboard _board,
        MockERC20 _tokenA,
        MockERC20 _tokenB
    ) {
        board = _board;
        tokenA = _tokenA;
        tokenB = _tokenB;

        // Setup actors
        actors.push(address(0x1001));
        actors.push(address(0x1002));
        actors.push(address(0x1003));
        actors.push(address(0x1004));
        actors.push(address(0x1005));

        // Mint tokens to all actors
        for (uint256 i = 0; i < actors.length; i++) {
            tokenA.mint(actors[i], 1_000_000 ether);
            tokenB.mint(actors[i], 1_000_000 ether);
            vm.prank(actors[i]);
            tokenA.approve(address(board), type(uint256).max);
            vm.prank(actors[i]);
            tokenB.approve(address(board), type(uint256).max);
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

        uint256 balanceBefore = tokenA.balanceOf(currentActor);
        if (balanceBefore < amountA) {
            return; // Skip if insufficient balance
        }

        calls_createOrder++;

        uint256 orderId = board.createOrder(address(tokenA), amountA, address(tokenB), amountB);

        ghost_totalTokenADeposited += amountA;
        ghost_ordersCreated++;
        ghost_activeOrders++;
        ghost_orderAmounts[orderId] = amountA;
        ghost_orderActive[orderId] = true;
    }

    /// @notice Fills an existing order
    function fillOrder(
        uint256 actorSeed,
        uint256 orderIdSeed
    ) external useActor(actorSeed) {
        uint256 nextId = board.nextOrderId();
        if (nextId == 0) {
            return; // No orders exist
        }

        uint256 orderId = bound(orderIdSeed, 0, nextId - 1);
        ISwapboard.Order memory order = board.getOrder(orderId);

        if (!order.active) {
            return; // Order not active
        }

        uint256 takerBalance = tokenB.balanceOf(currentActor);
        if (takerBalance < order.amountB) {
            return; // Insufficient balance
        }

        calls_fillOrder++;

        board.fillOrder(orderId);

        ghost_totalTokenAWithdrawn += order.amountA;
        ghost_ordersFilled++;
        ghost_activeOrders--;
        ghost_orderActive[orderId] = false;
    }

    /// @notice Cancels an order (only by maker)
    function cancelOrder(
        uint256 orderIdSeed
    ) external {
        uint256 nextId = board.nextOrderId();
        if (nextId == 0) {
            return;
        }

        uint256 orderId = bound(orderIdSeed, 0, nextId - 1);
        ISwapboard.Order memory order = board.getOrder(orderId);

        if (!order.active) {
            return;
        }

        // Only maker can cancel
        vm.prank(order.maker);
        calls_cancelOrder++;

        board.cancelOrder(orderId);

        ghost_totalTokenAWithdrawn += order.amountA;
        ghost_ordersCancelled++;
        ghost_activeOrders--;
        ghost_orderActive[orderId] = false;
    }

    /// @notice View function to get contract token balance
    function getContractTokenABalance() external view returns (uint256) {
        return tokenA.balanceOf(address(board));
    }

    /// @notice Calculate expected contract balance from ghost vars
    function getExpectedContractBalance() external view returns (uint256) {
        return ghost_totalTokenADeposited - ghost_totalTokenAWithdrawn;
    }

    /// @notice Count active orders by iterating
    function countActiveOrders() external view returns (uint256 count) {
        uint256 nextId = board.nextOrderId();
        for (uint256 i = 0; i < nextId; i++) {
            if (board.canFill(i)) {
                count++;
            }
        }
    }

    /// @notice Get sum of all active order amounts
    function sumActiveOrderAmounts() external view returns (uint256 total) {
        uint256 nextId = board.nextOrderId();
        for (uint256 i = 0; i < nextId; i++) {
            ISwapboard.Order memory order = board.getOrder(i);
            if (order.active) {
                total += order.amountA;
            }
        }
    }
}
