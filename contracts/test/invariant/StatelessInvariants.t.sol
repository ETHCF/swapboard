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
    Swapboard internal _board;
    MockERC20 internal _tokenA;
    MockERC20 internal _tokenB;
    MockWETH internal _mockWeth;

    address internal _maker = makeAddr("maker");
    address internal _taker = makeAddr("taker");

    /// @notice Deploys fixtures for each test
    function setUp() public {
        _mockWeth = new MockWETH();
        _board = new Swapboard(address(_mockWeth));
        _tokenA = new MockERC20("Token A", "TKA", 18);
        _tokenB = new MockERC20("Token B", "TKB", 18);

        _tokenA.mint(_maker, type(uint128).max);
        _tokenB.mint(_taker, type(uint128).max);

        vm.prank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        vm.prank(_taker);
        _tokenB.approve(address(_board), type(uint256).max);
    }

    /// @notice Property: After createOrder, _maker loses exactly amountA
    function testFuzz_createOrder_makerBalanceDecrease(
        uint256 amountA,
        uint256 amountB
    ) public {
        amountA = bound(amountA, 1, 1e30);
        amountB = bound(amountB, 1, 1e30);

        uint256 balanceBefore = _tokenA.balanceOf(_maker);

        vm.prank(_maker);
        _board.createOrder(address(_tokenA), amountA, address(_tokenB), amountB);

        uint256 balanceAfter = _tokenA.balanceOf(_maker);
        assertEq(balanceBefore - balanceAfter, amountA, "Maker balance decrease incorrect");
    }

    /// @notice Property: After createOrder, contract gains exactly amountA
    function testFuzz_createOrder_contractBalanceIncrease(
        uint256 amountA,
        uint256 amountB
    ) public {
        amountA = bound(amountA, 1, 1e30);
        amountB = bound(amountB, 1, 1e30);

        uint256 balanceBefore = _tokenA.balanceOf(address(_board));

        vm.prank(_maker);
        _board.createOrder(address(_tokenA), amountA, address(_tokenB), amountB);

        uint256 balanceAfter = _tokenA.balanceOf(address(_board));
        assertEq(balanceAfter - balanceBefore, amountA, "Contract balance increase incorrect");
    }

    /// @notice Property: After fillOrder, _taker gains exactly amountA
    function testFuzz_fillOrder_takerGainsTokenA(
        uint256 amountA,
        uint256 amountB
    ) public {
        amountA = bound(amountA, 1, 1e30);
        amountB = bound(amountB, 1, 1e30);

        vm.prank(_maker);
        uint256 orderId = _board.createOrder(address(_tokenA), amountA, address(_tokenB), amountB);

        uint256 takerBalanceBefore = _tokenA.balanceOf(_taker);

        vm.prank(_taker);
        _board.fillOrder(orderId, 0);

        uint256 takerBalanceAfter = _tokenA.balanceOf(_taker);
        assertEq(
            takerBalanceAfter - takerBalanceBefore, amountA, "Taker did not receive correct amountA"
        );
    }

    /// @notice Property: After fillOrder, _maker gains exactly amountB
    function testFuzz_fillOrder_makerGainsTokenB(
        uint256 amountA,
        uint256 amountB
    ) public {
        amountA = bound(amountA, 1, 1e30);
        amountB = bound(amountB, 1, 1e30);

        vm.prank(_maker);
        uint256 orderId = _board.createOrder(address(_tokenA), amountA, address(_tokenB), amountB);

        uint256 makerBalanceBefore = _tokenB.balanceOf(_maker);

        vm.prank(_taker);
        _board.fillOrder(orderId, 0);

        uint256 makerBalanceAfter = _tokenB.balanceOf(_maker);
        assertEq(
            makerBalanceAfter - makerBalanceBefore, amountB, "Maker did not receive correct amountB"
        );
    }

    /// @notice Property: After cancelOrder, _maker regains exactly amountA
    function testFuzz_cancelOrder_makerRegainsTokenA(
        uint256 amountA,
        uint256 amountB
    ) public {
        amountA = bound(amountA, 1, 1e30);
        amountB = bound(amountB, 1, 1e30);

        uint256 balanceInitial = _tokenA.balanceOf(_maker);

        vm.prank(_maker);
        uint256 orderId = _board.createOrder(address(_tokenA), amountA, address(_tokenB), amountB);

        vm.prank(_maker);
        _board.cancelOrder(orderId);

        uint256 balanceFinal = _tokenA.balanceOf(_maker);
        assertEq(balanceFinal, balanceInitial, "Maker did not regain full amountA after cancel");
    }

    /// @notice Property: Order state transitions are final
    function testFuzz_orderStateFinal_afterFill(
        uint256 amountA,
        uint256 amountB
    ) public {
        amountA = bound(amountA, 1, 1e30);
        amountB = bound(amountB, 1, 1e30);

        vm.prank(_maker);
        uint256 orderId = _board.createOrder(address(_tokenA), amountA, address(_tokenB), amountB);

        assertTrue(_board.canFill(orderId), "Order should be fillable");

        vm.prank(_taker);
        _board.fillOrder(orderId, 0);

        assertFalse(_board.canFill(orderId), "Order should not be fillable after fill");

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active, "Order should be inactive after fill");
    }

    /// @notice Property: nextOrderId monotonically increases
    function testFuzz_nextOrderId_monotonic(
        uint256 n
    ) public {
        n = bound(n, 1, 50);

        uint256 prevId = _board.nextOrderId();

        for (uint256 i = 0; i < n; ++i) {
            vm.prank(_maker);
            _board.createOrder(address(_tokenA), 1 ether, address(_tokenB), 1 ether);

            uint256 currentId = _board.nextOrderId();
            assertGt(currentId, prevId, "nextOrderId did not increase");
            prevId = currentId;
        }
    }
}
