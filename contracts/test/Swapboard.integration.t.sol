// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec

import {Test} from "forge-std/Test.sol";
import {Swapboard} from "../src/Swapboard.sol";
import {ISwapboard} from "../src/interfaces/ISwapboard.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract SwapboardIntegrationTest is Test {
    Swapboard internal _board;
    MockERC20 internal _weth;
    MockERC20 internal _usdc;
    MockERC20 internal _dai;
    MockERC20 internal _wbtc;

    address internal _alice = address(0xA11CE);
    address internal _bob = address(0xB0B);
    address internal _charlie = address(0xC4A7);
    address internal _dave = address(0xDA7E);

    /// @notice Deploys fixtures for each test
    function setUp() public {
        _board = new Swapboard();

        _weth = new MockERC20("Wrapped Ether", "WETH", 18);
        _usdc = new MockERC20("USD Coin", "USDC", 6);
        _dai = new MockERC20("Dai Stablecoin", "DAI", 18);
        _wbtc = new MockERC20("Wrapped Bitcoin", "WBTC", 8);

        _weth.mint(_alice, 1000 ether);
        _weth.mint(_bob, 1000 ether);
        _usdc.mint(_alice, 10_000_000e6);
        _usdc.mint(_bob, 10_000_000e6);
        _usdc.mint(_charlie, 10_000_000e6);
        _dai.mint(_alice, 10_000_000 ether);
        _dai.mint(_bob, 10_000_000 ether);
        _wbtc.mint(_dave, 100e8);
    }

    /// @notice Tests multiple users creating and filling orders
    function test_multipleUsersMultipleOrders() public {
        vm.startPrank(_alice);
        _weth.approve(address(_board), 100 ether);
        uint256 order0 = _board.createOrder(address(_weth), 10 ether, address(_usdc), 30_000e6, false);
        uint256 order1 = _board.createOrder(address(_weth), 20 ether, address(_usdc), 58_000e6, false);
        vm.stopPrank();

        vm.startPrank(_bob);
        _usdc.approve(address(_board), 1_000_000e6);
        uint256 order2 = _board.createOrder(address(_usdc), 100_000e6, address(_weth), 35 ether, false);
        vm.stopPrank();

        vm.startPrank(_dave);
        _wbtc.approve(address(_board), 10e8);
        uint256 order3 = _board.createOrder(address(_wbtc), 1e8, address(_usdc), 95_000e6, false);
        vm.stopPrank();

        assertEq(_board.getNextOrderId(), 4);
        assertTrue(_board.canFill(order0));
        assertTrue(_board.canFill(order1));
        assertTrue(_board.canFill(order2));
        assertTrue(_board.canFill(order3));

        vm.startPrank(_charlie);
        _usdc.approve(address(_board), 200_000e6);
        _board.fillOrder(order0, 10 ether, 0);
        _board.fillOrder(order3, 1e8, 0);
        vm.stopPrank();

        assertFalse(_board.canFill(order0));
        assertTrue(_board.canFill(order1));
        assertTrue(_board.canFill(order2));
        assertFalse(_board.canFill(order3));

        assertEq(_weth.balanceOf(_charlie), 10 ether);
        assertEq(_wbtc.balanceOf(_charlie), 1e8);
        assertEq(_usdc.balanceOf(_alice), 10_000_000e6 + 30_000e6);
        assertEq(_usdc.balanceOf(_dave), 95_000e6);
    }

    /// @notice Tests full create-then-fill order lifecycle
    function test_orderLifecycle_createFill() public {
        vm.startPrank(_alice);
        _weth.approve(address(_board), 50 ether);
        uint256 orderId = _board.createOrder(address(_weth), 50 ether, address(_usdc), 150_000e6, false);
        vm.stopPrank();

        uint256 bobWethBefore = _weth.balanceOf(_bob);
        uint256 aliceUsdcBefore = _usdc.balanceOf(_alice);

        vm.startPrank(_bob);
        _usdc.approve(address(_board), 150_000e6);
        _board.fillOrder(orderId, _board.getOrder(orderId).amountA, 0);
        vm.stopPrank();

        assertEq(_weth.balanceOf(_bob), bobWethBefore + 50 ether);
        assertEq(_usdc.balanceOf(_alice), aliceUsdcBefore + 150_000e6);
        assertEq(_weth.balanceOf(address(_board)), 0);

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active);
    }

    /// @notice Tests full create-then-cancel order lifecycle
    function test_orderLifecycle_createCancel() public {
        uint256 aliceWethBefore = _weth.balanceOf(_alice);

        vm.startPrank(_alice);
        _weth.approve(address(_board), 50 ether);
        uint256 orderId = _board.createOrder(address(_weth), 50 ether, address(_usdc), 150_000e6, false);

        assertEq(_weth.balanceOf(_alice), aliceWethBefore - 50 ether);
        assertEq(_weth.balanceOf(address(_board)), 50 ether);

        _board.cancelOrder(orderId);
        vm.stopPrank();

        assertEq(_weth.balanceOf(_alice), aliceWethBefore);
        assertEq(_weth.balanceOf(address(_board)), 0);

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active);
    }

    /// @notice Tests only one of two competing fillers succeeds
    function test_raceCondition_twoFillersOneOrder() public {
        vm.startPrank(_alice);
        _weth.approve(address(_board), 10 ether);
        uint256 orderId = _board.createOrder(address(_weth), 10 ether, address(_usdc), 30_000e6, false);
        vm.stopPrank();

        vm.prank(_bob);
        _usdc.approve(address(_board), 30_000e6);

        vm.prank(_charlie);
        _usdc.approve(address(_board), 30_000e6);

        vm.prank(_bob);
        _board.fillOrder(orderId, 10 ether, 0);

        vm.prank(_charlie);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        _board.fillOrder(orderId, 10 ether, 0);

        assertEq(_weth.balanceOf(_bob), 1000 ether + 10 ether);
        assertEq(_weth.balanceOf(_charlie), 0);
    }

    /// @notice Tests fill wins over concurrent cancel attempt
    function test_raceCondition_fillAndCancel() public {
        vm.startPrank(_alice);
        _weth.approve(address(_board), 10 ether);
        uint256 orderId = _board.createOrder(address(_weth), 10 ether, address(_usdc), 30_000e6, false);
        vm.stopPrank();

        vm.prank(_bob);
        _usdc.approve(address(_board), 30_000e6);

        vm.prank(_bob);
        _board.fillOrder(orderId, 10 ether, 0);

        vm.prank(_alice);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        _board.cancelOrder(orderId);
    }

    /// @notice Tests creating and filling a batch of orders
    function test_batchOperations() public {
        vm.startPrank(_alice);
        _weth.approve(address(_board), 100 ether);

        uint256[] memory orderIds = new uint256[](10);
        for (uint256 i = 0; i < 10; ++i) {
            orderIds[i] = _board.createOrder(address(_weth), 10 ether, address(_usdc), 30_000e6, false);
        }
        vm.stopPrank();

        assertEq(_board.getNextOrderId(), 10);
        assertEq(_weth.balanceOf(address(_board)), 100 ether);

        ISwapboard.Order[] memory orders = _board.getOrders(orderIds);
        assertEq(orders.length, 10);
        for (uint256 i = 0; i < 10; ++i) {
            assertEq(orders[i].maker, _alice);
            assertEq(orders[i].amountA, 10 ether);
            assertTrue(orders[i].active);
        }

        vm.startPrank(_bob);
        _usdc.approve(address(_board), 150_000e6);
        _board.fillOrder(orderIds[0], 10 ether, 0);
        _board.fillOrder(orderIds[2], 10 ether, 0);
        _board.fillOrder(orderIds[4], 10 ether, 0);
        _board.fillOrder(orderIds[6], 10 ether, 0);
        _board.fillOrder(orderIds[8], 10 ether, 0);
        vm.stopPrank();

        vm.startPrank(_alice);
        _board.cancelOrder(orderIds[1]);
        _board.cancelOrder(orderIds[3]);
        _board.cancelOrder(orderIds[5]);
        _board.cancelOrder(orderIds[7]);
        _board.cancelOrder(orderIds[9]);
        vm.stopPrank();

        assertEq(_weth.balanceOf(address(_board)), 0);
        assertEq(_weth.balanceOf(_bob), 1000 ether + 50 ether);
        assertEq(_weth.balanceOf(_alice), 1000 ether - 100 ether + 50 ether);
        assertEq(_usdc.balanceOf(_alice), 10_000_000e6 + 150_000e6);
    }

    /// @notice Tests orders between tokens with different decimals
    function test_differentDecimalTokens() public {
        vm.startPrank(_dave);
        _wbtc.approve(address(_board), 1e8);
        uint256 orderId = _board.createOrder(address(_wbtc), 1e8, address(_dai), 95_000 ether, false);
        vm.stopPrank();

        vm.startPrank(_bob);
        _dai.approve(address(_board), 95_000 ether);
        _board.fillOrder(orderId, _board.getOrder(orderId).amountA, 0);
        vm.stopPrank();

        assertEq(_wbtc.balanceOf(_bob), 1e8);
        assertEq(_dai.balanceOf(_dave), 95_000 ether);
    }

    /// @notice Tests creating and filling large amount orders
    function test_largeAmounts() public {
        uint128 largeAmount = type(uint128).max;
        _weth.mint(_alice, largeAmount);

        vm.startPrank(_alice);
        _weth.approve(address(_board), largeAmount);
        uint256 orderId = _board.createOrder(address(_weth), largeAmount, address(_usdc), 1e6, false);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertEq(order.amountA, largeAmount);

        vm.startPrank(_bob);
        _usdc.approve(address(_board), 1e6);
        _board.fillOrder(orderId, _board.getOrder(orderId).amountA, 0);
        vm.stopPrank();

        assertEq(_weth.balanceOf(_bob), uint256(1000 ether) + uint256(largeAmount));
    }

    /// @notice Tests creating and filling dust-sized orders
    function test_dustAmounts() public {
        vm.startPrank(_alice);
        _weth.approve(address(_board), 1);
        uint256 orderId = _board.createOrder(address(_weth), 1, address(_usdc), 1, false);
        vm.stopPrank();

        vm.startPrank(_bob);
        _usdc.approve(address(_board), 1);
        _board.fillOrder(orderId, _board.getOrder(orderId).amountA, 0);
        vm.stopPrank();

        assertEq(_weth.balanceOf(_bob), 1000 ether + 1);
        assertEq(_usdc.balanceOf(_alice), 10_000_000e6 + 1);
    }

    /// @notice Tests OrderCreated then OrderFilled event sequence
    function test_eventSequence() public {
        vm.startPrank(_alice);
        _weth.approve(address(_board), 10 ether);

        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderCreated({
            orderId: 0,
            maker: _alice,
            tokenA: address(_weth),
            amountA: 10 ether,
            tokenB: address(_usdc),
            amountB: 30_000e6,
            partialFillAllowed: false
        });
        uint256 orderId = _board.createOrder(address(_weth), 10 ether, address(_usdc), 30_000e6, false);
        vm.stopPrank();

        vm.startPrank(_bob);
        _usdc.approve(address(_board), 30_000e6);

        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderFilled({orderId: orderId, taker: _bob, amountA: 10 ether, amountB: 30_000e6});
        _board.fillOrder(orderId, _board.getOrder(orderId).amountA, 0);
        vm.stopPrank();
    }

    /// @notice Tests getOrders returns empty structs for missing IDs
    function test_getOrdersWithNonExistent() public {
        vm.startPrank(_alice);
        _weth.approve(address(_board), 20 ether);
        _board.createOrder(address(_weth), 10 ether, address(_usdc), 30_000e6, false);
        _board.createOrder(address(_weth), 10 ether, address(_usdc), 30_000e6, false);
        vm.stopPrank();

        uint256[] memory ids = new uint256[](4);
        ids[0] = 0;
        ids[1] = 999;
        ids[2] = 1;
        ids[3] = 1000;

        ISwapboard.Order[] memory orders = _board.getOrders(ids);
        assertEq(orders.length, 4);
        assertEq(orders[0].maker, _alice);
        assertEq(orders[1].maker, address(0));
        assertEq(orders[2].maker, _alice);
        assertEq(orders[3].maker, address(0));
    }

    /// @notice Stress tests creating and filling many orders
    function test_stressTest_manyOrders() public {
        uint256 numOrders = 100;

        vm.startPrank(_alice);
        _weth.mint(_alice, numOrders * 1 ether);
        _weth.approve(address(_board), numOrders * 1 ether);

        for (uint256 i = 0; i < numOrders; ++i) {
            _board.createOrder(address(_weth), 1 ether, address(_usdc), 3000e6, false);
        }
        vm.stopPrank();

        assertEq(_board.getNextOrderId(), numOrders);
        assertEq(_weth.balanceOf(address(_board)), numOrders * 1 ether);

        vm.startPrank(_bob);
        _usdc.approve(address(_board), numOrders * 3000e6);
        for (uint256 i = 0; i < numOrders; ++i) {
            _board.fillOrder(i, 1 ether, 0);
        }
        vm.stopPrank();

        assertEq(_weth.balanceOf(address(_board)), 0);
        assertEq(_weth.balanceOf(_bob), 1000 ether + numOrders * 1 ether);
    }
}
