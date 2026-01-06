// SPDX-License-Identifier: MIT
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

/// @notice Unit tests for Swapboard contract
/// @dev Uses Foundry's Test framework with MockERC20 tokens
contract SwapboardTest is Test {
    Swapboard public board;
    MockERC20 public tokenA;
    MockERC20 public tokenB;

    address public maker = address(0x1);
    address public taker = address(0x2);

    /// @dev 100 tokens with 18 decimals
    uint256 constant AMOUNT_A = 100 ether;
    /// @dev 250,000 tokens with 6 decimals (USDC-style)
    uint256 constant AMOUNT_B = 250_000e6;

    function setUp() public {
        board = new Swapboard();

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

        uint256 orderId = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B);
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
        board.createOrder(address(0), AMOUNT_A, address(tokenB), AMOUNT_B);
        vm.stopPrank();
    }

    function test_createOrder_revert_zeroAddress_tokenB() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        vm.expectRevert(ISwapboard.ZeroAddress.selector);
        board.createOrder(address(tokenA), AMOUNT_A, address(0), AMOUNT_B);
        vm.stopPrank();
    }

    function test_createOrder_revert_zeroAmount_amountA() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        board.createOrder(address(tokenA), 0, address(tokenB), AMOUNT_B);
        vm.stopPrank();
    }

    function test_createOrder_revert_zeroAmount_amountB() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), 0);
        vm.stopPrank();
    }

    function test_createOrder_revert_sameToken() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        vm.expectRevert(ISwapboard.SameToken.selector);
        board.createOrder(address(tokenA), AMOUNT_A, address(tokenA), AMOUNT_B);
        vm.stopPrank();
    }

    function test_createOrder_revert_notAContract_tokenA() public {
        vm.startPrank(maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotAContract.selector, address(0x999)));
        board.createOrder(address(0x999), AMOUNT_A, address(tokenB), AMOUNT_B);
        vm.stopPrank();
    }

    function test_createOrder_revert_notAContract_tokenB() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotAContract.selector, address(0x999)));
        board.createOrder(address(tokenA), AMOUNT_A, address(0x999), AMOUNT_B);
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
        board.createOrder(address(fot), 100 ether, address(tokenB), AMOUNT_B);
        vm.stopPrank();
    }

    function test_fillOrder() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        uint256 orderId = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B);
        vm.stopPrank();

        vm.startPrank(taker);
        tokenB.approve(address(board), AMOUNT_B);
        board.fillOrder(orderId);
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
        board.fillOrder(999);
        vm.stopPrank();
    }

    function test_fillOrder_revert_orderNotActive() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        uint256 orderId = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B);
        vm.stopPrank();

        vm.startPrank(taker);
        tokenB.approve(address(board), AMOUNT_B);
        board.fillOrder(orderId);

        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        board.fillOrder(orderId);
        vm.stopPrank();
    }

    function test_cancelOrder() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        uint256 orderId = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B);

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
        uint256 orderId = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B);
        board.cancelOrder(orderId);

        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        board.cancelOrder(orderId);
        vm.stopPrank();
    }

    function test_cancelOrder_revert_notMaker() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        uint256 orderId = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B);
        vm.stopPrank();

        vm.startPrank(taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotMaker.selector, orderId, taker, maker));
        board.cancelOrder(orderId);
        vm.stopPrank();
    }

    function test_canFill() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        uint256 orderId = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B);
        vm.stopPrank();

        assertTrue(board.canFill(orderId));
    }

    function test_canFill_false_notActive() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        uint256 orderId = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B);
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

        uint256 order0 = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B);
        uint256 order1 = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B * 2);
        uint256 order2 = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B * 3);
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

        uint256 order0 = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B);
        uint256 order1 = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B * 2);
        uint256 order2 = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B * 3);
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

        uint256 orderId = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B);
        board.fillOrder(orderId);
        vm.stopPrank();

        assertEq(tokenA.balanceOf(maker), AMOUNT_A * 10 - AMOUNT_A + AMOUNT_A);
        assertEq(tokenB.balanceOf(maker), AMOUNT_B);
    }

    function test_events_orderCreated() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);

        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderCreated(0, maker, address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B);

        board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B);
        vm.stopPrank();
    }

    function test_events_orderFilled() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        uint256 orderId = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B);
        vm.stopPrank();

        vm.startPrank(taker);
        tokenB.approve(address(board), AMOUNT_B);

        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderFilled(orderId, taker);

        board.fillOrder(orderId);
        vm.stopPrank();
    }

    function test_events_orderCanceled() public {
        vm.startPrank(maker);
        tokenA.approve(address(board), AMOUNT_A);
        uint256 orderId = board.createOrder(address(tokenA), AMOUNT_A, address(tokenB), AMOUNT_B);

        vm.expectEmit(true, false, false, true);
        emit ISwapboard.OrderCanceled(orderId);

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
        uint256 orderId = board.createOrder(address(tokenA), amountA, address(tokenB), amountB);
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
        uint256 orderId = board.createOrder(address(tokenA), amountA, address(tokenB), amountB);
        vm.stopPrank();

        vm.startPrank(taker);
        tokenB.approve(address(board), amountB);
        board.fillOrder(orderId);
        vm.stopPrank();

        assertEq(tokenA.balanceOf(taker), amountA);
        assertEq(tokenB.balanceOf(maker), amountB);
    }
}
