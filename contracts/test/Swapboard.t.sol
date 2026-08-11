// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec

/**
 * @title SwapboardTest
 * @notice Unit tests for the Swapboard contract
 * @dev Tests cover all public functions and error conditions.
 *      Run with: forge test -vvv
 */

import {Test} from "forge-std/Test.sol";
import {Swapboard} from "../src/Swapboard.sol";
import {ISwapboard} from "../src/interfaces/ISwapboard.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockFOT} from "./mocks/MockFOT.sol";
import {ETHRejecter} from "./mocks/ETHRejecter.sol";

/// @notice Unit tests for Swapboard contract
/// @dev Uses Foundry's Test framework with MockERC20 tokens
contract SwapboardTest is Test {
    Swapboard internal _board;
    MockERC20 internal _tokenA;
    MockERC20 internal _tokenB;

    address internal _eth;
    address internal _maker = address(0x1);
    address internal _taker = address(0x2);

    uint256 private constant AMOUNT_A = 100 ether;
    uint256 private constant AMOUNT_B = 250_000e6;
    uint256 private constant ETH_AMOUNT = 1 ether;

    /// @notice Deploys fixtures for each test
    function setUp() public {
        _board = new Swapboard();
        _eth = _board.getEth();

        _tokenA = new MockERC20("Token A", "TKA", 18);
        _tokenB = new MockERC20("Token B", "TKB", 6);

        vm.deal(_maker, 100 ether);
        vm.deal(_taker, 100 ether);

        _tokenA.mint(_maker, AMOUNT_A * 10);
        _tokenB.mint(_taker, AMOUNT_B * 10);
        // Maker also holds tokenB for ETH-buy orders; taker holds tokenA for ETH-sell fills.
        _tokenB.mint(_maker, AMOUNT_B * 10);
        _tokenA.mint(_taker, AMOUNT_A * 10);
    }

    // ========================================
    // State variable getters (_nextOrderId, _orders)
    // ========================================

    /// @notice version returns the semver string for this deployment
    function test_version() public view {
        assertEq(_board.version(), "2.0.0");
    }

    /// @notice getEth returns the canonical ETH sentinel
    function test_getEth() public view {
        assertEq(_board.getEth(), 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    }

    /// @notice getNextOrderId starts at zero and increments on create
    function test_getNextOrderId() public {
        assertEq(_board.getNextOrderId(), 0);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        uint256 order0 = _board.createOrder(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        assertEq(order0, 0);
        assertEq(_board.getNextOrderId(), 1);

        uint256 order1 = _board.createOrder(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        vm.stopPrank();

        assertEq(order1, 1);
        assertEq(_board.getNextOrderId(), 2);
    }

    /// @notice getOrder returns full order details for an existing order
    function test_getOrder() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertEq(order.maker, _maker);
        assertEq(order.tokenA, address(_tokenA));
        assertEq(order.amountA, AMOUNT_A);
        assertEq(order.tokenB, address(_tokenB));
        assertEq(order.amountB, AMOUNT_B);
        assertTrue(order.active);
    }

    /// @notice getOrder returns empty defaults for a non-existent order
    function test_getOrder_nonExistent() public view {
        ISwapboard.Order memory order = _board.getOrder(999);
        assertEq(order.maker, address(0));
        assertEq(order.tokenA, address(0));
        assertEq(order.amountA, 0);
        assertEq(order.tokenB, address(0));
        assertEq(order.amountB, 0);
        assertFalse(order.active);
    }

    /// @notice Tests createOrder
    function test_createOrder() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);

        uint256 orderId = _board.createOrder(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        vm.stopPrank();

        assertEq(orderId, 0);
        assertEq(_board.getNextOrderId(), 1);

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertEq(order.maker, _maker);
        assertEq(order.tokenA, address(_tokenA));
        assertEq(order.amountA, AMOUNT_A);
        assertEq(order.tokenB, address(_tokenB));
        assertEq(order.amountB, AMOUNT_B);
        assertTrue(order.active);

        assertEq(_tokenA.balanceOf(address(_board)), AMOUNT_A);
        assertEq(_tokenA.balanceOf(_maker), AMOUNT_A * 10 - AMOUNT_A);
    }

    /// @notice Tests createOrder revert zeroAddress _tokenA
    function test_createOrder_revert_zeroAddress_tokenA() public {
        vm.startPrank(_maker);
        vm.expectRevert(ISwapboard.ZeroAddress.selector);
        _board.createOrder(address(0), AMOUNT_A, address(_tokenB), AMOUNT_B);
        vm.stopPrank();
    }

    /// @notice Tests createOrder revert zeroAddress _tokenB
    function test_createOrder_revert_zeroAddress_tokenB() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        vm.expectRevert(ISwapboard.ZeroAddress.selector);
        _board.createOrder(address(_tokenA), AMOUNT_A, address(0), AMOUNT_B);
        vm.stopPrank();
    }

    /// @notice Tests createOrder revert zeroAmount amountA
    function test_createOrder_revert_zeroAmount_amountA() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.createOrder(address(_tokenA), 0, address(_tokenB), AMOUNT_B);
        vm.stopPrank();
    }

    /// @notice Tests createOrder revert zeroAmount amountB
    function test_createOrder_revert_zeroAmount_amountB() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.createOrder(address(_tokenA), AMOUNT_A, address(_tokenB), 0);
        vm.stopPrank();
    }

    /// @notice Tests createOrder revert sameToken
    function test_createOrder_revert_sameToken() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        vm.expectRevert(ISwapboard.SameToken.selector);
        _board.createOrder(address(_tokenA), AMOUNT_A, address(_tokenA), AMOUNT_B);
        vm.stopPrank();
    }

    /// @notice Tests createOrder revert notAContract _tokenA
    function test_createOrder_revert_notAContract_tokenA() public {
        vm.startPrank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotAContract.selector, address(0x999)));
        _board.createOrder(address(0x999), AMOUNT_A, address(_tokenB), AMOUNT_B);
        vm.stopPrank();
    }

    /// @notice Tests createOrder revert notAContract _tokenB
    function test_createOrder_revert_notAContract_tokenB() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotAContract.selector, address(0x999)));
        _board.createOrder(address(_tokenA), AMOUNT_A, address(0x999), AMOUNT_B);
        vm.stopPrank();
    }

    /// @notice Tests createOrder revert FOT
    function test_createOrder_revert_FOT() public {
        MockFOT fot = new MockFOT();
        fot.mint(_maker, 1000 ether);

        vm.startPrank(_maker);
        fot.approve(address(_board), 100 ether);

        vm.expectRevert(abi.encodeWithSelector(ISwapboard.BalanceMismatch.selector, 100 ether, 95 ether));
        _board.createOrder(address(fot), 100 ether, address(_tokenB), AMOUNT_B);
        vm.stopPrank();
    }

    /// @notice Tests fillOrder
    function test_fillOrder() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _board.fillOrder(orderId, 0);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active);

        assertEq(_tokenA.balanceOf(_taker), AMOUNT_A * 10 + AMOUNT_A);
        assertEq(_tokenB.balanceOf(_maker), AMOUNT_B * 10 + AMOUNT_B);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
    }

    /// @notice Tests fillOrder revert orderNotFound
    function test_fillOrder_revert_orderNotFound() public {
        vm.startPrank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, 999));
        _board.fillOrder(999, 0);
        vm.stopPrank();
    }

    /// @notice Tests fillOrder revert orderNotActive
    function test_fillOrder_revert_orderNotActive() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _board.fillOrder(orderId, 0);

        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        _board.fillOrder(orderId, 0);
        vm.stopPrank();
    }

    /// @notice Tests cancelOrder
    function test_cancelOrder() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);

        uint256 balanceBefore = _tokenA.balanceOf(_maker);
        _board.cancelOrder(orderId);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(_tokenA.balanceOf(_maker), balanceBefore + AMOUNT_A);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
    }

    /// @notice Tests cancelOrder revert orderNotFound
    function test_cancelOrder_revert_orderNotFound() public {
        vm.startPrank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, 999));
        _board.cancelOrder(999);
        vm.stopPrank();
    }

    /// @notice Tests cancelOrder revert orderNotActive
    function test_cancelOrder_revert_orderNotActive() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        _board.cancelOrder(orderId);

        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        _board.cancelOrder(orderId);
        vm.stopPrank();
    }

    /// @notice Tests cancelOrder revert notMaker
    function test_cancelOrder_revert_notMaker() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        vm.stopPrank();

        vm.startPrank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotMaker.selector, orderId, _taker, _maker));
        _board.cancelOrder(orderId);
        vm.stopPrank();
    }

    /// @notice Tests canFill
    function test_canFill() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        vm.stopPrank();

        assertTrue(_board.canFill(orderId));
    }

    /// @notice Tests canFill false notActive
    function test_canFill_false_notActive() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        _board.cancelOrder(orderId);
        vm.stopPrank();

        assertFalse(_board.canFill(orderId));
    }

    /// @notice Tests canFill false nonExistent
    function test_canFill_false_nonExistent() public view {
        assertFalse(_board.canFill(999));
    }

    /// @notice Tests getOrders
    function test_getOrders() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 3);

        uint256 order0 = _board.createOrder(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        uint256 order1 = _board.createOrder(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B * 2);
        uint256 order2 = _board.createOrder(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B * 3);
        vm.stopPrank();

        uint256[] memory ids = new uint256[](3);
        ids[0] = order0;
        ids[1] = order1;
        ids[2] = order2;

        ISwapboard.Order[] memory orders = _board.getOrders(ids);

        assertEq(orders.length, 3);
        assertEq(orders[0].amountB, AMOUNT_B);
        assertEq(orders[1].amountB, AMOUNT_B * 2);
        assertEq(orders[2].amountB, AMOUNT_B * 3);
    }

    /// @notice Tests getOrders empty
    function test_getOrders_empty() public view {
        uint256[] memory ids = new uint256[](0);
        ISwapboard.Order[] memory orders = _board.getOrders(ids);
        assertEq(orders.length, 0);
    }

    /// @notice Tests multipleOrders
    function test_multipleOrders() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 3);

        uint256 order0 = _board.createOrder(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        uint256 order1 = _board.createOrder(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B * 2);
        uint256 order2 = _board.createOrder(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B * 3);
        vm.stopPrank();

        assertEq(order0, 0);
        assertEq(order1, 1);
        assertEq(order2, 2);
        assertEq(_board.getNextOrderId(), 3);
    }

    /// @notice Tests filling an order as both _maker and _taker
    function test_selfFill() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        _tokenB.mint(_maker, AMOUNT_B);
        _tokenB.approve(address(_board), AMOUNT_B);

        uint256 orderId = _board.createOrder(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        _board.fillOrder(orderId, 0);
        vm.stopPrank();

        assertEq(_tokenA.balanceOf(_maker), AMOUNT_A * 10 - AMOUNT_A + AMOUNT_A);
        assertEq(_tokenB.balanceOf(_maker), AMOUNT_B * 10 + AMOUNT_B);
    }

    /// @notice Tests events orderCreated
    function test_events_orderCreated() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);

        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderCreated({
            orderId: 0,
            maker: _maker,
            tokenA: address(_tokenA),
            amountA: AMOUNT_A,
            tokenB: address(_tokenB),
            amountB: AMOUNT_B
        });

        _board.createOrder(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        vm.stopPrank();
    }

    /// @notice Tests events orderFilled
    function test_events_orderFilled() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);

        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderFilled({orderId: orderId, taker: _taker});

        _board.fillOrder(orderId, 0);
        vm.stopPrank();
    }

    /// @notice Tests events orderCanceled
    function test_events_orderCanceled() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);

        vm.expectEmit(true, false, false, true);
        emit ISwapboard.OrderCanceled({orderId: orderId});

        _board.cancelOrder(orderId);
        vm.stopPrank();
    }

    /// @notice Fuzz tests createOrder
    function testFuzz_createOrder(
        uint256 amountA,
        uint256 amountB
    ) public {
        amountA = bound(amountA, 1, type(uint128).max);
        amountB = bound(amountB, 1, type(uint128).max);

        _tokenA.mint(_maker, amountA);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), amountA);
        uint256 orderId = _board.createOrder(address(_tokenA), amountA, address(_tokenB), amountB);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertEq(order.amountA, amountA);
        assertEq(order.amountB, amountB);
    }

    /// @notice Fuzz tests fillOrder
    function testFuzz_fillOrder(
        uint256 amountA,
        uint256 amountB
    ) public {
        amountA = bound(amountA, 1, type(uint128).max);
        amountB = bound(amountB, 1, type(uint128).max);

        _tokenA.mint(_maker, amountA);
        _tokenB.mint(_taker, amountB);

        uint256 takerTokenABefore = _tokenA.balanceOf(_taker);
        uint256 makerTokenBBefore = _tokenB.balanceOf(_maker);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), amountA);
        uint256 orderId = _board.createOrder(address(_tokenA), amountA, address(_tokenB), amountB);
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), amountB);
        _board.fillOrder(orderId, 0);
        vm.stopPrank();

        assertEq(_tokenA.balanceOf(_taker), takerTokenABefore + amountA);
        assertEq(_tokenB.balanceOf(_maker), makerTokenBBefore + amountB);
    }

    /// @notice Tests fillOrder revert deadlineExpired
    function test_fillOrder_revert_deadlineExpired() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        vm.stopPrank();

        vm.warp(1000);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        vm.expectRevert(ISwapboard.DeadlineExpired.selector);
        _board.fillOrder(orderId, 999);
        vm.stopPrank();
    }

    /// @notice Tests fillOrder deadlineZero noExpiry
    function test_fillOrder_deadlineZero_noExpiry() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        vm.stopPrank();

        vm.warp(type(uint256).max);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _board.fillOrder(orderId, 0);
        vm.stopPrank();

        assertFalse(_board.getOrder(orderId).active);
    }

    // ============ createOrder with ETH as tokenA ============

    /// @notice Tests createOrder selling ETH
    function test_createOrder_sellEth() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B);

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertEq(order.maker, _maker);
        assertEq(order.tokenA, _eth);
        assertEq(order.amountA, ETH_AMOUNT);
        assertEq(order.tokenB, address(_tokenB));
        assertEq(order.amountB, AMOUNT_B);
        assertTrue(order.active);
        assertEq(orderId, 0);
        assertEq(_board.getNextOrderId(), 1);
        assertEq(address(_board).balance, ETH_AMOUNT);
    }

    /// @notice Tests createOrder selling ETH reverts on overpayment
    function test_createOrder_sellEth_revert_amountMismatch_tooHigh() public {
        vm.prank(_maker);
        vm.expectRevert(
            abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, ETH_AMOUNT, ETH_AMOUNT + 0.5 ether)
        );
        _board.createOrder{value: ETH_AMOUNT + 0.5 ether}(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B);
    }

    /// @notice Tests createOrder selling ETH reverts on underpayment
    function test_createOrder_sellEth_revert_amountMismatch() public {
        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, ETH_AMOUNT, ETH_AMOUNT - 1));
        _board.createOrder{value: ETH_AMOUNT - 1}(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B);
    }

    /// @notice Tests createOrder selling ETH emits OrderCreated
    function test_createOrder_sellEth_event() public {
        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderCreated({
            orderId: 0, maker: _maker, tokenA: _eth, amountA: ETH_AMOUNT, tokenB: address(_tokenB), amountB: AMOUNT_B
        });

        vm.prank(_maker);
        _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B);
    }

    /// @notice Tests createOrder selling ETH reverts on zero amount
    function test_createOrder_sellEth_revert_zeroAmount() public {
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.createOrder{value: 0}(_eth, 0, address(_tokenB), AMOUNT_B);
    }

    /// @notice Tests createOrder selling ETH reverts on zero address tokenB
    function test_createOrder_sellEth_revert_zeroAddress() public {
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.ZeroAddress.selector);
        _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(0), AMOUNT_B);
    }

    /// @notice Tests createOrder selling ETH reverts when tokenB is also ETH
    function test_createOrder_sellEth_revert_sameToken() public {
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.SameToken.selector);
        _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, _eth, AMOUNT_B);
    }

    /// @notice Tests createOrder selling ETH reverts when tokenB is an EOA
    function test_createOrder_sellEth_revert_notAContract() public {
        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotAContract.selector, address(0xDEAD)));
        _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(0xDEAD), AMOUNT_B);
    }

    /// @notice Tests createOrder selling ETH assigns sequential IDs
    function test_createOrder_sellEth_sequentialIds() public {
        vm.startPrank(_maker);
        uint256 id0 = _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B);
        uint256 id1 = _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B);
        vm.stopPrank();

        assertEq(id0, 0);
        assertEq(id1, 1);
        assertEq(address(_board).balance, 2 * ETH_AMOUNT);
    }

    /// @notice Tests createOrder with ERC20 reverts if ETH is sent
    function test_createOrder_erc20_revert_accidentalEth() public {
        vm.startPrank(_maker);
        _tokenB.approve(address(_board), AMOUNT_B);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, 0, 1 ether));
        _board.createOrder{value: 1 ether}(address(_tokenB), AMOUNT_B, address(_tokenA), 1 ether);
        vm.stopPrank();
    }

    // ============ fillOrder paying with ETH ============

    /// @notice Tests fillOrder when tokenB is ETH
    function test_fillOrder_payEth() public {
        vm.startPrank(_maker);
        _tokenB.approve(address(_board), AMOUNT_B);
        uint256 orderId = _board.createOrder(address(_tokenB), AMOUNT_B, _eth, ETH_AMOUNT);
        vm.stopPrank();

        uint256 makerEthBefore = _maker.balance;
        uint256 takerTokenBefore = _tokenB.balanceOf(_taker);

        vm.prank(_taker);
        _board.fillOrder{value: ETH_AMOUNT}(orderId, 0);

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(_maker.balance, makerEthBefore + ETH_AMOUNT);
        assertEq(_tokenB.balanceOf(_taker), takerTokenBefore + AMOUNT_B);
        assertEq(address(_board).balance, 0);
    }

    /// @notice Tests fillOrder paying ETH reverts on overpayment
    function test_fillOrder_payEth_revert_amountMismatch_tooHigh() public {
        vm.startPrank(_maker);
        _tokenB.approve(address(_board), AMOUNT_B);
        uint256 orderId = _board.createOrder(address(_tokenB), AMOUNT_B, _eth, ETH_AMOUNT);
        vm.stopPrank();

        vm.prank(_taker);
        vm.expectRevert(
            abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, ETH_AMOUNT, ETH_AMOUNT + 0.25 ether)
        );
        _board.fillOrder{value: ETH_AMOUNT + 0.25 ether}(orderId, 0);
    }

    /// @notice Tests fillOrder paying ETH emits OrderFilled
    function test_fillOrder_payEth_event() public {
        vm.startPrank(_maker);
        _tokenB.approve(address(_board), AMOUNT_B);
        uint256 orderId = _board.createOrder(address(_tokenB), AMOUNT_B, _eth, ETH_AMOUNT);
        vm.stopPrank();

        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderFilled({orderId: orderId, taker: _taker});

        vm.prank(_taker);
        _board.fillOrder{value: ETH_AMOUNT}(orderId, 0);
    }

    /// @notice Tests fillOrder paying ETH reverts on underpayment
    function test_fillOrder_payEth_revert_amountMismatch_tooLow() public {
        vm.startPrank(_maker);
        _tokenB.approve(address(_board), AMOUNT_B);
        uint256 orderId = _board.createOrder(address(_tokenB), AMOUNT_B, _eth, ETH_AMOUNT);
        vm.stopPrank();

        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, ETH_AMOUNT, ETH_AMOUNT - 1));
        _board.fillOrder{value: ETH_AMOUNT - 1}(orderId, 0);
    }

    /// @notice Tests fillOrder paying ETH reverts when order not found
    function test_fillOrder_payEth_revert_orderNotFound() public {
        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, 999));
        _board.fillOrder{value: ETH_AMOUNT}(999, 0);
    }

    /// @notice Tests fillOrder paying ETH reverts when order not active
    function test_fillOrder_payEth_revert_orderNotActive() public {
        vm.startPrank(_maker);
        _tokenB.approve(address(_board), AMOUNT_B);
        uint256 orderId = _board.createOrder(address(_tokenB), AMOUNT_B, _eth, ETH_AMOUNT);
        vm.stopPrank();

        vm.prank(_taker);
        _board.fillOrder{value: ETH_AMOUNT}(orderId, 0);

        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        _board.fillOrder{value: ETH_AMOUNT}(orderId, 0);
    }

    /// @notice Tests fillOrder paying ETH reverts after deadline
    function test_fillOrder_payEth_revert_deadlineExpired() public {
        vm.startPrank(_maker);
        _tokenB.approve(address(_board), AMOUNT_B);
        uint256 orderId = _board.createOrder(address(_tokenB), AMOUNT_B, _eth, ETH_AMOUNT);
        vm.stopPrank();

        vm.warp(1000);

        vm.prank(_taker);
        vm.expectRevert(ISwapboard.DeadlineExpired.selector);
        _board.fillOrder{value: ETH_AMOUNT}(orderId, 999);
    }

    /// @notice Tests fillOrder with ERC20 tokenB reverts if ETH is sent
    function test_fillOrder_erc20_revert_accidentalEth() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, 0, 0.1 ether));
        _board.fillOrder{value: 0.1 ether}(orderId, 0);
        vm.stopPrank();
    }

    // ============ cancelOrder returning ETH ============

    /// @notice Tests cancelOrder returns ETH to maker
    function test_cancelOrder_returnEth() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B);

        uint256 makerEthBefore = _maker.balance;

        vm.prank(_maker);
        _board.cancelOrder(orderId);

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(_maker.balance, makerEthBefore + ETH_AMOUNT);
        assertEq(address(_board).balance, 0);
    }

    /// @notice Tests cancelOrder returning ETH emits OrderCanceled
    function test_cancelOrder_returnEth_event() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B);

        vm.expectEmit(true, false, false, true);
        emit ISwapboard.OrderCanceled({orderId: orderId});

        vm.prank(_maker);
        _board.cancelOrder(orderId);
    }

    /// @notice Tests cancelOrder returning ETH reverts when not maker
    function test_cancelOrder_returnEth_revert_notMaker() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B);

        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotMaker.selector, orderId, _taker, _maker));
        _board.cancelOrder(orderId);
    }

    /// @notice Tests cancelOrder returning ETH reverts when order not found
    function test_cancelOrder_returnEth_revert_orderNotFound() public {
        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, 999));
        _board.cancelOrder(999);
    }

    /// @notice Tests cancelOrder returning ETH reverts when order not active
    function test_cancelOrder_returnEth_revert_orderNotActive() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B);

        vm.prank(_maker);
        _board.cancelOrder(orderId);

        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        _board.cancelOrder(orderId);
    }

    /// @notice Tests cancelOrder reverts when maker rejects ETH
    function test_cancelOrder_returnEth_revert_ethTransferFailed() public {
        ETHRejecter rejecter = new ETHRejecter();
        vm.deal(address(rejecter), 10 ether);

        vm.prank(address(rejecter));
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B);

        vm.prank(address(rejecter));
        vm.expectRevert(ETHRejecter.RejectETH.selector);
        _board.cancelOrder(orderId);
    }

    // ============ fillOrder receiving ETH ============

    /// @notice Tests fillOrder when tokenA is ETH
    function test_fillOrder_receiveEth() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B);

        uint256 takerEthBefore = _taker.balance;
        uint256 makerTokenBefore = _tokenB.balanceOf(_maker);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _board.fillOrder(orderId, 0);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(_taker.balance, takerEthBefore + ETH_AMOUNT);
        assertEq(_tokenB.balanceOf(_maker), makerTokenBefore + AMOUNT_B);
        assertEq(address(_board).balance, 0);
    }

    /// @notice Tests fillOrder receiving ETH emits OrderFilled
    function test_fillOrder_receiveEth_event() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);

        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderFilled({orderId: orderId, taker: _taker});
        _board.fillOrder(orderId, 0);
        vm.stopPrank();
    }

    /// @notice Tests fillOrder receiving ETH reverts when order not found
    function test_fillOrder_receiveEth_revert_orderNotFound() public {
        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, 999));
        _board.fillOrder(999, 0);
    }

    /// @notice Tests fillOrder receiving ETH reverts when order not active
    function test_fillOrder_receiveEth_revert_orderNotActive() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _board.fillOrder(orderId, 0);
        vm.stopPrank();

        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        _board.fillOrder(orderId, 0);
    }

    /// @notice Tests fillOrder receiving ETH reverts when taker rejects ETH
    function test_fillOrder_receiveEth_revert_ethTransferFailed() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B);

        ETHRejecter rejecter = new ETHRejecter();
        _tokenB.mint(address(rejecter), AMOUNT_B);

        vm.startPrank(address(rejecter));
        _tokenB.approve(address(_board), AMOUNT_B);
        vm.expectRevert(ETHRejecter.RejectETH.selector);
        _board.fillOrder(orderId, 0);
        vm.stopPrank();
    }

    /// @notice Tests fillOrder receiving ETH reverts after deadline
    function test_fillOrder_receiveEth_revert_deadlineExpired() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B);

        vm.warp(1000);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        vm.expectRevert(ISwapboard.DeadlineExpired.selector);
        _board.fillOrder(orderId, 999);
        vm.stopPrank();
    }

    // ============ No receive() ============

    /// @notice Tests plain ETH transfers to the contract revert (no receive/fallback)
    function test_plainEthTransfer_reverts() public {
        uint256 boardBefore = address(_board).balance;
        uint256 makerBefore = _maker.balance;

        vm.prank(_maker);
        (bool success,) = address(_board).call{value: 1 ether}("");

        assertFalse(success);
        assertEq(address(_board).balance, boardBefore);
        assertEq(_maker.balance, makerBefore);
    }

    // ============ Round-trips ============

    /// @notice Tests full ETH sell then ERC20 fill
    function test_roundTrip_sellEth_fillWithToken() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B);

        uint256 takerEthBefore = _taker.balance;

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _board.fillOrder(orderId, 0);
        vm.stopPrank();

        assertEq(_taker.balance, takerEthBefore + ETH_AMOUNT);
        assertEq(address(_board).balance, 0);
    }

    /// @notice Tests ETH sell then cancel returns ETH
    function test_roundTrip_sellEth_cancel() public {
        uint256 makerEthBefore = _maker.balance;

        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B);

        assertEq(_maker.balance, makerEthBefore - ETH_AMOUNT);

        vm.prank(_maker);
        _board.cancelOrder(orderId);

        assertEq(_maker.balance, makerEthBefore);
        assertEq(address(_board).balance, 0);
    }

    /// @notice Tests ERC20 sell filled with ETH
    function test_roundTrip_sellToken_fillWithEth() public {
        vm.startPrank(_maker);
        _tokenB.approve(address(_board), AMOUNT_B);
        uint256 orderId = _board.createOrder(address(_tokenB), AMOUNT_B, _eth, ETH_AMOUNT);
        vm.stopPrank();

        uint256 makerEthBefore = _maker.balance;
        uint256 takerTokenBefore = _tokenB.balanceOf(_taker);

        vm.prank(_taker);
        _board.fillOrder{value: ETH_AMOUNT}(orderId, 0);

        assertEq(_maker.balance, makerEthBefore + ETH_AMOUNT);
        assertEq(_tokenB.balanceOf(_taker), takerTokenBefore + AMOUNT_B);
    }

    /// @notice Tests multiple ETH sell orders can coexist
    function test_multipleEthOrders() public {
        vm.startPrank(_maker);
        uint256 id0 = _board.createOrder{value: 1 ether}(_eth, 1 ether, address(_tokenB), AMOUNT_B);
        uint256 id1 = _board.createOrder{value: 2 ether}(_eth, 2 ether, address(_tokenB), AMOUNT_B);
        uint256 id2 = _board.createOrder{value: 3 ether}(_eth, 3 ether, address(_tokenB), AMOUNT_B);
        vm.stopPrank();

        assertEq(address(_board).balance, 6 ether);

        vm.prank(_maker);
        _board.cancelOrder(id1);

        assertEq(address(_board).balance, 4 ether);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _board.fillOrder(id0, 0);
        vm.stopPrank();

        assertEq(address(_board).balance, 3 ether);
        assertTrue(_board.canFill(id2));
        assertFalse(_board.canFill(id0));
        assertFalse(_board.canFill(id1));
    }

    // ============ Fuzz tests ============

    /// @notice Fuzz tests createOrder selling ETH
    function testFuzz_createOrder_sellEth(
        uint256 ethAmount,
        uint256 amountB
    ) public {
        ethAmount = bound(ethAmount, 1, 100 ether);
        amountB = bound(amountB, 1, 1e30);

        vm.deal(_maker, ethAmount + 1 ether);

        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ethAmount}(_eth, ethAmount, address(_tokenB), amountB);

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertEq(order.amountA, ethAmount);
        assertEq(order.amountB, amountB);
        assertEq(order.tokenA, _eth);
        assertEq(address(_board).balance, ethAmount);
    }

    /// @notice Fuzz tests createOrder selling ETH reverts on excess msg.value
    function testFuzz_createOrder_sellEth_revert_excess(
        uint256 ethAmount,
        uint256 excess
    ) public {
        ethAmount = bound(ethAmount, 1, 50 ether);
        excess = bound(excess, 1, 50 ether);

        vm.deal(_maker, ethAmount + excess);

        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, ethAmount, ethAmount + excess));
        _board.createOrder{value: ethAmount + excess}(_eth, ethAmount, address(_tokenB), AMOUNT_B);
    }

    /// @notice Fuzz tests fillOrder paying with ETH
    function testFuzz_fillOrder_payEth(
        uint256 tokenAmount,
        uint256 ethAmount
    ) public {
        tokenAmount = bound(tokenAmount, 1, 1e30);
        ethAmount = bound(ethAmount, 1, 100 ether);

        _tokenB.mint(_maker, tokenAmount);
        vm.deal(_taker, ethAmount + 1 ether);

        uint256 makerEthBefore = _maker.balance;
        uint256 takerTokenBefore = _tokenB.balanceOf(_taker);

        vm.startPrank(_maker);
        _tokenB.approve(address(_board), tokenAmount);
        uint256 orderId = _board.createOrder(address(_tokenB), tokenAmount, _eth, ethAmount);
        vm.stopPrank();

        vm.prank(_taker);
        _board.fillOrder{value: ethAmount}(orderId, 0);

        assertEq(_maker.balance, makerEthBefore + ethAmount);
        assertEq(_tokenB.balanceOf(_taker), takerTokenBefore + tokenAmount);
    }

    /// @notice Fuzz tests cancelOrder returning ETH
    function testFuzz_cancelOrder_returnEth(
        uint256 ethAmount
    ) public {
        ethAmount = bound(ethAmount, 1, 100 ether);
        vm.deal(_maker, ethAmount);

        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ethAmount}(_eth, ethAmount, address(_tokenB), AMOUNT_B);

        uint256 makerEthBefore = _maker.balance;

        vm.prank(_maker);
        _board.cancelOrder(orderId);

        assertEq(_maker.balance, makerEthBefore + ethAmount);
    }

    /// @notice Fuzz tests fillOrder receiving ETH
    function testFuzz_fillOrder_receiveEth(
        uint256 ethAmount,
        uint256 tokenAmount
    ) public {
        ethAmount = bound(ethAmount, 1, 100 ether);
        tokenAmount = bound(tokenAmount, 1, 1e30);

        vm.deal(_maker, ethAmount);
        _tokenB.mint(_taker, tokenAmount);

        uint256 takerEthBefore = _taker.balance;
        uint256 makerTokenBefore = _tokenB.balanceOf(_maker);

        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ethAmount}(_eth, ethAmount, address(_tokenB), tokenAmount);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), tokenAmount);
        _board.fillOrder(orderId, 0);
        vm.stopPrank();

        assertEq(_taker.balance, takerEthBefore + ethAmount);
        assertEq(_tokenB.balanceOf(_maker), makerTokenBefore + tokenAmount);
    }
}
