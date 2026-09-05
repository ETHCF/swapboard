// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec

import {Test} from "forge-std/Test.sol";
import {Swapboard} from "../src/Swapboard.sol";
import {ISwapboard} from "../src/interfaces/ISwapboard.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {FillTestLib} from "./helpers/FillTestLib.sol";
import {OrderTestLib} from "./helpers/OrderTestLib.sol";

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
        uint256 order0 = _board.createOrder(_order(address(_weth), 10 ether, address(_usdc), 30_000e6));
        uint256 order1 = _board.createOrder(_order(address(_weth), 20 ether, address(_usdc), 58_000e6));
        vm.stopPrank();

        vm.startPrank(_bob);
        _usdc.approve(address(_board), 1_000_000e6);
        uint256 order2 = _board.createOrder(_order(address(_usdc), 100_000e6, address(_weth), 35 ether));
        vm.stopPrank();

        vm.startPrank(_dave);
        _wbtc.approve(address(_board), 10e8);
        uint256 order3 = _board.createOrder(_order(address(_wbtc), 1e8, address(_usdc), 95_000e6));
        vm.stopPrank();

        assertEq(_board.getNextOrderId(), 4);
        assertTrue(_board.canFill(order0));
        assertTrue(_board.canFill(order1));
        assertTrue(_board.canFill(order2));
        assertTrue(_board.canFill(order3));
        assertEq(_weth.getTransferFromCalls(), 2);
        assertEq(_usdc.getTransferFromCalls(), 1);
        assertEq(_wbtc.getTransferFromCalls(), 1);

        vm.startPrank(_charlie);
        _usdc.approve(address(_board), 200_000e6);
        uint256 wethPullsBefore = _weth.getTransferFromCalls();
        uint256 wbtcPullsBefore = _wbtc.getTransferFromCalls();
        uint256 usdcPullsBefore = _usdc.getTransferFromCalls();
        _fillOrder(order0, 10 ether);
        _fillOrder(order3, 1e8);
        vm.stopPrank();

        assertFalse(_board.canFill(order0));
        assertFalse(_board.getOrder(order0).active);
        assertEq(_board.getOrder(order0).availableA, 0);
        assertTrue(_board.canFill(order1));
        assertTrue(_board.canFill(order2));
        assertFalse(_board.canFill(order3));
        assertFalse(_board.getOrder(order3).active);
        assertEq(_board.getOrder(order3).availableA, 0);
        assertEq(_weth.getTransferFromCalls(), wethPullsBefore);
        assertEq(_wbtc.getTransferFromCalls(), wbtcPullsBefore);
        assertEq(_usdc.getTransferFromCalls(), usdcPullsBefore + 2);

        assertEq(_weth.balanceOf(_charlie), 10 ether);
        assertEq(_wbtc.balanceOf(_charlie), 1e8);
        assertEq(_usdc.balanceOf(_alice), 10_000_000e6 + 30_000e6);
        assertEq(_usdc.balanceOf(_dave), 95_000e6);
    }

    /// @notice Tests full create-then-fill order lifecycle
    function test_orderLifecycle_createFill() public {
        vm.startPrank(_alice);
        _weth.approve(address(_board), 50 ether);
        uint256 orderId = _board.createOrder(_order(address(_weth), 50 ether, address(_usdc), 150_000e6));
        vm.stopPrank();

        assertEq(_weth.getTransferFromCalls(), 1);

        uint256 bobWethBefore = _weth.balanceOf(_bob);
        uint256 aliceUsdcBefore = _usdc.balanceOf(_alice);
        uint256 wethPullsBefore = _weth.getTransferFromCalls();
        uint256 usdcPullsBefore = _usdc.getTransferFromCalls();

        vm.startPrank(_bob);
        _usdc.approve(address(_board), 150_000e6);
        _fillOrder(orderId, _board.getOrder(orderId).availableA);
        vm.stopPrank();

        assertEq(_weth.balanceOf(_bob), bobWethBefore + 50 ether);
        assertEq(_usdc.balanceOf(_alice), aliceUsdcBefore + 150_000e6);
        assertEq(_weth.balanceOf(address(_board)), 0);
        assertEq(_weth.getTransferFromCalls(), wethPullsBefore);
        assertEq(_usdc.getTransferFromCalls(), usdcPullsBefore + 1);

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(order.availableA, 0);
    }

    /// @notice Tests full create-then-cancel order lifecycle
    function test_orderLifecycle_createCancel() public {
        uint256 aliceWethBefore = _weth.balanceOf(_alice);

        vm.startPrank(_alice);
        _weth.approve(address(_board), 50 ether);
        uint256 orderId = _board.createOrder(_order(address(_weth), 50 ether, address(_usdc), 150_000e6));

        assertEq(_weth.balanceOf(_alice), aliceWethBefore - 50 ether);
        assertEq(_weth.balanceOf(address(_board)), 50 ether);
        assertEq(_weth.getTransferFromCalls(), 1);

        _board.cancelOrder(orderId);
        vm.stopPrank();

        assertEq(_weth.balanceOf(_alice), aliceWethBefore);
        assertEq(_weth.balanceOf(address(_board)), 0);

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(order.availableA, 0);
    }

    /// @notice Tests only one of two competing fillers succeeds
    function test_raceCondition_twoFillersOneOrder() public {
        vm.startPrank(_alice);
        _weth.approve(address(_board), 10 ether);
        uint256 orderId = _board.createOrder(_order(address(_weth), 10 ether, address(_usdc), 30_000e6));
        vm.stopPrank();

        assertEq(_weth.getTransferFromCalls(), 1);

        vm.prank(_bob);
        _usdc.approve(address(_board), 30_000e6);

        vm.prank(_charlie);
        _usdc.approve(address(_board), 30_000e6);

        uint256 wethPullsBefore = _weth.getTransferFromCalls();
        uint256 usdcPullsBefore = _usdc.getTransferFromCalls();
        vm.startPrank(_bob);
        _fillOrder(orderId, 10 ether);
        vm.stopPrank();

        ISwapboard.Order memory orderBeforeCharlie = _board.getOrder(orderId);
        uint128 amountBCharlie = FillTestLib.quoteAmountB(orderBeforeCharlie, 10 ether);
        vm.startPrank(_charlie);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        _board.fillOrder(orderId, 10 ether, amountBCharlie, 0);
        vm.stopPrank();

        assertFalse(_board.getOrder(orderId).active);
        assertEq(_board.getOrder(orderId).availableA, 0);
        assertEq(_weth.getTransferFromCalls(), wethPullsBefore);
        assertEq(_usdc.getTransferFromCalls(), usdcPullsBefore + 1);
        assertEq(_weth.balanceOf(_bob), 1000 ether + 10 ether);
        assertEq(_weth.balanceOf(_charlie), 0);
    }

    /// @notice Tests fill wins over concurrent cancel attempt
    function test_raceCondition_fillAndCancel() public {
        vm.startPrank(_alice);
        _weth.approve(address(_board), 10 ether);
        uint256 orderId = _board.createOrder(_order(address(_weth), 10 ether, address(_usdc), 30_000e6));
        vm.stopPrank();

        assertEq(_weth.getTransferFromCalls(), 1);

        vm.startPrank(_bob);
        _usdc.approve(address(_board), 30_000e6);
        uint256 wethPullsBefore = _weth.getTransferFromCalls();
        uint256 usdcPullsBefore = _usdc.getTransferFromCalls();
        _fillOrder(orderId, 10 ether);
        vm.stopPrank();

        assertFalse(_board.getOrder(orderId).active);
        assertEq(_board.getOrder(orderId).availableA, 0);
        assertEq(_weth.getTransferFromCalls(), wethPullsBefore);
        assertEq(_usdc.getTransferFromCalls(), usdcPullsBefore + 1);

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
            orderIds[i] = _board.createOrder(_order(address(_weth), 10 ether, address(_usdc), 30_000e6));
        }
        vm.stopPrank();

        assertEq(_board.getNextOrderId(), 10);
        assertEq(_weth.balanceOf(address(_board)), 100 ether);
        assertEq(_weth.getTransferFromCalls(), 10);

        ISwapboard.Order[] memory orders = _board.getOrders(orderIds);
        assertEq(orders.length, 10);
        for (uint256 i = 0; i < 10; ++i) {
            assertEq(orders[i].maker, _alice);
            assertEq(orders[i].amountA, 10 ether);
            assertTrue(orders[i].active);
        }

        vm.startPrank(_bob);
        _usdc.approve(address(_board), 150_000e6);
        uint256 wethPullsBefore = _weth.getTransferFromCalls();
        uint256 usdcPullsBefore = _usdc.getTransferFromCalls();
        _fillOrder(orderIds[0], 10 ether);
        _fillOrder(orderIds[2], 10 ether);
        _fillOrder(orderIds[4], 10 ether);
        _fillOrder(orderIds[6], 10 ether);
        _fillOrder(orderIds[8], 10 ether);
        vm.stopPrank();

        assertEq(_weth.getTransferFromCalls(), wethPullsBefore);
        assertEq(_usdc.getTransferFromCalls(), usdcPullsBefore + 5);
        for (uint256 i = 0; i < 10; i += 2) {
            assertFalse(_board.getOrder(orderIds[i]).active);
            assertEq(_board.getOrder(orderIds[i]).availableA, 0);
        }

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
        uint256 orderId = _board.createOrder(_order(address(_wbtc), 1e8, address(_dai), 95_000 ether));
        vm.stopPrank();

        assertEq(_wbtc.getTransferFromCalls(), 1);

        uint256 wbtcPullsBefore = _wbtc.getTransferFromCalls();
        uint256 daiPullsBefore = _dai.getTransferFromCalls();
        vm.startPrank(_bob);
        _dai.approve(address(_board), 95_000 ether);
        _fillOrder(orderId, _board.getOrder(orderId).availableA);
        vm.stopPrank();

        assertFalse(_board.getOrder(orderId).active);
        assertEq(_board.getOrder(orderId).availableA, 0);
        assertEq(_wbtc.getTransferFromCalls(), wbtcPullsBefore);
        assertEq(_dai.getTransferFromCalls(), daiPullsBefore + 1);
        assertEq(_wbtc.balanceOf(_bob), 1e8);
        assertEq(_dai.balanceOf(_dave), 95_000 ether);
    }

    /// @notice Tests creating and filling large amount orders
    function test_largeAmounts() public {
        uint128 largeAmount = type(uint128).max;
        _weth.mint(_alice, largeAmount);

        vm.startPrank(_alice);
        _weth.approve(address(_board), largeAmount);
        uint256 orderId = _board.createOrder(_order(address(_weth), largeAmount, address(_usdc), 1e6));
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertEq(order.amountA, largeAmount);
        assertEq(_weth.getTransferFromCalls(), 1);

        uint256 wethPullsBefore = _weth.getTransferFromCalls();
        uint256 usdcPullsBefore = _usdc.getTransferFromCalls();
        vm.startPrank(_bob);
        _usdc.approve(address(_board), 1e6);
        _fillOrder(orderId, _board.getOrder(orderId).availableA);
        vm.stopPrank();

        assertFalse(_board.getOrder(orderId).active);
        assertEq(_board.getOrder(orderId).availableA, 0);
        assertEq(_weth.getTransferFromCalls(), wethPullsBefore);
        assertEq(_usdc.getTransferFromCalls(), usdcPullsBefore + 1);
        assertEq(_weth.balanceOf(_bob), uint256(1000 ether) + uint256(largeAmount));
    }

    /// @notice Tests creating and filling dust-sized orders
    function test_dustAmounts() public {
        vm.startPrank(_alice);
        _weth.approve(address(_board), 1);
        uint256 orderId = _board.createOrder(_order(address(_weth), 1, address(_usdc), 1));
        vm.stopPrank();

        assertEq(_weth.getTransferFromCalls(), 1);

        uint256 wethPullsBefore = _weth.getTransferFromCalls();
        uint256 usdcPullsBefore = _usdc.getTransferFromCalls();
        vm.startPrank(_bob);
        _usdc.approve(address(_board), 1);
        _fillOrder(orderId, _board.getOrder(orderId).availableA);
        vm.stopPrank();

        assertFalse(_board.getOrder(orderId).active);
        assertEq(_board.getOrder(orderId).availableA, 0);
        assertEq(_weth.getTransferFromCalls(), wethPullsBefore);
        assertEq(_usdc.getTransferFromCalls(), usdcPullsBefore + 1);
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
        uint256 orderId = _board.createOrder(_order(address(_weth), 10 ether, address(_usdc), 30_000e6));
        vm.stopPrank();

        assertEq(_weth.getTransferFromCalls(), 1);

        vm.startPrank(_bob);
        _usdc.approve(address(_board), 30_000e6);

        uint256 wethPullsBefore = _weth.getTransferFromCalls();
        uint256 usdcPullsBefore = _usdc.getTransferFromCalls();
        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderFilled({orderId: orderId, taker: _bob, amountA: 10 ether, amountB: 30_000e6});
        _fillOrder(orderId, _board.getOrder(orderId).availableA);
        vm.stopPrank();

        assertFalse(_board.getOrder(orderId).active);
        assertEq(_board.getOrder(orderId).availableA, 0);
        assertEq(_weth.getTransferFromCalls(), wethPullsBefore);
        assertEq(_usdc.getTransferFromCalls(), usdcPullsBefore + 1);
    }

    /// @notice Tests getOrders returns empty structs for missing IDs
    function test_getOrdersWithNonExistent() public {
        vm.startPrank(_alice);
        _weth.approve(address(_board), 20 ether);
        _board.createOrder(_order(address(_weth), 10 ether, address(_usdc), 30_000e6));
        _board.createOrder(_order(address(_weth), 10 ether, address(_usdc), 30_000e6));
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
            _board.createOrder(_order(address(_weth), 1 ether, address(_usdc), 3000e6));
        }
        vm.stopPrank();

        assertEq(_board.getNextOrderId(), numOrders);
        assertEq(_weth.balanceOf(address(_board)), numOrders * 1 ether);
        assertEq(_weth.getTransferFromCalls(), numOrders);

        vm.startPrank(_bob);
        _usdc.approve(address(_board), numOrders * 3000e6);
        uint256 wethPullsBefore = _weth.getTransferFromCalls();
        uint256 usdcPullsBefore = _usdc.getTransferFromCalls();
        for (uint256 i = 0; i < numOrders; ++i) {
            _fillOrder(i, 1 ether);
        }
        vm.stopPrank();

        assertEq(_weth.getTransferFromCalls(), wethPullsBefore);
        assertEq(_usdc.getTransferFromCalls(), usdcPullsBefore + numOrders);
        assertFalse(_board.getOrder(0).active);
        assertEq(_board.getOrder(0).availableA, 0);
        assertFalse(_board.getOrder(numOrders - 1).active);
        assertEq(_board.getOrder(numOrders - 1).availableA, 0);
        assertEq(_weth.balanceOf(address(_board)), 0);
        assertEq(_weth.balanceOf(_bob), 1000 ether + numOrders * 1 ether);
    }

    /// @notice Multi-user partial fills against one order, then completion
    function test_partialFill_multiUserThenComplete() public {
        vm.startPrank(_alice);
        _weth.approve(address(_board), 100 ether);
        uint256 orderId = _board.createOrder(_orderPartial(address(_weth), 100 ether, address(_usdc), 300_000e6));
        vm.stopPrank();

        assertEq(_weth.getTransferFromCalls(), 1);

        uint256 wethPullsBefore = _weth.getTransferFromCalls();
        uint256 usdcPullsBefore = _usdc.getTransferFromCalls();
        vm.startPrank(_bob);
        _usdc.approve(address(_board), 200_000e6);
        _fillOrder(orderId, 40 ether);
        vm.stopPrank();

        ISwapboard.Order memory afterBob = _board.getOrder(orderId);
        assertTrue(afterBob.active);
        assertEq(afterBob.amountA, 100 ether);
        assertEq(afterBob.availableA, 60 ether);
        assertEq(_weth.getTransferFromCalls(), wethPullsBefore);
        assertEq(_usdc.getTransferFromCalls(), usdcPullsBefore + 1);

        vm.startPrank(_charlie);
        _usdc.approve(address(_board), 200_000e6);
        _fillOrder(orderId, 60 ether);
        vm.stopPrank();

        ISwapboard.Order memory done = _board.getOrder(orderId);
        assertFalse(done.active);
        assertEq(done.availableA, 0);
        assertEq(done.availableB, 0);
        assertEq(_weth.getTransferFromCalls(), wethPullsBefore);
        assertEq(_usdc.getTransferFromCalls(), usdcPullsBefore + 2);
        assertEq(_weth.balanceOf(_bob), 1000 ether + 40 ether);
        assertEq(_weth.balanceOf(_charlie), 60 ether);
        assertEq(_weth.balanceOf(address(_board)), 0);
    }

    /// @notice Race: second filler cannot take more than remaining availableA
    function test_partialFill_race_secondFillerTooHigh() public {
        vm.startPrank(_alice);
        _weth.approve(address(_board), 10 ether);
        uint256 orderId = _board.createOrder(_orderPartial(address(_weth), 10 ether, address(_usdc), 30_000e6));
        vm.stopPrank();

        assertEq(_weth.getTransferFromCalls(), 1);

        uint256 wethPullsBefore = _weth.getTransferFromCalls();
        uint256 usdcPullsBefore = _usdc.getTransferFromCalls();
        vm.startPrank(_bob);
        _usdc.approve(address(_board), 30_000e6);
        _fillOrder(orderId, 7 ether);
        vm.stopPrank();

        uint128 remainingA = _board.getOrder(orderId).availableA;
        assertEq(remainingA, 3 ether);
        assertEq(_weth.getTransferFromCalls(), wethPullsBefore);
        assertEq(_usdc.getTransferFromCalls(), usdcPullsBefore + 1);

        vm.startPrank(_charlie);
        _usdc.approve(address(_board), 30_000e6);
        ISwapboard.Order memory order = _board.getOrder(orderId);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.FillAmountTooHigh.selector, orderId, 4 ether, remainingA));
        _board.fillOrder(orderId, 4 ether, FillTestLib.quoteAmountB(order, 4 ether), 0);
        vm.stopPrank();

        assertTrue(_board.canFill(orderId));
        assertEq(_board.getOrder(orderId).availableA, 3 ether);
        assertEq(_usdc.getTransferFromCalls(), usdcPullsBefore + 1);
    }

    /// @notice Lifecycle: create → partial fill → cancel returns remaining tokenA
    function test_partialFill_lifecycle_createPartialCancel() public {
        uint256 aliceWethBefore = _weth.balanceOf(_alice);

        vm.startPrank(_alice);
        _weth.approve(address(_board), 50 ether);
        uint256 orderId = _board.createOrder(_orderPartial(address(_weth), 50 ether, address(_usdc), 150_000e6));
        vm.stopPrank();

        assertEq(_weth.getTransferFromCalls(), 1);

        uint256 wethPullsBefore = _weth.getTransferFromCalls();
        uint256 usdcPullsBefore = _usdc.getTransferFromCalls();
        vm.startPrank(_bob);
        _usdc.approve(address(_board), 150_000e6);
        _fillOrder(orderId, 20 ether);
        vm.stopPrank();

        assertEq(_weth.getTransferFromCalls(), wethPullsBefore);
        assertEq(_usdc.getTransferFromCalls(), usdcPullsBefore + 1);

        vm.prank(_alice);
        _board.cancelOrder(orderId);

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertEq(order.maker, address(0));
        assertFalse(order.active);
        assertEq(order.amountA, 0);
        assertEq(order.availableA, 0);
        assertEq(order.availableB, 0);
        assertEq(_weth.balanceOf(_alice), aliceWethBefore - 20 ether);
        assertEq(_weth.balanceOf(_bob), 1000 ether + 20 ether);
        assertEq(_weth.balanceOf(address(_board)), 0);
    }

    /// @notice Lifecycle: create → partial → fill exact remaining
    function test_partialFill_lifecycle_createPartialComplete() public {
        vm.startPrank(_alice);
        _weth.approve(address(_board), 50 ether);
        uint256 orderId = _board.createOrder(_orderPartial(address(_weth), 50 ether, address(_usdc), 150_000e6));
        vm.stopPrank();

        assertEq(_weth.getTransferFromCalls(), 1);

        uint256 wethPullsBefore = _weth.getTransferFromCalls();
        uint256 usdcPullsBefore = _usdc.getTransferFromCalls();
        vm.startPrank(_bob);
        _usdc.approve(address(_board), 150_000e6);
        _fillOrder(orderId, 15 ether);
        uint128 remainingA = _board.getOrder(orderId).availableA;
        _fillOrder(orderId, remainingA);
        vm.stopPrank();

        assertFalse(_board.canFill(orderId));
        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(order.availableA, 0);
        assertEq(_weth.getTransferFromCalls(), wethPullsBefore);
        assertEq(_usdc.getTransferFromCalls(), usdcPullsBefore + 2);
        assertEq(_weth.balanceOf(_bob), 1000 ether + 50 ether);
        assertEq(_weth.balanceOf(address(_board)), 0);
    }

    /// @notice Tests batch create aggregates the same token and fills independently
    function test_batchCreate_sameTokenThenFill() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_weth), 10 ether, address(_usdc), 30_000e6);
        orders[1] = _orderPartial(address(_weth), 20 ether, address(_usdc), 58_000e6);

        vm.startPrank(_alice);
        _weth.approve(address(_board), 30 ether);
        uint256[] memory ids = _board.createOrders(orders);
        vm.stopPrank();

        assertEq(_weth.getTransferFromCalls(), 1);
        assertEq(_weth.balanceOf(address(_board)), 30 ether);

        uint256 wethPullsBefore = _weth.getTransferFromCalls();
        uint256 usdcPullsBefore = _usdc.getTransferFromCalls();
        vm.startPrank(_bob);
        _usdc.approve(address(_board), 88_000e6);
        _fillOrder(ids[0], 10 ether);
        _fillOrder(ids[1], 5 ether);
        vm.stopPrank();

        assertFalse(_board.canFill(ids[0]));
        assertFalse(_board.getOrder(ids[0]).active);
        assertEq(_board.getOrder(ids[0]).availableA, 0);
        assertTrue(_board.canFill(ids[1]));
        assertEq(_board.getOrder(ids[1]).availableA, 15 ether);
        assertEq(_weth.getTransferFromCalls(), wethPullsBefore);
        assertEq(_usdc.getTransferFromCalls(), usdcPullsBefore + 2);
        assertEq(_weth.balanceOf(_bob), 1000 ether + 15 ether);
    }

    /// @notice Tests batch create then batch fill aggregates tokenB pull
    function test_batchCreate_thenFillOrders() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_weth), 10 ether, address(_usdc), 30_000e6);
        orders[1] = _order(address(_weth), 20 ether, address(_usdc), 58_000e6);

        vm.startPrank(_alice);
        _weth.approve(address(_board), 30 ether);
        uint256[] memory ids = _board.createOrders(orders);
        vm.stopPrank();

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = FillTestLib.fillParams(_board.getOrder(ids[0]), ids[0], 10 ether);
        fills[1] = FillTestLib.fillParams(_board.getOrder(ids[1]), ids[1], 20 ether);

        vm.startPrank(_bob);
        _usdc.approve(address(_board), 88_000e6);
        uint256 wethPullsBefore = _weth.getTransferFromCalls();
        uint256 usdcPullsBefore = _usdc.getTransferFromCalls();
        _board.fillOrders(fills, 0);
        vm.stopPrank();

        assertEq(_weth.getTransferFromCalls(), wethPullsBefore);
        assertEq(_usdc.getTransferFromCalls(), usdcPullsBefore + 1);
        assertEq(_weth.balanceOf(address(_board)), 0);
        assertEq(_weth.balanceOf(_bob), 1000 ether + 30 ether);
        assertFalse(_board.canFill(ids[0]));
        assertFalse(_board.canFill(ids[1]));
        assertFalse(_board.getOrder(ids[0]).active);
        assertFalse(_board.getOrder(ids[1]).active);
        assertEq(_board.getOrder(ids[0]).availableA, 0);
        assertEq(_board.getOrder(ids[1]).availableA, 0);
    }

    /// @notice Tests batch create then batch cancel restores maker balances
    function test_batchCreate_thenCancelOrders() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_weth), 10 ether, address(_usdc), 30_000e6);
        orders[1] = _order(address(_weth), 20 ether, address(_usdc), 58_000e6);

        uint256 aliceWethBefore = _weth.balanceOf(_alice);

        vm.startPrank(_alice);
        _weth.approve(address(_board), 30 ether);
        uint256[] memory ids = _board.createOrders(orders);
        assertEq(_weth.getTransferFromCalls(), 1);
        _board.cancelOrders(ids);
        vm.stopPrank();

        assertEq(_weth.balanceOf(_alice), aliceWethBefore);
        assertEq(_weth.balanceOf(address(_board)), 0);
        assertEq(_board.getOrder(ids[0]).maker, address(0));
        assertEq(_board.getOrder(ids[1]).maker, address(0));
        assertFalse(_board.canFill(ids[0]));
        assertFalse(_board.canFill(ids[1]));
        assertFalse(_board.getOrder(ids[0]).active);
        assertFalse(_board.getOrder(ids[1]).active);
        assertEq(_board.getOrder(ids[0]).availableA, 0);
        assertEq(_board.getOrder(ids[1]).availableA, 0);
    }

    /// @notice Tests a maker can resize an order then a taker fills at the new price
    function test_modifyOrder_thenFill() public {
        uint256 aliceWethBefore = _weth.balanceOf(_alice);
        uint256 charlieUsdcBefore = _usdc.balanceOf(_charlie);

        vm.startPrank(_alice);
        _weth.approve(address(_board), 10 ether);
        uint256 orderId = _board.createOrder(_order(address(_weth), 10 ether, address(_usdc), 30_000e6));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        _board.modifyOrder(
            orderId,
            ISwapboard.OrderAmounts({
                amountA: snapshot.amountA,
                amountB: snapshot.amountB,
                availableA: snapshot.availableA,
                availableB: snapshot.availableB
            }),
            ISwapboard.ModifyOrderParams({availableA: 4 ether, availableB: 12_000e6})
        );
        vm.stopPrank();

        assertEq(_weth.balanceOf(_alice), aliceWethBefore - 4 ether);
        assertEq(_weth.balanceOf(address(_board)), 4 ether);

        vm.startPrank(_charlie);
        _usdc.approve(address(_board), 12_000e6);
        _fillOrder(orderId, 4 ether);
        vm.stopPrank();

        assertFalse(_board.canFill(orderId));
        assertEq(_weth.balanceOf(_alice), aliceWethBefore - 4 ether);
        assertEq(_weth.balanceOf(_charlie), 4 ether);
        assertEq(_usdc.balanceOf(_alice), 10_000_000e6 + 12_000e6);
        assertEq(_usdc.balanceOf(_charlie), charlieUsdcBefore - 12_000e6);
        assertEq(_weth.balanceOf(address(_board)), 0);
    }

    /// @notice Tests enabling partial fills mid-life then filling in parts
    function test_setPartialFillAllowed_thenPartialFill() public {
        vm.startPrank(_alice);
        _weth.approve(address(_board), 10 ether);
        uint256 orderId = _board.createOrder(_order(address(_weth), 10 ether, address(_usdc), 30_000e6));
        assertFalse(_board.getOrder(orderId).partialFillAllowed);

        vm.expectEmit(true, false, false, true, address(_board));
        emit ISwapboard.OrderPartialFillUpdated(orderId, true);
        _board.setPartialFillAllowed(orderId, true);
        vm.stopPrank();

        assertTrue(_board.getOrder(orderId).partialFillAllowed);
        assertEq(_board.getOrder(orderId).availableA, 10 ether);
        assertEq(_board.getOrder(orderId).availableB, 30_000e6);

        vm.startPrank(_charlie);
        _usdc.approve(address(_board), 30_000e6);
        _fillOrder(orderId, 4 ether);
        vm.stopPrank();

        ISwapboard.Order memory afterPartial = _board.getOrder(orderId);
        assertTrue(afterPartial.active);
        assertTrue(afterPartial.partialFillAllowed);
        assertEq(afterPartial.availableA, 6 ether);
        assertEq(_weth.balanceOf(_charlie), 4 ether);
        assertEq(_weth.balanceOf(address(_board)), 6 ether);
    }

    /// @notice Tests batch resize of two orders then fills at the new sizes
    function test_modifyOrders_thenFillEach() public {
        vm.startPrank(_alice);
        _weth.approve(address(_board), 30 ether);
        uint256 order0 = _board.createOrder(_order(address(_weth), 10 ether, address(_usdc), 30_000e6));
        uint256 order1 = _board.createOrder(_order(address(_weth), 20 ether, address(_usdc), 58_000e6));

        ISwapboard.Order memory snap0 = _board.getOrder(order0);
        ISwapboard.Order memory snap1 = _board.getOrder(order1);
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = ISwapboard.ModifyOrdersParams({
            orderId: order0,
            previousAmounts: ISwapboard.OrderAmounts({
                amountA: snap0.amountA,
                amountB: snap0.amountB,
                availableA: snap0.availableA,
                availableB: snap0.availableB
            }),
            updatedOrder: ISwapboard.ModifyOrderParams({availableA: 4 ether, availableB: 12_000e6})
        });
        mods[1] = ISwapboard.ModifyOrdersParams({
            orderId: order1,
            previousAmounts: ISwapboard.OrderAmounts({
                amountA: snap1.amountA,
                amountB: snap1.amountB,
                availableA: snap1.availableA,
                availableB: snap1.availableB
            }),
            updatedOrder: ISwapboard.ModifyOrderParams({availableA: 8 ether, availableB: 24_000e6})
        });
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_weth.balanceOf(address(_board)), 12 ether);

        vm.startPrank(_charlie);
        _usdc.approve(address(_board), 36_000e6);
        _fillOrder(order0, 4 ether);
        _fillOrder(order1, 8 ether);
        vm.stopPrank();

        assertFalse(_board.canFill(order0));
        assertFalse(_board.canFill(order1));
        assertEq(_weth.balanceOf(address(_board)), 0);
        assertEq(_weth.balanceOf(_charlie), 12 ether);
    }

    /// @notice Tests batch modify nets independent tokenA assets then fills each
    function test_modifyOrders_netsIndependentTokens_thenFillEach() public {
        vm.startPrank(_alice);
        _weth.approve(address(_board), 100 ether);
        _dai.approve(address(_board), 1_000_000 ether);

        uint256 wethSmall = _board.createOrder(_order(address(_weth), 10 ether, address(_usdc), 30_000e6));
        uint256 wethLarge = _board.createOrder(_order(address(_weth), 40 ether, address(_usdc), 120_000e6));
        uint256 daiSmall = _board.createOrder(_order(address(_dai), 100 ether, address(_usdc), 100e6));
        uint256 daiLarge = _board.createOrder(_order(address(_dai), 400 ether, address(_usdc), 400e6));

        ISwapboard.ModifyOrdersParams[] memory mods =
            _independentTokenModifyParams(wethSmall, wethLarge, daiSmall, daiLarge);

        uint256 aliceWethBefore = _weth.balanceOf(_alice);
        uint256 aliceDaiBefore = _dai.balanceOf(_alice);
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(aliceWethBefore - _weth.balanceOf(_alice), 10 ether);
        assertEq(_dai.balanceOf(_alice) - aliceDaiBefore, 150 ether);
        assertEq(_weth.balanceOf(address(_board)), 60 ether);
        assertEq(_dai.balanceOf(address(_board)), 350 ether);

        vm.startPrank(_charlie);
        _usdc.approve(address(_board), 530_000e6);
        _fillOrder(wethSmall, 30 ether);
        _fillOrder(wethLarge, 30 ether);
        _fillOrder(daiSmall, 150 ether);
        _fillOrder(daiLarge, 200 ether);
        vm.stopPrank();

        assertFalse(_board.canFill(wethSmall));
        assertFalse(_board.canFill(wethLarge));
        assertFalse(_board.canFill(daiSmall));
        assertFalse(_board.canFill(daiLarge));
        assertEq(_weth.balanceOf(address(_board)), 0);
        assertEq(_dai.balanceOf(address(_board)), 0);
        assertEq(_weth.balanceOf(_charlie), 60 ether);
        assertEq(_dai.balanceOf(_charlie), 350 ether);
    }

    /// @notice Builds the WETH/DAI netting batch used by the independent-token integration test
    function _independentTokenModifyParams(
        uint256 wethSmall,
        uint256 wethLarge,
        uint256 daiSmall,
        uint256 daiLarge
    ) private pure returns (ISwapboard.ModifyOrdersParams[] memory mods) {
        mods = new ISwapboard.ModifyOrdersParams[](4);
        // WETH: +20 / -10 => net pull 10
        mods[0] = ISwapboard.ModifyOrdersParams({
            orderId: wethSmall,
            previousAmounts: ISwapboard.OrderAmounts({
                amountA: 10 ether, amountB: 30_000e6, availableA: 10 ether, availableB: 30_000e6
            }),
            updatedOrder: ISwapboard.ModifyOrderParams({availableA: 30 ether, availableB: 90_000e6})
        });
        mods[1] = ISwapboard.ModifyOrdersParams({
            orderId: wethLarge,
            previousAmounts: ISwapboard.OrderAmounts({
                amountA: 40 ether, amountB: 120_000e6, availableA: 40 ether, availableB: 120_000e6
            }),
            updatedOrder: ISwapboard.ModifyOrderParams({availableA: 30 ether, availableB: 90_000e6})
        });
        // DAI: +50 / -200 => net refund 150
        mods[2] = ISwapboard.ModifyOrdersParams({
            orderId: daiSmall,
            previousAmounts: ISwapboard.OrderAmounts({
                amountA: 100 ether, amountB: 100e6, availableA: 100 ether, availableB: 100e6
            }),
            updatedOrder: ISwapboard.ModifyOrderParams({availableA: 150 ether, availableB: 150e6})
        });
        mods[3] = ISwapboard.ModifyOrdersParams({
            orderId: daiLarge,
            previousAmounts: ISwapboard.OrderAmounts({
                amountA: 400 ether, amountB: 400e6, availableA: 400 ether, availableB: 400e6
            }),
            updatedOrder: ISwapboard.ModifyOrderParams({availableA: 200 ether, availableB: 200e6})
        });
    }

    function _fillOrder(
        uint256 orderId,
        uint128 amountA
    ) private {
        FillTestLib.fill(_board, orderId, amountA);
    }

    function _fillOrderPayEth(
        uint256 orderId,
        uint128 amountA,
        uint128 minAmountB
    ) private {
        FillTestLib.fillPayEth(_board, orderId, amountA, minAmountB);
    }

    function _order(
        address tokenA,
        uint128 amountA,
        address tokenB,
        uint128 amountB
    ) private pure returns (ISwapboard.CreateOrderParams memory) {
        return OrderTestLib.order(tokenA, amountA, tokenB, amountB);
    }

    function _orderPartial(
        address tokenA,
        uint128 amountA,
        address tokenB,
        uint128 amountB
    ) private pure returns (ISwapboard.CreateOrderParams memory) {
        return OrderTestLib.orderPartial(tokenA, amountA, tokenB, amountB);
    }
}
