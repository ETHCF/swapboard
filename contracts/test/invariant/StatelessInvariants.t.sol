// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.33;

// solhint-disable use-natspec
// solhint-disable gas-small-strings

import {Test} from "forge-std/Test.sol";
import {Swapboard} from "../../src/Swapboard.sol";
import {ISwapboard} from "../../src/interfaces/ISwapboard.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockWETH} from "../mocks/MockWETH.sol";

/// @title SwapboardStatelessInvariantTest
/// @notice Stateless invariant tests using direct property assertions
contract SwapboardStatelessInvariantTest is Test {
    Swapboard public board;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    MockWETH public mockWeth;

    address public maker = makeAddr("maker");
    address public taker = makeAddr("taker");

    /// @notice Deploys fixtures for each test
    function setUp() public {
        mockWeth = new MockWETH();
        board = new Swapboard(address(mockWeth));
        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);

        tokenA.mint(maker, type(uint128).max);
        tokenB.mint(taker, type(uint128).max);

        vm.prank(maker);
        tokenA.approve(address(board), type(uint256).max);
        vm.prank(taker);
        tokenB.approve(address(board), type(uint256).max);
    }

    /// @notice Property: After createOrder, maker loses exactly amountA
    function testFuzz_createOrder_makerBalanceDecrease(
        uint256 amountA,
        uint256 amountB
    ) public {
        amountA = bound(amountA, 1, 1e30);
        amountB = bound(amountB, 1, 1e30);

        uint256 balanceBefore = tokenA.balanceOf(maker);

        vm.prank(maker);
        board.createOrder(address(tokenA), amountA, address(tokenB), amountB);

        uint256 balanceAfter = tokenA.balanceOf(maker);
        assertEq(balanceBefore - balanceAfter, amountA, "Maker balance decrease incorrect");
    }

    /// @notice Property: After createOrder, contract gains exactly amountA
    function testFuzz_createOrder_contractBalanceIncrease(
        uint256 amountA,
        uint256 amountB
    ) public {
        amountA = bound(amountA, 1, 1e30);
        amountB = bound(amountB, 1, 1e30);

        uint256 balanceBefore = tokenA.balanceOf(address(board));

        vm.prank(maker);
        board.createOrder(address(tokenA), amountA, address(tokenB), amountB);

        uint256 balanceAfter = tokenA.balanceOf(address(board));
        assertEq(balanceAfter - balanceBefore, amountA, "Contract balance increase incorrect");
    }

    /// @notice Property: After fillOrder, taker gains exactly amountA
    function testFuzz_fillOrder_takerGainsTokenA(
        uint256 amountA,
        uint256 amountB
    ) public {
        amountA = bound(amountA, 1, 1e30);
        amountB = bound(amountB, 1, 1e30);

        vm.prank(maker);
        uint256 orderId = board.createOrder(address(tokenA), amountA, address(tokenB), amountB);

        uint256 takerBalanceBefore = tokenA.balanceOf(taker);

        vm.prank(taker);
        board.fillOrder(orderId, 0);

        uint256 takerBalanceAfter = tokenA.balanceOf(taker);
        assertEq(
            takerBalanceAfter - takerBalanceBefore, amountA, "Taker did not receive correct amountA"
        );
    }

    /// @notice Property: After fillOrder, maker gains exactly amountB
    function testFuzz_fillOrder_makerGainsTokenB(
        uint256 amountA,
        uint256 amountB
    ) public {
        amountA = bound(amountA, 1, 1e30);
        amountB = bound(amountB, 1, 1e30);

        vm.prank(maker);
        uint256 orderId = board.createOrder(address(tokenA), amountA, address(tokenB), amountB);

        uint256 makerBalanceBefore = tokenB.balanceOf(maker);

        vm.prank(taker);
        board.fillOrder(orderId, 0);

        uint256 makerBalanceAfter = tokenB.balanceOf(maker);
        assertEq(
            makerBalanceAfter - makerBalanceBefore, amountB, "Maker did not receive correct amountB"
        );
    }

    /// @notice Property: After cancelOrder, maker regains exactly amountA
    function testFuzz_cancelOrder_makerRegainsTokenA(
        uint256 amountA,
        uint256 amountB
    ) public {
        amountA = bound(amountA, 1, 1e30);
        amountB = bound(amountB, 1, 1e30);

        uint256 balanceInitial = tokenA.balanceOf(maker);

        vm.prank(maker);
        uint256 orderId = board.createOrder(address(tokenA), amountA, address(tokenB), amountB);

        vm.prank(maker);
        board.cancelOrder(orderId);

        uint256 balanceFinal = tokenA.balanceOf(maker);
        assertEq(balanceFinal, balanceInitial, "Maker did not regain full amountA after cancel");
    }

    /// @notice Property: Order state transitions are final
    function testFuzz_orderStateFinal_afterFill(
        uint256 amountA,
        uint256 amountB
    ) public {
        amountA = bound(amountA, 1, 1e30);
        amountB = bound(amountB, 1, 1e30);

        vm.prank(maker);
        uint256 orderId = board.createOrder(address(tokenA), amountA, address(tokenB), amountB);

        assertTrue(board.canFill(orderId), "Order should be fillable");

        vm.prank(taker);
        board.fillOrder(orderId, 0);

        assertFalse(board.canFill(orderId), "Order should not be fillable after fill");

        ISwapboard.Order memory order = board.getOrder(orderId);
        assertFalse(order.active, "Order should be inactive after fill");
    }

    /// @notice Property: nextOrderId monotonically increases
    function testFuzz_nextOrderId_monotonic(
        uint256 n
    ) public {
        n = bound(n, 1, 50);

        uint256 prevId = board.nextOrderId();

        for (uint256 i = 0; i < n; ++i) {
            vm.prank(maker);
            board.createOrder(address(tokenA), 1 ether, address(tokenB), 1 ether);

            uint256 currentId = board.nextOrderId();
            assertGt(currentId, prevId, "nextOrderId did not increase");
            prevId = currentId;
        }
    }
}
