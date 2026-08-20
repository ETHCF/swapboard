// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec
// solhint-disable gas-small-strings

import {Test} from "forge-std/Test.sol";
import {Swapboard} from "../../src/Swapboard.sol";
import {ISwapboard} from "../../src/interfaces/ISwapboard.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @title SwapboardStatelessInvariantTest
/// @notice Stateless invariant tests using direct property assertions
contract SwapboardStatelessInvariantTest is Test {
    Swapboard internal _board;
    MockERC20 internal _tokenA;
    MockERC20 internal _tokenB;

    address internal _maker = makeAddr("maker");
    address internal _taker = makeAddr("taker");

    /// @notice Deploys fixtures for each test
    function setUp() public {
        _board = new Swapboard();
        _tokenA = new MockERC20("Token A", "TKA", 18);
        _tokenB = new MockERC20("Token B", "TKB", 18);

        _tokenA.mint(_maker, type(uint128).max);
        _tokenB.mint(_taker, type(uint128).max);

        vm.prank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        vm.prank(_taker);
        _tokenB.approve(address(_board), type(uint256).max);
    }

    /// @notice Property: create sets available equal to original amounts
    function testFuzz_createOrder_availableEqualsOriginal(
        uint256 amountASeed,
        uint256 amountBSeed
    ) public {
        // casting to 'uint128' is safe because bound is capped at uint128.max
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountA = uint128(bound(amountASeed, 1, type(uint128).max));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountB = uint128(bound(amountBSeed, 1, type(uint128).max));

        vm.prank(_maker);
        uint256 orderId = _board.createOrder(address(_tokenA), amountA, address(_tokenB), amountB, false);

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertEq(order.amountA, amountA, "amountA not set to original");
        assertEq(order.amountB, amountB, "amountB not set to original");
        assertEq(order.availableA, amountA, "availableA must equal amountA on create");
        assertEq(order.availableB, amountB, "availableB must equal amountB on create");
    }

    /// @notice Property: fills decrement available only; originals stay fixed
    function testFuzz_fillOrder_decrementsAvailableOnly(
        uint256 amountASeed,
        uint256 amountBSeed,
        uint256 fillASeed
    ) public {
        // casting to 'uint128' is safe because bound is capped at uint128.max
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountA = uint128(bound(amountASeed, 2, type(uint64).max));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountB = uint128(bound(amountBSeed, 2, type(uint64).max));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 fillA = uint128(bound(fillASeed, 1, amountA));

        uint256 amountBIn =
            fillA == amountA ? amountB : (uint256(fillA) * uint256(amountB) + uint256(amountA) - 1) / uint256(amountA);
        vm.assume(amountBIn > 0);

        vm.prank(_maker);
        uint256 orderId = _board.createOrder(address(_tokenA), amountA, address(_tokenB), amountB, true);

        vm.prank(_taker);
        _board.fillOrder(orderId, fillA, 0);

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertEq(order.amountA, amountA, "amountA must stay fixed across fills");
        assertEq(order.amountB, amountB, "amountB must stay fixed across fills");
        assertEq(order.availableA, amountA - fillA, "availableA not decremented correctly");
        assertEq(order.availableB, amountB - amountBIn, "availableB not decremented correctly");
        assertTrue(!(order.availableA > order.amountA), "availableA exceeds amountA");
        assertTrue(!(order.availableB > order.amountB), "availableB exceeds amountB");
    }

    /// @notice Property: full fill zeroes available and preserves originals
    function testFuzz_fillOrder_full_zeroesAvailableKeepsOriginals(
        uint256 amountASeed,
        uint256 amountBSeed
    ) public {
        // casting to 'uint128' is safe because bound is capped at uint128.max
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountA = uint128(bound(amountASeed, 1, type(uint128).max));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountB = uint128(bound(amountBSeed, 1, type(uint128).max));

        vm.prank(_maker);
        uint256 orderId = _board.createOrder(address(_tokenA), amountA, address(_tokenB), amountB, false);

        vm.prank(_taker);
        _board.fillOrder(orderId, amountA, 0);

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active, "order should be inactive after full fill");
        assertEq(order.amountA, amountA, "amountA must stay fixed after full fill");
        assertEq(order.amountB, amountB, "amountB must stay fixed after full fill");
        assertEq(order.availableA, 0, "availableA must be 0 after full fill");
        assertEq(order.availableB, 0, "availableB must be 0 after full fill");
    }

    /// @notice Property: cancel zeroes available and preserves originals
    function testFuzz_cancelOrder_zeroesAvailableKeepsOriginals(
        uint256 amountASeed,
        uint256 amountBSeed,
        uint256 fillASeed
    ) public {
        // casting to 'uint128' is safe because bound is capped at uint128.max
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountA = uint128(bound(amountASeed, 2, type(uint64).max));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountB = uint128(bound(amountBSeed, 2, type(uint64).max));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 fillA = uint128(bound(fillASeed, 1, amountA - 1));

        uint256 amountBIn = (uint256(fillA) * uint256(amountB) + uint256(amountA) - 1) / uint256(amountA);
        vm.assume(amountBIn > 0 && amountBIn < amountB);

        vm.prank(_maker);
        uint256 orderId = _board.createOrder(address(_tokenA), amountA, address(_tokenB), amountB, true);

        vm.prank(_taker);
        _board.fillOrder(orderId, fillA, 0);

        vm.prank(_maker);
        _board.cancelOrder(orderId);

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active, "order should be inactive after cancel");
        assertEq(order.amountA, amountA, "amountA must stay fixed after cancel");
        assertEq(order.amountB, amountB, "amountB must stay fixed after cancel");
        assertEq(order.availableA, 0, "availableA must be 0 after cancel");
        assertEq(order.availableB, 0, "availableB must be 0 after cancel");
    }

    /// @notice Property: fill progress is readable as (amount - available) / amount
    function testFuzz_fillProgress_monotonicAcrossTwoFills(
        uint256 amountASeed,
        uint256 amountBSeed,
        uint256 fillA1Seed
    ) public {
        // casting to 'uint128' is safe because bound is capped at uint64.max
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountA = uint128(bound(amountASeed, 3, type(uint64).max));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountB = uint128(bound(amountBSeed, 3, type(uint64).max));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 fillA1 = uint128(bound(fillA1Seed, 1, amountA - 2));

        uint256 bIn1 = (uint256(fillA1) * uint256(amountB) + uint256(amountA) - 1) / uint256(amountA);
        vm.assume(bIn1 > 0 && bIn1 < amountB);

        vm.prank(_maker);
        uint256 orderId = _board.createOrder(address(_tokenA), amountA, address(_tokenB), amountB, true);

        vm.prank(_taker);
        _board.fillOrder(orderId, fillA1, 0);

        ISwapboard.Order memory afterFirst = _board.getOrder(orderId);
        uint256 filledA1 = uint256(afterFirst.amountA) - uint256(afterFirst.availableA);
        uint256 filledB1 = uint256(afterFirst.amountB) - uint256(afterFirst.availableB);
        assertEq(filledA1, fillA1, "filled A after first fill incorrect");
        assertEq(filledB1, bIn1, "filled B after first fill incorrect");
        assertEq(afterFirst.amountA, amountA, "amountA changed after first fill");
        assertEq(afterFirst.amountB, amountB, "amountB changed after first fill");

        uint128 fillA2 = afterFirst.availableA;
        vm.assume(fillA2 > 0 && afterFirst.availableB > 0);

        vm.prank(_taker);
        _board.fillOrder(orderId, fillA2, 0);

        ISwapboard.Order memory afterSecond = _board.getOrder(orderId);
        assertEq(afterSecond.amountA, amountA, "amountA changed after second fill");
        assertEq(afterSecond.amountB, amountB, "amountB changed after second fill");
        assertTrue(
            !(afterSecond.availableA > afterFirst.availableA) && !(afterSecond.availableB > afterFirst.availableB),
            "available amounts must not increase"
        );
        uint256 filledA2 = uint256(afterSecond.amountA) - uint256(afterSecond.availableA);
        assertTrue(!(filledA2 < filledA1), "filled A must be monotonic");
    }

    /// @notice Property: After createOrder, _maker loses exactly amountA
    function testFuzz_createOrder_makerBalanceDecrease(
        uint256 amountASeed,
        uint256 amountBSeed
    ) public {
        // casting to 'uint128' is safe because bound is capped at uint128.max
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountA = uint128(bound(amountASeed, 1, type(uint128).max));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountB = uint128(bound(amountBSeed, 1, type(uint128).max));

        uint256 balanceBefore = _tokenA.balanceOf(_maker);

        vm.prank(_maker);
        _board.createOrder(address(_tokenA), amountA, address(_tokenB), amountB, false);

        uint256 balanceAfter = _tokenA.balanceOf(_maker);
        assertEq(balanceBefore - balanceAfter, amountA, "Maker balance decrease incorrect");
    }

    /// @notice Property: After createOrder, contract gains exactly amountA
    function testFuzz_createOrder_contractBalanceIncrease(
        uint256 amountASeed,
        uint256 amountBSeed
    ) public {
        // casting to 'uint128' is safe because bound is capped at uint128.max
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountA = uint128(bound(amountASeed, 1, type(uint128).max));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountB = uint128(bound(amountBSeed, 1, type(uint128).max));

        uint256 balanceBefore = _tokenA.balanceOf(address(_board));

        vm.prank(_maker);
        _board.createOrder(address(_tokenA), amountA, address(_tokenB), amountB, false);

        uint256 balanceAfter = _tokenA.balanceOf(address(_board));
        assertEq(balanceAfter - balanceBefore, amountA, "Contract balance increase incorrect");
    }

    /// @notice Property: After fillOrder, _taker gains exactly amountA
    function testFuzz_fillOrder_takerGainsTokenA(
        uint256 amountASeed,
        uint256 amountBSeed
    ) public {
        // casting to 'uint128' is safe because bound is capped at uint128.max
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountA = uint128(bound(amountASeed, 1, type(uint128).max));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountB = uint128(bound(amountBSeed, 1, type(uint128).max));

        vm.prank(_maker);
        uint256 orderId = _board.createOrder(address(_tokenA), amountA, address(_tokenB), amountB, false);

        uint256 takerBalanceBefore = _tokenA.balanceOf(_taker);

        vm.prank(_taker);
        _board.fillOrder(orderId, amountA, 0);

        uint256 takerBalanceAfter = _tokenA.balanceOf(_taker);
        assertEq(takerBalanceAfter - takerBalanceBefore, amountA, "Taker did not receive correct amountA");
    }

    /// @notice Property: After fillOrder, _maker gains exactly amountB
    function testFuzz_fillOrder_makerGainsTokenB(
        uint256 amountASeed,
        uint256 amountBSeed
    ) public {
        // casting to 'uint128' is safe because bound is capped at uint128.max
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountA = uint128(bound(amountASeed, 1, type(uint128).max));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountB = uint128(bound(amountBSeed, 1, type(uint128).max));

        vm.prank(_maker);
        uint256 orderId = _board.createOrder(address(_tokenA), amountA, address(_tokenB), amountB, false);

        uint256 makerBalanceBefore = _tokenB.balanceOf(_maker);

        vm.prank(_taker);
        _board.fillOrder(orderId, amountA, 0);

        uint256 makerBalanceAfter = _tokenB.balanceOf(_maker);
        assertEq(makerBalanceAfter - makerBalanceBefore, amountB, "Maker did not receive correct amountB");
    }

    /// @notice Property: After cancelOrder, _maker regains exactly amountA
    function testFuzz_cancelOrder_makerRegainsTokenA(
        uint256 amountASeed,
        uint256 amountBSeed
    ) public {
        // casting to 'uint128' is safe because bound is capped at uint128.max
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountA = uint128(bound(amountASeed, 1, type(uint128).max));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountB = uint128(bound(amountBSeed, 1, type(uint128).max));

        uint256 balanceInitial = _tokenA.balanceOf(_maker);

        vm.prank(_maker);
        uint256 orderId = _board.createOrder(address(_tokenA), amountA, address(_tokenB), amountB, false);

        vm.prank(_maker);
        _board.cancelOrder(orderId);

        uint256 balanceFinal = _tokenA.balanceOf(_maker);
        assertEq(balanceFinal, balanceInitial, "Maker did not regain full amountA after cancel");
    }

    /// @notice Property: Order state transitions are final
    function testFuzz_orderStateFinal_afterFill(
        uint256 amountASeed,
        uint256 amountBSeed
    ) public {
        // casting to 'uint128' is safe because bound is capped at uint128.max
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountA = uint128(bound(amountASeed, 1, type(uint128).max));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountB = uint128(bound(amountBSeed, 1, type(uint128).max));

        vm.prank(_maker);
        uint256 orderId = _board.createOrder(address(_tokenA), amountA, address(_tokenB), amountB, false);

        assertTrue(_board.canFill(orderId), "Order should be fillable");

        vm.prank(_taker);
        _board.fillOrder(orderId, amountA, 0);

        assertFalse(_board.canFill(orderId), "Order should not be fillable after fill");

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active, "Order should be inactive after fill");
    }

    /// @notice Property: nextOrderId monotonically increases
    function testFuzz_nextOrderId_monotonic(
        uint256 n
    ) public {
        n = bound(n, 1, 50);

        uint256 prevId = _board.getNextOrderId();

        for (uint256 i = 0; i < n; ++i) {
            vm.prank(_maker);
            _board.createOrder(address(_tokenA), 1 ether, address(_tokenB), 1 ether, false);

            uint256 currentId = _board.getNextOrderId();
            assertGt(currentId, prevId, "nextOrderId did not increase");
            prevId = currentId;
        }
    }
}
