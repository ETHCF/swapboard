// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec
// solhint-disable gas-small-strings

import {Test} from "forge-std/Test.sol";
import {FillTestLib} from "../helpers/FillTestLib.sol";
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
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: amountA,
                tokenB: address(_tokenB),
                amountB: amountB,
                partialFillAllowed: false
            })
        );

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertEq(order.amountA, amountA);
        assertEq(order.amountB, amountB);
        assertEq(order.availableA, amountA);
        assertEq(order.availableB, amountB);
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
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: amountA,
                tokenB: address(_tokenB),
                amountB: amountB,
                partialFillAllowed: true
            })
        );

        vm.startPrank(_taker);
        FillTestLib.fill(_board, orderId, fillA);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertEq(order.amountA, amountA);
        assertEq(order.amountB, amountB);
        assertEq(order.availableA, amountA - fillA);
        assertEq(order.availableB, amountB - amountBIn);
        assertTrue(!(order.availableA > order.amountA));
        assertTrue(!(order.availableB > order.amountB));
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
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: amountA,
                tokenB: address(_tokenB),
                amountB: amountB,
                partialFillAllowed: false
            })
        );

        vm.startPrank(_taker);
        FillTestLib.fill(_board, orderId, amountA);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(order.amountA, amountA);
        assertEq(order.amountB, amountB);
        assertEq(order.availableA, 0);
        assertEq(order.availableB, 0);
    }

    /// @notice Property: cancel deletes the order and refunds remaining availableA
    function testFuzz_cancelOrder_deletesOrderKeepsRefund(
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
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: amountA,
                tokenB: address(_tokenB),
                amountB: amountB,
                partialFillAllowed: true
            })
        );

        vm.startPrank(_taker);
        FillTestLib.fill(_board, orderId, fillA);
        vm.stopPrank();

        uint256 makerBefore = _tokenA.balanceOf(_maker);
        uint128 remainingA = _board.getOrder(orderId).availableA;

        vm.prank(_maker);
        _board.cancelOrder(orderId);

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertEq(order.maker, address(0));
        assertFalse(order.active);
        assertEq(order.amountA, 0);
        assertEq(order.amountB, 0);
        assertEq(order.availableA, 0);
        assertEq(order.availableB, 0);
        assertEq(_tokenA.balanceOf(_maker), makerBefore + remainingA);
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
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: amountA,
                tokenB: address(_tokenB),
                amountB: amountB,
                partialFillAllowed: true
            })
        );

        vm.startPrank(_taker);
        FillTestLib.fill(_board, orderId, fillA1);
        vm.stopPrank();

        ISwapboard.Order memory afterFirst = _board.getOrder(orderId);
        uint256 filledA1 = uint256(afterFirst.amountA) - uint256(afterFirst.availableA);
        uint256 filledB1 = uint256(afterFirst.amountB) - uint256(afterFirst.availableB);
        assertEq(filledA1, fillA1);
        assertEq(filledB1, bIn1);
        assertEq(afterFirst.amountA, amountA);
        assertEq(afterFirst.amountB, amountB);

        uint128 fillA2 = afterFirst.availableA;
        vm.assume(fillA2 > 0 && afterFirst.availableB > 0);

        vm.startPrank(_taker);
        FillTestLib.fill(_board, orderId, fillA2);
        vm.stopPrank();

        ISwapboard.Order memory afterSecond = _board.getOrder(orderId);
        assertEq(afterSecond.amountA, amountA);
        assertEq(afterSecond.amountB, amountB);
        assertTrue(
            !(afterSecond.availableA > afterFirst.availableA) && !(afterSecond.availableB > afterFirst.availableB)
        );
        uint256 filledA2 = uint256(afterSecond.amountA) - uint256(afterSecond.availableA);
        assertTrue(!(filledA2 < filledA1));
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
        _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: amountA,
                tokenB: address(_tokenB),
                amountB: amountB,
                partialFillAllowed: false
            })
        );

        uint256 balanceAfter = _tokenA.balanceOf(_maker);
        assertEq(balanceBefore - balanceAfter, amountA);
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
        _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: amountA,
                tokenB: address(_tokenB),
                amountB: amountB,
                partialFillAllowed: false
            })
        );

        uint256 balanceAfter = _tokenA.balanceOf(address(_board));
        assertEq(balanceAfter - balanceBefore, amountA);
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
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: amountA,
                tokenB: address(_tokenB),
                amountB: amountB,
                partialFillAllowed: false
            })
        );

        uint256 takerBalanceBefore = _tokenA.balanceOf(_taker);

        vm.startPrank(_taker);
        FillTestLib.fill(_board, orderId, amountA);
        vm.stopPrank();

        uint256 takerBalanceAfter = _tokenA.balanceOf(_taker);
        assertEq(takerBalanceAfter - takerBalanceBefore, amountA);
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
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: amountA,
                tokenB: address(_tokenB),
                amountB: amountB,
                partialFillAllowed: false
            })
        );

        uint256 makerBalanceBefore = _tokenB.balanceOf(_maker);

        vm.startPrank(_taker);
        FillTestLib.fill(_board, orderId, amountA);
        vm.stopPrank();

        uint256 makerBalanceAfter = _tokenB.balanceOf(_maker);
        assertEq(makerBalanceAfter - makerBalanceBefore, amountB);
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
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: amountA,
                tokenB: address(_tokenB),
                amountB: amountB,
                partialFillAllowed: false
            })
        );

        vm.prank(_maker);
        _board.cancelOrder(orderId);

        uint256 balanceFinal = _tokenA.balanceOf(_maker);
        assertEq(balanceFinal, balanceInitial);
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
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: amountA,
                tokenB: address(_tokenB),
                amountB: amountB,
                partialFillAllowed: false
            })
        );

        assertTrue(_board.canFill(orderId));

        vm.startPrank(_taker);
        FillTestLib.fill(_board, orderId, amountA);
        vm.stopPrank();

        assertFalse(_board.canFill(orderId));

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active);
    }

    /// @notice Property: nextOrderId monotonically increases
    function testFuzz_nextOrderId_monotonic(
        uint256 n
    ) public {
        n = bound(n, 1, 50);

        uint256 prevId = _board.getNextOrderId();

        for (uint256 i = 0; i < n; ++i) {
            vm.prank(_maker);
            _board.createOrder(
                ISwapboard.CreateOrderParams({
                    tokenA: address(_tokenA),
                    amountA: 1 ether,
                    tokenB: address(_tokenB),
                    amountB: 1 ether,
                    partialFillAllowed: false
                })
            );

            uint256 currentId = _board.getNextOrderId();
            assertGt(currentId, prevId);
            prevId = currentId;
        }
    }
}
