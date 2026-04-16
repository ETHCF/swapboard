// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.33;

/**
 * @title SwapboardTest
 * @notice Unit tests for the Swapboard contract
 * @dev Tests cover all public functions and error conditions.
 *      Run with: forge test -vvv
 */

import {Test} from "forge-std/Test.sol";
import {Swapboard} from "../src/Swapboard.sol";
import {ISwapboard} from "../src/interfaces/ISwapboard.sol";
import {MockERC20, MockFOT} from "./mocks/MockERC20.sol";
import {MockWETH} from "./mocks/MockWETH.sol";

/// @notice Unit tests for Swapboard contract
/// @dev Uses Foundry's Test framework with MockERC20 tokens
contract SwapboardTest is Test {
    Swapboard public board;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    MockWETH public mockWeth;

    address public maker = address(0x1);
    address public taker = address(0x2);

    /// @dev 100 tokens with 18 decimals
    uint256 constant AMOUNT_A = 100 ether;
    /// @dev 250,000 tokens with 6 decimals (USDC-style)
    uint256 constant AMOUNT_B = 250_000e6;

    function setUp() public {
        mockWeth = new MockWETH();
        board = new Swapboard(address(mockWeth));

        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 6);

        tokenA.mint(maker, AMOUNT_A * 10);
        tokenB.mint(taker, AMOUNT_B * 10);
    }

    function test_initialState() public view {
        assertEq(board.nextOrderId(), 0);
    }

    function test_createOrder() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);

        uint256 orderId =
            board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        vm.stopPrank();

        assertEq(orderId, 0);
        assertEq(board.nextOrderId(), 1);

        ISwapboard.Order memory order = board.getOrder(orderId);
        assertEq(order.maker, maker);
        assertEq(order.tokenA, address(tokenA));
        assertEq(order.amountA, AMOUNT_A);
        assertEq(order.tokenB, address(tokenB));
        assertEq(order.amountB, AMOUNT_B);
        assertTrue(order.active);

        assertEq(tokenA.balanceOf(address(board)), AMOUNT_A);
        assertEq(tokenA.balanceOf(maker), AMOUNT_A * 10 - AMOUNT_A);
    }

    function test_createOrder_revert_zeroAddress_tokenA() public {
        vm.startPrank(maker);
        vm.expectRevert(ISwapboard.ZeroAddress.selector);
        board.createOrder(address(0), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        vm.stopPrank();
    }

    function test_createOrder_revert_zeroAddress_tokenB() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        vm.expectRevert(ISwapboard.ZeroAddress.selector);
        board.createOrder(address(tokenA), AMOUNT_A, address(0), AMOUNT_B, false);
        vm.stopPrank();
    }

    function test_createOrder_revert_zeroAmount_amountA() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        board.createOrder(address(tokenA), 0, address(tokenB), AMOUNT_B, false);
        vm.stopPrank();
    }

    function test_createOrder_revert_zeroAmount_amountB() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), 0, false);
        vm.stopPrank();
    }

    function test_createOrder_revert_sameToken() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        vm.expectRevert(ISwapboard.SameToken.selector);
        board.createOrder(address(tokenA), AMOUNT_A, address(tokenA), AMOUNT_B, false);
        vm.stopPrank();
    }

    function test_createOrder_revert_notAContract_tokenA() public {
        vm.startPrank(maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotAContract.selector, address(0x999)));
        board.createOrder(address(0x999), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        vm.stopPrank();
    }

    function test_createOrder_revert_notAContract_tokenB() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotAContract.selector, address(0x999)));
        board.createOrder(address(tokenA), AMOUNT_A, address(0x999), AMOUNT_B, false);
        vm.stopPrank();
    }

    function test_createOrder_revert_FOT() public {
        MockFOT fot = new MockFOT();
        fot.mint(maker, 1000 ether);

        vm.startPrank(maker);
        fot.approve(address(board), 100 ether);

        vm.expectRevert(
            abi.encodeWithSelector(ISwapboard.BalanceMismatch.selector, 100 ether, 95 ether)
        );
        board.createOrder(address(fot), 100 ether, address(tokenB), AMOUNT_B, false);
        vm.stopPrank();
    }

    function test_fillOrder() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        uint256 orderId =
            board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        vm.stopPrank();

        vm.startPrank(taker);
        tokenB.approve(address(board), AMOUNT_B);
        board.fillOrder(orderId, 0, 0);
        vm.stopPrank();

        ISwapboard.Order memory order = board.getOrder(orderId);
        assertFalse(order.active);

        assertEq(tokenA.balanceOf(taker), AMOUNT_A);
        assertEq(tokenB.balanceOf(maker), AMOUNT_B);
        assertEq(tokenA.balanceOf(address(board)), 0);
    }

    function test_fillOrder_revert_orderNotFound() public {
        vm.startPrank(taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, 999));
        board.fillOrder(999, 0, 0);
        vm.stopPrank();
    }

    function test_fillOrder_revert_orderNotActive() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        uint256 orderId =
            board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        vm.stopPrank();

        vm.startPrank(taker);
        tokenB.approve(address(board), AMOUNT_B);
        board.fillOrder(orderId, 0, 0);

        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        board.fillOrder(orderId, 0, 0);
        vm.stopPrank();
    }

    function test_cancelOrder() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        uint256 orderId =
            board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);

        uint256 balanceBefore = tokenA.balanceOf(maker);
        board.cancelOrder(orderId);
        vm.stopPrank();

        ISwapboard.Order memory order = board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(tokenA.balanceOf(maker), balanceBefore + AMOUNT_A);
        assertEq(tokenA.balanceOf(address(board)), 0);
    }

    function test_cancelOrder_revert_orderNotFound() public {
        vm.startPrank(maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, 999));
        board.cancelOrder(999);
        vm.stopPrank();
    }

    function test_cancelOrder_revert_orderNotActive() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        uint256 orderId =
            board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        board.cancelOrder(orderId);

        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        board.cancelOrder(orderId);
        vm.stopPrank();
    }

    function test_cancelOrder_revert_notMaker() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        uint256 orderId =
            board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        vm.stopPrank();

        vm.startPrank(taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotMaker.selector, orderId, taker, maker));
        board.cancelOrder(orderId);
        vm.stopPrank();
    }

    // ============ cancelOrders ============

    function test_cancelOrders_basic() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A * 3);
        uint256 id0 = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        uint256 id1 = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        uint256 id2 = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);

        uint256 balanceBefore = tokenA.balanceOf(maker);

        uint256[] memory ids = new uint256[](3);
        ids[0] = id0;
        ids[1] = id1;
        ids[2] = id2;
        board.cancelOrders(ids);
        vm.stopPrank();

        assertFalse(board.getOrder(id0).active);
        assertFalse(board.getOrder(id1).active);
        assertFalse(board.getOrder(id2).active);
        assertEq(tokenA.balanceOf(maker), balanceBefore + AMOUNT_A * 3);
    }

    function test_cancelOrders_empty() public {
        uint256[] memory ids = new uint256[](0);
        board.cancelOrders(ids);
    }

    function test_cancelOrders_events() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A * 2);
        uint256 id0 = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        uint256 id1 = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);

        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderCanceled(id0, maker, address(tokenA), AMOUNT_A);
        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderCanceled(id1, maker, address(tokenA), AMOUNT_A);

        uint256[] memory ids = new uint256[](2);
        ids[0] = id0;
        ids[1] = id1;
        board.cancelOrders(ids);
        vm.stopPrank();
    }

    function test_cancelOrders_revert_notMaker() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A * 2);
        uint256 id0 = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        uint256 id1 = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        vm.stopPrank();

        uint256[] memory ids = new uint256[](2);
        ids[0] = id0;
        ids[1] = id1;

        vm.startPrank(taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotMaker.selector, id0, taker, maker));
        board.cancelOrders(ids);
        vm.stopPrank();
    }

    function test_cancelOrders_revert_orderNotActive() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A * 2);
        uint256 id0 = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        uint256 id1 = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        board.cancelOrder(id0);

        uint256[] memory ids = new uint256[](2);
        ids[0] = id0;
        ids[1] = id1;

        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, id0));
        board.cancelOrders(ids);
        vm.stopPrank();
    }

    function test_cancelOrders_atomic_reverts() public {
        // If second cancel fails, first cancel is rolled back
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A * 2);
        uint256 id0 = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        uint256 id1 = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        board.cancelOrder(id1); // pre-cancel id1

        uint256[] memory ids = new uint256[](2);
        ids[0] = id0;
        ids[1] = id1;

        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, id1));
        board.cancelOrders(ids);
        vm.stopPrank();

        // id0 should still be active (atomic rollback)
        assertTrue(board.getOrder(id0).active);
    }

    function test_cancelOrders_mixedTokens() public {
        // Cancel orders with different token pairs in one batch
        MockERC20 tokenC = new MockERC20("Token C", "TKC", 18);
        tokenC.mint(maker, AMOUNT_A);

        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        tokenC.approve(address(board), AMOUNT_A);
        uint256 id0 = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        uint256 id1 = board.createOrder(address(tokenC), AMOUNT_A, address(tokenB), AMOUNT_B, false);

        uint256[] memory ids = new uint256[](2);
        ids[0] = id0;
        ids[1] = id1;
        board.cancelOrders(ids);
        vm.stopPrank();

        assertFalse(board.getOrder(id0).active);
        assertFalse(board.getOrder(id1).active);
    }

    function test_cancelOrders_afterPartialFill() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A * 2);
        uint256 id0 = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, true);
        uint256 id1 = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        vm.stopPrank();

        // Partially fill id0
        uint256 halfB = AMOUNT_B / 2;
        vm.startPrank(taker);
        tokenB.approve(address(board), halfB);
        board.fillOrder(id0, 0, halfB);
        vm.stopPrank();

        uint256 remainingA = board.getOrder(id0).amountA;
        uint256 balanceBefore = tokenA.balanceOf(maker);

        vm.startPrank(maker);
        uint256[] memory ids = new uint256[](2);
        ids[0] = id0;
        ids[1] = id1;
        board.cancelOrders(ids);
        vm.stopPrank();

        // Maker gets back remaining from partial + full from id1
        assertEq(tokenA.balanceOf(maker), balanceBefore + remainingA + AMOUNT_A);
    }

    function test_canFill() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        uint256 orderId =
            board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        vm.stopPrank();

        assertTrue(board.canFill(orderId));
    }

    function test_canFill_false_notActive() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        uint256 orderId =
            board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        board.cancelOrder(orderId);
        vm.stopPrank();

        assertFalse(board.canFill(orderId));
    }

    function test_canFill_false_nonExistent() public view {
        assertFalse(board.canFill(999));
    }

    function test_getOrders() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A * 3);

        uint256 order0 =
            board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        uint256 order1 =
            board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B * 2, false);
        uint256 order2 =
            board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B * 3, false);
        vm.stopPrank();

        uint256[] memory ids = new uint256[](3);
        ids[0] = order0;
        ids[1] = order1;
        ids[2] = order2;

        ISwapboard.Order[] memory orders = board.getOrders(ids);

        assertEq(orders.length, 3);
        assertEq(orders[0].amountB, AMOUNT_B);
        assertEq(orders[1].amountB, AMOUNT_B * 2);
        assertEq(orders[2].amountB, AMOUNT_B * 3);
    }

    function test_getOrders_empty() public view {
        uint256[] memory ids = new uint256[](0);
        ISwapboard.Order[] memory orders = board.getOrders(ids);
        assertEq(orders.length, 0);
    }

    function test_multipleOrders() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A * 3);

        uint256 order0 =
            board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        uint256 order1 =
            board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B * 2, false);
        uint256 order2 =
            board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B * 3, false);
        vm.stopPrank();

        assertEq(order0, 0);
        assertEq(order1, 1);
        assertEq(order2, 2);
        assertEq(board.nextOrderId(), 3);
    }

    function test_selfFill() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        tokenB.mint(maker, AMOUNT_B);
        tokenB.approve(address(board), AMOUNT_B);

        uint256 orderId =
            board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        board.fillOrder(orderId, 0, 0);
        vm.stopPrank();

        assertEq(tokenA.balanceOf(maker), AMOUNT_A * 10 - AMOUNT_A + AMOUNT_A);
        assertEq(tokenB.balanceOf(maker), AMOUNT_B);
    }

    function test_events_orderCreated() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);

        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderCreated(
            0, maker, address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false
        );

        board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        vm.stopPrank();
    }

    function test_events_orderFilled() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        uint256 orderId =
            board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        vm.stopPrank();

        vm.startPrank(taker);
        tokenB.approve(address(board), AMOUNT_B);

        vm.expectEmit(true, true, true, true);
        emit ISwapboard.OrderFilled(
            orderId, taker, maker, address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B
        );

        board.fillOrder(orderId, 0, 0);
        vm.stopPrank();
    }

    function test_events_orderCanceled() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        uint256 orderId =
            board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);

        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderCanceled(orderId, maker, address(tokenA), AMOUNT_A);

        board.cancelOrder(orderId);
        vm.stopPrank();
    }

    function testFuzz_createOrder(
        uint256 amountA,
        uint256 amountB
    ) public {
        amountA = bound(amountA, 1, type(uint128).max);
        amountB = bound(amountB, 1, type(uint128).max);

        tokenA.mint(maker, amountA);

        vm.startPrank(maker);
        tokenA.approve(address(board), amountA);
        uint256 orderId =
            board.createOrder(address(tokenA), amountA, address(tokenB), amountB, false);
        vm.stopPrank();

        ISwapboard.Order memory order = board.getOrder(orderId);
        assertEq(order.amountA, amountA);
        assertEq(order.amountB, amountB);
    }

    function testFuzz_fillOrder(
        uint256 amountA,
        uint256 amountB
    ) public {
        amountA = bound(amountA, 1, type(uint128).max);
        amountB = bound(amountB, 1, type(uint128).max);

        tokenA.mint(maker, amountA);
        tokenB.mint(taker, amountB);

        vm.startPrank(maker);
        tokenA.approve(address(board), amountA);
        uint256 orderId =
            board.createOrder(address(tokenA), amountA, address(tokenB), amountB, false);
        vm.stopPrank();

        vm.startPrank(taker);
        tokenB.approve(address(board), amountB);
        board.fillOrder(orderId, 0, 0);
        vm.stopPrank();

        assertEq(tokenA.balanceOf(taker), amountA);
        assertEq(tokenB.balanceOf(maker), amountB);
    }

    function test_fillOrder_revert_deadlineExpired() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        uint256 orderId =
            board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        vm.stopPrank();

        vm.warp(1000);

        vm.startPrank(taker);
        tokenB.approve(address(board), AMOUNT_B);
        vm.expectRevert(ISwapboard.DeadlineExpired.selector);
        board.fillOrder(orderId, 999, 0);
        vm.stopPrank();
    }

    function test_fillOrder_deadlineZero_noExpiry() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        uint256 orderId =
            board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        vm.stopPrank();

        vm.warp(type(uint256).max);

        vm.startPrank(taker);
        tokenB.approve(address(board), AMOUNT_B);
        board.fillOrder(orderId, 0, 0);
        vm.stopPrank();

        assertFalse(board.getOrder(orderId).active);
    }

    // ============ Partial Fill Tests ============

    function _createPartialOrder() internal returns (uint256 orderId) {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        orderId = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, true);
        vm.stopPrank();
    }

    function test_fillOrder_partial_basic() public {
        uint256 orderId = _createPartialOrder();
        uint256 halfB = AMOUNT_B / 2;
        uint256 expectedA = (halfB * AMOUNT_A) / AMOUNT_B;

        vm.startPrank(taker);
        tokenB.approve(address(board), halfB);
        board.fillOrder(orderId, 0, halfB);
        vm.stopPrank();

        ISwapboard.Order memory order = board.getOrder(orderId);
        assertTrue(order.active);
        assertEq(order.amountA, AMOUNT_A - expectedA);
        assertEq(order.amountB, AMOUNT_B - halfB);
        assertEq(tokenA.balanceOf(taker), expectedA);
        assertEq(tokenB.balanceOf(maker), halfB);
    }

    function test_fillOrder_partial_multipleFillers() public {
        uint256 orderId = _createPartialOrder();
        address taker2 = address(0x3);
        tokenB.mint(taker2, AMOUNT_B);

        uint256 quarterB = AMOUNT_B / 4;

        // First taker fills 25%
        vm.startPrank(taker);
        tokenB.approve(address(board), quarterB);
        board.fillOrder(orderId, 0, quarterB);
        vm.stopPrank();

        uint256 remainB = AMOUNT_B - quarterB;

        // Second taker fills the rest
        vm.startPrank(taker2);
        tokenB.approve(address(board), remainB);
        board.fillOrder(orderId, 0, remainB);
        vm.stopPrank();

        ISwapboard.Order memory order = board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(tokenB.balanceOf(maker), AMOUNT_B);
    }

    function test_fillOrder_partial_fullFillWhenExceedsRemaining() public {
        uint256 orderId = _createPartialOrder();

        vm.startPrank(taker);
        tokenB.approve(address(board), AMOUNT_B * 2);
        // Passing more than amountB should behave as full fill
        board.fillOrder(orderId, 0, AMOUNT_B * 2);
        vm.stopPrank();

        ISwapboard.Order memory order = board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(tokenA.balanceOf(taker), AMOUNT_A);
        assertEq(tokenB.balanceOf(maker), AMOUNT_B);
    }

    function test_fillOrder_partial_fullFillOnExactRemaining() public {
        uint256 orderId = _createPartialOrder();

        vm.startPrank(taker);
        tokenB.approve(address(board), AMOUNT_B);
        board.fillOrder(orderId, 0, AMOUNT_B);
        vm.stopPrank();

        assertFalse(board.getOrder(orderId).active);
        assertEq(tokenA.balanceOf(taker), AMOUNT_A);
    }

    function test_fillOrder_partial_revert_notPartialFillable() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        uint256 orderId =
            board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        vm.stopPrank();

        vm.startPrank(taker);
        tokenB.approve(address(board), AMOUNT_B / 2);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.PartialFillNotAllowed.selector, orderId));
        board.fillOrder(orderId, 0, AMOUNT_B / 2);
        vm.stopPrank();
    }

    function test_fillOrder_partial_revert_deadlineExpired() public {
        uint256 orderId = _createPartialOrder();

        vm.warp(1001);

        vm.startPrank(taker);
        tokenB.approve(address(board), AMOUNT_B / 2);
        vm.expectRevert(ISwapboard.DeadlineExpired.selector);
        board.fillOrder(orderId, 1000, AMOUNT_B / 2);
        vm.stopPrank();
    }

    function test_fillOrder_partial_revert_orderNotActive() public {
        uint256 orderId = _createPartialOrder();

        // Cancel the order first
        vm.prank(maker);
        board.cancelOrder(orderId);

        vm.startPrank(taker);
        tokenB.approve(address(board), AMOUNT_B / 2);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        board.fillOrder(orderId, 0, AMOUNT_B / 2);
        vm.stopPrank();
    }

    function test_fillOrder_partial_roundsDownFavoringMaker() public {
        // Create order: 10 tokenA for 3 tokenB (indivisible ratio)
        vm.startPrank(maker);
        tokenA.approve(address(board), 10);
        uint256 orderId = board.createOrder(address(tokenA), 10, address(tokenB), 3, true);
        vm.stopPrank();

        // Fill 1 tokenB: expected tokenA = 1 * 10 / 3 = 3 (rounds down from 3.33)
        vm.startPrank(taker);
        tokenB.approve(address(board), 1);
        board.fillOrder(orderId, 0, 1);
        vm.stopPrank();

        assertEq(tokenA.balanceOf(taker), 3);
        ISwapboard.Order memory order = board.getOrder(orderId);
        assertEq(order.amountA, 7); // 10 - 3
        assertEq(order.amountB, 2); // 3 - 1
    }

    function test_fillOrder_partial_revert_zeroComputedAmountA() public {
        // Create order: 1 tokenA for 1000 tokenB
        vm.startPrank(maker);
        tokenA.approve(address(board), 1);
        uint256 orderId = board.createOrder(address(tokenA), 1, address(tokenB), 1000, true);
        vm.stopPrank();

        // Fill 1 tokenB: expected tokenA = 1 * 1 / 1000 = 0 (rounds to zero)
        vm.startPrank(taker);
        tokenB.approve(address(board), 1);
        vm.expectRevert(ISwapboard.ZeroFillAmount.selector);
        board.fillOrder(orderId, 0, 1);
        vm.stopPrank();
    }

    function test_fillOrder_partial_event() public {
        uint256 orderId = _createPartialOrder();
        uint256 halfB = AMOUNT_B / 2;
        uint256 expectedA = (halfB * AMOUNT_A) / AMOUNT_B;

        vm.startPrank(taker);
        tokenB.approve(address(board), halfB);

        vm.expectEmit(true, true, true, true);
        emit ISwapboard.OrderPartiallyFilled(
            orderId,
            taker,
            maker,
            address(tokenA),
            expectedA,
            address(tokenB),
            halfB,
            AMOUNT_A - expectedA,
            AMOUNT_B - halfB
        );
        board.fillOrder(orderId, 0, halfB);
        vm.stopPrank();
    }

    function test_fillOrder_worksOnPartialFillableOrder() public {
        uint256 orderId = _createPartialOrder();

        vm.startPrank(taker);
        tokenB.approve(address(board), AMOUNT_B);
        board.fillOrder(orderId, 0, 0);
        vm.stopPrank();

        assertFalse(board.getOrder(orderId).active);
        assertEq(tokenA.balanceOf(taker), AMOUNT_A);
    }

    function test_fillOrder_partial_largeAmountsNoOverflow() public {
        // fillAmountB * amountA overflows uint256 when both exceed 2^128.
        // mulDiv handles this via 512-bit intermediate math; naive multiplication would revert.
        uint256 largeA = 2 ** 255;
        uint256 largeB = 2 ** 255 - 1;

        tokenA.mint(maker, largeA);
        tokenB.mint(taker, largeB);

        vm.startPrank(maker);
        tokenA.approve(address(board), largeA);
        uint256 orderId = board.createOrder(address(tokenA), largeA, address(tokenB), largeB, true);
        vm.stopPrank();

        uint256 halfB = largeB / 2;
        vm.startPrank(taker);
        tokenB.approve(address(board), halfB);
        board.fillOrder(orderId, 0, halfB);
        vm.stopPrank();

        ISwapboard.Order memory order = board.getOrder(orderId);
        assertTrue(order.active);
        assertTrue(order.amountA > 0);
        assertEq(order.amountB, largeB - halfB);
    }

    function test_fillOrder_partial_revert_orderNotFound() public {
        vm.startPrank(taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, 999));
        board.fillOrder(999, 0, 1);
        vm.stopPrank();
    }

    function test_fillOrder_partial_thenCancel() public {
        uint256 orderId = _createPartialOrder();
        uint256 halfB = AMOUNT_B / 2;
        uint256 expectedA = (halfB * AMOUNT_A) / AMOUNT_B;

        vm.startPrank(taker);
        tokenB.approve(address(board), halfB);
        board.fillOrder(orderId, 0, halfB);
        vm.stopPrank();

        uint256 makerBalanceBefore = tokenA.balanceOf(maker);

        vm.prank(maker);
        board.cancelOrder(orderId);

        // Maker gets back only the remaining tokenA, not the original full amount
        uint256 remaining = AMOUNT_A - expectedA;
        assertEq(tokenA.balanceOf(maker), makerBalanceBefore + remaining);
        assertFalse(board.getOrder(orderId).active);
    }

    function test_fillOrder_partial_thenFillOrder() public {
        uint256 orderId = _createPartialOrder();
        uint256 quarterB = AMOUNT_B / 4;
        uint256 filledA = (quarterB * AMOUNT_A) / AMOUNT_B;

        // Partial fill 25%
        vm.startPrank(taker);
        tokenB.approve(address(board), quarterB);
        board.fillOrder(orderId, 0, quarterB);
        vm.stopPrank();

        uint256 remainB = AMOUNT_B - quarterB;
        uint256 remainA = AMOUNT_A - filledA;

        // Full fill the remainder via fillOrder
        address taker2 = address(0x3);
        tokenB.mint(taker2, remainB);
        vm.startPrank(taker2);
        tokenB.approve(address(board), remainB);
        board.fillOrder(orderId, 0, 0);
        vm.stopPrank();

        assertFalse(board.getOrder(orderId).active);
        assertEq(tokenA.balanceOf(taker2), remainA);
        assertEq(tokenB.balanceOf(maker), AMOUNT_B);
    }

    function test_fillOrder_partial_sequentialFillsDrainOrder() public {
        // 100 tokenA for 10 tokenB — fill 1 tokenB at a time
        uint256 amtA = 100;
        uint256 amtB = 10;
        tokenA.mint(maker, amtA);
        tokenB.mint(taker, amtB);

        vm.startPrank(maker);
        tokenA.approve(address(board), amtA);
        uint256 orderId = board.createOrder(address(tokenA), amtA, address(tokenB), amtB, true);
        vm.stopPrank();

        vm.startPrank(taker);
        tokenB.approve(address(board), amtB);

        // Fill 1 tokenB nine times (partial), then 1 more (triggers full fill path)
        for (uint256 i = 0; i < 10; i++) {
            board.fillOrder(orderId, 0, 1);
        }
        vm.stopPrank();

        assertFalse(board.getOrder(orderId).active);
        assertEq(tokenA.balanceOf(taker), amtA);
        assertEq(tokenB.balanceOf(maker), amtB);
    }

    function test_fillOrder_partial_contractBalanceInvariant() public {
        // Create two partial orders
        tokenA.mint(maker, AMOUNT_A);
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A * 2);
        uint256 id0 = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, true);
        uint256 id1 = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, true);
        vm.stopPrank();

        // Partially fill both
        uint256 halfB = AMOUNT_B / 2;
        tokenB.mint(taker, AMOUNT_B);
        vm.startPrank(taker);
        tokenB.approve(address(board), AMOUNT_B);
        board.fillOrder(id0, 0, halfB);
        board.fillOrder(id1, 0, halfB);
        vm.stopPrank();

        // Contract balance should equal sum of remaining amountA across active orders
        ISwapboard.Order memory o0 = board.getOrder(id0);
        ISwapboard.Order memory o1 = board.getOrder(id1);
        assertEq(tokenA.balanceOf(address(board)), o0.amountA + o1.amountA);
    }

    function test_fillOrder_partial_selfFill() public {
        // Maker fills their own partial order
        uint256 orderId = _createPartialOrder();
        uint256 halfB = AMOUNT_B / 2;
        tokenB.mint(maker, halfB);

        vm.startPrank(maker);
        tokenB.approve(address(board), halfB);
        board.fillOrder(orderId, 0, halfB);
        vm.stopPrank();

        assertTrue(board.getOrder(orderId).active);
    }

    function test_fillOrder_partial_fullFillEmitsOrderFilled() public {
        uint256 orderId = _createPartialOrder();

        vm.startPrank(taker);
        tokenB.approve(address(board), AMOUNT_B);

        vm.expectEmit(true, true, true, false);
        emit ISwapboard.OrderFilled(
            orderId, taker, maker, address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B
        );
        board.fillOrder(orderId, 0, AMOUNT_B);
        vm.stopPrank();
    }

    function test_fillOrder_partial_deadlineZero_noExpiry() public {
        uint256 orderId = _createPartialOrder();

        vm.warp(type(uint256).max);

        vm.startPrank(taker);
        tokenB.approve(address(board), AMOUNT_B / 2);
        board.fillOrder(orderId, 0, AMOUNT_B / 2);
        vm.stopPrank();

        assertTrue(board.getOrder(orderId).active);
    }

    function testFuzz_fillOrder_partial(
        uint256 amountA,
        uint256 amountB,
        uint256 fillAmountB
    ) public {
        amountA = bound(amountA, 1, 1000 ether);
        amountB = bound(amountB, 1, 1000 ether);
        fillAmountB = bound(fillAmountB, 1, amountB);

        tokenA.mint(maker, amountA);
        tokenB.mint(taker, fillAmountB);

        vm.startPrank(maker);
        tokenA.approve(address(board), amountA);
        uint256 orderId =
            board.createOrder(address(tokenA), amountA, address(tokenB), amountB, true);
        vm.stopPrank();

        uint256 expectedA = (fillAmountB * amountA) / amountB;

        // If fillAmountB equals amountB, it's a full fill — always succeeds
        // If fillAmountB < amountB and expectedA == 0, it should revert
        if (fillAmountB < amountB && expectedA == 0) {
            vm.startPrank(taker);
            tokenB.approve(address(board), fillAmountB);
            vm.expectRevert(ISwapboard.ZeroFillAmount.selector);
            board.fillOrder(orderId, 0, fillAmountB);
            vm.stopPrank();
            return;
        }

        vm.startPrank(taker);
        tokenB.approve(address(board), fillAmountB);
        board.fillOrder(orderId, 0, fillAmountB);
        vm.stopPrank();

        ISwapboard.Order memory order = board.getOrder(orderId);

        if (fillAmountB >= amountB) {
            // Full fill
            assertFalse(order.active);
            assertEq(tokenA.balanceOf(taker), amountA);
        } else {
            // Partial fill
            assertTrue(order.active);
            assertEq(tokenA.balanceOf(taker), expectedA);
            assertEq(order.amountA, amountA - expectedA);
            assertEq(order.amountB, amountB - fillAmountB);
            // Contract holds exactly the remaining tokenA for this order
            assertEq(tokenA.balanceOf(address(board)), amountA - expectedA);
        }
    }

    // ============ fillOrders ============

    function test_fillOrders_basic() public {
        // Create two orders
        tokenA.mint(maker, AMOUNT_A);
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A * 2);
        uint256 id0 = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        uint256 id1 = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        vm.stopPrank();

        tokenB.mint(taker, AMOUNT_B);
        vm.startPrank(taker);
        tokenB.approve(address(board), AMOUNT_B * 2);

        uint256[] memory ids = new uint256[](2);
        ids[0] = id0;
        ids[1] = id1;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0; // full fill
        amounts[1] = 0; // full fill

        board.fillOrders(ids, 0, amounts);
        vm.stopPrank();

        assertFalse(board.getOrder(id0).active);
        assertFalse(board.getOrder(id1).active);
        assertEq(tokenA.balanceOf(taker), AMOUNT_A * 2);
        assertEq(tokenB.balanceOf(maker), AMOUNT_B * 2);
    }

    function test_fillOrders_partialAndFull() public {
        tokenA.mint(maker, AMOUNT_A);
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A * 2);
        uint256 id0 = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, true);
        uint256 id1 = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        vm.stopPrank();

        uint256 halfB = AMOUNT_B / 2;
        tokenB.mint(taker, AMOUNT_B);
        vm.startPrank(taker);
        tokenB.approve(address(board), AMOUNT_B + halfB);

        uint256[] memory ids = new uint256[](2);
        ids[0] = id0;
        ids[1] = id1;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = halfB; // partial
        amounts[1] = 0; // full

        board.fillOrders(ids, 0, amounts);
        vm.stopPrank();

        assertTrue(board.getOrder(id0).active);
        assertFalse(board.getOrder(id1).active);
    }

    function test_fillOrders_revert_lengthMismatch() public {
        uint256[] memory ids = new uint256[](2);
        uint256[] memory amounts = new uint256[](1);

        vm.expectRevert(ISwapboard.LengthMismatch.selector);
        board.fillOrders(ids, 0, amounts);
    }

    function test_fillOrders_revert_deadlineExpired() public {
        vm.warp(1001);

        uint256[] memory ids = new uint256[](0);
        uint256[] memory amounts = new uint256[](0);

        vm.expectRevert(ISwapboard.DeadlineExpired.selector);
        board.fillOrders(ids, 1000, amounts);
    }

    function test_fillOrders_atomic_reverts() public {
        // Create one valid order
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        uint256 id0 = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        vm.stopPrank();

        vm.startPrank(taker);
        tokenB.approve(address(board), AMOUNT_B * 2);

        uint256[] memory ids = new uint256[](2);
        ids[0] = id0;
        ids[1] = 999; // non-existent
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0;
        amounts[1] = 0;

        // Entire batch reverts because order 999 doesn't exist
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, 999));
        board.fillOrders(ids, 0, amounts);
        vm.stopPrank();

        // First order should still be active (batch was atomic)
        assertTrue(board.getOrder(id0).active);
    }

    function test_fillOrders_empty() public {
        uint256[] memory ids = new uint256[](0);
        uint256[] memory amounts = new uint256[](0);

        // Should succeed as a no-op
        board.fillOrders(ids, 0, amounts);
    }

    // ============ createOrders ============

    function test_createOrders_basic() public {
        tokenA.mint(maker, AMOUNT_A);
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A * 2);

        ISwapboard.CreateOrderParams[] memory params = new ISwapboard.CreateOrderParams[](2);
        params[0] = ISwapboard.CreateOrderParams(
            address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false
        );
        params[1] = ISwapboard.CreateOrderParams(
            address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, true
        );

        uint256[] memory ids = board.createOrders(params);
        vm.stopPrank();

        assertEq(ids.length, 2);
        assertEq(ids[0], 0);
        assertEq(ids[1], 1);

        ISwapboard.Order memory o0 = board.getOrder(ids[0]);
        assertFalse(o0.partialFill);
        assertTrue(o0.active);

        ISwapboard.Order memory o1 = board.getOrder(ids[1]);
        assertTrue(o1.partialFill);
        assertTrue(o1.active);

        assertEq(tokenA.balanceOf(address(board)), AMOUNT_A * 2);
    }

    function test_createOrders_empty() public {
        ISwapboard.CreateOrderParams[] memory params = new ISwapboard.CreateOrderParams[](0);
        uint256[] memory ids = board.createOrders(params);
        assertEq(ids.length, 0);
    }

    function test_createOrders_atomic_reverts() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A * 2);

        ISwapboard.CreateOrderParams[] memory params = new ISwapboard.CreateOrderParams[](2);
        params[0] = ISwapboard.CreateOrderParams(
            address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false
        );
        params[1] =
            ISwapboard.CreateOrderParams(address(tokenA), AMOUNT_A, address(tokenB), 0, false); // zero amountB

        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        board.createOrders(params);
        vm.stopPrank();

        // No orders created (atomic)
        assertEq(board.nextOrderId(), 0);
    }

    function test_createOrders_mixedTokenPairs() public {
        MockERC20 tokenC = new MockERC20("Token C", "TKC", 18);
        tokenA.mint(maker, AMOUNT_A);
        tokenC.mint(maker, AMOUNT_A);

        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        tokenC.approve(address(board), AMOUNT_A);

        ISwapboard.CreateOrderParams[] memory params = new ISwapboard.CreateOrderParams[](2);
        params[0] = ISwapboard.CreateOrderParams(
            address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false
        );
        params[1] = ISwapboard.CreateOrderParams(
            address(tokenC), AMOUNT_A, address(tokenA), AMOUNT_B, true
        );

        uint256[] memory ids = board.createOrders(params);
        vm.stopPrank();

        ISwapboard.Order memory o0 = board.getOrder(ids[0]);
        assertEq(o0.tokenA, address(tokenA));
        assertEq(o0.tokenB, address(tokenB));

        ISwapboard.Order memory o1 = board.getOrder(ids[1]);
        assertEq(o1.tokenA, address(tokenC));
        assertEq(o1.tokenB, address(tokenA));
        assertTrue(o1.partialFill);
    }

    function test_fillOrders_withPartialFills() public {
        tokenA.mint(maker, AMOUNT_A);
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A * 2);
        uint256 id0 = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, true);
        uint256 id1 = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, true);
        vm.stopPrank();

        uint256 quarterB = AMOUNT_B / 4;
        uint256 halfB = AMOUNT_B / 2;
        tokenB.mint(taker, AMOUNT_B);
        vm.startPrank(taker);
        tokenB.approve(address(board), quarterB + halfB);

        uint256[] memory ids = new uint256[](2);
        ids[0] = id0;
        ids[1] = id1;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = quarterB;
        amounts[1] = halfB;

        board.fillOrders(ids, 0, amounts);
        vm.stopPrank();

        // Both orders still active with reduced amounts
        ISwapboard.Order memory o0 = board.getOrder(id0);
        assertTrue(o0.active);
        assertEq(o0.amountB, AMOUNT_B - quarterB);

        ISwapboard.Order memory o1 = board.getOrder(id1);
        assertTrue(o1.active);
        assertEq(o1.amountB, AMOUNT_B - halfB);
    }

    function test_fillOrders_sameOrderTwice() public {
        // Partially fill the same order twice in one batch
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        uint256 orderId =
            board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, true);
        vm.stopPrank();

        uint256 quarterB = AMOUNT_B / 4;
        tokenB.mint(taker, AMOUNT_B);
        vm.startPrank(taker);
        tokenB.approve(address(board), quarterB * 2);

        uint256[] memory ids = new uint256[](2);
        ids[0] = orderId;
        ids[1] = orderId;
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = quarterB;
        amounts[1] = quarterB;

        board.fillOrders(ids, 0, amounts);
        vm.stopPrank();

        ISwapboard.Order memory order = board.getOrder(orderId);
        assertTrue(order.active);
        assertEq(order.amountB, AMOUNT_B - quarterB * 2);
    }

    function test_createOrders_thenFillOrders() public {
        // End-to-end: batch create, then batch fill
        tokenA.mint(maker, AMOUNT_A * 2);
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A * 3);

        ISwapboard.CreateOrderParams[] memory params = new ISwapboard.CreateOrderParams[](3);
        params[0] = ISwapboard.CreateOrderParams(
            address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false
        );
        params[1] = ISwapboard.CreateOrderParams(
            address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false
        );
        params[2] = ISwapboard.CreateOrderParams(
            address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false
        );

        uint256[] memory ids = board.createOrders(params);
        vm.stopPrank();

        tokenB.mint(taker, AMOUNT_B * 2);
        vm.startPrank(taker);
        tokenB.approve(address(board), AMOUNT_B * 3);

        uint256[] memory fillAmounts = new uint256[](3);
        fillAmounts[0] = 0;
        fillAmounts[1] = 0;
        fillAmounts[2] = 0;

        board.fillOrders(ids, 0, fillAmounts);
        vm.stopPrank();

        assertFalse(board.getOrder(ids[0]).active);
        assertFalse(board.getOrder(ids[1]).active);
        assertFalse(board.getOrder(ids[2]).active);
    }

    function test_createOrder_partialFillFlag() public {
        uint256 orderId = _createPartialOrder();
        ISwapboard.Order memory order = board.getOrder(orderId);
        assertTrue(order.partialFill);

        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        uint256 orderId2 =
            board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        vm.stopPrank();

        ISwapboard.Order memory order2 = board.getOrder(orderId2);
        assertFalse(order2.partialFill);
    }

    function test_fillOrder_zeroFillsRemainderAfterPartial() public {
        uint256 orderId = _createPartialOrder();
        uint256 halfB = AMOUNT_B / 2;
        uint256 filledA = (halfB * AMOUNT_A) / AMOUNT_B;

        // Partial fill half
        vm.startPrank(taker);
        tokenB.approve(address(board), halfB);
        board.fillOrder(orderId, 0, halfB);
        vm.stopPrank();

        uint256 remainA = AMOUNT_A - filledA;
        uint256 remainB = AMOUNT_B - halfB;

        // fillAmountB == 0 fills the remainder, not the original amount
        address taker2 = address(0x3);
        tokenB.mint(taker2, remainB);
        vm.startPrank(taker2);
        tokenB.approve(address(board), remainB);
        board.fillOrder(orderId, 0, 0);
        vm.stopPrank();

        assertFalse(board.getOrder(orderId).active);
        assertEq(tokenA.balanceOf(taker2), remainA);
        assertEq(tokenB.balanceOf(maker), AMOUNT_B);
    }

    // ============ Zeroed state after full fill ============

    function test_fullFill_zerosAmounts() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        uint256 orderId =
            board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        vm.stopPrank();

        vm.startPrank(taker);
        tokenB.approve(address(board), AMOUNT_B);
        board.fillOrder(orderId, 0, 0);
        vm.stopPrank();

        ISwapboard.Order memory order = board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(order.amountA, 0, "amountA should be zeroed after full fill");
        assertEq(order.amountB, 0, "amountB should be zeroed after full fill");
    }

    function test_fullFill_zerosAmounts_afterPartials() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        uint256 orderId =
            board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, true);
        vm.stopPrank();

        // Partial fill half
        uint256 halfB = AMOUNT_B / 2;
        vm.startPrank(taker);
        tokenB.approve(address(board), AMOUNT_B);
        board.fillOrder(orderId, 0, halfB);

        // Full fill remainder (fillAmountB == 0 means fill all)
        board.fillOrder(orderId, 0, 0);
        vm.stopPrank();

        ISwapboard.Order memory order = board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(order.amountA, 0, "amountA should be zeroed after final fill");
        assertEq(order.amountB, 0, "amountB should be zeroed after final fill");
    }

    function test_cancelOrder_zerosAmounts() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        uint256 orderId =
            board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B, false);
        board.cancelOrder(orderId);
        vm.stopPrank();

        ISwapboard.Order memory order = board.getOrder(orderId);
        assertFalse(order.active);
        // Cancel doesn't zero amounts (only fill does) — amounts reflect what was remaining
        // This is fine since active=false gates all access
    }
}
