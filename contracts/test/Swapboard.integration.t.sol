// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {Swapboard} from "../src/Swapboard.sol";
import {ISwapboard} from "../src/interfaces/ISwapboard.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockWETH} from "./mocks/MockWETH.sol";

contract SwapboardIntegrationTest is Test {
    Swapboard public board;
    MockWETH public mockWeth;
    MockERC20 public weth;
    MockERC20 public usdc;
    MockERC20 public dai;
    MockERC20 public wbtc;

    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public charlie = address(0xC4A7);
    address public dave = address(0xDA7E);

    function setUp() public {
        mockWeth = new MockWETH();
        board = new Swapboard(address(mockWeth));

        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        dai = new MockERC20("Dai Stablecoin", "DAI", 18);
        wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);

        weth.mint(alice, 1000 ether);
        weth.mint(bob, 1000 ether);
        usdc.mint(alice, 10_000_000e6);
        usdc.mint(bob, 10_000_000e6);
        usdc.mint(charlie, 10_000_000e6);
        dai.mint(alice, 10_000_000 ether);
        dai.mint(bob, 10_000_000 ether);
        wbtc.mint(dave, 100e8);
    }

    function test_multipleUsersMultipleOrders() public {
        vm.startPrank(alice);
        weth.approve(address(board), 100 ether);
        uint256 order0 = board.createOrder(address(weth), 10 ether, address(usdc), 30_000e6);
        uint256 order1 = board.createOrder(address(weth), 20 ether, address(usdc), 58_000e6);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(board), 1_000_000e6);
        uint256 order2 = board.createOrder(address(usdc), 100_000e6, address(weth), 35 ether);
        vm.stopPrank();

        vm.startPrank(dave);
        wbtc.approve(address(board), 10e8);
        uint256 order3 = board.createOrder(address(wbtc), 1e8, address(usdc), 95_000e6);
        vm.stopPrank();

        assertEq(board.nextOrderId(), 4);
        assertTrue(board.canFill(order0));
        assertTrue(board.canFill(order1));
        assertTrue(board.canFill(order2));
        assertTrue(board.canFill(order3));

        vm.startPrank(charlie);
        usdc.approve(address(board), 200_000e6);
        board.fillOrder(order0);
        board.fillOrder(order3);
        vm.stopPrank();

        assertFalse(board.canFill(order0));
        assertTrue(board.canFill(order1));
        assertTrue(board.canFill(order2));
        assertFalse(board.canFill(order3));

        assertEq(weth.balanceOf(charlie), 10 ether);
        assertEq(wbtc.balanceOf(charlie), 1e8);
        assertEq(usdc.balanceOf(alice), 10_000_000e6 + 30_000e6);
        assertEq(usdc.balanceOf(dave), 95_000e6);
    }

    function test_orderLifecycle_createFill() public {
        vm.startPrank(alice);
        weth.approve(address(board), 50 ether);
        uint256 orderId = board.createOrder(address(weth), 50 ether, address(usdc), 150_000e6);
        vm.stopPrank();

        uint256 bobWethBefore = weth.balanceOf(bob);
        uint256 aliceUsdcBefore = usdc.balanceOf(alice);

        vm.startPrank(bob);
        usdc.approve(address(board), 150_000e6);
        board.fillOrder(orderId);
        vm.stopPrank();

        assertEq(weth.balanceOf(bob), bobWethBefore + 50 ether);
        assertEq(usdc.balanceOf(alice), aliceUsdcBefore + 150_000e6);
        assertEq(weth.balanceOf(address(board)), 0);

        ISwapboard.Order memory order = board.getOrder(orderId);
        assertFalse(order.active);
    }

    function test_orderLifecycle_createCancel() public {
        uint256 aliceWethBefore = weth.balanceOf(alice);

        vm.startPrank(alice);
        weth.approve(address(board), 50 ether);
        uint256 orderId = board.createOrder(address(weth), 50 ether, address(usdc), 150_000e6);

        assertEq(weth.balanceOf(alice), aliceWethBefore - 50 ether);
        assertEq(weth.balanceOf(address(board)), 50 ether);

        board.cancelOrder(orderId);
        vm.stopPrank();

        assertEq(weth.balanceOf(alice), aliceWethBefore);
        assertEq(weth.balanceOf(address(board)), 0);

        ISwapboard.Order memory order = board.getOrder(orderId);
        assertFalse(order.active);
    }

    function test_raceCondition_twoFillersOneOrder() public {
        vm.startPrank(alice);
        weth.approve(address(board), 10 ether);
        uint256 orderId = board.createOrder(address(weth), 10 ether, address(usdc), 30_000e6);
        vm.stopPrank();

        vm.prank(bob);
        usdc.approve(address(board), 30_000e6);

        vm.prank(charlie);
        usdc.approve(address(board), 30_000e6);

        vm.prank(bob);
        board.fillOrder(orderId);

        vm.prank(charlie);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        board.fillOrder(orderId);

        assertEq(weth.balanceOf(bob), 1000 ether + 10 ether);
        assertEq(weth.balanceOf(charlie), 0);
    }

    function test_raceCondition_fillAndCancel() public {
        vm.startPrank(alice);
        weth.approve(address(board), 10 ether);
        uint256 orderId = board.createOrder(address(weth), 10 ether, address(usdc), 30_000e6);
        vm.stopPrank();

        vm.prank(bob);
        usdc.approve(address(board), 30_000e6);

        vm.prank(bob);
        board.fillOrder(orderId);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        board.cancelOrder(orderId);
    }

    function test_batchOperations() public {
        vm.startPrank(alice);
        weth.approve(address(board), 100 ether);

        uint256[] memory orderIds = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            orderIds[i] = board.createOrder(address(weth), 10 ether, address(usdc), 30_000e6);
        }
        vm.stopPrank();

        assertEq(board.nextOrderId(), 10);
        assertEq(weth.balanceOf(address(board)), 100 ether);

        ISwapboard.Order[] memory orders = board.getOrders(orderIds);
        assertEq(orders.length, 10);
        for (uint256 i = 0; i < 10; i++) {
            assertEq(orders[i].maker, alice);
            assertEq(orders[i].amountA, 10 ether);
            assertTrue(orders[i].active);
        }

        vm.startPrank(bob);
        usdc.approve(address(board), 150_000e6);
        board.fillOrder(orderIds[0]);
        board.fillOrder(orderIds[2]);
        board.fillOrder(orderIds[4]);
        board.fillOrder(orderIds[6]);
        board.fillOrder(orderIds[8]);
        vm.stopPrank();

        vm.startPrank(alice);
        board.cancelOrder(orderIds[1]);
        board.cancelOrder(orderIds[3]);
        board.cancelOrder(orderIds[5]);
        board.cancelOrder(orderIds[7]);
        board.cancelOrder(orderIds[9]);
        vm.stopPrank();

        assertEq(weth.balanceOf(address(board)), 0);
        assertEq(weth.balanceOf(bob), 1000 ether + 50 ether);
        assertEq(weth.balanceOf(alice), 1000 ether - 100 ether + 50 ether);
        assertEq(usdc.balanceOf(alice), 10_000_000e6 + 150_000e6);
    }

    function test_differentDecimalTokens() public {
        vm.startPrank(dave);
        wbtc.approve(address(board), 1e8);
        uint256 orderId = board.createOrder(address(wbtc), 1e8, address(dai), 95_000 ether);
        vm.stopPrank();

        vm.startPrank(bob);
        dai.approve(address(board), 95_000 ether);
        board.fillOrder(orderId);
        vm.stopPrank();

        assertEq(wbtc.balanceOf(bob), 1e8);
        assertEq(dai.balanceOf(dave), 95_000 ether);
    }

    function test_largeAmounts() public {
        uint256 largeAmount = type(uint128).max;
        weth.mint(alice, largeAmount);

        vm.startPrank(alice);
        weth.approve(address(board), largeAmount);
        uint256 orderId = board.createOrder(address(weth), largeAmount, address(usdc), 1e6);
        vm.stopPrank();

        ISwapboard.Order memory order = board.getOrder(orderId);
        assertEq(order.amountA, largeAmount);

        vm.startPrank(bob);
        usdc.approve(address(board), 1e6);
        board.fillOrder(orderId);
        vm.stopPrank();

        assertEq(weth.balanceOf(bob), 1000 ether + largeAmount);
    }

    function test_dustAmounts() public {
        vm.startPrank(alice);
        weth.approve(address(board), 1);
        uint256 orderId = board.createOrder(address(weth), 1, address(usdc), 1);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(board), 1);
        board.fillOrder(orderId);
        vm.stopPrank();

        assertEq(weth.balanceOf(bob), 1000 ether + 1);
        assertEq(usdc.balanceOf(alice), 10_000_000e6 + 1);
    }

    function test_eventSequence() public {
        vm.startPrank(alice);
        weth.approve(address(board), 10 ether);

        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderCreated(0, alice, address(weth), 10 ether, address(usdc), 30_000e6);
        uint256 orderId = board.createOrder(address(weth), 10 ether, address(usdc), 30_000e6);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(board), 30_000e6);

        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderFilled(orderId, bob);
        board.fillOrder(orderId);
        vm.stopPrank();
    }

    function test_getOrdersWithNonExistent() public {
        vm.startPrank(alice);
        weth.approve(address(board), 20 ether);
        board.createOrder(address(weth), 10 ether, address(usdc), 30_000e6);
        board.createOrder(address(weth), 10 ether, address(usdc), 30_000e6);
        vm.stopPrank();

        uint256[] memory ids = new uint256[](4);
        ids[0] = 0;
        ids[1] = 999;
        ids[2] = 1;
        ids[3] = 1000;

        ISwapboard.Order[] memory orders = board.getOrders(ids);
        assertEq(orders.length, 4);
        assertEq(orders[0].maker, alice);
        assertEq(orders[1].maker, address(0));
        assertEq(orders[2].maker, alice);
        assertEq(orders[3].maker, address(0));
    }

    function test_stressTest_manyOrders() public {
        uint256 numOrders = 100;

        vm.startPrank(alice);
        weth.mint(alice, numOrders * 1 ether);
        weth.approve(address(board), numOrders * 1 ether);

        for (uint256 i = 0; i < numOrders; i++) {
            board.createOrder(address(weth), 1 ether, address(usdc), 3000e6);
        }
        vm.stopPrank();

        assertEq(board.nextOrderId(), numOrders);
        assertEq(weth.balanceOf(address(board)), numOrders * 1 ether);

        vm.startPrank(bob);
        usdc.approve(address(board), numOrders * 3000e6);
        for (uint256 i = 0; i < numOrders; i++) {
            board.fillOrder(i);
        }
        vm.stopPrank();

        assertEq(weth.balanceOf(address(board)), 0);
        assertEq(weth.balanceOf(bob), 1000 ether + numOrders * 1 ether);
    }
}
