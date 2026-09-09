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
import {stdError} from "forge-std/StdError.sol";
import {stdStorage, StdStorage} from "forge-std/StdStorage.sol";
import {Swapboard} from "../src/Swapboard.sol";
import {ISwapboard} from "../src/interfaces/ISwapboard.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockFOT} from "./mocks/MockFOT.sol";
import {MockRevertOnZeroERC20} from "./mocks/MockRevertOnZeroERC20.sol";
import {ETHRejecter} from "./mocks/ETHRejecter.sol";
import {FillTestLib} from "./helpers/FillTestLib.sol";
import {OrderTestLib} from "./helpers/OrderTestLib.sol";

/// @notice Unit tests for Swapboard contract
/// @dev Uses Foundry's Test framework with MockERC20 tokens
contract SwapboardTest is Test {
    using stdStorage for StdStorage;

    StdStorage private _stdstore;

    Swapboard internal _board;
    MockERC20 internal _tokenA;
    MockERC20 internal _tokenB;

    address internal _eth;
    address internal _maker = address(0x1);
    address internal _taker = address(0x2);

    uint128 private constant AMOUNT_A = 100 ether;
    uint128 private constant AMOUNT_B = 250_000e6;
    uint128 private constant ETH_AMOUNT = 1 ether;

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

    function _fillOrder(
        uint256 orderId,
        uint128 amountA
    ) private {
        FillTestLib.fill(_board, orderId, amountA);
    }

    function _fillOrder(
        uint256 orderId,
        uint128 amountA,
        uint256 deadline
    ) private {
        ISwapboard.Order memory order = _board.getOrder(orderId);
        FillTestLib.fill(_board, orderId, amountA, FillTestLib.quoteAmountB(order, amountA), deadline);
    }

    function _fillOrderQuoted(
        ISwapboard.Order memory order,
        uint256 orderId,
        uint128 amountA
    ) private {
        FillTestLib.fill(_board, order, orderId, amountA);
    }

    function _fillOrderQuoted(
        ISwapboard.Order memory order,
        uint256 orderId,
        uint128 amountA,
        uint256 deadline
    ) private {
        FillTestLib.fill(_board, order, orderId, amountA, deadline);
    }

    function _fillOrderPayEth(
        uint256 orderId,
        uint128 amountA,
        uint128 minAmountB
    ) private {
        FillTestLib.fillPayEth(_board, orderId, amountA, minAmountB);
    }

    function _fillOrderPayEth(
        uint256 orderId,
        uint128 amountA,
        uint128 minAmountB,
        uint256 deadline
    ) private {
        FillTestLib.fillPayEth(_board, orderId, amountA, minAmountB, deadline);
    }

    /// @notice Net amount after MockFOT's 5% fee (matches `transfer` / `transferFrom`)
    function _fotNet(
        uint256 gross
    ) private pure returns (uint256) {
        return gross - (gross * 5) / 100;
    }

    function _tf(
        MockERC20 token
    ) private view returns (uint256) {
        return token.getTransferFromCalls();
    }

    function _modify(
        uint128 availableA,
        uint128 availableB
    ) private pure returns (ISwapboard.ModifyOrderParams memory) {
        return ISwapboard.ModifyOrderParams({availableA: availableA, availableB: availableB});
    }

    function _amounts(
        ISwapboard.Order memory order
    ) private pure returns (ISwapboard.OrderAmounts memory) {
        return ISwapboard.OrderAmounts({
            amountA: order.amountA, amountB: order.amountB, availableA: order.availableA, availableB: order.availableB
        });
    }

    function _modItem(
        uint256 orderId,
        ISwapboard.Order memory snapshot,
        uint128 availableA,
        uint128 availableB
    ) private pure returns (ISwapboard.ModifyOrdersParams memory) {
        return ISwapboard.ModifyOrdersParams({
            orderId: orderId, previousAmounts: _amounts(snapshot), updatedOrder: _modify(availableA, availableB)
        });
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
        uint256 order0 = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        assertEq(order0, 0);
        assertEq(_board.getNextOrderId(), 1);

        uint256 order1 = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        assertEq(order1, 1);
        assertEq(_board.getNextOrderId(), 2);
    }

    /// @notice getOrder returns full order details for an existing order
    function test_getOrder() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertEq(order.maker, _maker);
        assertEq(order.tokenA, address(_tokenA));
        assertEq(order.amountA, AMOUNT_A);
        assertEq(order.tokenB, address(_tokenB));
        assertEq(order.amountB, AMOUNT_B);
        assertEq(order.availableA, AMOUNT_A);
        assertEq(order.availableB, AMOUNT_B);
        assertTrue(order.active);
        assertFalse(order.partialFillAllowed);
    }

    /// @notice getOrder returns empty defaults for a non-existent order
    function test_getOrder_nonExistent() public view {
        ISwapboard.Order memory order = _board.getOrder(999);
        assertEq(order.maker, address(0));
        assertEq(order.tokenA, address(0));
        assertEq(order.amountA, 0);
        assertEq(order.tokenB, address(0));
        assertEq(order.amountB, 0);
        assertEq(order.availableA, 0);
        assertEq(order.availableB, 0);
        assertFalse(order.active);
        assertFalse(order.partialFillAllowed);
    }

    /// @notice Tests createOrder
    function test_createOrder() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);

        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        assertEq(orderId, 0);
        assertEq(_board.getNextOrderId(), 1);

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertEq(order.maker, _maker);
        assertEq(order.tokenA, address(_tokenA));
        assertEq(order.amountA, AMOUNT_A);
        assertEq(order.tokenB, address(_tokenB));
        assertEq(order.amountB, AMOUNT_B);
        assertEq(order.availableA, AMOUNT_A);
        assertEq(order.availableB, AMOUNT_B);
        assertTrue(order.active);
        assertFalse(order.partialFillAllowed);

        assertEq(_tf(_tokenA), 1);
        assertEq(_tokenA.balanceOf(address(_board)), AMOUNT_A);
        assertEq(_tokenA.balanceOf(_maker), AMOUNT_A * 10 - AMOUNT_A);
    }

    /// @notice Tests createOrder stores partialFillAllowed=true
    function test_createOrder_partialFillAllowed_true() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertTrue(order.partialFillAllowed);
        assertTrue(order.active);
        assertEq(_tf(_tokenA), 1);
    }

    /// @notice Tests createOrder stores partialFillAllowed=false
    function test_createOrder_partialFillAllowed_false() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertTrue(order.active);
        assertEq(order.availableA, AMOUNT_A);
        assertFalse(order.partialFillAllowed);
        assertEq(_tf(_tokenA), 1);
    }

    /// @notice Tests OrderCreated includes partialFillAllowed=true
    function test_events_orderCreated_partialFillAllowed_true() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);

        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderCreated({
            orderId: 0,
            maker: _maker,
            tokenA: address(_tokenA),
            amountA: AMOUNT_A,
            tokenB: address(_tokenB),
            amountB: AMOUNT_B,
            partialFillAllowed: true
        });

        _board.createOrder(_orderPartial(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        assertEq(_tf(_tokenA), 1);
    }

    /// @notice Tests ETH sell order stores partialFillAllowed
    function test_createOrder_sellEth_partialFillAllowed_true() public {
        vm.prank(_maker);
        uint256 orderId =
            _board.createOrder{value: ETH_AMOUNT}(_orderPartial(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertTrue(order.partialFillAllowed);
        assertEq(order.tokenA, _eth);
        assertEq(order.amountA, ETH_AMOUNT);
    }

    /// @notice Tests createOrder revert zeroAddress _tokenA
    function test_createOrder_revert_zeroAddress_tokenA() public {
        vm.startPrank(_maker);
        vm.expectRevert(ISwapboard.ZeroAddress.selector);
        _board.createOrder(_order(address(0), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();
    }

    /// @notice Tests createOrder revert zeroAddress _tokenB
    function test_createOrder_revert_zeroAddress_tokenB() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        vm.expectRevert(ISwapboard.ZeroAddress.selector);
        _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(0), AMOUNT_B));
        vm.stopPrank();
    }

    /// @notice Tests createOrder revert zeroAmount amountA
    function test_createOrder_revert_zeroAmount_amountA() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.createOrder(_order(address(_tokenA), 0, address(_tokenB), AMOUNT_B));
        vm.stopPrank();
    }

    /// @notice Tests createOrder revert zeroAmount amountB
    function test_createOrder_revert_zeroAmount_amountB() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), 0));
        vm.stopPrank();
    }

    /// @notice Tests createOrder revert sameToken
    function test_createOrder_revert_sameToken() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        vm.expectRevert(ISwapboard.SameToken.selector);
        _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenA), AMOUNT_B));
        vm.stopPrank();
    }

    /// @notice Tests createOrder revert notAContract _tokenA
    function test_createOrder_revert_notAContract_tokenA() public {
        vm.startPrank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotAContract.selector, address(0x999)));
        _board.createOrder(_order(address(0x999), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();
    }

    /// @notice Tests createOrder revert notAContract _tokenB
    function test_createOrder_revert_notAContract_tokenB() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotAContract.selector, address(0x999)));
        _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(0x999), AMOUNT_B));
        vm.stopPrank();
    }

    /// @notice Tests createOrder revert FOT
    function test_createOrder_revert_FOT() public {
        MockFOT fot = new MockFOT();
        fot.mint(_maker, 1000 ether);

        vm.startPrank(_maker);
        fot.approve(address(_board), 100 ether);

        vm.expectRevert(abi.encodeWithSelector(ISwapboard.BalanceMismatch.selector, 100 ether, 95 ether));
        _board.createOrder(_order(address(fot), 100 ether, address(_tokenB), AMOUNT_B));
        vm.stopPrank();
    }

    /// @notice Tests fillOrder
    function test_fillOrder() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        uint256 tokenAPullsBefore = _tf(_tokenA);
        uint256 tokenBPullsBefore = _tf(_tokenB);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _fillOrder(orderId, AMOUNT_A);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(order.availableA, 0);
        assertEq(_tf(_tokenA), tokenAPullsBefore);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 1);
        assertEq(_tokenA.balanceOf(_taker), AMOUNT_A * 10 + AMOUNT_A);
        assertEq(_tokenB.balanceOf(_maker), AMOUNT_B * 10 + AMOUNT_B);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
    }

    /// @notice Tests fillOrder revert orderNotFound
    function test_fillOrder_revert_orderNotFound() public {
        vm.startPrank(_taker);
        ISwapboard.Order memory order = _board.getOrder(999);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, 999));
        _fillOrderQuoted(order, 999, 1);
        vm.stopPrank();
    }

    /// @notice Tests fillOrder revert orderNotActive
    function test_fillOrder_revert_orderNotActive() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _fillOrder(orderId, AMOUNT_A);

        ISwapboard.Order memory order = _board.getOrder(orderId);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        _fillOrderQuoted(order, orderId, AMOUNT_A);
        vm.stopPrank();
    }

    /// @notice Tests cancelOrder
    function test_cancelOrder() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));

        uint256 balanceBefore = _tokenA.balanceOf(_maker);
        _board.cancelOrder(orderId);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(order.availableA, 0);
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

    /// @notice Tests cancelOrder revert orderNotFound after a prior cancel
    function test_cancelOrder_revert_orderNotFound_afterCancel() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        _board.cancelOrder(orderId);

        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, orderId));
        _board.cancelOrder(orderId);
        vm.stopPrank();
    }

    /// @notice Tests cancelOrder revert notMaker
    function test_cancelOrder_revert_notMaker() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
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
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        assertTrue(_board.canFill(orderId));
    }

    /// @notice Tests canFill false notActive
    function test_canFill_false_notActive() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
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

        uint256 order0 = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        uint256 order1 = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B * 2));
        uint256 order2 = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B * 3));
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

        uint256 order0 = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        uint256 order1 = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B * 2));
        uint256 order2 = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B * 3));
        vm.stopPrank();

        assertEq(order0, 0);
        assertEq(order1, 1);
        assertEq(order2, 2);
        assertEq(_board.getNextOrderId(), 3);
    }

    /// @notice Tests multiple same-pair orders can all be filled in reverse order
    function test_multipleOrdersSameTokenPair() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 5);

        uint256[] memory orderIds = new uint256[](5);
        for (uint256 i = 0; i < 5; ++i) {
            orderIds[i] = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        }
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B * 5);
        uint256 takerABefore = _tokenA.balanceOf(_taker);
        uint256 makerBBefore = _tokenB.balanceOf(_maker);
        for (uint256 i = 5; i > 0; --i) {
            ISwapboard.Order memory order = _board.getOrder(orderIds[i - 1]);
            _fillOrderQuoted(order, orderIds[i - 1], AMOUNT_A);
        }
        vm.stopPrank();

        assertEq(_tokenA.balanceOf(address(_board)), 0);
        assertEq(_tokenA.balanceOf(_taker), takerABefore + AMOUNT_A * 5);
        assertEq(_tokenB.balanceOf(_maker), makerBBefore + AMOUNT_B * 5);
        for (uint256 i = 0; i < 5; ++i) {
            assertFalse(_board.getOrder(orderIds[i]).active);
            assertEq(_board.getOrder(orderIds[i]).availableA, 0);
        }
    }

    /// @notice Tests filling an order as both _maker and _taker
    function test_selfFill() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        _tokenB.mint(_maker, AMOUNT_B);
        _tokenB.approve(address(_board), AMOUNT_B);

        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        uint256 tokenAPullsBefore = _tf(_tokenA);
        uint256 tokenBPullsBefore = _tf(_tokenB);
        _fillOrder(orderId, AMOUNT_A);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(order.availableA, 0);
        assertEq(_tf(_tokenA), tokenAPullsBefore);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 1);
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
            amountB: AMOUNT_B,
            partialFillAllowed: false
        });

        _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        assertEq(_tf(_tokenA), 1);
    }

    /// @notice Tests events orderFilled
    function test_events_orderFilled() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        uint256 tokenAPullsBefore = _tf(_tokenA);
        uint256 tokenBPullsBefore = _tf(_tokenB);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);

        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderFilled({orderId: orderId, taker: _taker, amountA: AMOUNT_A, amountB: AMOUNT_B});

        _fillOrder(orderId, AMOUNT_A);
        vm.stopPrank();

        assertFalse(_board.getOrder(orderId).active);
        assertEq(_board.getOrder(orderId).availableA, 0);
        assertEq(_tf(_tokenA), tokenAPullsBefore);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 1);
    }

    /// @notice Tests events orderCanceled
    function test_events_orderCanceled() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));

        vm.expectEmit(true, false, false, true);
        emit ISwapboard.OrderCanceled({orderId: orderId});

        _board.cancelOrder(orderId);
        vm.stopPrank();
    }

    /// @notice Fuzz tests createOrder
    function testFuzz_createOrder(
        uint256 amountASeed,
        uint256 amountBSeed
    ) public {
        // casting to 'uint128' is safe because bound is capped at uint128.max
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountA = uint128(bound(amountASeed, 1, type(uint128).max));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountB = uint128(bound(amountBSeed, 1, type(uint128).max));

        _tokenA.mint(_maker, amountA);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), amountA);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), amountA, address(_tokenB), amountB));
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertEq(order.amountA, amountA);
        assertEq(order.amountB, amountB);
        assertEq(order.availableA, amountA);
        assertEq(order.availableB, amountB);
        assertEq(_tf(_tokenA), 1);
    }

    /// @notice Fuzz tests fillOrder
    function testFuzz_fillOrder(
        uint256 amountASeed,
        uint256 amountBSeed
    ) public {
        // casting to 'uint128' is safe because bound is capped at uint128.max
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountA = uint128(bound(amountASeed, 1, type(uint128).max));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountB = uint128(bound(amountBSeed, 1, type(uint128).max));

        _tokenA.mint(_maker, amountA);
        _tokenB.mint(_taker, amountB);

        uint256 takerTokenABefore = _tokenA.balanceOf(_taker);
        uint256 makerTokenBBefore = _tokenB.balanceOf(_maker);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), amountA);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), amountA, address(_tokenB), amountB));
        vm.stopPrank();

        uint256 tokenAPullsBefore = _tf(_tokenA);
        uint256 tokenBPullsBefore = _tf(_tokenB);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), amountB);
        _fillOrder(orderId, amountA);
        vm.stopPrank();

        assertFalse(_board.getOrder(orderId).active);
        assertEq(_board.getOrder(orderId).availableA, 0);
        assertEq(_tf(_tokenA), tokenAPullsBefore);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 1);
        assertEq(_tokenA.balanceOf(_taker), takerTokenABefore + amountA);
        assertEq(_tokenB.balanceOf(_maker), makerTokenBBefore + amountB);
    }

    /// @notice Tests fillOrder revert deadlineExpired
    function test_fillOrder_revert_deadlineExpired() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        vm.warp(1000);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        ISwapboard.Order memory order = _board.getOrder(orderId);
        vm.expectRevert(ISwapboard.DeadlineExpired.selector);
        _fillOrderQuoted(order, orderId, AMOUNT_A, 999);
        vm.stopPrank();
    }

    /// @notice Tests fillOrder deadlineZero noExpiry
    function test_fillOrder_deadlineZero_noExpiry() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        vm.warp(type(uint256).max);

        uint256 tokenAPullsBefore = _tf(_tokenA);
        uint256 tokenBPullsBefore = _tf(_tokenB);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _fillOrder(orderId, AMOUNT_A);
        vm.stopPrank();

        assertFalse(_board.getOrder(orderId).active);
        assertEq(_board.getOrder(orderId).availableA, 0);
        assertEq(_tf(_tokenA), tokenAPullsBefore);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 1);
    }

    /// @notice Tests fillOrder succeeds when block.timestamp equals deadline
    function test_fillOrder_deadlineEqual_succeeds() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        uint256 deadline = 1000;
        vm.warp(deadline);

        uint256 tokenAPullsBefore = _tf(_tokenA);
        uint256 tokenBPullsBefore = _tf(_tokenB);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _fillOrder(orderId, AMOUNT_A, deadline);
        vm.stopPrank();

        assertFalse(_board.getOrder(orderId).active);
        assertEq(_board.getOrder(orderId).availableA, 0);
        assertEq(_tf(_tokenA), tokenAPullsBefore);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 1);
    }

    // ============ createOrder with ETH as tokenA ============

    /// @notice Tests createOrder selling ETH
    function test_createOrder_sellEth() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));

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
        _board.createOrder{value: ETH_AMOUNT + 0.5 ether}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));
    }

    /// @notice Tests createOrder selling ETH reverts on underpayment
    function test_createOrder_sellEth_revert_amountMismatch() public {
        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, ETH_AMOUNT, ETH_AMOUNT - 1));
        _board.createOrder{value: ETH_AMOUNT - 1}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));
    }

    /// @notice Tests createOrder selling ETH emits OrderCreated
    function test_createOrder_sellEth_event() public {
        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderCreated({
            orderId: 0,
            maker: _maker,
            tokenA: _eth,
            amountA: ETH_AMOUNT,
            tokenB: address(_tokenB),
            amountB: AMOUNT_B,
            partialFillAllowed: false
        });

        vm.prank(_maker);
        _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));
    }

    /// @notice Tests createOrder selling ETH reverts on zero amount
    function test_createOrder_sellEth_revert_zeroAmount() public {
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.createOrder{value: 0}(_order(_eth, 0, address(_tokenB), AMOUNT_B));
    }

    /// @notice Tests createOrder selling ETH reverts on zero amountB
    function test_createOrder_sellEth_revert_zeroAmount_amountB() public {
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), 0));
    }

    /// @notice Tests createOrder selling ETH reverts on zero address tokenB
    function test_createOrder_sellEth_revert_zeroAddress() public {
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.ZeroAddress.selector);
        _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(0), AMOUNT_B));
    }

    /// @notice Tests createOrder selling ETH reverts when tokenB is also ETH
    function test_createOrder_sellEth_revert_sameToken() public {
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.SameToken.selector);
        _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, _eth, AMOUNT_B));
    }

    /// @notice Tests createOrder selling ETH reverts when tokenB is an EOA
    function test_createOrder_sellEth_revert_notAContract() public {
        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotAContract.selector, address(0xDEAD)));
        _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(0xDEAD), AMOUNT_B));
    }

    /// @notice Tests createOrder selling ETH assigns sequential IDs
    function test_createOrder_sellEth_sequentialIds() public {
        vm.startPrank(_maker);
        uint256 id0 = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));
        uint256 id1 = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));
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
        _board.createOrder{value: 1 ether}(_order(address(_tokenB), AMOUNT_B, address(_tokenA), 1 ether));
        vm.stopPrank();
    }

    /// @notice Tests createOrder wanting ETH reverts if ETH is sent on create
    function test_createOrder_wantEth_revert_accidentalEth() public {
        vm.startPrank(_maker);
        _tokenB.approve(address(_board), AMOUNT_B);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, 0, 1 ether));
        _board.createOrder{value: 1 ether}(_order(address(_tokenB), AMOUNT_B, _eth, ETH_AMOUNT));
        vm.stopPrank();
    }

    /// @notice Tests maker can self-fill an ETH sell order
    function test_selfFill_sellEth() public {
        uint256 makerEthBefore = _maker.balance;
        uint256 makerTokenBefore = _tokenB.balanceOf(_maker);

        vm.startPrank(_maker);
        _tokenB.approve(address(_board), AMOUNT_B);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));
        uint256 tokenBPullsBefore = _tf(_tokenB);
        ISwapboard.Order memory order = _board.getOrder(orderId);
        _fillOrderQuoted(order, orderId, ETH_AMOUNT);
        vm.stopPrank();

        assertFalse(_board.canFill(orderId));
        assertFalse(_board.getOrder(orderId).active);
        assertEq(_board.getOrder(orderId).availableA, 0);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 1);
        assertEq(address(_board).balance, 0);
        assertEq(_maker.balance, makerEthBefore);
        assertEq(_tokenB.balanceOf(_maker), makerTokenBefore);
    }

    /// @notice Tests maker can self-fill an order paid in ETH
    function test_selfFill_payEth() public {
        uint256 makerEthBefore = _maker.balance;
        uint256 makerTokenBefore = _tokenB.balanceOf(_maker);

        vm.startPrank(_maker);
        _tokenB.approve(address(_board), AMOUNT_B);
        uint256 orderId = _board.createOrder(_order(address(_tokenB), AMOUNT_B, _eth, ETH_AMOUNT));
        _fillOrderPayEth(orderId, AMOUNT_B, ETH_AMOUNT, 0);
        vm.stopPrank();

        assertFalse(_board.canFill(orderId));
        assertFalse(_board.getOrder(orderId).active);
        assertEq(_board.getOrder(orderId).availableA, 0);
        assertEq(_tokenB.balanceOf(_maker), makerTokenBefore);
        assertEq(_maker.balance, makerEthBefore);
    }

    /// @notice Tests ETH sell order views: getOrder, canFill, getOrders
    function test_views_sellEthOrder() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertEq(order.maker, _maker);
        assertEq(order.tokenA, _eth);
        assertEq(order.amountA, ETH_AMOUNT);
        assertEq(order.tokenB, address(_tokenB));
        assertEq(order.amountB, AMOUNT_B);
        assertTrue(order.active);
        assertTrue(_board.canFill(orderId));

        uint256[] memory ids = new uint256[](1);
        ids[0] = orderId;
        ISwapboard.Order[] memory orders = _board.getOrders(ids);
        assertEq(orders.length, 1);
        assertEq(orders[0].tokenA, _eth);
        assertEq(orders[0].amountA, ETH_AMOUNT);
    }

    // ============ fillOrder paying with ETH ============

    /// @notice Tests fillOrder when tokenB is ETH
    function test_fillOrder_payEth() public {
        vm.startPrank(_maker);
        _tokenB.approve(address(_board), AMOUNT_B);
        uint256 orderId = _board.createOrder(_order(address(_tokenB), AMOUNT_B, _eth, ETH_AMOUNT));
        vm.stopPrank();

        uint256 makerEthBefore = _maker.balance;
        uint256 takerTokenBefore = _tokenB.balanceOf(_taker);

        vm.prank(_taker);
        _fillOrderPayEth(orderId, AMOUNT_B, ETH_AMOUNT, 0);

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(order.availableA, 0);
        assertEq(_maker.balance, makerEthBefore + ETH_AMOUNT);
        assertEq(_tokenB.balanceOf(_taker), takerTokenBefore + AMOUNT_B);
        assertEq(address(_board).balance, 0);
    }

    /// @notice Tests fillOrder paying ETH reverts on overpayment
    function test_fillOrder_payEth_revert_amountMismatch_tooHigh() public {
        vm.startPrank(_maker);
        _tokenB.approve(address(_board), AMOUNT_B);
        uint256 orderId = _board.createOrder(_order(address(_tokenB), AMOUNT_B, _eth, ETH_AMOUNT));
        vm.stopPrank();

        vm.prank(_taker);
        vm.expectRevert(
            abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, ETH_AMOUNT, ETH_AMOUNT + 0.25 ether)
        );
        _board.fillOrder{value: ETH_AMOUNT + 0.25 ether}(orderId, AMOUNT_B, ETH_AMOUNT, 0);
    }

    /// @notice Tests fillOrder paying ETH emits OrderFilled
    function test_fillOrder_payEth_event() public {
        vm.startPrank(_maker);
        _tokenB.approve(address(_board), AMOUNT_B);
        uint256 orderId = _board.createOrder(_order(address(_tokenB), AMOUNT_B, _eth, ETH_AMOUNT));
        vm.stopPrank();

        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderFilled({orderId: orderId, taker: _taker, amountA: AMOUNT_B, amountB: ETH_AMOUNT});

        vm.prank(_taker);
        _fillOrderPayEth(orderId, AMOUNT_B, ETH_AMOUNT, 0);

        assertFalse(_board.getOrder(orderId).active);
        assertEq(_board.getOrder(orderId).availableA, 0);
    }

    /// @notice Tests fillOrder paying ETH reverts on underpayment
    function test_fillOrder_payEth_revert_amountMismatch_tooLow() public {
        vm.startPrank(_maker);
        _tokenB.approve(address(_board), AMOUNT_B);
        uint256 orderId = _board.createOrder(_order(address(_tokenB), AMOUNT_B, _eth, ETH_AMOUNT));
        vm.stopPrank();

        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, ETH_AMOUNT, ETH_AMOUNT - 1));
        _board.fillOrder{value: ETH_AMOUNT - 1}(orderId, AMOUNT_B, ETH_AMOUNT, 0);
    }

    /// @notice Tests fillOrder paying ETH reverts when quoted payment is below the taker minimum
    function test_fillOrder_payEth_revert_fillAmountMismatch() public {
        vm.startPrank(_maker);
        _tokenB.approve(address(_board), AMOUNT_B);
        uint256 orderId = _board.createOrder(_order(address(_tokenB), AMOUNT_B, _eth, ETH_AMOUNT));
        vm.stopPrank();

        vm.startPrank(_taker);
        vm.expectRevert(
            abi.encodeWithSelector(ISwapboard.FillAmountMismatch.selector, orderId, ETH_AMOUNT, ETH_AMOUNT + 1)
        );
        _board.fillOrder{value: ETH_AMOUNT}(orderId, AMOUNT_B, ETH_AMOUNT + 1, 0);
        vm.stopPrank();

        assertTrue(_board.canFill(orderId));
    }

    /// @notice Tests fillOrder paying ETH reverts when order not found
    function test_fillOrder_payEth_revert_orderNotFound() public {
        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, 999));
        _fillOrderPayEth(999, ETH_AMOUNT, ETH_AMOUNT, 0);
    }

    /// @notice Tests fillOrder paying ETH reverts when order not active
    function test_fillOrder_payEth_revert_orderNotActive() public {
        vm.startPrank(_maker);
        _tokenB.approve(address(_board), AMOUNT_B);
        uint256 orderId = _board.createOrder(_order(address(_tokenB), AMOUNT_B, _eth, ETH_AMOUNT));
        vm.stopPrank();

        vm.prank(_taker);
        _fillOrderPayEth(orderId, AMOUNT_B, ETH_AMOUNT, 0);

        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        _fillOrderPayEth(orderId, AMOUNT_B, ETH_AMOUNT, 0);
    }

    /// @notice Tests fillOrder paying ETH reverts after deadline
    function test_fillOrder_payEth_revert_deadlineExpired() public {
        vm.startPrank(_maker);
        _tokenB.approve(address(_board), AMOUNT_B);
        uint256 orderId = _board.createOrder(_order(address(_tokenB), AMOUNT_B, _eth, ETH_AMOUNT));
        vm.stopPrank();

        vm.warp(1000);

        vm.prank(_taker);
        vm.expectRevert(ISwapboard.DeadlineExpired.selector);
        _fillOrderPayEth(orderId, AMOUNT_B, ETH_AMOUNT, 999);
    }

    /// @notice Tests fillOrder paying ETH succeeds when timestamp equals deadline
    function test_fillOrder_payEth_deadlineEqual_succeeds() public {
        vm.startPrank(_maker);
        _tokenB.approve(address(_board), AMOUNT_B);
        uint256 orderId = _board.createOrder(_order(address(_tokenB), AMOUNT_B, _eth, ETH_AMOUNT));
        vm.stopPrank();

        uint256 deadline = 1000;
        vm.warp(deadline);

        vm.prank(_taker);
        _fillOrderPayEth(orderId, AMOUNT_B, ETH_AMOUNT, deadline);

        assertFalse(_board.canFill(orderId));
        assertFalse(_board.getOrder(orderId).active);
        assertEq(_board.getOrder(orderId).availableA, 0);
    }

    /// @notice Tests fillOrder with ERC20 tokenB reverts if ETH is sent
    function test_fillOrder_erc20_revert_accidentalEth() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, 0, 0.1 ether));
        _board.fillOrder{value: 0.1 ether}(orderId, AMOUNT_A, AMOUNT_B, 0);
        vm.stopPrank();
    }

    // ============ cancelOrder returning ETH ============

    /// @notice Tests cancelOrder returns ETH to maker
    function test_cancelOrder_returnEth() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));

        uint256 makerEthBefore = _maker.balance;

        vm.prank(_maker);
        _board.cancelOrder(orderId);

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(order.availableA, 0);
        assertEq(_maker.balance, makerEthBefore + ETH_AMOUNT);
        assertEq(address(_board).balance, 0);
    }

    /// @notice Tests cancelOrder returning ETH emits OrderCanceled
    function test_cancelOrder_returnEth_event() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));

        vm.expectEmit(true, false, false, true);
        emit ISwapboard.OrderCanceled({orderId: orderId});

        vm.prank(_maker);
        _board.cancelOrder(orderId);
    }

    /// @notice Tests cancelOrder returning ETH reverts when not maker
    function test_cancelOrder_returnEth_revert_notMaker() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));

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

    /// @notice Tests cancelOrder returning ETH reverts when order was already cancelled
    function test_cancelOrder_returnEth_revert_orderNotFound_afterCancel() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));

        vm.prank(_maker);
        _board.cancelOrder(orderId);

        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, orderId));
        _board.cancelOrder(orderId);
    }

    /// @notice Tests cancelOrder reverts when maker rejects ETH and leaves escrow intact
    function test_cancelOrder_returnEth_revert_ethTransferFailed() public {
        ETHRejecter rejecter = new ETHRejecter();
        vm.deal(address(rejecter), 10 ether);

        vm.prank(address(rejecter));
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));

        uint256 boardEthBefore = address(_board).balance;

        vm.prank(address(rejecter));
        vm.expectRevert(ETHRejecter.RejectETH.selector);
        _board.cancelOrder(orderId);

        assertTrue(_board.canFill(orderId));
        assertEq(address(_board).balance, boardEthBefore);
        assertEq(_board.getOrder(orderId).amountA, ETH_AMOUNT);
    }

    /// @notice Tests fillOrder paying ETH reverts when maker rejects ETH and leaves escrow intact
    function test_fillOrder_payEth_revert_ethTransferFailed() public {
        ETHRejecter rejecter = new ETHRejecter();
        _tokenB.mint(address(rejecter), AMOUNT_B);

        vm.startPrank(address(rejecter));
        _tokenB.approve(address(_board), AMOUNT_B);
        uint256 orderId = _board.createOrder(_order(address(_tokenB), AMOUNT_B, _eth, ETH_AMOUNT));
        vm.stopPrank();

        uint256 boardTokenBefore = _tokenB.balanceOf(address(_board));
        uint256 takerEthBefore = _taker.balance;

        vm.prank(_taker);
        vm.expectRevert(ETHRejecter.RejectETH.selector);
        _fillOrderPayEth(orderId, AMOUNT_B, ETH_AMOUNT, 0);

        assertTrue(_board.canFill(orderId));
        assertEq(_tokenB.balanceOf(address(_board)), boardTokenBefore);
        assertEq(_taker.balance, takerEthBefore);
    }

    // ============ fillOrder receiving ETH ============

    /// @notice Tests fillOrder when tokenA is ETH
    function test_fillOrder_receiveEth() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));

        uint256 takerEthBefore = _taker.balance;
        uint256 makerTokenBefore = _tokenB.balanceOf(_maker);

        uint256 tokenBPullsBefore = _tf(_tokenB);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _fillOrder(orderId, ETH_AMOUNT);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(order.availableA, 0);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 1);
        assertEq(_taker.balance, takerEthBefore + ETH_AMOUNT);
        assertEq(_tokenB.balanceOf(_maker), makerTokenBefore + AMOUNT_B);
        assertEq(address(_board).balance, 0);
    }

    /// @notice Tests fillOrder receiving ETH emits OrderFilled
    function test_fillOrder_receiveEth_event() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);

        uint256 tokenBPullsBefore = _tf(_tokenB);
        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderFilled({orderId: orderId, taker: _taker, amountA: ETH_AMOUNT, amountB: AMOUNT_B});
        _fillOrder(orderId, ETH_AMOUNT);
        vm.stopPrank();

        assertFalse(_board.getOrder(orderId).active);
        assertEq(_board.getOrder(orderId).availableA, 0);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 1);
    }

    /// @notice Tests fillOrder receiving ETH reverts when order not found
    function test_fillOrder_receiveEth_revert_orderNotFound() public {
        vm.prank(_taker);
        ISwapboard.Order memory order = _board.getOrder(999);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, 999));
        _fillOrderQuoted(order, 999, 1);
    }

    /// @notice Tests fillOrder receiving ETH reverts when order not active
    function test_fillOrder_receiveEth_revert_orderNotActive() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _fillOrder(orderId, ETH_AMOUNT);
        vm.stopPrank();

        vm.prank(_taker);
        ISwapboard.Order memory order = _board.getOrder(orderId);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        _fillOrderQuoted(order, orderId, ETH_AMOUNT);
    }

    /// @notice Tests fillOrder receiving ETH reverts when taker rejects ETH and leaves escrow intact
    function test_fillOrder_receiveEth_revert_ethTransferFailed() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));

        ETHRejecter rejecter = new ETHRejecter();
        _tokenB.mint(address(rejecter), AMOUNT_B);

        uint256 boardEthBefore = address(_board).balance;
        uint256 makerTokenBefore = _tokenB.balanceOf(_maker);

        vm.startPrank(address(rejecter));
        _tokenB.approve(address(_board), AMOUNT_B);
        ISwapboard.Order memory order = _board.getOrder(orderId);
        vm.expectRevert(ETHRejecter.RejectETH.selector);
        _fillOrderQuoted(order, orderId, ETH_AMOUNT);
        vm.stopPrank();

        assertTrue(_board.canFill(orderId));
        assertEq(address(_board).balance, boardEthBefore);
        assertEq(_tokenB.balanceOf(_maker), makerTokenBefore);
    }

    /// @notice Tests fillOrder receiving ETH reverts after deadline
    function test_fillOrder_receiveEth_revert_deadlineExpired() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));

        vm.warp(1000);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        ISwapboard.Order memory order = _board.getOrder(orderId);
        vm.expectRevert(ISwapboard.DeadlineExpired.selector);
        _fillOrderQuoted(order, orderId, ETH_AMOUNT, 999);
        vm.stopPrank();
    }

    // ============ No receive() ============

    /// @notice Tests plain ETH transfers to the contract revert (no receive/fallback)
    function test_plainEthTransfer_reverts() public {
        uint256 boardBefore = address(_board).balance;
        uint256 makerBefore = _maker.balance;

        vm.prank(_maker);
        // forge-lint: disable-next-line(low-level-calls)
        (bool success,) = address(_board).call{value: 1 ether}("");

        assertFalse(success);
        assertEq(address(_board).balance, boardBefore);
        assertEq(_maker.balance, makerBefore);
    }

    // ============ Round-trips ============

    /// @notice Tests full ETH sell then ERC20 fill
    function test_roundTrip_sellEth_fillWithToken() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));

        uint256 takerEthBefore = _taker.balance;

        uint256 tokenBPullsBefore = _tf(_tokenB);
        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _fillOrder(orderId, ETH_AMOUNT);
        vm.stopPrank();

        assertFalse(_board.getOrder(orderId).active);
        assertEq(_board.getOrder(orderId).availableA, 0);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 1);
        assertEq(_taker.balance, takerEthBefore + ETH_AMOUNT);
        assertEq(address(_board).balance, 0);
    }

    /// @notice Tests ETH sell then cancel returns ETH
    function test_roundTrip_sellEth_cancel() public {
        uint256 makerEthBefore = _maker.balance;

        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));

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
        uint256 orderId = _board.createOrder(_order(address(_tokenB), AMOUNT_B, _eth, ETH_AMOUNT));
        vm.stopPrank();

        uint256 makerEthBefore = _maker.balance;
        uint256 takerTokenBefore = _tokenB.balanceOf(_taker);

        vm.prank(_taker);
        _fillOrderPayEth(orderId, AMOUNT_B, ETH_AMOUNT, 0);

        assertFalse(_board.getOrder(orderId).active);
        assertEq(_board.getOrder(orderId).availableA, 0);
        assertEq(_maker.balance, makerEthBefore + ETH_AMOUNT);
        assertEq(_tokenB.balanceOf(_taker), takerTokenBefore + AMOUNT_B);
    }

    /// @notice Tests multiple ETH sell orders can coexist
    function test_multipleEthOrders() public {
        vm.startPrank(_maker);
        uint256 id0 = _board.createOrder{value: 1 ether}(_order(_eth, 1 ether, address(_tokenB), AMOUNT_B));
        uint256 id1 = _board.createOrder{value: 2 ether}(_order(_eth, 2 ether, address(_tokenB), AMOUNT_B));
        uint256 id2 = _board.createOrder{value: 3 ether}(_order(_eth, 3 ether, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        assertEq(address(_board).balance, 6 ether);

        vm.prank(_maker);
        _board.cancelOrder(id1);

        assertEq(address(_board).balance, 4 ether);

        uint256 tokenBPullsBefore = _tf(_tokenB);
        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _fillOrder(id0, 1 ether);
        vm.stopPrank();

        assertEq(address(_board).balance, 3 ether);
        assertTrue(_board.canFill(id2));
        assertFalse(_board.canFill(id0));
        assertFalse(_board.canFill(id1));
        assertFalse(_board.getOrder(id0).active);
        assertEq(_board.getOrder(id0).availableA, 0);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 1);
    }

    // ============ Fuzz tests ============

    /// @notice Fuzz tests createOrder selling ETH
    function testFuzz_createOrder_sellEth(
        uint256 ethAmountSeed,
        uint256 amountBSeed
    ) public {
        // casting to 'uint128' is safe because bound is within uint128 range
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 ethAmount = uint128(bound(ethAmountSeed, 1, 100 ether));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountB = uint128(bound(amountBSeed, 1, type(uint128).max));

        vm.deal(_maker, ethAmount + 1 ether);

        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ethAmount}(_order(_eth, ethAmount, address(_tokenB), amountB));

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertEq(order.amountA, ethAmount);
        assertEq(order.amountB, amountB);
        assertEq(order.tokenA, _eth);
        assertEq(address(_board).balance, ethAmount);
    }

    /// @notice Fuzz tests createOrder selling ETH reverts on excess msg.value
    function testFuzz_createOrder_sellEth_revert_excess(
        uint256 ethAmountSeed,
        uint256 excessSeed
    ) public {
        // casting to 'uint128' is safe because bound is within uint128 range
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 ethAmount = uint128(bound(ethAmountSeed, 1, 50 ether));
        uint256 excess = bound(excessSeed, 1, 50 ether);

        vm.deal(_maker, ethAmount + excess);

        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, ethAmount, ethAmount + excess));
        _board.createOrder{value: ethAmount + excess}(_order(_eth, ethAmount, address(_tokenB), AMOUNT_B));
    }

    /// @notice Fuzz tests fillOrder paying with ETH
    function testFuzz_fillOrder_payEth(
        uint256 tokenAmountSeed,
        uint256 ethAmountSeed
    ) public {
        // casting to 'uint128' is safe because bound is within uint128 range
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 tokenAmount = uint128(bound(tokenAmountSeed, 1, type(uint128).max));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 ethAmount = uint128(bound(ethAmountSeed, 1, 100 ether));

        _tokenB.mint(_maker, tokenAmount);
        vm.deal(_taker, ethAmount + 1 ether);

        uint256 makerEthBefore = _maker.balance;
        uint256 takerTokenBefore = _tokenB.balanceOf(_taker);

        vm.startPrank(_maker);
        _tokenB.approve(address(_board), tokenAmount);
        uint256 orderId = _board.createOrder(_order(address(_tokenB), tokenAmount, _eth, ethAmount));
        vm.stopPrank();

        vm.prank(_taker);
        _fillOrderPayEth(orderId, tokenAmount, ethAmount, 0);

        assertEq(_maker.balance, makerEthBefore + ethAmount);
        assertEq(_tokenB.balanceOf(_taker), takerTokenBefore + tokenAmount);
    }

    /// @notice Fuzz tests cancelOrder returning ETH
    function testFuzz_cancelOrder_returnEth(
        uint256 ethAmountSeed
    ) public {
        // casting to 'uint128' is safe because bound is within uint128 range
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 ethAmount = uint128(bound(ethAmountSeed, 1, 100 ether));
        vm.deal(_maker, ethAmount);

        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ethAmount}(_order(_eth, ethAmount, address(_tokenB), AMOUNT_B));

        uint256 makerEthBefore = _maker.balance;

        vm.prank(_maker);
        _board.cancelOrder(orderId);

        assertEq(_maker.balance, makerEthBefore + ethAmount);
    }

    /// @notice Fuzz tests fillOrder receiving ETH
    function testFuzz_fillOrder_receiveEth(
        uint256 ethAmountSeed,
        uint256 tokenAmountSeed
    ) public {
        // casting to 'uint128' is safe because bound is within uint128 range
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 ethAmount = uint128(bound(ethAmountSeed, 1, 100 ether));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 tokenAmount = uint128(bound(tokenAmountSeed, 1, type(uint128).max));

        vm.deal(_maker, ethAmount);
        _tokenB.mint(_taker, tokenAmount);

        uint256 takerEthBefore = _taker.balance;
        uint256 makerTokenBefore = _tokenB.balanceOf(_maker);

        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ethAmount}(_order(_eth, ethAmount, address(_tokenB), tokenAmount));

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), tokenAmount);
        ISwapboard.Order memory order = _board.getOrder(orderId);
        _fillOrderQuoted(order, orderId, ethAmount);
        vm.stopPrank();

        assertEq(_taker.balance, takerEthBefore + ethAmount);
        assertEq(_tokenB.balanceOf(_maker), makerTokenBefore + tokenAmount);
    }

    // ============ Partial fills ============

    /// @notice Tests fillOrder reverts when partial fills are disabled and amountA is not the full remaining
    function test_fillOrder_revert_partialFillNotAllowed() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        ISwapboard.Order memory order = _board.getOrder(orderId);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.PartialFillNotAllowed.selector, orderId));
        _fillOrderQuoted(order, orderId, AMOUNT_A / 2);
        vm.stopPrank();

        assertTrue(_board.canFill(orderId));
        assertEq(_board.getOrder(orderId).amountA, AMOUNT_A);
    }

    /// @notice Tests fillOrder reverts when requested amountA exceeds remaining
    function test_fillOrder_revert_fillAmountTooHigh() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        ISwapboard.Order memory order = _board.getOrder(orderId);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.FillAmountTooHigh.selector, orderId, AMOUNT_A + 1, AMOUNT_A));
        _fillOrderQuoted(order, orderId, AMOUNT_A + 1);
        vm.stopPrank();
    }

    /// @notice Tests fillOrder reverts when quoted payment is below the taker minimum
    function test_fillOrder_revert_fillAmountMismatch() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        vm.expectRevert(
            abi.encodeWithSelector(ISwapboard.FillAmountMismatch.selector, orderId, AMOUNT_B, AMOUNT_B + 1)
        );
        _board.fillOrder(orderId, AMOUNT_A, AMOUNT_B + 1, 0);
        vm.stopPrank();

        assertTrue(_board.canFill(orderId));
    }

    /// @notice Tests fillOrder succeeds when quoted payment exceeds the taker minimum
    function test_fillOrder_minAmountB_acceptsHigherQuotedPayment() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), 3);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), 3, address(_tokenB), 100));
        vm.stopPrank();

        uint128 fillA = 1;
        uint128 quotedB = FillTestLib.quoteAmountB(_board.getOrder(orderId), fillA);
        assertGt(quotedB, 1);

        uint256 makerBBefore = _tokenB.balanceOf(_maker);
        uint256 takerABefore = _tokenA.balanceOf(_taker);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), quotedB);
        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderFilled({orderId: orderId, taker: _taker, amountA: fillA, amountB: quotedB});
        _board.fillOrder(orderId, fillA, quotedB - 1, 0);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertTrue(order.active);
        assertEq(order.availableA, 2);
        assertEq(order.availableB, 100 - quotedB);
        assertEq(_tokenA.balanceOf(_taker), takerABefore + fillA);
        assertEq(_tokenB.balanceOf(_maker), makerBBefore + quotedB);
    }

    /// @notice Tests fillOrder paying ETH succeeds when quoted payment exceeds the taker minimum
    function test_fillOrder_payEth_minAmountB_acceptsHigherQuotedPayment() public {
        uint128 totalA = 3 ether;
        uint128 totalEth = 100 ether;

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), totalA);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), totalA, _eth, totalEth));
        vm.stopPrank();

        uint128 fillA = 1 ether;
        uint128 quotedEth = FillTestLib.quoteAmountB(_board.getOrder(orderId), fillA);
        assertGt(quotedEth, 1 ether);

        uint256 makerEthBefore = _maker.balance;
        uint256 takerABefore = _tokenA.balanceOf(_taker);

        vm.startPrank(_taker);
        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderFilled({orderId: orderId, taker: _taker, amountA: fillA, amountB: quotedEth});
        _board.fillOrder{value: quotedEth}(orderId, fillA, quotedEth - 1, 0);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertTrue(order.active);
        assertEq(order.availableA, 2 ether);
        assertEq(order.availableB, totalEth - quotedEth);
        assertEq(_tokenA.balanceOf(_taker), takerABefore + fillA);
        assertEq(_maker.balance, makerEthBefore + quotedEth);
    }

    /// @notice Tests fillOrders succeeds when quoted payment exceeds the taker minimum
    function test_fillOrders_minAmountB_acceptsHigherQuotedPayment() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), 3);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), 3, address(_tokenB), 100));
        vm.stopPrank();

        uint128 fillA = 1;
        ISwapboard.Order memory order = _board.getOrder(orderId);
        uint128 quotedB = FillTestLib.quoteAmountB(order, fillA);
        assertGt(quotedB, 1);

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](1);
        fills[0] = ISwapboard.FillOrderParams({orderId: orderId, amountA: fillA, minAmountB: quotedB - 1});

        uint256 makerBBefore = _tokenB.balanceOf(_maker);
        uint256 takerABefore = _tokenA.balanceOf(_taker);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), quotedB);
        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderFilled({orderId: orderId, taker: _taker, amountA: fillA, amountB: quotedB});
        _board.fillOrders(fills, 0);
        vm.stopPrank();

        order = _board.getOrder(orderId);
        assertTrue(order.active);
        assertEq(order.availableA, 2);
        assertEq(order.availableB, 100 - quotedB);
        assertEq(_tokenA.balanceOf(_taker), takerABefore + fillA);
        assertEq(_tokenB.balanceOf(_maker), makerBBefore + quotedB);
    }

    /// @notice Tests fillOrders reverts FillAmountMismatch on a later leg
    function test_fillOrders_revert_fillAmountMismatch_laterItem() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        uint256 id0 = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        uint256 id1 = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = FillTestLib.fillParams(_board.getOrder(id0), id0, AMOUNT_A);
        fills[1] = ISwapboard.FillOrderParams({orderId: id1, amountA: AMOUNT_A, minAmountB: AMOUNT_B + 1});

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B * 2);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.FillAmountMismatch.selector, id1, AMOUNT_B, AMOUNT_B + 1));
        _board.fillOrders(fills, 0);
        vm.stopPrank();

        assertTrue(_board.canFill(id0));
        assertTrue(_board.canFill(id1));
    }

    /// @notice Tests fillOrder reverts on zero amountA
    function test_fillOrder_revert_zeroAmountA() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        ISwapboard.Order memory order = _board.getOrder(orderId);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _fillOrderQuoted(order, orderId, 0);
        vm.stopPrank();
    }

    /// @notice Tests fillOrder reverts ZeroAmount when quoted tokenB payment rounds to 0
    /// @dev Unreachable via normal fills (availableB=0 implies inactive). Force availableB=0 while
    ///      keeping the order active so the ceil branch returns amountBIn=0.
    function test_fillOrder_revert_zeroAmountBIn() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        // Order.availableB is struct field depth 8 (maker=0 … availableA=7, availableB=8).
        _stdstore.enable_packed_slots();
        _stdstore.target(address(_board));
        _stdstore.sig(_board.getOrder.selector);
        _stdstore.with_key(orderId);
        _stdstore.depth(8);
        _stdstore.checked_write(uint256(0));

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertEq(order.availableB, 0);
        assertTrue(order.active);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        // Partial fill: ceil((1 * 0 + availableA - 1) / availableA) == 0 → ZeroAmount
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _fillOrderQuoted(order, orderId, 1);
        vm.stopPrank();
    }

    /// @notice Tests ceil payment can exhaust amountB while leaving tokenA dust
    function test_fillOrder_partial_ceilExhaustsAmountBWithDust() public {
        uint128 amountA = 100;
        uint128 amountB = 1;

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), amountA);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), amountA, address(_tokenB), amountB));
        vm.stopPrank();

        uint256 tokenAPullsBefore = _tf(_tokenA);
        uint256 tokenBPullsBefore = _tf(_tokenB);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), amountB);
        _fillOrder(orderId, 1);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(order.amountA, 100);
        assertEq(order.amountB, 1);
        assertEq(order.availableB, 0);
        // Dust remaining tokenA after amountB exhausted is expected (not worth gas to refund).
        assertEq(order.availableA, 99);
        assertEq(_tf(_tokenA), tokenAPullsBefore);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 1);
        assertEq(_tokenA.balanceOf(address(_board)), 99);
    }

    /// @notice Tests a single partial fill reduces remaining amounts and keeps the order active
    function test_fillOrder_partial_updatesRemaining() public {
        uint128 amountA = 100 ether;
        uint128 amountB = 250_000e6;
        uint128 fillA = 40 ether;
        uint256 expectedBIn = (uint256(fillA) * uint256(amountB) + uint256(amountA) - 1) / uint256(amountA);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), amountA);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), amountA, address(_tokenB), amountB));
        vm.stopPrank();

        uint256 takerABefore = _tokenA.balanceOf(_taker);
        uint256 makerBBefore = _tokenB.balanceOf(_maker);

        uint256 tokenAPullsBefore = _tf(_tokenA);
        uint256 tokenBPullsBefore = _tf(_tokenB);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), expectedBIn);
        _fillOrder(orderId, fillA);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertTrue(order.active);
        assertEq(order.amountA, amountA);
        assertEq(order.amountB, amountB);
        assertEq(order.availableA, amountA - fillA);
        assertEq(order.availableB, amountB - expectedBIn);
        assertEq(_tf(_tokenA), tokenAPullsBefore);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 1);
        assertEq(_tokenA.balanceOf(_taker), takerABefore + fillA);
        assertEq(_tokenB.balanceOf(_maker), makerBBefore + expectedBIn);
        assertEq(_tokenA.balanceOf(address(_board)), amountA - fillA);
    }

    /// @notice Tests multiple partial fills can complete an order
    function test_fillOrder_partial_multipleFillsComplete() public {
        uint128 amountA = 100 ether;
        uint128 amountB = 4e6;

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), amountA);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), amountA, address(_tokenB), amountB));
        vm.stopPrank();

        uint256 tokenAPullsBefore = _tf(_tokenA);
        uint256 tokenBPullsBefore = _tf(_tokenB);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), amountB);
        _fillOrder(orderId, 25 ether);
        _fillOrder(orderId, 25 ether);
        _fillOrder(orderId, 25 ether);
        _fillOrder(orderId, 25 ether);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(order.amountA, amountA);
        assertEq(order.amountB, amountB);
        assertEq(order.availableA, 0);
        assertEq(order.availableB, 0);
        assertEq(_tf(_tokenA), tokenAPullsBefore);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 4);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
    }

    /// @notice Tests ceil rounding can exhaust amountB while leaving tokenA dust (expected)
    function test_fillOrder_partial_roundingLeavesDust() public {
        uint128 amountA = 100;
        uint128 amountB = 3;
        uint128 fillA = 34;
        // Exact B share would be 1.02; ceil charges 2.
        uint256 expectedBIn = 2;

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), amountA);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), amountA, address(_tokenB), amountB));
        vm.stopPrank();

        uint256 takerABefore = _tokenA.balanceOf(_taker);

        uint256 tokenAPullsBefore = _tf(_tokenA);
        uint256 tokenBPullsBefore = _tf(_tokenB);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), expectedBIn);
        _fillOrder(orderId, fillA);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertTrue(order.active);
        assertEq(order.amountA, amountA);
        assertEq(order.amountB, amountB);
        assertEq(order.availableA, amountA - fillA);
        assertEq(order.availableB, amountB - expectedBIn);
        assertEq(_tf(_tokenA), tokenAPullsBefore);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 1);
        assertEq(_tokenA.balanceOf(_taker), takerABefore + fillA);
        // Ceil on tokenB can leave a richer residual A/B ratio; dust is not refunded (not worth
        // the gas) and can be picked up when this token is tokenB on another order.
        assertEq(_tokenA.balanceOf(address(_board)), amountA - fillA);
        assertEq(expectedBIn, 2);
    }

    /// @notice Tests partial fill then cancel returns remaining tokenA
    function test_fillOrder_partial_thenCancel() public {
        uint128 amountA = 100 ether;
        uint128 amountB = 4e6;
        uint128 fillA = 25 ether;
        uint256 expectedBIn = (uint256(fillA) * uint256(amountB) + uint256(amountA) - 1) / uint256(amountA);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), amountA);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), amountA, address(_tokenB), amountB));
        vm.stopPrank();

        uint256 tokenAPullsBefore = _tf(_tokenA);
        uint256 tokenBPullsBefore = _tf(_tokenB);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), expectedBIn);
        _fillOrder(orderId, fillA);
        vm.stopPrank();

        assertEq(_tf(_tokenA), tokenAPullsBefore);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 1);

        uint256 makerABefore = _tokenA.balanceOf(_maker);
        vm.prank(_maker);
        _board.cancelOrder(orderId);

        assertFalse(_board.canFill(orderId));
        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertEq(order.maker, address(0));
        assertEq(order.amountA, 0);
        assertEq(order.amountB, 0);
        assertEq(order.availableA, 0);
        assertEq(order.availableB, 0);
        assertFalse(order.active);
        assertEq(_tokenA.balanceOf(_maker), makerABefore + (amountA - fillA));
        assertEq(_tokenA.balanceOf(address(_board)), 0);
    }

    /// @notice Tests partial fill emits OrderFilled with filled amounts
    function test_fillOrder_partial_event() public {
        uint128 amountA = 100 ether;
        uint128 amountB = 4e6;
        uint128 fillA = 25 ether;
        // casting to 'uint128' is safe because ceil result is <= amountB
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 expectedBIn = uint128((uint256(fillA) * uint256(amountB) + uint256(amountA) - 1) / uint256(amountA));

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), amountA);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), amountA, address(_tokenB), amountB));
        vm.stopPrank();

        uint256 tokenAPullsBefore = _tf(_tokenA);
        uint256 tokenBPullsBefore = _tf(_tokenB);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), expectedBIn);
        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderFilled({orderId: orderId, taker: _taker, amountA: fillA, amountB: expectedBIn});
        _fillOrder(orderId, fillA);
        vm.stopPrank();

        assertEq(_tf(_tokenA), tokenAPullsBefore);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 1);
    }

    /// @notice Tests ETH sell order can be partially filled by requesting amountA ETH
    function test_fillOrder_partial_receiveEth() public {
        uint128 ethAmount = 4 ether;
        uint128 tokenAmount = 400e6;
        uint128 fillA = 1 ether;
        uint256 expectedBIn = (uint256(fillA) * uint256(tokenAmount) + uint256(ethAmount) - 1) / uint256(ethAmount);

        vm.prank(_maker);
        uint256 orderId =
            _board.createOrder{value: ethAmount}(_orderPartial(_eth, ethAmount, address(_tokenB), tokenAmount));

        uint256 takerEthBefore = _taker.balance;

        uint256 tokenBPullsBefore = _tf(_tokenB);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), expectedBIn);
        _fillOrder(orderId, fillA);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertTrue(order.active);
        assertEq(order.amountA, ethAmount);
        assertEq(order.amountB, tokenAmount);
        assertEq(order.availableA, ethAmount - fillA);
        assertEq(order.availableB, tokenAmount - expectedBIn);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 1);
        assertEq(_taker.balance, takerEthBefore + fillA);
        assertEq(address(_board).balance, ethAmount - fillA);
    }

    /// @notice Tests want-ETH order can be partially filled with exact ceiled msg.value
    function test_fillOrder_partial_payEth() public {
        uint128 tokenAmount = 400e6;
        uint128 ethAmount = 4 ether;
        uint128 fillA = 100e6;

        vm.startPrank(_maker);
        _tokenB.approve(address(_board), tokenAmount);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenB), tokenAmount, _eth, ethAmount));
        vm.stopPrank();

        uint128 expectedEthIn = FillTestLib.quoteAmountB(_board.getOrder(orderId), fillA);

        uint256 makerEthBefore = _maker.balance;
        uint256 takerTokenBefore = _tokenB.balanceOf(_taker);

        vm.prank(_taker);
        _fillOrderPayEth(orderId, fillA, expectedEthIn);

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertTrue(order.active);
        assertEq(order.amountA, tokenAmount);
        assertEq(order.amountB, ethAmount);
        assertEq(order.availableA, tokenAmount - fillA);
        assertEq(order.availableB, ethAmount - expectedEthIn);
        assertEq(_maker.balance, makerEthBefore + expectedEthIn);
        assertEq(_tokenB.balanceOf(_taker), takerTokenBefore + fillA);
    }

    /// @notice Tests want-ETH create stores partialFillAllowed=true
    function test_createOrder_wantEth_partialFillAllowed_true() public {
        vm.startPrank(_maker);
        _tokenB.approve(address(_board), AMOUNT_B);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenB), AMOUNT_B, _eth, ETH_AMOUNT));
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertTrue(order.partialFillAllowed);
        assertEq(_tf(_tokenB), 1);
        assertEq(order.tokenA, address(_tokenB));
        assertEq(order.tokenB, _eth);
        assertEq(order.amountA, AMOUNT_B);
        assertEq(order.amountB, ETH_AMOUNT);
        assertEq(order.availableA, AMOUNT_B);
        assertEq(order.availableB, ETH_AMOUNT);
    }

    /// @notice Tests partial want-ETH fill reverts when msg.value is not the ceiled tokenB amount
    function test_fillOrder_partial_payEth_revert_amountMismatch() public {
        uint128 tokenAmount = 400e6;
        uint128 ethAmount = 4 ether;
        uint128 fillA = 100e6;

        vm.startPrank(_maker);
        _tokenB.approve(address(_board), tokenAmount);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenB), tokenAmount, _eth, ethAmount));
        vm.stopPrank();

        uint128 expectedEthIn = FillTestLib.quoteAmountB(_board.getOrder(orderId), fillA);

        vm.prank(_taker);
        vm.expectRevert(
            abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, expectedEthIn, expectedEthIn - 1)
        );
        _board.fillOrder{value: expectedEthIn - 1}(orderId, fillA, expectedEthIn, 0);
    }

    /// @notice Tests FillAmountTooHigh uses remaining availableA after a prior partial fill
    function test_fillOrder_partial_then_revert_fillAmountTooHigh() public {
        uint128 amountA = 100 ether;
        uint128 amountB = 4e6;
        uint128 fillA = 25 ether;

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), amountA);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), amountA, address(_tokenB), amountB));
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), amountB);
        ISwapboard.Order memory order = _board.getOrder(orderId);
        _fillOrderQuoted(order, orderId, fillA);
        uint128 remainingA = _board.getOrder(orderId).availableA;
        assertEq(remainingA, amountA - fillA);

        ISwapboard.Order memory orderAfter = _board.getOrder(orderId);
        vm.expectRevert(
            abi.encodeWithSelector(ISwapboard.FillAmountTooHigh.selector, orderId, remainingA + 1, remainingA)
        );
        _fillOrderQuoted(orderAfter, orderId, remainingA + 1);
        vm.stopPrank();
    }

    /// @notice Tests a partial fill then an exact remaining fill completes the order
    function test_fillOrder_partial_thenExactRemainingCompletes() public {
        uint128 amountA = 100 ether;
        uint128 amountB = 4e6;
        uint128 fillA1 = 40 ether;

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), amountA);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), amountA, address(_tokenB), amountB));
        vm.stopPrank();

        uint256 tokenAPullsBefore = _tf(_tokenA);
        uint256 tokenBPullsBefore = _tf(_tokenB);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), amountB);
        _fillOrder(orderId, fillA1);

        uint128 remainingA = _board.getOrder(orderId).availableA;
        _fillOrder(orderId, remainingA);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(order.amountA, amountA);
        assertEq(order.amountB, amountB);
        assertEq(order.availableA, 0);
        assertEq(order.availableB, 0);
        assertEq(_tf(_tokenA), tokenAPullsBefore);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 2);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
    }

    /// @notice Tests partial fill reverts when deadline has expired
    function test_fillOrder_partial_revert_deadlineExpired() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        vm.warp(1000);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        ISwapboard.Order memory order = _board.getOrder(orderId);
        vm.expectRevert(ISwapboard.DeadlineExpired.selector);
        _fillOrderQuoted(order, orderId, AMOUNT_A / 2, 999);
        vm.stopPrank();

        assertTrue(_board.canFill(orderId));
        assertEq(_board.getOrder(orderId).availableA, AMOUNT_A);
    }

    /// @notice Tests FOT tokenB on a partial fill reverts BalanceMismatch; order unchanged
    function test_fillOrder_partial_fotTokenB_revert_balanceMismatch() public {
        MockFOT fotB = new MockFOT();
        uint128 amountA = 100 ether;
        uint128 amountB = 100 ether;
        uint128 fillA = 40 ether;
        uint256 expectedBIn = (uint256(fillA) * uint256(amountB) + uint256(amountA) - 1) / uint256(amountA);

        fotB.mint(_taker, 1000 ether);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), amountA);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), amountA, address(fotB), amountB));
        vm.stopPrank();

        uint256 makerFotBefore = fotB.balanceOf(_maker);
        uint256 takerABefore = _tokenA.balanceOf(_taker);
        uint256 takerFotBefore = fotB.balanceOf(_taker);

        vm.startPrank(_taker);
        fotB.approve(address(_board), expectedBIn);
        ISwapboard.Order memory orderBefore = _board.getOrder(orderId);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.BalanceMismatch.selector, expectedBIn, _fotNet(expectedBIn)));
        _fillOrderQuoted(orderBefore, orderId, fillA);
        vm.stopPrank();

        assertTrue(_board.canFill(orderId));
        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertTrue(order.active);
        assertEq(order.availableA, amountA);
        assertEq(order.availableB, amountB);
        assertEq(fotB.balanceOf(address(_board)), 0);
        assertEq(fotB.balanceOf(_maker), makerFotBefore);
        assertEq(fotB.balanceOf(_taker), takerFotBefore);
        assertEq(_tokenA.balanceOf(_taker), takerABefore);
        assertEq(_tokenA.balanceOf(address(_board)), amountA);
    }

    /// @notice Tests FOT tokenB on a full fill reverts BalanceMismatch; order unchanged
    function test_fillOrder_fotTokenB_revert_balanceMismatch() public {
        MockFOT fotB = new MockFOT();
        fotB.mint(_taker, 1000 ether);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(fotB), AMOUNT_B));
        vm.stopPrank();

        vm.startPrank(_taker);
        fotB.approve(address(_board), AMOUNT_B);
        ISwapboard.Order memory orderBefore = _board.getOrder(orderId);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.BalanceMismatch.selector, AMOUNT_B, _fotNet(AMOUNT_B)));
        _fillOrderQuoted(orderBefore, orderId, AMOUNT_A);
        vm.stopPrank();

        assertTrue(_board.canFill(orderId));
        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertTrue(order.active);
        assertEq(order.availableA, AMOUNT_A);
        assertEq(order.availableB, AMOUNT_B);
        assertEq(fotB.balanceOf(address(_board)), 0);
        assertEq(_tokenA.balanceOf(address(_board)), AMOUNT_A);
    }

    /// @notice Tests aggregated FOT tokenB pull on fillOrders reverts BalanceMismatch
    function test_fillOrders_fotTokenB_revert_balanceMismatch() public {
        MockFOT fotB = new MockFOT();
        fotB.mint(_taker, 1000 ether);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), AMOUNT_A, address(fotB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), AMOUNT_A, address(fotB), AMOUNT_B);
        uint256[] memory ids = _board.createOrders(orders);
        vm.stopPrank();

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = FillTestLib.fillParams(_board.getOrder(ids[0]), ids[0], AMOUNT_A);
        fills[1] = FillTestLib.fillParams(_board.getOrder(ids[1]), ids[1], AMOUNT_A);

        uint256 expectedBIn = uint256(AMOUNT_B) * 2;

        vm.startPrank(_taker);
        fotB.approve(address(_board), expectedBIn);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.BalanceMismatch.selector, expectedBIn, _fotNet(expectedBIn)));
        _board.fillOrders(fills, 0);
        vm.stopPrank();

        assertTrue(_board.canFill(ids[0]));
        assertTrue(_board.canFill(ids[1]));
        assertEq(_board.getOrder(ids[0]).availableA, AMOUNT_A);
        assertEq(_board.getOrder(ids[1]).availableA, AMOUNT_A);
        assertEq(fotB.balanceOf(address(_board)), 0);
        assertEq(_tokenA.balanceOf(address(_board)), AMOUNT_A * 2);
    }

    /// @notice Tests getOrders reflects original vs available after a partial fill
    function test_getOrders_afterPartialFill() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        uint256 order0 = _board.createOrder(_orderPartial(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        uint256 order1 = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B * 2));
        vm.stopPrank();

        uint128 fillA = AMOUNT_A / 4;
        uint256 expectedBIn = (uint256(fillA) * uint256(AMOUNT_B) + uint256(AMOUNT_A) - 1) / uint256(AMOUNT_A);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), expectedBIn);
        ISwapboard.Order memory order = _board.getOrder(order0);
        _fillOrderQuoted(order, order0, fillA);
        vm.stopPrank();

        uint256[] memory ids = new uint256[](2);
        ids[0] = order0;
        ids[1] = order1;
        ISwapboard.Order[] memory orders = _board.getOrders(ids);

        assertEq(orders[0].amountA, AMOUNT_A);
        assertEq(orders[0].amountB, AMOUNT_B);
        assertEq(orders[0].availableA, AMOUNT_A - fillA);
        assertEq(orders[0].availableB, AMOUNT_B - expectedBIn);
        assertTrue(orders[0].active);

        assertEq(orders[1].amountA, AMOUNT_A);
        assertEq(orders[1].amountB, AMOUNT_B * 2);
        assertEq(orders[1].availableA, AMOUNT_A);
        assertEq(orders[1].availableB, AMOUNT_B * 2);
        assertTrue(orders[1].active);
    }

    /// @notice Tests Order fields are stored and readable via getOrder
    function test_orderStruct_storagePacking() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertEq(order.maker, _maker);
        assertTrue(order.active);
        assertTrue(order.partialFillAllowed);
        assertEq(order.tokenA, address(_tokenA));
        assertEq(order.tokenB, address(_tokenB));
        assertEq(order.amountA, AMOUNT_A);
        assertEq(order.amountB, AMOUNT_B);
        assertEq(order.availableA, AMOUNT_A);
        assertEq(order.availableB, AMOUNT_B);
    }

    /// @notice Fuzz: partial fills reduce remaining amounts and never overspend escrow
    function testFuzz_fillOrder_partial(
        uint256 amountASeed,
        uint256 amountBSeed,
        uint256 fillASeed
    ) public {
        // casting to 'uint128' is safe because bound is capped at uint128.max
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountA = uint128(bound(amountASeed, 1, type(uint128).max));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountB = uint128(bound(amountBSeed, 1, type(uint128).max));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 fillA = uint128(bound(fillASeed, 1, amountA));

        uint256 amountBIn =
            fillA == amountA ? amountB : (uint256(fillA) * uint256(amountB) + uint256(amountA) - 1) / uint256(amountA);
        vm.assume(amountBIn > 0);

        _tokenA.mint(_maker, amountA);
        _tokenB.mint(_taker, amountBIn);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), amountA);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), amountA, address(_tokenB), amountB));
        vm.stopPrank();

        uint256 takerABefore = _tokenA.balanceOf(_taker);
        uint256 makerBBefore = _tokenB.balanceOf(_maker);

        uint256 tokenAPullsBefore = _tf(_tokenA);
        uint256 tokenBPullsBefore = _tf(_tokenB);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), amountBIn);
        _fillOrder(orderId, fillA);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertEq(order.amountA, amountA);
        assertEq(order.amountB, amountB);
        assertEq(order.availableA, amountA - fillA);
        assertEq(order.availableB, amountB - amountBIn);
        assertEq(_tf(_tokenA), tokenAPullsBefore);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 1);
        assertEq(_tokenA.balanceOf(_taker), takerABefore + fillA);
        assertEq(_tokenB.balanceOf(_maker), makerBBefore + amountBIn);
        assertEq(_tokenA.balanceOf(address(_board)), amountA - fillA);

        if (order.availableA == 0 || order.availableB == 0) {
            assertFalse(order.active);
        } else {
            assertTrue(order.active);
        }
    }

    /// @notice Fuzz: non-partial orders reject any amountA other than the full remaining
    function testFuzz_fillOrder_partialFillNotAllowed(
        uint256 amountASeed,
        uint256 amountBSeed,
        uint256 fillASeed
    ) public {
        // casting to 'uint128' is safe because bound is capped at uint128.max
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountA = uint128(bound(amountASeed, 2, type(uint128).max));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountB = uint128(bound(amountBSeed, 2, type(uint128).max));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 fillA = uint128(bound(fillASeed, 1, amountA - 1));

        _tokenA.mint(_maker, amountA);
        _tokenB.mint(_taker, amountB);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), amountA);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), amountA, address(_tokenB), amountB));
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), amountB);
        ISwapboard.Order memory order = _board.getOrder(orderId);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.PartialFillNotAllowed.selector, orderId));
        _fillOrderQuoted(order, orderId, fillA);
        vm.stopPrank();
    }

    /// @notice Fuzz: fillAmountTooHigh when requested amountA exceeds remaining
    function testFuzz_fillOrder_fillAmountTooHigh(
        uint256 amountASeed,
        uint256 amountBSeed
    ) public {
        // casting to 'uint128' is safe because bound is capped below uint128.max
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountA = uint128(bound(amountASeed, 1, type(uint128).max - 1));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountB = uint128(bound(amountBSeed, 1, type(uint128).max));
        uint128 requested = amountA + 1;

        _tokenA.mint(_maker, amountA);
        _tokenB.mint(_taker, amountB);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), amountA);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), amountA, address(_tokenB), amountB));
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), amountB);
        ISwapboard.Order memory order = _board.getOrder(orderId);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.FillAmountTooHigh.selector, orderId, requested, amountA));
        _fillOrderQuoted(order, orderId, requested);
        vm.stopPrank();
    }

    /// @notice Fuzz: two partial fills never exceed original escrow
    function testFuzz_fillOrder_partial_twoFills(
        uint256 amountASeed,
        uint256 amountBSeed,
        uint256 fillA1Seed
    ) public {
        // casting to 'uint128' is safe because bound is capped at uint64.max
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountA = uint128(bound(amountASeed, 2, type(uint64).max));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountB = uint128(bound(amountBSeed, 2, type(uint64).max));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 fillA1 = uint128(bound(fillA1Seed, 1, amountA - 1));

        uint256 bIn1 = (uint256(fillA1) * uint256(amountB) + uint256(amountA) - 1) / uint256(amountA);
        vm.assume(bIn1 > 0 && bIn1 < amountB);

        uint128 fillA2 = amountA - fillA1;
        uint256 bIn2 = amountB - bIn1;

        _tokenA.mint(_maker, amountA);
        _tokenB.mint(_taker, amountB);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), amountA);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), amountA, address(_tokenB), amountB));
        vm.stopPrank();

        uint256 tokenAPullsBefore = _tf(_tokenA);
        uint256 tokenBPullsBefore = _tf(_tokenB);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), amountB);
        _fillOrder(orderId, fillA1);
        _fillOrder(orderId, fillA2);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(order.amountA, amountA);
        assertEq(order.amountB, amountB);
        assertEq(order.availableA, 0);
        assertEq(order.availableB, 0);
        assertEq(fillA1 + fillA2, amountA);
        assertEq(bIn1 + bIn2, amountB);
        assertEq(_tf(_tokenA), tokenAPullsBefore);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 2);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
    }

    /// @notice Tests createOrder(CreateOrderParams) deposits tokenA
    function test_createOrder_struct() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertEq(orderId, 0);
        assertEq(order.maker, _maker);
        assertEq(order.tokenA, address(_tokenA));
        assertEq(order.amountA, AMOUNT_A);
        assertEq(order.tokenB, address(_tokenB));
        assertEq(order.amountB, AMOUNT_B);
        assertTrue(order.partialFillAllowed);
        assertEq(_tokenA.balanceOf(address(_board)), AMOUNT_A);
        assertEq(_tf(_tokenA), 1);
    }

    /// @notice Tests createOrders assigns sequential ids and stores each order
    function test_createOrders() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        orders[1] = _orderPartial(address(_tokenB), AMOUNT_B, address(_tokenA), AMOUNT_A);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        _tokenB.approve(address(_board), AMOUNT_B);
        uint256[] memory ids = _board.createOrders(orders);
        vm.stopPrank();

        assertEq(ids.length, 2);
        assertEq(ids[0], 0);
        assertEq(ids[1], 1);
        assertEq(_board.getNextOrderId(), 2);
        assertEq(_board.getOrder(ids[0]).tokenA, address(_tokenA));
        assertEq(_board.getOrder(ids[1]).tokenA, address(_tokenB));
        assertTrue(_board.getOrder(ids[1]).partialFillAllowed);
        assertEq(_tf(_tokenA), 1);
        assertEq(_tf(_tokenB), 1);
        assertEq(_tokenA.balanceOf(address(_board)), AMOUNT_A);
        assertEq(_tokenB.balanceOf(address(_board)), AMOUNT_B);
    }

    /// @notice Tests repeated tokenA is pulled once for the aggregated amount
    function test_createOrders_aggregatesSameToken() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](3);
        orders[0] = _order(address(_tokenA), 10 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _orderPartial(address(_tokenA), 25 ether, address(_tokenB), AMOUNT_B);
        orders[2] = _order(address(_tokenA), 5 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), 40 ether);
        uint256[] memory ids = _board.createOrders(orders);
        vm.stopPrank();

        assertEq(ids.length, 3);
        assertEq(_tf(_tokenA), 1);
        assertEq(_tokenA.balanceOf(address(_board)), 40 ether);
        assertEq(_board.getOrder(ids[0]).availableA, 10 ether);
        assertEq(_board.getOrder(ids[1]).availableA, 25 ether);
        assertEq(_board.getOrder(ids[2]).availableA, 5 ether);
    }

    /// @notice Tests interleaved tokenA/tokenB/ETH deposits aggregate to one pull per unique asset
    function test_createOrders_aggregatesSameTokenAndEth() public {
        address[9] memory tokens = [
            address(_tokenA),
            address(_tokenB),
            _eth,
            address(_tokenA),
            address(_tokenA),
            _eth,
            address(_tokenB),
            address(_tokenA),
            address(_tokenB)
        ];
        uint128[9] memory amounts = [uint128(1 ether), 2e6, 0.1 ether, 3 ether, 4 ether, 0.2 ether, 5e6, 6 ether, 7e6];

        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](9);
        for (uint256 i = 0; i < 9; ++i) {
            address tokenB = tokens[i] == address(_tokenA) ? address(_tokenB) : address(_tokenA);
            orders[i] = _order(tokens[i], amounts[i], tokenB, 1e6);
        }

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), 14 ether);
        _tokenB.approve(address(_board), 14e6);
        uint256[] memory ids = _board.createOrders{value: 0.3 ether}(orders);
        vm.stopPrank();

        assertEq(ids.length, 9);
        assertEq(_tf(_tokenA), 1);
        assertEq(_tf(_tokenB), 1);
        assertEq(_tokenA.balanceOf(address(_board)), 14 ether);
        assertEq(_tokenB.balanceOf(address(_board)), 14e6);
        assertEq(address(_board).balance, 0.3 ether);
        for (uint256 i = 0; i < 9; ++i) {
            assertEq(_board.getOrder(ids[i]).tokenA, tokens[i]);
            assertEq(_board.getOrder(ids[i]).availableA, amounts[i]);
        }
    }

    /// @notice Tests ETH deposits are summed and ERC20 still aggregates
    function test_createOrders_mixedEthAndToken() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](3);
        orders[0] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        orders[1] = _order(_eth, 1 ether, address(_tokenB), AMOUNT_B);
        orders[2] = _orderPartial(address(_tokenA), AMOUNT_A, _eth, ETH_AMOUNT);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        uint256[] memory ids = _board.createOrders{value: 1 ether}(orders);
        vm.stopPrank();

        assertEq(ids.length, 3);
        assertEq(_tf(_tokenA), 1);
        assertEq(_tokenA.balanceOf(address(_board)), AMOUNT_A * 2);
        assertEq(address(_board).balance, 1 ether);
        assertEq(_board.getOrder(ids[1]).tokenA, _eth);
        assertEq(_board.getOrder(ids[2]).tokenB, _eth);
    }

    /// @notice Tests an all-ETH batch pulls no ERC20 and checks total msg.value
    function test_createOrders_allEth() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(_eth, 1 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _orderPartial(_eth, 2 ether, address(_tokenA), AMOUNT_A);

        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders{value: 3 ether}(orders);

        assertEq(ids.length, 2);
        assertEq(_tf(_tokenA), 0);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
        assertEq(address(_board).balance, 3 ether);
        assertEq(_board.getOrder(ids[0]).amountA, 1 ether);
        assertEq(_board.getOrder(ids[1]).amountA, 2 ether);
    }

    /// @notice Tests empty createOrders reverts
    function test_createOrders_revert_empty() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](0);

        vm.expectRevert(ISwapboard.ZeroAmount.selector);

        _board.createOrders(orders);
    }

    /// @notice Tests aggregated ETH below msg.value reverts
    function test_createOrders_revert_ethMismatch_tooLow() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(_eth, 1 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(_eth, 1 ether, address(_tokenA), AMOUNT_A);

        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, 2 ether, 1 ether));

        _board.createOrders{value: 1 ether}(orders);
    }

    /// @notice Tests accidental ETH on an ERC20-only batch reverts
    function test_createOrders_revert_accidentalEth() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, 0, 1 ether));
        _board.createOrders{value: 1 ether}(orders);
        vm.stopPrank();

        assertEq(_tf(_tokenA), 0);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
    }

    /// @notice Tests aggregated ETH above msg.value reverts
    function test_createOrders_revert_ethMismatch_tooHigh() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](1);
        orders[0] = _order(_eth, 1 ether, address(_tokenB), AMOUNT_B);

        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, 1 ether, 2 ether));
        _board.createOrders{value: 2 ether}(orders);
    }

    /// @notice Tests createOrders reverts on a zero amount in the batch
    function test_createOrders_revert_zeroAmount() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), 0, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.createOrders(orders);
        vm.stopPrank();

        assertEq(_tf(_tokenA), 0);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
    }

    /// @notice Tests createOrders validates each order before pulling
    function test_createOrders_revert_sameToken() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), AMOUNT_A, address(_tokenA), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        vm.expectRevert(ISwapboard.SameToken.selector);
        _board.createOrders(orders);
        vm.stopPrank();

        assertEq(_tf(_tokenA), 0);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
    }

    /// @notice Tests aggregated FOT pull rejects the combined amount
    function test_createOrders_revert_fotAggregated() public {
        MockFOT fot = new MockFOT();
        fot.mint(_maker, 100 ether);

        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(fot), 40 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(fot), 60 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        fot.approve(address(_board), 100 ether);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.BalanceMismatch.selector, 100 ether, 95 ether));
        _board.createOrders(orders);
        vm.stopPrank();

        assertEq(fot.balanceOf(address(_board)), 0);
        assertEq(fot.balanceOf(_maker), 100 ether);
    }

    /// @notice Tests createOrders emits OrderCreated for each order
    function test_createOrders_events() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        orders[1] = _orderPartial(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);

        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderCreated({
            orderId: 0,
            maker: _maker,
            tokenA: address(_tokenA),
            amountA: AMOUNT_A,
            tokenB: address(_tokenB),
            amountB: AMOUNT_B,
            partialFillAllowed: false
        });
        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderCreated({
            orderId: 1,
            maker: _maker,
            tokenA: address(_tokenA),
            amountA: AMOUNT_A,
            tokenB: address(_tokenB),
            amountB: AMOUNT_B,
            partialFillAllowed: true
        });
        _board.createOrders(orders);
        vm.stopPrank();

        assertEq(_tf(_tokenA), 1);
    }

    /// @notice Tests a struct-created order can be filled
    function test_createOrder_struct_thenFill() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        uint256 tokenAPullsBefore = _tf(_tokenA);
        uint256 tokenBPullsBefore = _tf(_tokenB);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        ISwapboard.Order memory order = _board.getOrder(orderId);
        _fillOrderQuoted(order, orderId, AMOUNT_A);
        vm.stopPrank();

        assertFalse(_board.getOrder(orderId).active);
        assertEq(_board.getOrder(orderId).availableA, 0);
        assertEq(_tf(_tokenA), tokenAPullsBefore);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 1);
        assertEq(_tokenA.balanceOf(_taker), AMOUNT_A * 10 + AMOUNT_A);
        assertEq(_tokenB.balanceOf(_maker), AMOUNT_B * 10 + AMOUNT_B);
    }

    /// @notice Tests createOrders reverts ZeroAddress on a later item without pulling
    function test_createOrders_revert_zeroAddress_laterItem() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(0), AMOUNT_A, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        vm.expectRevert(ISwapboard.ZeroAddress.selector);
        _board.createOrders(orders);
        vm.stopPrank();

        assertEq(_tf(_tokenA), 0);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
    }

    /// @notice Tests createOrders reverts NotAContract on a later item without pulling
    function test_createOrders_revert_notAContract_laterItem() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), AMOUNT_A, address(0x999), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotAContract.selector, address(0x999)));
        _board.createOrders(orders);
        vm.stopPrank();

        assertEq(_tf(_tokenA), 0);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
    }

    /// @notice Tests createOrders reverts when a later order has amountB == 0
    function test_createOrders_revert_zeroAmountB() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), 0);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.createOrders(orders);
        vm.stopPrank();

        assertEq(_tf(_tokenA), 0);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
    }

    /// @notice Tests mixed ERC20+ETH batch reverts when msg.value is not the ETH sum
    function test_createOrders_revert_mixedEthMismatch() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        orders[1] = _order(_eth, 1 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, 1 ether, 0));
        _board.createOrders(orders);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, 1 ether, 2 ether));
        _board.createOrders{value: 2 ether}(orders);
        vm.stopPrank();

        assertEq(_tf(_tokenA), 0);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
        assertEq(address(_board).balance, 0);
    }

    /// @notice Tests createOrders ids continue after a prior createOrder
    function test_createOrders_idsContinueAfterCreateOrder() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 3);
        uint256 first = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));

        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        uint256[] memory ids = _board.createOrders(orders);
        vm.stopPrank();

        assertEq(first, 0);
        assertEq(ids[0], 1);
        assertEq(ids[1], 2);
        assertEq(_board.getNextOrderId(), 3);
        assertEq(_tf(_tokenA), 2);
        assertEq(_tokenA.balanceOf(address(_board)), AMOUNT_A * 3);
    }

    /// @notice Tests cancelling ERC20 and ETH legs from the same batch
    function test_createOrders_thenCancelEthAndErc20() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        orders[1] = _order(_eth, 1 ether, address(_tokenB), AMOUNT_B);

        uint256 makerABefore = _tokenA.balanceOf(_maker);
        uint256 makerEthBefore = _maker.balance;

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256[] memory ids = _board.createOrders{value: 1 ether}(orders);
        _board.cancelOrder(ids[0]);
        _board.cancelOrder(ids[1]);
        vm.stopPrank();

        assertEq(_tf(_tokenA), 1);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
        assertEq(address(_board).balance, 0);
        assertEq(_tokenA.balanceOf(_maker), makerABefore);
        assertEq(_maker.balance, makerEthBefore);
        assertFalse(_board.canFill(ids[0]));
        assertFalse(_board.canFill(ids[1]));
        assertFalse(_board.getOrder(ids[0]).active);
        assertFalse(_board.getOrder(ids[1]).active);
        assertEq(_board.getOrder(ids[0]).availableA, 0);
        assertEq(_board.getOrder(ids[1]).availableA, 0);
    }

    /// @notice Tests aggregated pull reverts when allowance is below the summed amount
    function test_createOrders_revert_insufficientAllowance() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);

        uint256 makerABefore = _tokenA.balanceOf(_maker);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        vm.expectRevert(stdError.arithmeticError);
        _board.createOrders(orders);
        vm.stopPrank();

        assertEq(_tf(_tokenA), 0);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
        assertEq(_tokenA.balanceOf(_maker), makerABefore);
        assertEq(_tokenA.allowance(_maker, address(_board)), AMOUNT_A);
        assertEq(_board.getNextOrderId(), 0);
    }

    /// @notice Tests a one-item createOrders matches createOrder accounting
    function test_createOrders_singleElement() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](1);
        orders[0] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256[] memory ids = _board.createOrders(orders);
        vm.stopPrank();

        assertEq(ids.length, 1);
        assertEq(ids[0], 0);
        assertEq(_board.getNextOrderId(), 1);
        assertEq(_tf(_tokenA), 1);
        assertEq(_tokenA.balanceOf(address(_board)), AMOUNT_A);
        ISwapboard.Order memory order = _board.getOrder(ids[0]);
        assertEq(order.maker, _maker);
        assertEq(order.amountA, AMOUNT_A);
        assertEq(order.availableA, AMOUNT_A);
        assertTrue(order.active);
    }

    /// @notice Property: two same-tokenA orders pull once for the summed amount
    function testFuzz_createOrders_aggregatesSameToken(
        uint256 amountA1Seed,
        uint256 amountA2Seed
    ) public {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountA1 = uint128(bound(amountA1Seed, 1, type(uint64).max));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountA2 = uint128(bound(amountA2Seed, 1, type(uint64).max));
        uint256 totalA = uint256(amountA1) + uint256(amountA2);

        _tokenA.mint(_maker, totalA);

        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), amountA1, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), amountA2, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), totalA);
        _board.createOrders(orders);
        vm.stopPrank();

        assertEq(_tf(_tokenA), 1);
        assertEq(_tokenA.balanceOf(address(_board)), totalA);
    }

    /// @notice Tests createOrders reverts ZeroAddress on tokenB of a later item
    function test_createOrders_revert_zeroAddress_tokenB_laterItem() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), AMOUNT_A, address(0), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        vm.expectRevert(ISwapboard.ZeroAddress.selector);
        _board.createOrders(orders);
        vm.stopPrank();

        assertEq(_tf(_tokenA), 0);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
    }

    /// @notice Tests createOrders reverts NotAContract on tokenA of a later item
    function test_createOrders_revert_notAContract_tokenA_laterItem() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(0x999), AMOUNT_A, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotAContract.selector, address(0x999)));
        _board.createOrders(orders);
        vm.stopPrank();

        assertEq(_tf(_tokenA), 0);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
    }

    /// @notice Tests createOrders reverts when balance is below the aggregated amount
    function test_createOrders_revert_insufficientBalance() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);

        uint256 excess = _tokenA.balanceOf(_maker) - AMOUNT_A;
        vm.prank(_maker);
        assertTrue(_tokenA.transfer(address(0xdead), excess));

        uint256 makerBefore = _tokenA.balanceOf(_maker);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        vm.expectRevert(stdError.arithmeticError);
        _board.createOrders(orders);
        vm.stopPrank();

        assertEq(_tf(_tokenA), 0);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
        assertEq(_tokenA.balanceOf(_maker), makerBefore);
        assertEq(_board.getNextOrderId(), 0);
    }

    /// @notice Tests createOrders then fills each order independently
    function test_createOrders_thenFillEach() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        uint256[] memory ids = _board.createOrders(orders);
        vm.stopPrank();

        uint256 tokenAPullsBefore = _tf(_tokenA);
        uint256 tokenBPullsBefore = _tf(_tokenB);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B * 2);
        ISwapboard.Order memory order = _board.getOrder(ids[0]);
        _fillOrderQuoted(order, ids[0], AMOUNT_A);
        _fillOrder(ids[1], AMOUNT_A);
        vm.stopPrank();

        assertFalse(_board.canFill(ids[0]));
        assertFalse(_board.canFill(ids[1]));
        assertFalse(_board.getOrder(ids[0]).active);
        assertFalse(_board.getOrder(ids[1]).active);
        assertEq(_board.getOrder(ids[0]).availableA, 0);
        assertEq(_board.getOrder(ids[1]).availableA, 0);
        assertEq(_tf(_tokenA), tokenAPullsBefore);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 2);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
        assertEq(_tokenA.balanceOf(_taker), AMOUNT_A * 10 + AMOUNT_A * 2);
        assertEq(_tokenB.balanceOf(_maker), AMOUNT_B * 10 + AMOUNT_B * 2);
    }

    /// @notice Property: ETH tokenA deposits require msg.value equal to the sum
    function testFuzz_createOrders_aggregatesEth(
        uint256 amount1Seed,
        uint256 amount2Seed
    ) public {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amount1 = uint128(bound(amount1Seed, 1, 50 ether));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amount2 = uint128(bound(amount2Seed, 1, 50 ether));
        uint256 totalEth = uint256(amount1) + uint256(amount2);

        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(_eth, amount1, address(_tokenB), AMOUNT_B);
        orders[1] = _order(_eth, amount2, address(_tokenA), AMOUNT_A);

        vm.deal(_maker, totalEth);
        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders{value: totalEth}(orders);

        assertEq(ids.length, 2);
        assertEq(address(_board).balance, totalEth);
        assertEq(_board.getOrder(ids[0]).availableA, amount1);
        assertEq(_board.getOrder(ids[1]).availableA, amount2);
        assertEq(_tf(_tokenA), 0);
    }

    /// @notice Tests cancelOrders returns aggregated ERC20 and ETH refunds
    function test_cancelOrders_mixedEthAndErc20() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        orders[1] = _order(_eth, 1 ether, address(_tokenB), AMOUNT_B);

        uint256 makerABefore = _tokenA.balanceOf(_maker);
        uint256 makerEthBefore = _maker.balance;

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256[] memory ids = _board.createOrders{value: 1 ether}(orders);
        _board.cancelOrders(ids);
        vm.stopPrank();

        assertEq(_tokenA.balanceOf(address(_board)), 0);
        assertEq(address(_board).balance, 0);
        assertEq(_tokenA.balanceOf(_maker), makerABefore);
        assertEq(_maker.balance, makerEthBefore);
        assertFalse(_board.canFill(ids[0]));
        assertFalse(_board.canFill(ids[1]));
        assertFalse(_board.getOrder(ids[0]).active);
        assertFalse(_board.getOrder(ids[1]).active);
        assertEq(_board.getOrder(ids[0]).availableA, 0);
        assertEq(_board.getOrder(ids[1]).availableA, 0);
    }

    /// @notice Tests repeated tokenA refunds are returned in one ERC20 transfer
    function test_cancelOrders_aggregatesSameToken() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](3);
        orders[0] = _order(address(_tokenA), 10 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), 25 ether, address(_tokenB), AMOUNT_B);
        orders[2] = _order(address(_tokenA), 5 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), 40 ether);
        uint256[] memory ids = _board.createOrders(orders);
        uint256 makerBefore = _tokenA.balanceOf(_maker);
        _board.cancelOrders(ids);
        vm.stopPrank();

        assertEq(_tokenA.balanceOf(address(_board)), 0);
        assertEq(_tokenA.balanceOf(_maker), makerBefore + 40 ether);
        for (uint256 i = 0; i < 3; ++i) {
            assertFalse(_board.canFill(ids[i]));
            assertFalse(_board.getOrder(ids[i]).active);
            assertEq(_board.getOrder(ids[i]).availableA, 0);
        }
    }

    /// @notice Tests empty cancelOrders reverts
    function test_cancelOrders_revert_empty() public {
        uint256[] memory orderIds = new uint256[](0);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.cancelOrders(orderIds);
    }

    /// @notice Tests cancelOrders validates order0 then reverts NotMaker on a later distinct maker
    function test_cancelOrders_revert_notMaker_laterItem() public {
        address maker2 = address(0x3);
        _tokenA.mint(maker2, AMOUNT_A);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 order0 = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        vm.startPrank(maker2);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 order1 = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        uint256[] memory cancelIds = new uint256[](2);
        cancelIds[0] = order0;
        cancelIds[1] = order1;

        vm.startPrank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotMaker.selector, order1, _maker, maker2));
        _board.cancelOrders(cancelIds);
        vm.stopPrank();

        assertTrue(_board.canFill(order0));
        assertTrue(_board.canFill(order1));
        assertEq(_tokenA.balanceOf(address(_board)), AMOUNT_A * 2);
    }

    /// @notice Tests cancelOrders reverts DuplicateOrderId
    function test_cancelOrders_revert_duplicateOrderId() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));

        uint256[] memory cancelIds = new uint256[](2);
        cancelIds[0] = orderId;
        cancelIds[1] = orderId;
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.DuplicateOrderId.selector, orderId));
        _board.cancelOrders(cancelIds);
        vm.stopPrank();

        assertTrue(_board.canFill(orderId));
        assertEq(_tokenA.balanceOf(address(_board)), AMOUNT_A);
    }

    /// @notice Tests a one-item cancelOrders matches cancelOrder accounting
    function test_cancelOrders_singleElement() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        uint256 makerBefore = _tokenA.balanceOf(_maker);

        uint256[] memory cancelIds = new uint256[](1);
        cancelIds[0] = orderId;
        _board.cancelOrders(cancelIds);
        vm.stopPrank();

        assertFalse(_board.getOrder(orderId).active);
        assertEq(_board.getOrder(orderId).maker, address(0));
        assertEq(_board.getOrder(orderId).availableA, 0);
        assertEq(_tokenA.balanceOf(_maker), makerBefore + AMOUNT_A);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
    }

    /// @notice Tests cancelOrders emits OrderCanceled for each order
    function test_cancelOrders_events() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        uint256[] memory ids = _board.createOrders(orders);

        vm.expectEmit(true, false, false, false);
        emit ISwapboard.OrderCanceled({orderId: ids[0]});
        vm.expectEmit(true, false, false, false);
        emit ISwapboard.OrderCanceled({orderId: ids[1]});
        _board.cancelOrders(ids);
        vm.stopPrank();
    }

    /// @notice Tests cancelOrders reverts OrderNotFound on a later item without refunding
    function test_cancelOrders_revert_orderNotFound_laterItem() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));

        uint256[] memory cancelIds = new uint256[](2);
        cancelIds[0] = orderId;
        cancelIds[1] = 999;
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, 999));
        _board.cancelOrders(cancelIds);
        vm.stopPrank();

        assertTrue(_board.canFill(orderId));
        assertEq(_tokenA.balanceOf(address(_board)), AMOUNT_A);
    }

    /// @notice Tests cancelOrders reverts OrderNotActive when a filled order is included
    function test_cancelOrders_revert_orderNotActive_laterItem() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        uint256[] memory ids = _board.createOrders(orders);
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        ISwapboard.Order memory order = _board.getOrder(ids[0]);
        _fillOrderQuoted(order, ids[0], AMOUNT_A);
        vm.stopPrank();

        uint256[] memory cancelIds = new uint256[](2);
        cancelIds[0] = ids[1];
        cancelIds[1] = ids[0];

        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, ids[0]));
        _board.cancelOrders(cancelIds);

        assertTrue(_board.canFill(ids[1]));
        assertEq(_tokenA.balanceOf(address(_board)), AMOUNT_A);
    }

    /// @notice Tests cancelOrders refunds only remaining availableA after a partial fill
    function test_cancelOrders_afterPartialFill() public {
        uint128 amountA = 100 ether;
        uint128 fillA = 25 ether;

        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _orderPartial(address(_tokenA), amountA, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), amountA + AMOUNT_A);
        uint256[] memory ids = _board.createOrders(orders);
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        ISwapboard.Order memory order = _board.getOrder(ids[0]);
        _fillOrderQuoted(order, ids[0], fillA);
        vm.stopPrank();

        uint256 makerBefore = _tokenA.balanceOf(_maker);
        vm.prank(_maker);
        _board.cancelOrders(ids);

        assertEq(_tokenA.balanceOf(_maker), makerBefore + (amountA - fillA) + AMOUNT_A);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
        assertEq(_board.getOrder(ids[0]).maker, address(0));
        assertEq(_board.getOrder(ids[1]).maker, address(0));
    }

    /// @notice Tests cancelOrders returns summed ETH for an all-ETH batch
    function test_cancelOrders_allEth() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(_eth, 1 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(_eth, 2 ether, address(_tokenA), AMOUNT_A);

        uint256 makerEthBefore = _maker.balance;
        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders{value: 3 ether}(orders);

        vm.prank(_maker);
        _board.cancelOrders(ids);

        assertEq(_maker.balance, makerEthBefore);
        assertEq(address(_board).balance, 0);
        assertEq(_board.getOrder(ids[0]).maker, address(0));
        assertEq(_board.getOrder(ids[1]).maker, address(0));
    }

    /// @notice Tests cancelOrders reverts when maker rejects ETH and leaves escrow intact
    function test_cancelOrders_revert_ethTransferFailed() public {
        ETHRejecter rejecter = new ETHRejecter();
        vm.deal(address(rejecter), 10 ether);

        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(_eth, 1 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(_eth, 1 ether, address(_tokenA), AMOUNT_A);

        vm.prank(address(rejecter));
        uint256[] memory ids = _board.createOrders{value: 2 ether}(orders);

        uint256 boardEthBefore = address(_board).balance;
        vm.prank(address(rejecter));
        vm.expectRevert(ETHRejecter.RejectETH.selector);
        _board.cancelOrders(ids);

        assertTrue(_board.canFill(ids[0]));
        assertTrue(_board.canFill(ids[1]));
        assertEq(address(_board).balance, boardEthBefore);
    }

    /// @notice Tests cancelOrders restores distinct tokenA balances independently
    function test_cancelOrders_differentTokenA() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenB), AMOUNT_B, address(_tokenA), AMOUNT_A);

        uint256 makerABefore = _tokenA.balanceOf(_maker);
        uint256 makerBBefore = _tokenB.balanceOf(_maker);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        _tokenB.approve(address(_board), AMOUNT_B);
        uint256[] memory ids = _board.createOrders(orders);
        _board.cancelOrders(ids);
        vm.stopPrank();

        assertEq(_tokenA.balanceOf(_maker), makerABefore);
        assertEq(_tokenB.balanceOf(_maker), makerBBefore);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
        assertEq(_tokenB.balanceOf(address(_board)), 0);
    }

    /// @notice Tests cancelOrders clears order storage
    function test_cancelOrders_deletesStorage() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        uint256[] memory ids = _board.createOrders(orders);
        _board.cancelOrders(ids);
        vm.stopPrank();

        for (uint256 i = 0; i < 2; ++i) {
            ISwapboard.Order memory order = _board.getOrder(ids[i]);
            assertEq(order.maker, address(0));
            assertFalse(order.active);
            assertEq(order.amountA, 0);
            assertEq(order.amountB, 0);
            assertEq(order.availableA, 0);
            assertEq(order.availableB, 0);
        }
    }

    /// @notice Tests DuplicateOrderId when a repeated id is not adjacent
    function test_cancelOrders_revert_duplicateOrderId_nonAdjacent() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        uint256[] memory ids = _board.createOrders(orders);

        uint256[] memory cancelIds = new uint256[](3);
        cancelIds[0] = ids[0];
        cancelIds[1] = ids[1];
        cancelIds[2] = ids[0];
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.DuplicateOrderId.selector, ids[0]));
        _board.cancelOrders(cancelIds);
        vm.stopPrank();

        assertTrue(_board.canFill(ids[0]));
        assertTrue(_board.canFill(ids[1]));
        assertEq(_tokenA.balanceOf(address(_board)), AMOUNT_A * 2);
    }

    /// @notice Property: cancelOrders refunds the summed remaining same-tokenA amounts
    function testFuzz_cancelOrders_aggregatesSameToken(
        uint256 amountA1Seed,
        uint256 amountA2Seed
    ) public {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountA1 = uint128(bound(amountA1Seed, 1, type(uint64).max));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountA2 = uint128(bound(amountA2Seed, 1, type(uint64).max));
        uint256 totalA = uint256(amountA1) + uint256(amountA2);

        _tokenA.mint(_maker, totalA);

        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), amountA1, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), amountA2, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), totalA);
        uint256[] memory ids = _board.createOrders(orders);
        uint256 makerBefore = _tokenA.balanceOf(_maker);
        _board.cancelOrders(ids);
        vm.stopPrank();

        assertEq(_tokenA.balanceOf(_maker), makerBefore + totalA);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
        assertEq(_board.getOrder(ids[0]).maker, address(0));
        assertEq(_board.getOrder(ids[1]).maker, address(0));
    }

    /// @notice Tests fillOrders fills two orders and pulls tokenB once
    function test_fillOrders_aggregatesSameTokenB() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        uint256[] memory ids = _board.createOrders(orders);
        vm.stopPrank();

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = FillTestLib.fillParams(_board.getOrder(ids[0]), ids[0], AMOUNT_A);
        fills[1] = FillTestLib.fillParams(_board.getOrder(ids[1]), ids[1], AMOUNT_A);

        uint256 takerABefore = _tokenA.balanceOf(_taker);
        uint256 makerBBefore = _tokenB.balanceOf(_maker);
        uint256 tokenAPullsBefore = _tf(_tokenA);
        uint256 tokenBPullsBefore = _tf(_tokenB);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B * 2);
        _board.fillOrders(fills, 0);
        vm.stopPrank();

        assertEq(_tf(_tokenA), tokenAPullsBefore);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 1);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
        assertEq(_tokenA.balanceOf(_taker), takerABefore + AMOUNT_A * 2);
        assertEq(_tokenB.balanceOf(_maker), makerBBefore + AMOUNT_B * 2);
        assertFalse(_board.canFill(ids[0]));
        assertFalse(_board.canFill(ids[1]));
        assertFalse(_board.getOrder(ids[0]).active);
        assertFalse(_board.getOrder(ids[1]).active);
        assertEq(_board.getOrder(ids[0]).availableA, 0);
        assertEq(_board.getOrder(ids[1]).availableA, 0);
    }

    /// @notice Tests the same orderId twice when partial fills leave enough liquidity
    function test_fillOrders_sameOrderId_partialThenPartial() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        uint128 fillA1 = AMOUNT_A / 4;
        uint128 fillA2 = AMOUNT_A / 4;
        uint256 bIn1 = (uint256(fillA1) * uint256(AMOUNT_B) + uint256(AMOUNT_A) - 1) / uint256(AMOUNT_A);
        uint128 remA = AMOUNT_A - fillA1;
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 remB = uint128(uint256(AMOUNT_B) - bIn1);
        uint256 bIn2 = (uint256(fillA2) * uint256(remB) + uint256(remA) - 1) / uint256(remA);

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = FillTestLib.fillParams(_board.getOrder(orderId), orderId, fillA1);
        fills[1] = FillTestLib.fillParams(_board.getOrder(orderId), orderId, fillA2);

        uint256 tokenAPullsBefore = _tf(_tokenA);
        uint256 tokenBPullsBefore = _tf(_tokenB);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), bIn1 + bIn2);
        _board.fillOrders(fills, 0);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertTrue(order.active);
        assertEq(order.availableA, AMOUNT_A - fillA1 - fillA2);
        assertEq(_tf(_tokenA), tokenAPullsBefore);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 1);
        assertEq(_tokenA.balanceOf(address(_board)), order.availableA);
    }

    /// @notice Tests same orderId twice reverts when the second leg exceeds remaining
    function test_fillOrders_revert_sameOrderId_insufficientRemaining() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = FillTestLib.fillParams(_board.getOrder(orderId), orderId, AMOUNT_A / 2);
        fills[1] = FillTestLib.fillParams(_board.getOrder(orderId), orderId, AMOUNT_A);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B * 2);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.FillAmountTooHigh.selector, orderId, AMOUNT_A, AMOUNT_A / 2));
        _board.fillOrders(fills, 0);
        vm.stopPrank();

        assertTrue(_board.canFill(orderId));
        assertEq(_board.getOrder(orderId).availableA, AMOUNT_A);
        assertEq(_tf(_tokenB), 0);
        assertEq(_tokenA.balanceOf(address(_board)), AMOUNT_A);
    }

    /// @notice Tests empty fillOrders reverts
    function test_fillOrders_revert_empty() public {
        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](0);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.fillOrders(fills, 0);
    }

    /// @notice Tests fillOrders reverts on expired deadline without transferring
    function test_fillOrders_revert_deadlineExpired() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](1);
        fills[0] = FillTestLib.fillParams(_board.getOrder(orderId), orderId, AMOUNT_A);

        vm.warp(100);
        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        vm.expectRevert(ISwapboard.DeadlineExpired.selector);
        _board.fillOrders(fills, 99);
        vm.stopPrank();

        assertTrue(_board.canFill(orderId));
        assertEq(_tf(_tokenB), 0);
    }

    /// @notice Tests fillOrders ETH tokenB mismatch reverts after validating
    function test_fillOrders_revert_ethMismatch() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), AMOUNT_A, _eth, 1 ether);
        orders[1] = _order(address(_tokenA), AMOUNT_A, _eth, 1 ether);
        uint256[] memory ids = _board.createOrders(orders);
        vm.stopPrank();

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = FillTestLib.fillParams(_board.getOrder(ids[0]), ids[0], AMOUNT_A);
        fills[1] = FillTestLib.fillParams(_board.getOrder(ids[1]), ids[1], AMOUNT_A);

        vm.deal(_taker, 5 ether);
        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, 2 ether, 1 ether));
        _board.fillOrders{value: 1 ether}(fills, 0);

        assertTrue(_board.canFill(ids[0]));
        assertTrue(_board.canFill(ids[1]));
        assertEq(_tokenA.balanceOf(address(_board)), AMOUNT_A * 2);
    }

    /// @notice Tests fillOrders aggregates ETH tokenB to one maker send and ETH tokenA out
    function test_fillOrders_mixedEthLegs() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 idSell = _board.createOrder(_order(address(_tokenA), AMOUNT_A, _eth, 1 ether));
        uint256 idBuy = _board.createOrder{value: 2 ether}(_order(_eth, 2 ether, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = FillTestLib.fillParams(_board.getOrder(idSell), idSell, AMOUNT_A);
        fills[1] = FillTestLib.fillParams(_board.getOrder(idBuy), idBuy, 2 ether);

        uint256 makerEthBefore = _maker.balance;
        uint256 takerEthBefore = _taker.balance;
        uint256 takerABefore = _tokenA.balanceOf(_taker);
        uint256 tokenAPullsBefore = _tf(_tokenA);
        uint256 tokenBPullsBefore = _tf(_tokenB);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _board.fillOrders{value: 1 ether}(fills, 0);
        vm.stopPrank();

        assertEq(_tf(_tokenA), tokenAPullsBefore);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 1);
        assertEq(_maker.balance, makerEthBefore + 1 ether);
        assertEq(_taker.balance, takerEthBefore - 1 ether + 2 ether);
        assertEq(_tokenA.balanceOf(_taker), takerABefore + AMOUNT_A);
        assertEq(address(_board).balance, 0);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
        assertFalse(_board.canFill(idSell));
        assertFalse(_board.canFill(idBuy));
        assertFalse(_board.getOrder(idSell).active);
        assertFalse(_board.getOrder(idBuy).active);
        assertEq(_board.getOrder(idSell).availableA, 0);
        assertEq(_board.getOrder(idBuy).availableA, 0);
    }

    /// @notice Tests a one-item fillOrders matches fillOrder accounting
    function test_fillOrders_singleElement() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](1);
        fills[0] = FillTestLib.fillParams(_board.getOrder(orderId), orderId, AMOUNT_A);

        uint256 takerABefore = _tokenA.balanceOf(_taker);
        uint256 tokenAPullsBefore = _tf(_tokenA);
        uint256 tokenBPullsBefore = _tf(_tokenB);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _board.fillOrders(fills, 0);
        vm.stopPrank();

        assertFalse(_board.canFill(orderId));
        assertFalse(_board.getOrder(orderId).active);
        assertEq(_board.getOrder(orderId).availableA, 0);
        assertEq(_tf(_tokenA), tokenAPullsBefore);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 1);
        assertEq(_tokenA.balanceOf(_taker), takerABefore + AMOUNT_A);
    }

    /// @notice Tests fillOrders emits OrderFilled for each leg
    function test_fillOrders_events() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        uint256[] memory ids = _board.createOrders(orders);
        vm.stopPrank();

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = FillTestLib.fillParams(_board.getOrder(ids[0]), ids[0], AMOUNT_A);
        fills[1] = FillTestLib.fillParams(_board.getOrder(ids[1]), ids[1], AMOUNT_A);

        uint256 tokenAPullsBefore = _tf(_tokenA);
        uint256 tokenBPullsBefore = _tf(_tokenB);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B * 2);
        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderFilled({orderId: ids[0], taker: _taker, amountA: AMOUNT_A, amountB: AMOUNT_B});
        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderFilled({orderId: ids[1], taker: _taker, amountA: AMOUNT_A, amountB: AMOUNT_B});
        _board.fillOrders(fills, 0);
        vm.stopPrank();

        assertFalse(_board.getOrder(ids[0]).active);
        assertFalse(_board.getOrder(ids[1]).active);
        assertEq(_board.getOrder(ids[0]).availableA, 0);
        assertEq(_board.getOrder(ids[1]).availableA, 0);
        assertEq(_tf(_tokenA), tokenAPullsBefore);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 1);
    }

    /// @notice Tests fillOrders reverts OrderNotFound on a later item without transferring
    function test_fillOrders_revert_orderNotFound_laterItem() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = FillTestLib.fillParams(_board.getOrder(orderId), orderId, AMOUNT_A);
        fills[1] = FillTestLib.fillParams(_board.getOrder(999), 999, AMOUNT_A);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B * 2);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, 999));
        _board.fillOrders(fills, 0);
        vm.stopPrank();

        assertTrue(_board.canFill(orderId));
        assertEq(_tf(_tokenB), 0);
        assertEq(_tokenA.balanceOf(address(_board)), AMOUNT_A);
    }

    /// @notice Property: two same-tokenB fills pull once for the summed amount
    function testFuzz_fillOrders_aggregatesSameTokenB(
        uint256 amountA1Seed,
        uint256 amountA2Seed
    ) public {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountA1 = uint128(bound(amountA1Seed, 1, type(uint64).max));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountA2 = uint128(bound(amountA2Seed, 1, type(uint64).max));
        uint128 amountB1 = amountA1;
        uint128 amountB2 = amountA2;
        uint256 totalA = uint256(amountA1) + uint256(amountA2);
        uint256 totalB = uint256(amountB1) + uint256(amountB2);

        _tokenA.mint(_maker, totalA);
        _tokenB.mint(_taker, totalB);

        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), amountA1, address(_tokenB), amountB1);
        orders[1] = _order(address(_tokenA), amountA2, address(_tokenB), amountB2);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), totalA);
        uint256[] memory ids = _board.createOrders(orders);
        vm.stopPrank();

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = FillTestLib.fillParams(_board.getOrder(ids[0]), ids[0], amountA1);
        fills[1] = FillTestLib.fillParams(_board.getOrder(ids[1]), ids[1], amountA2);

        uint256 tokenAPullsBefore = _tf(_tokenA);
        uint256 tokenBPullsBefore = _tf(_tokenB);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), totalB);
        _board.fillOrders(fills, 0);
        vm.stopPrank();

        assertEq(_tf(_tokenA), tokenAPullsBefore);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 1);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
        assertEq(_tokenB.balanceOf(address(_board)), 0);
        assertFalse(_board.getOrder(ids[0]).active);
        assertFalse(_board.getOrder(ids[1]).active);
        assertEq(_board.getOrder(ids[0]).availableA, 0);
        assertEq(_board.getOrder(ids[1]).availableA, 0);
    }

    /// @notice Tests fillOrders reverts ZeroAmount when a leg has amountA == 0
    function test_fillOrders_revert_zeroAmountA() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = FillTestLib.fillParams(_board.getOrder(orderId), orderId, AMOUNT_A);
        fills[1] = FillTestLib.fillParams(_board.getOrder(orderId), orderId, 0);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.fillOrders(fills, 0);
        vm.stopPrank();

        assertTrue(_board.canFill(orderId));
        assertEq(_tf(_tokenB), 0);
        assertEq(_tokenA.balanceOf(address(_board)), AMOUNT_A);
    }

    /// @notice Tests fillOrders reverts OrderNotActive when a later leg targets a spent order
    function test_fillOrders_revert_orderNotActive_laterItem() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = FillTestLib.fillParams(_board.getOrder(orderId), orderId, AMOUNT_A);
        fills[1] = FillTestLib.fillParams(_board.getOrder(orderId), orderId, 1);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B + 1);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        _board.fillOrders(fills, 0);
        vm.stopPrank();

        assertTrue(_board.canFill(orderId));
        assertEq(_tokenA.balanceOf(address(_board)), AMOUNT_A);
        assertEq(_tf(_tokenB), 0);
    }

    /// @notice Tests PartialFillNotAllowed when the same non-partial order appears twice
    function test_fillOrders_revert_partialFillNotAllowed_sameOrderId() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = FillTestLib.fillParams(_board.getOrder(orderId), orderId, AMOUNT_A / 2);
        fills[1] = FillTestLib.fillParams(_board.getOrder(orderId), orderId, AMOUNT_A / 2);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.PartialFillNotAllowed.selector, orderId));
        _board.fillOrders(fills, 0);
        vm.stopPrank();

        assertTrue(_board.canFill(orderId));
        assertEq(_board.getOrder(orderId).availableA, AMOUNT_A);
        assertEq(_tf(_tokenB), 0);
    }

    /// @notice Tests fillOrders reverts when msg.value exceeds required ETH tokenB
    function test_fillOrders_revert_ethMismatch_tooHigh() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, _eth, 1 ether));
        vm.stopPrank();

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](1);
        fills[0] = FillTestLib.fillParams(_board.getOrder(orderId), orderId, AMOUNT_A);

        vm.deal(_taker, 5 ether);
        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, 1 ether, 2 ether));
        _board.fillOrders{value: 2 ether}(fills, 0);

        assertTrue(_board.canFill(orderId));
        assertEq(_tokenA.balanceOf(address(_board)), AMOUNT_A);
    }

    /// @notice Tests ERC20-only fillOrders reverts when msg.value is non-zero
    function test_fillOrders_revert_accidentalEth() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](1);
        fills[0] = FillTestLib.fillParams(_board.getOrder(orderId), orderId, AMOUNT_A);

        vm.deal(_taker, 1 ether);
        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, 0, 1 ether));
        _board.fillOrders{value: 1 ether}(fills, 0);
        vm.stopPrank();

        assertTrue(_board.canFill(orderId));
        assertEq(_tf(_tokenB), 0);
    }

    /// @notice Tests fillOrders pulls each distinct tokenB once
    function test_fillOrders_differentTokenB() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        _tokenB.approve(address(_board), AMOUNT_B);
        uint256 id0 = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        uint256 id1 = _board.createOrder(_order(address(_tokenB), AMOUNT_B, address(_tokenA), AMOUNT_A));
        vm.stopPrank();

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = FillTestLib.fillParams(_board.getOrder(id0), id0, AMOUNT_A);
        fills[1] = FillTestLib.fillParams(_board.getOrder(id1), id1, AMOUNT_B);

        uint256 makerABefore = _tokenA.balanceOf(_maker);
        uint256 makerBBefore = _tokenB.balanceOf(_maker);
        uint256 tokenAPullsBefore = _tf(_tokenA);
        uint256 tokenBPullsBefore = _tf(_tokenB);

        vm.startPrank(_taker);
        _tokenA.approve(address(_board), AMOUNT_A);
        _tokenB.approve(address(_board), AMOUNT_B);
        _board.fillOrders(fills, 0);
        vm.stopPrank();

        assertEq(_tf(_tokenA), tokenAPullsBefore + 1);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 1);
        assertEq(_tokenA.balanceOf(_maker), makerABefore + AMOUNT_A);
        assertEq(_tokenB.balanceOf(_maker), makerBBefore + AMOUNT_B);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
        assertEq(_tokenB.balanceOf(address(_board)), 0);
        assertFalse(_board.getOrder(id0).active);
        assertFalse(_board.getOrder(id1).active);
        assertEq(_board.getOrder(id0).availableA, 0);
        assertEq(_board.getOrder(id1).availableA, 0);
    }

    /// @notice Tests fillOrders pays two makers separately after one aggregated pull
    function test_fillOrders_differentMakers_sameTokenB() public {
        address maker2 = address(0x3);
        _tokenA.mint(maker2, AMOUNT_A);
        vm.prank(maker2);
        _tokenA.approve(address(_board), AMOUNT_A);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 id0 = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        vm.prank(maker2);
        uint256 id1 = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = FillTestLib.fillParams(_board.getOrder(id0), id0, AMOUNT_A);
        fills[1] = FillTestLib.fillParams(_board.getOrder(id1), id1, AMOUNT_A);

        uint256 makerBBefore = _tokenB.balanceOf(_maker);
        uint256 maker2BBefore = _tokenB.balanceOf(maker2);
        uint256 tokenAPullsBefore = _tf(_tokenA);
        uint256 tokenBPullsBefore = _tf(_tokenB);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B * 2);
        _board.fillOrders(fills, 0);
        vm.stopPrank();

        assertEq(_tf(_tokenA), tokenAPullsBefore);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 1);
        assertEq(_tokenB.balanceOf(_maker), makerBBefore + AMOUNT_B);
        assertEq(_tokenB.balanceOf(maker2), maker2BBefore + AMOUNT_B);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
        assertFalse(_board.getOrder(id0).active);
        assertFalse(_board.getOrder(id1).active);
        assertEq(_board.getOrder(id0).availableA, 0);
        assertEq(_board.getOrder(id1).availableA, 0);
    }

    /// @notice Tests same orderId partial then exact remaining completes the order
    function test_fillOrders_sameOrderId_partialThenRemaining() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        uint128 fillA1 = AMOUNT_A / 4;
        uint256 bIn1 = (uint256(fillA1) * uint256(AMOUNT_B) + uint256(AMOUNT_A) - 1) / uint256(AMOUNT_A);
        uint128 remA = AMOUNT_A - fillA1;
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 remB = uint128(uint256(AMOUNT_B) - bIn1);

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = FillTestLib.fillParams(_board.getOrder(orderId), orderId, fillA1);
        fills[1] = FillTestLib.fillParams(_board.getOrder(orderId), orderId, remA);

        uint256 tokenAPullsBefore = _tf(_tokenA);
        uint256 tokenBPullsBefore = _tf(_tokenB);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), bIn1 + remB);
        _board.fillOrders(fills, 0);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(_board.canFill(orderId));
        assertFalse(order.active);
        assertEq(order.availableA, 0);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
        assertEq(_tf(_tokenA), tokenAPullsBefore);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 1);
    }

    /// @notice Tests aggregated tokenB pull reverts when allowance is too low
    function test_fillOrders_revert_insufficientAllowance() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        uint256[] memory ids = _board.createOrders(orders);
        vm.stopPrank();

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = FillTestLib.fillParams(_board.getOrder(ids[0]), ids[0], AMOUNT_A);
        fills[1] = FillTestLib.fillParams(_board.getOrder(ids[1]), ids[1], AMOUNT_A);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        vm.expectRevert(stdError.arithmeticError);
        _board.fillOrders(fills, 0);
        vm.stopPrank();

        assertTrue(_board.canFill(ids[0]));
        assertTrue(_board.canFill(ids[1]));
        assertEq(_tokenA.balanceOf(address(_board)), AMOUNT_A * 2);
        assertEq(_tokenB.allowance(_taker, address(_board)), AMOUNT_B);
    }

    /// @notice Tests aggregated tokenB pull reverts when balance is too low
    function test_fillOrders_revert_insufficientBalance() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        uint256[] memory ids = _board.createOrders(orders);
        vm.stopPrank();

        uint256 excess = _tokenB.balanceOf(_taker) - AMOUNT_B;
        vm.prank(_taker);
        assertTrue(_tokenB.transfer(address(0xdead), excess));

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = FillTestLib.fillParams(_board.getOrder(ids[0]), ids[0], AMOUNT_A);
        fills[1] = FillTestLib.fillParams(_board.getOrder(ids[1]), ids[1], AMOUNT_A);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B * 2);
        vm.expectRevert(stdError.arithmeticError);
        _board.fillOrders(fills, 0);
        vm.stopPrank();

        assertTrue(_board.canFill(ids[0]));
        assertTrue(_board.canFill(ids[1]));
        assertEq(_tokenA.balanceOf(address(_board)), AMOUNT_A * 2);
    }

    /// @notice Tests fillOrders reverts when maker rejects ETH tokenB and leaves escrow intact
    function test_fillOrders_revert_ethTransferFailed_maker() public {
        ETHRejecter rejecter = new ETHRejecter();
        _tokenB.mint(address(rejecter), AMOUNT_B);

        vm.startPrank(address(rejecter));
        _tokenB.approve(address(_board), AMOUNT_B);
        uint256 orderId = _board.createOrder(_order(address(_tokenB), AMOUNT_B, _eth, ETH_AMOUNT));
        vm.stopPrank();

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](1);
        fills[0] = FillTestLib.fillParams(_board.getOrder(orderId), orderId, AMOUNT_B);

        uint256 boardTokenBefore = _tokenB.balanceOf(address(_board));
        vm.prank(_taker);
        vm.expectRevert(ETHRejecter.RejectETH.selector);
        _board.fillOrders{value: ETH_AMOUNT}(fills, 0);

        assertTrue(_board.canFill(orderId));
        assertEq(_tokenB.balanceOf(address(_board)), boardTokenBefore);
    }

    /// @notice Tests fillOrders reverts when taker rejects ETH tokenA and leaves escrow intact
    function test_fillOrders_revert_ethTransferFailed_taker() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));

        ETHRejecter rejecter = new ETHRejecter();
        _tokenB.mint(address(rejecter), AMOUNT_B);

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](1);
        fills[0] = FillTestLib.fillParams(_board.getOrder(orderId), orderId, ETH_AMOUNT);

        uint256 boardEthBefore = address(_board).balance;
        vm.startPrank(address(rejecter));
        _tokenB.approve(address(_board), AMOUNT_B);
        vm.expectRevert(ETHRejecter.RejectETH.selector);
        _board.fillOrders(fills, 0);
        vm.stopPrank();

        assertTrue(_board.canFill(orderId));
        assertEq(address(_board).balance, boardEthBefore);
    }

    /// @notice Tests fillOrders succeeds when block.timestamp equals deadline
    function test_fillOrders_deadlineEqual_succeeds() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](1);
        fills[0] = FillTestLib.fillParams(_board.getOrder(orderId), orderId, AMOUNT_A);

        uint256 deadline = 1000;
        vm.warp(deadline);

        uint256 tokenAPullsBefore = _tf(_tokenA);
        uint256 tokenBPullsBefore = _tf(_tokenB);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _board.fillOrders(fills, deadline);
        vm.stopPrank();

        assertFalse(_board.canFill(orderId));
        assertFalse(_board.getOrder(orderId).active);
        assertEq(_board.getOrder(orderId).availableA, 0);
        assertEq(_tf(_tokenA), tokenAPullsBefore);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 1);
    }

    /// @notice Tests fillOrders deadlineZero noExpiry
    function test_fillOrders_deadlineZero_noExpiry() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](1);
        fills[0] = FillTestLib.fillParams(_board.getOrder(orderId), orderId, AMOUNT_A);

        vm.warp(type(uint256).max);

        uint256 tokenAPullsBefore = _tf(_tokenA);
        uint256 tokenBPullsBefore = _tf(_tokenB);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _board.fillOrders(fills, 0);
        vm.stopPrank();

        assertFalse(_board.getOrder(orderId).active);
        assertEq(_board.getOrder(orderId).availableA, 0);
        assertEq(_tf(_tokenA), tokenAPullsBefore);
        assertEq(_tf(_tokenB), tokenBPullsBefore + 1);
    }

    /// @notice Tests fillOrders reverts FillAmountTooHigh on a later distinct order without pulling
    function test_fillOrders_revert_fillAmountTooHigh_laterDistinctOrder() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _orderPartial(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        orders[1] = _orderPartial(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        uint256[] memory ids = _board.createOrders(orders);
        vm.stopPrank();

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = FillTestLib.fillParams(_board.getOrder(ids[0]), ids[0], AMOUNT_A);
        fills[1] = FillTestLib.fillParams(_board.getOrder(ids[1]), ids[1], AMOUNT_A + 1);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B * 2);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.FillAmountTooHigh.selector, ids[1], AMOUNT_A + 1, AMOUNT_A));
        _board.fillOrders(fills, 0);
        vm.stopPrank();

        assertTrue(_board.canFill(ids[0]));
        assertTrue(_board.canFill(ids[1]));
        assertEq(_tokenA.balanceOf(address(_board)), AMOUNT_A * 2);
        assertEq(_tf(_tokenB), 0);
    }

    /// @notice Property: ETH tokenB fills require msg.value equal to the summed payment
    function testFuzz_fillOrders_aggregatesEthTokenB(
        uint256 amountA1Seed,
        uint256 amountA2Seed
    ) public {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountA1 = uint128(bound(amountA1Seed, 1 ether, 50 ether));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountA2 = uint128(bound(amountA2Seed, 1 ether, 50 ether));
        uint128 ethB1 = amountA1;
        uint128 ethB2 = amountA2;
        uint256 totalA = uint256(amountA1) + uint256(amountA2);
        uint256 totalEth = uint256(ethB1) + uint256(ethB2);

        _tokenA.mint(_maker, totalA);
        vm.deal(_taker, totalEth);

        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), amountA1, _eth, ethB1);
        orders[1] = _order(address(_tokenA), amountA2, _eth, ethB2);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), totalA);
        uint256[] memory ids = _board.createOrders(orders);
        vm.stopPrank();

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = FillTestLib.fillParams(_board.getOrder(ids[0]), ids[0], amountA1);
        fills[1] = FillTestLib.fillParams(_board.getOrder(ids[1]), ids[1], amountA2);

        uint256 makerEthBefore = _maker.balance;
        uint256 tokenAPullsBefore = _tf(_tokenA);
        vm.prank(_taker);
        _board.fillOrders{value: totalEth}(fills, 0);

        assertEq(_tf(_tokenA), tokenAPullsBefore);
        assertEq(_maker.balance, makerEthBefore + totalEth);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
        assertEq(address(_board).balance, 0);
        assertFalse(_board.getOrder(ids[0]).active);
        assertFalse(_board.getOrder(ids[1]).active);
        assertEq(_board.getOrder(ids[0]).availableA, 0);
        assertEq(_board.getOrder(ids[1]).availableA, 0);
    }

    // ============ modifyOrder ============

    /// @notice Tests modifyOrder reverts when previousAmounts does not match on-chain state
    function test_modifyOrder_reverts_on_state_mismatch() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A + 10 ether);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        _board.modifyOrder(orderId, _amounts(snapshot), _modify(AMOUNT_A + 10 ether, AMOUNT_B));
        vm.stopPrank();

        ISwapboard.Order memory afterFirst = _board.getOrder(orderId);

        vm.startPrank(_maker);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISwapboard.OrderStateMismatch.selector,
                orderId,
                snapshot.amountA,
                snapshot.amountB,
                snapshot.availableA,
                snapshot.availableB,
                afterFirst.amountA,
                afterFirst.amountB,
                afterFirst.availableA,
                afterFirst.availableB
            )
        );
        _board.modifyOrder(orderId, _amounts(snapshot), _modify(AMOUNT_A + 10 ether, AMOUNT_B));
        vm.stopPrank();
    }

    /// @notice Tests modifyOrder reverts when caller is not the maker
    function test_modifyOrder_reverts_notMaker() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotMaker.selector, orderId, _taker, _maker));
        _board.modifyOrder(orderId, _amounts(snapshot), _modify(AMOUNT_A, AMOUNT_B));
    }

    /// @notice Tests modifyOrder reverts when availableA is zero
    function test_modifyOrder_reverts_zeroAvailableA() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.modifyOrder(orderId, _amounts(snapshot), _modify(0, AMOUNT_B));
        vm.stopPrank();
    }

    /// @notice Tests modifyOrder reverts when availableB is zero
    function test_modifyOrder_reverts_zeroAvailableB() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.modifyOrder(orderId, _amounts(snapshot), _modify(AMOUNT_A, 0));
        vm.stopPrank();
    }

    /// @notice Tests modifyOrder reverts when remainings are unchanged
    function test_modifyOrder_reverts_noChange() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        uint256 makerTokenABefore = _tokenA.balanceOf(_maker);
        vm.expectRevert(ISwapboard.NoChange.selector);
        _board.modifyOrder(orderId, _amounts(snapshot), _modify(AMOUNT_A, AMOUNT_B));
        vm.stopPrank();

        assertEq(_tokenA.balanceOf(_maker), makerTokenABefore);
        ISwapboard.Order memory after_ = _board.getOrder(orderId);
        assertEq(after_.amountA, AMOUNT_A);
        assertEq(after_.availableA, AMOUNT_A);
        assertEq(after_.availableB, AMOUNT_B);
    }

    /// @notice Tests modifyOrder refunds tokenA when remaining availableA decreases
    function test_modifyOrder_refunds_tokenA_when_availableA_decreases() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        uint128 fillAmountA = AMOUNT_A / 2;
        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _fillOrder(orderId, fillAmountA);
        vm.stopPrank();

        ISwapboard.Order memory before = _board.getOrder(orderId);
        assertEq(before.availableA, AMOUNT_A - fillAmountA);

        uint128 newAvailableA = before.availableA / 2;
        uint128 expectedRefund = before.availableA - newAvailableA;
        uint256 makerBefore = _tokenA.balanceOf(_maker);

        vm.prank(_maker);
        _board.modifyOrder(orderId, _amounts(before), _modify(newAvailableA, before.availableB));

        assertEq(_tokenA.balanceOf(_maker) - makerBefore, expectedRefund);

        ISwapboard.Order memory after_ = _board.getOrder(orderId);
        assertEq(after_.amountA, newAvailableA);
        assertEq(after_.availableA, newAvailableA);
        assertEq(after_.amountB, before.availableB);
        assertEq(after_.availableB, before.availableB);
    }

    /// @notice Tests modifyOrder pulls additional tokenA when remaining availableA increases
    function test_modifyOrder_tops_up_tokenA_when_availableA_increases() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A + 25 ether);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        uint128 fillAmountA = AMOUNT_A / 2;
        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _fillOrder(orderId, fillAmountA);
        vm.stopPrank();

        ISwapboard.Order memory before = _board.getOrder(orderId);
        uint128 newAvailableA = before.availableA + 25 ether;
        uint256 makerBefore = _tokenA.balanceOf(_maker);

        vm.prank(_maker);
        _board.modifyOrder(orderId, _amounts(before), _modify(newAvailableA, before.availableB));

        assertEq(makerBefore - _tokenA.balanceOf(_maker), 25 ether);

        ISwapboard.Order memory after_ = _board.getOrder(orderId);
        assertEq(after_.amountA, newAvailableA);
        assertEq(after_.availableA, newAvailableA);
        assertEq(after_.availableB, before.availableB);
    }

    /// @notice Tests modifyOrder can change availableB without moving tokenA escrow
    function test_modifyOrder_updates_availableB_only() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        uint256 makerBefore = _tokenA.balanceOf(_maker);
        _board.modifyOrder(orderId, _amounts(snapshot), _modify(AMOUNT_A, AMOUNT_B * 2));
        vm.stopPrank();

        assertEq(_tokenA.balanceOf(_maker), makerBefore);

        ISwapboard.Order memory after_ = _board.getOrder(orderId);
        assertEq(after_.amountA, AMOUNT_A);
        assertEq(after_.amountB, AMOUNT_B * 2);
        assertEq(after_.availableA, AMOUNT_A);
        assertEq(after_.availableB, AMOUNT_B * 2);
        assertEq(after_.tokenA, address(_tokenA));
        assertEq(after_.tokenB, address(_tokenB));
    }

    /// @notice Tests modifyOrder can set remaining below previously filled amounts
    function test_modifyOrder_allows_any_remaining_afterPartialFill() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        uint128 fillAmountA = 60 ether;
        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _fillOrder(orderId, fillAmountA);
        vm.stopPrank();

        ISwapboard.Order memory before = _board.getOrder(orderId);
        assertEq(before.availableA, 40 ether);

        uint128 newAvailableA = 10 ether;
        uint256 makerBefore = _tokenA.balanceOf(_maker);

        vm.prank(_maker);
        _board.modifyOrder(orderId, _amounts(before), _modify(newAvailableA, before.availableB));

        assertEq(_tokenA.balanceOf(_maker) - makerBefore, 30 ether);

        ISwapboard.Order memory after_ = _board.getOrder(orderId);
        assertEq(after_.amountA, newAvailableA);
        assertEq(after_.availableA, newAvailableA);
        assertTrue(after_.active);
    }

    /// @notice Tests modifyOrder emits OrderModified
    function test_modifyOrder_emits_event() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        uint128 newAvailableB = AMOUNT_B / 2;

        vm.expectEmit(true, false, false, true, address(_board));
        emit ISwapboard.OrderModified(orderId, AMOUNT_A, newAvailableB);

        _board.modifyOrder(orderId, _amounts(snapshot), _modify(AMOUNT_A, newAvailableB));
        vm.stopPrank();
    }

    /// @notice Tests setPartialFillAllowed enables partial fills and emits OrderPartialFillUpdated
    function test_setPartialFillAllowed_enables() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        assertFalse(_board.getOrder(orderId).partialFillAllowed);

        vm.expectEmit(true, false, false, true, address(_board));
        emit ISwapboard.OrderPartialFillUpdated(orderId, true);
        _board.setPartialFillAllowed(orderId, true);
        vm.stopPrank();

        ISwapboard.Order memory after_ = _board.getOrder(orderId);
        assertTrue(after_.partialFillAllowed);
        assertEq(after_.availableA, AMOUNT_A);
        assertEq(after_.availableB, AMOUNT_B);
        assertEq(after_.amountA, AMOUNT_A);
        assertEq(after_.amountB, AMOUNT_B);
    }

    /// @notice Tests setPartialFillAllowed reverts when the flag is already the requested value
    function test_setPartialFillAllowed_reverts_noChange() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        assertFalse(_board.getOrder(orderId).partialFillAllowed);

        vm.expectRevert(ISwapboard.NoChange.selector);
        _board.setPartialFillAllowed(orderId, false);
        vm.stopPrank();

        assertFalse(_board.getOrder(orderId).partialFillAllowed);
    }

    /// @notice Tests setPartialFillAllowed reverts when re-setting the same enabled value
    function test_setPartialFillAllowed_reverts_noChange_afterEnable() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        _board.setPartialFillAllowed(orderId, true);

        vm.expectRevert(ISwapboard.NoChange.selector);
        _board.setPartialFillAllowed(orderId, true);
        vm.stopPrank();

        assertTrue(_board.getOrder(orderId).partialFillAllowed);
    }

    /// @notice Tests setPartialFillAllowed reverts for a non-existent order
    function test_setPartialFillAllowed_reverts_orderNotFound() public {
        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, 999));
        _board.setPartialFillAllowed(999, true);
    }

    /// @notice Tests setPartialFillAllowed reverts after a full fill (order is inactive)
    function test_setPartialFillAllowed_reverts_orderNotActive_afterFill() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _fillOrder(orderId, AMOUNT_A);
        vm.stopPrank();

        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        _board.setPartialFillAllowed(orderId, true);
    }

    /// @notice Tests setPartialFillAllowed reverts after cancel (order is deleted)
    function test_setPartialFillAllowed_reverts_orderNotFound_afterCancel() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        _board.cancelOrder(orderId);
        vm.stopPrank();

        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, orderId));
        _board.setPartialFillAllowed(orderId, true);
    }

    /// @notice Tests modifyOrder reverts for a non-existent order
    function test_modifyOrder_reverts_orderNotFound() public {
        ISwapboard.OrderAmounts memory previous =
            ISwapboard.OrderAmounts({amountA: 1, amountB: 1, availableA: 1, availableB: 1});

        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, 999));
        _board.modifyOrder(999, previous, _modify(1, 1));
    }

    /// @notice Tests modifyOrder reverts after a full fill (order is inactive)
    function test_modifyOrder_reverts_orderNotActive_afterFill() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _fillOrder(orderId, AMOUNT_A);
        vm.stopPrank();

        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        _board.modifyOrder(orderId, _amounts(snapshot), _modify(AMOUNT_A, AMOUNT_B));
    }

    /// @notice Tests modifyOrder reverts after cancel (order is deleted)
    function test_modifyOrder_reverts_orderNotFound_afterCancel() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        _board.cancelOrder(orderId);
        vm.stopPrank();

        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, orderId));
        _board.modifyOrder(orderId, _amounts(snapshot), _modify(AMOUNT_A, AMOUNT_B));
    }

    /// @notice Tests modifyOrder reverts when a fill races between snapshot and modify
    function test_modifyOrder_reverts_stateMismatch_afterFill() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _fillOrder(orderId, AMOUNT_A / 2);
        vm.stopPrank();

        ISwapboard.Order memory afterFill = _board.getOrder(orderId);

        vm.prank(_maker);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISwapboard.OrderStateMismatch.selector,
                orderId,
                snapshot.amountA,
                snapshot.amountB,
                snapshot.availableA,
                snapshot.availableB,
                afterFill.amountA,
                afterFill.amountB,
                afterFill.availableA,
                afterFill.availableB
            )
        );
        _board.modifyOrder(orderId, _amounts(snapshot), _modify(AMOUNT_A, AMOUNT_B));
    }

    /// @notice Tests ZeroAmount blocks setting remaining to 0; cancel is required to close the order
    function test_modifyOrder_reverts_zeroRemaining_mustCancel() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        uint256 makerBefore = _tokenA.balanceOf(_maker);
        uint256 boardBefore = _tokenA.balanceOf(address(_board));

        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.modifyOrder(orderId, _amounts(snapshot), _modify(0, AMOUNT_B));

        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.modifyOrder(orderId, _amounts(snapshot), _modify(AMOUNT_A, 0));

        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.modifyOrder(orderId, _amounts(snapshot), _modify(0, 0));

        assertTrue(_board.canFill(orderId));
        assertEq(_tokenA.balanceOf(_maker), makerBefore);
        assertEq(_tokenA.balanceOf(address(_board)), boardBefore);
        assertEq(_board.getOrder(orderId).availableA, AMOUNT_A);
        assertEq(_board.getOrder(orderId).availableB, AMOUNT_B);

        _board.cancelOrder(orderId);
        vm.stopPrank();

        assertFalse(_board.canFill(orderId));
        assertEq(_board.getOrder(orderId).maker, address(0));
        assertEq(_tokenA.balanceOf(_maker), makerBefore + AMOUNT_A);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
    }

    /// @notice Tests ZeroAmount still blocks remaining 0 after a partial fill; leftover escrow is cancelled
    function test_modifyOrder_reverts_zeroRemaining_afterPartialFill_mustCancel() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _fillOrder(orderId, AMOUNT_A / 2);
        vm.stopPrank();

        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        assertEq(snapshot.availableA, AMOUNT_A / 2);

        uint256 makerBefore = _tokenA.balanceOf(_maker);
        uint256 boardBefore = _tokenA.balanceOf(address(_board));

        vm.startPrank(_maker);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.modifyOrder(orderId, _amounts(snapshot), _modify(0, snapshot.availableB));

        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.modifyOrder(orderId, _amounts(snapshot), _modify(snapshot.availableA, 0));

        assertTrue(_board.canFill(orderId));
        assertEq(_tokenA.balanceOf(address(_board)), boardBefore);

        _board.cancelOrder(orderId);
        vm.stopPrank();

        assertFalse(_board.canFill(orderId));
        assertEq(_tokenA.balanceOf(_maker), makerBefore + snapshot.availableA);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
    }

    /// @notice Tests ZeroAmount blocks setting ETH remaining to 0; cancel refunds escrow instead
    function test_modifyOrder_sellEth_reverts_zeroRemaining_mustCancel() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        uint256 makerBefore = _maker.balance;
        uint256 boardBefore = address(_board).balance;

        vm.startPrank(_maker);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.modifyOrder(orderId, _amounts(snapshot), _modify(0, AMOUNT_B));

        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.modifyOrder(orderId, _amounts(snapshot), _modify(ETH_AMOUNT, 0));

        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.modifyOrder(orderId, _amounts(snapshot), _modify(0, 0));

        assertTrue(_board.canFill(orderId));
        assertEq(_maker.balance, makerBefore);
        assertEq(address(_board).balance, boardBefore);
        assertEq(_board.getOrder(orderId).availableA, ETH_AMOUNT);

        _board.cancelOrder(orderId);
        vm.stopPrank();

        assertFalse(_board.canFill(orderId));
        assertEq(_maker.balance, makerBefore + ETH_AMOUNT);
        assertEq(address(_board).balance, 0);
    }

    /// @notice Tests modifyOrder reverts if ETH is sent when tokenA is ERC20
    function test_modifyOrder_erc20_revert_accidentalEth() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, 0, 1 ether));
        _board.modifyOrder{value: 1 ether}(orderId, _amounts(snapshot), _modify(AMOUNT_A, AMOUNT_B * 2));
        vm.stopPrank();
    }

    /// @notice Tests modifyOrder selling ETH refunds excess escrow
    function test_modifyOrder_sellEth_refunds() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        uint128 newAvailableA = ETH_AMOUNT / 2;
        uint256 makerBefore = _maker.balance;
        uint256 boardBefore = address(_board).balance;

        vm.prank(_maker);
        _board.modifyOrder(orderId, _amounts(snapshot), _modify(newAvailableA, AMOUNT_B));

        ISwapboard.Order memory after_ = _board.getOrder(orderId);
        assertEq(after_.availableA, newAvailableA);
        assertEq(after_.amountA, newAvailableA);
        assertEq(_maker.balance, makerBefore + newAvailableA);
        assertEq(address(_board).balance, boardBefore - newAvailableA);
    }

    /// @notice Tests modifyOrder selling ETH tops up escrow with msg.value
    function test_modifyOrder_sellEth_topsUp() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        uint128 extra = 0.5 ether;
        uint128 newAvailableA = ETH_AMOUNT + extra;
        uint256 makerBefore = _maker.balance;
        uint256 boardBefore = address(_board).balance;

        vm.prank(_maker);
        _board.modifyOrder{value: extra}(orderId, _amounts(snapshot), _modify(newAvailableA, AMOUNT_B));

        ISwapboard.Order memory after_ = _board.getOrder(orderId);
        assertEq(after_.availableA, newAvailableA);
        assertEq(after_.amountA, newAvailableA);
        assertEq(_maker.balance, makerBefore - extra);
        assertEq(address(_board).balance, boardBefore + extra);
    }

    /// @notice Tests modifyOrder selling ETH reverts when msg.value is too low
    function test_modifyOrder_sellEth_revert_ethMismatch_tooLow() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, 0.5 ether, 0));
        _board.modifyOrder(orderId, _amounts(snapshot), _modify(ETH_AMOUNT + 0.5 ether, AMOUNT_B));
    }

    /// @notice Tests modifyOrder selling ETH reverts when msg.value is too high
    function test_modifyOrder_sellEth_revert_ethMismatch_tooHigh() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, 0.5 ether, 1 ether));
        _board.modifyOrder{value: 1 ether}(orderId, _amounts(snapshot), _modify(ETH_AMOUNT + 0.5 ether, AMOUNT_B));
    }

    /// @notice Tests modifyOrder selling ETH reverts when shrinking remaining but ETH is also sent
    function test_modifyOrder_sellEth_refund_revert_accidentalEth() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, 0, 0.1 ether));
        _board.modifyOrder{value: 0.1 ether}(orderId, _amounts(snapshot), _modify(ETH_AMOUNT / 2, AMOUNT_B));
    }

    /// @notice Tests modifyOrder ETH refund reverts when maker rejects ETH and leaves escrow intact
    function test_modifyOrder_sellEth_revert_ethTransferFailed() public {
        ETHRejecter rejecter = new ETHRejecter();
        vm.deal(address(rejecter), 10 ether);

        vm.prank(address(rejecter));
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        uint256 boardEthBefore = address(_board).balance;

        vm.prank(address(rejecter));
        vm.expectRevert(ETHRejecter.RejectETH.selector);
        _board.modifyOrder(orderId, _amounts(snapshot), _modify(ETH_AMOUNT / 2, AMOUNT_B));

        assertTrue(_board.canFill(orderId));
        assertEq(address(_board).balance, boardEthBefore);
        assertEq(_board.getOrder(orderId).availableA, ETH_AMOUNT);
    }

    /// @notice Tests modifyOrder top-up rejects FOT tokenA via BalanceMismatch
    function test_modifyOrder_revert_FOT_topUp() public {
        MockFOT fot = new MockFOT();
        fot.setFeePercent(0);
        fot.mint(_maker, 1000 ether);

        vm.startPrank(_maker);
        fot.approve(address(_board), type(uint256).max);
        uint256 orderId = _board.createOrder(_order(address(fot), 100 ether, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        vm.stopPrank();

        fot.setFeePercent(5);

        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.BalanceMismatch.selector, 50 ether, _fotNet(50 ether)));
        _board.modifyOrder(orderId, _amounts(snapshot), _modify(150 ether, AMOUNT_B));

        assertEq(_board.getOrder(orderId).availableA, 100 ether);
        assertEq(fot.balanceOf(address(_board)), 100 ether);
    }

    /// @notice Tests fillOrder still works after modify changes remaining size and price
    function test_modifyOrder_thenFill() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        uint128 newA = AMOUNT_A / 2;
        uint128 newB = AMOUNT_B / 5;
        _board.modifyOrder(orderId, _amounts(snapshot), _modify(newA, newB));
        vm.stopPrank();

        ISwapboard.Order memory modified = _board.getOrder(orderId);
        assertEq(modified.availableA, newA);
        assertEq(modified.availableB, newB);
        assertEq(modified.amountA, newA);
        assertEq(modified.amountB, newB);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), newB);
        _fillOrder(orderId, newA);
        vm.stopPrank();

        ISwapboard.Order memory filled = _board.getOrder(orderId);
        assertFalse(filled.active);
        assertEq(filled.availableA, 0);
        assertEq(_tokenA.balanceOf(_taker), AMOUNT_A * 10 + newA);
        assertEq(_tokenB.balanceOf(_maker), AMOUNT_B * 10 + newB);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
    }

    /// @notice Tests fillOrder paying ETH after modify of an ETH-buy order's remaining tokenA
    function test_modifyOrder_thenFill_payEth() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, _eth, ETH_AMOUNT));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        _board.modifyOrder(orderId, _amounts(snapshot), _modify(AMOUNT_A / 2, ETH_AMOUNT / 2));
        vm.stopPrank();

        vm.prank(_taker);
        _fillOrderPayEth(orderId, AMOUNT_A / 2, ETH_AMOUNT / 2);

        assertFalse(_board.getOrder(orderId).active);
        assertEq(_tokenA.balanceOf(_taker), AMOUNT_A * 10 + AMOUNT_A / 2);
        assertEq(address(_board).balance, 0);
    }

    /// @notice Tests modifyOrder leaves token pair and maker unchanged
    function test_modifyOrder_preserves_tokens_and_maker() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        _board.modifyOrder(orderId, _amounts(snapshot), _modify(AMOUNT_A / 2, AMOUNT_B * 2));
        vm.stopPrank();

        ISwapboard.Order memory after_ = _board.getOrder(orderId);
        assertEq(after_.tokenA, address(_tokenA));
        assertEq(after_.tokenB, address(_tokenB));
        assertEq(after_.maker, _maker);
        assertTrue(after_.active);
    }

    /// @notice Tests modifyOrder reverts when previousAmounts.amountA is stale
    function test_modifyOrder_reverts_stateMismatch_wrongAmountA() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        ISwapboard.OrderAmounts memory previous = _amounts(snapshot);
        previous.amountA = snapshot.amountA - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                ISwapboard.OrderStateMismatch.selector,
                orderId,
                previous.amountA,
                previous.amountB,
                previous.availableA,
                previous.availableB,
                snapshot.amountA,
                snapshot.amountB,
                snapshot.availableA,
                snapshot.availableB
            )
        );
        _board.modifyOrder(orderId, previous, _modify(AMOUNT_A, AMOUNT_B));
        vm.stopPrank();
    }

    /// @notice Tests modifyOrder reverts when previousAmounts.amountB is stale
    function test_modifyOrder_reverts_stateMismatch_wrongAmountB() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        ISwapboard.OrderAmounts memory previous = _amounts(snapshot);
        previous.amountB = snapshot.amountB - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                ISwapboard.OrderStateMismatch.selector,
                orderId,
                previous.amountA,
                previous.amountB,
                previous.availableA,
                previous.availableB,
                snapshot.amountA,
                snapshot.amountB,
                snapshot.availableA,
                snapshot.availableB
            )
        );
        _board.modifyOrder(orderId, previous, _modify(AMOUNT_A, AMOUNT_B));
        vm.stopPrank();
    }

    /// @notice Tests modifyOrder reverts when previousAmounts.availableA is stale
    function test_modifyOrder_reverts_stateMismatch_wrongAvailableA() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        ISwapboard.OrderAmounts memory previous = _amounts(snapshot);
        previous.availableA = snapshot.availableA - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                ISwapboard.OrderStateMismatch.selector,
                orderId,
                previous.amountA,
                previous.amountB,
                previous.availableA,
                previous.availableB,
                snapshot.amountA,
                snapshot.amountB,
                snapshot.availableA,
                snapshot.availableB
            )
        );
        _board.modifyOrder(orderId, previous, _modify(AMOUNT_A, AMOUNT_B));
        vm.stopPrank();
    }

    /// @notice Tests modifyOrder reverts when previousAmounts.availableB is stale
    function test_modifyOrder_reverts_stateMismatch_wrongAvailableB() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        ISwapboard.OrderAmounts memory previous = _amounts(snapshot);
        previous.availableB = snapshot.availableB - 1;
        vm.expectRevert(
            abi.encodeWithSelector(
                ISwapboard.OrderStateMismatch.selector,
                orderId,
                previous.amountA,
                previous.amountB,
                previous.availableA,
                previous.availableB,
                snapshot.amountA,
                snapshot.amountB,
                snapshot.availableA,
                snapshot.availableB
            )
        );
        _board.modifyOrder(orderId, previous, _modify(AMOUNT_A, AMOUNT_B));
        vm.stopPrank();
    }

    /// @notice Tests modifyOrder top-up reverts when allowance is insufficient
    function test_modifyOrder_revert_insufficientAllowance() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        _tokenA.approve(address(_board), 0);

        uint256 makerBefore = _tokenA.balanceOf(_maker);
        uint256 boardBefore = _tokenA.balanceOf(address(_board));

        vm.expectRevert(stdError.arithmeticError);
        _board.modifyOrder(orderId, _amounts(snapshot), _modify(AMOUNT_A + 1 ether, AMOUNT_B));
        vm.stopPrank();

        ISwapboard.Order memory after_ = _board.getOrder(orderId);
        assertEq(after_.availableA, AMOUNT_A);
        assertEq(_tokenA.balanceOf(_maker), makerBefore);
        assertEq(_tokenA.balanceOf(address(_board)), boardBefore);
    }

    /// @notice Tests modifyOrder top-up reverts when maker tokenA balance is insufficient
    function test_modifyOrder_revert_insufficientBalance() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        uint256 leftover = _tokenA.balanceOf(_maker);
        assertTrue(_tokenA.transfer(address(0xdead), leftover));

        uint256 boardBefore = _tokenA.balanceOf(address(_board));
        vm.expectRevert(stdError.arithmeticError);
        _board.modifyOrder(orderId, _amounts(snapshot), _modify(AMOUNT_A + 1 ether, AMOUNT_B));
        vm.stopPrank();

        assertEq(_board.getOrder(orderId).availableA, AMOUNT_A);
        assertEq(_tokenA.balanceOf(address(_board)), boardBefore);
        assertEq(_tokenA.balanceOf(_maker), 0);
    }

    /// @notice Tests cancelOrder after modify refunds the updated remaining escrow
    function test_modifyOrder_thenCancel() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        uint128 newA = AMOUNT_A / 4;
        _board.modifyOrder(orderId, _amounts(snapshot), _modify(newA, AMOUNT_B));

        uint256 makerBefore = _tokenA.balanceOf(_maker);
        _board.cancelOrder(orderId);
        vm.stopPrank();

        assertEq(_tokenA.balanceOf(_maker) - makerBefore, newA);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
        assertEq(_board.getOrder(orderId).maker, address(0));
        assertFalse(_board.canFill(orderId));
    }

    /// @notice Tests setPartialFillAllowed can disable partial fills so a later partial fill reverts
    function test_setPartialFillAllowed_disables_then_partialFillReverts() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));

        vm.expectEmit(true, false, false, true, address(_board));
        emit ISwapboard.OrderPartialFillUpdated(orderId, false);
        _board.setPartialFillAllowed(orderId, false);
        vm.stopPrank();

        assertFalse(_board.getOrder(orderId).partialFillAllowed);
        assertEq(_board.getOrder(orderId).availableA, AMOUNT_A);
        assertEq(_board.getOrder(orderId).availableB, AMOUNT_B);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        ISwapboard.Order memory order = _board.getOrder(orderId);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.PartialFillNotAllowed.selector, orderId));
        _fillOrderQuoted(order, orderId, AMOUNT_A / 2);
        vm.stopPrank();

        assertTrue(_board.canFill(orderId));
        assertEq(_board.getOrder(orderId).availableA, AMOUNT_A);
    }

    /// @notice Tests setPartialFillAllowed can enable partial fills so a later partial fill succeeds
    function test_setPartialFillAllowed_enables_then_partialFill() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        _board.setPartialFillAllowed(orderId, true);
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _fillOrder(orderId, AMOUNT_A / 2);
        vm.stopPrank();

        ISwapboard.Order memory after_ = _board.getOrder(orderId);
        assertTrue(after_.active);
        assertEq(after_.availableA, AMOUNT_A / 2);
        assertTrue(after_.partialFillAllowed);
    }

    /// @notice Tests setPartialFillAllowed reverts when caller is not the maker
    function test_setPartialFillAllowed_reverts_notMaker() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotMaker.selector, orderId, _taker, _maker));
        _board.setPartialFillAllowed(orderId, true);

        assertFalse(_board.getOrder(orderId).partialFillAllowed);
    }

    /// @notice Tests modifyOrder leaves partialFillAllowed unchanged
    function test_modifyOrder_preserves_partialFillAllowed() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_orderPartial(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        assertTrue(snapshot.partialFillAllowed);

        _board.modifyOrder(orderId, _amounts(snapshot), _modify(AMOUNT_A / 2, AMOUNT_B / 2));
        vm.stopPrank();

        ISwapboard.Order memory after_ = _board.getOrder(orderId);
        assertTrue(after_.partialFillAllowed);
        assertEq(after_.availableA, AMOUNT_A / 2);
        assertEq(after_.availableB, AMOUNT_B / 2);
    }

    /// @notice Tests modifyOrder selling ETH reverts when remainings are unchanged
    function test_modifyOrder_sellEth_reverts_noChange() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        uint256 makerBefore = _maker.balance;
        uint256 boardBefore = address(_board).balance;

        vm.prank(_maker);
        vm.expectRevert(ISwapboard.NoChange.selector);
        _board.modifyOrder(orderId, _amounts(snapshot), _modify(ETH_AMOUNT, AMOUNT_B));

        assertEq(_maker.balance, makerBefore);
        assertEq(address(_board).balance, boardBefore);
        assertEq(_board.getOrder(orderId).availableA, ETH_AMOUNT);
        assertEq(_board.getOrder(orderId).availableB, AMOUNT_B);
    }

    /// @notice Tests modifyOrder selling ETH with unchanged availableA still allows availableB updates
    function test_modifyOrder_sellEth_availableB_only_succeeds() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        uint256 makerBefore = _maker.balance;
        uint256 boardBefore = address(_board).balance;

        vm.prank(_maker);
        _board.modifyOrder(orderId, _amounts(snapshot), _modify(ETH_AMOUNT, AMOUNT_B * 2));

        ISwapboard.Order memory after_ = _board.getOrder(orderId);
        assertEq(after_.availableA, ETH_AMOUNT);
        assertEq(after_.amountB, AMOUNT_B * 2);
        assertEq(_maker.balance, makerBefore);
        assertEq(address(_board).balance, boardBefore);
    }

    /// @notice Fuzz tests modifyOrder remaining ERC20 amounts and escrow deltas
    function testFuzz_modifyOrder_availableA(
        uint256 newASeed,
        uint256 newBSeed
    ) public {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 newA = uint128(bound(newASeed, 1, AMOUNT_A * 5));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 newB = uint128(bound(newBSeed, 1, AMOUNT_B * 5));
        vm.assume(newA != AMOUNT_A || newB != AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        uint256 makerBefore = _tokenA.balanceOf(_maker);
        uint256 boardBefore = _tokenA.balanceOf(address(_board));

        _board.modifyOrder(orderId, _amounts(snapshot), _modify(newA, newB));
        vm.stopPrank();

        ISwapboard.Order memory after_ = _board.getOrder(orderId);
        assertEq(after_.amountA, newA);
        assertEq(after_.availableA, newA);
        assertEq(after_.amountB, newB);
        assertEq(after_.availableB, newB);
        assertTrue(after_.active);

        if (newA > AMOUNT_A) {
            assertEq(makerBefore - _tokenA.balanceOf(_maker), newA - AMOUNT_A);
            assertEq(_tokenA.balanceOf(address(_board)) - boardBefore, newA - AMOUNT_A);
        } else {
            assertEq(_tokenA.balanceOf(_maker) - makerBefore, AMOUNT_A - newA);
            assertEq(boardBefore - _tokenA.balanceOf(address(_board)), AMOUNT_A - newA);
        }
    }

    /// @notice Fuzz tests modifyOrder ETH tokenA top-up and refund
    function testFuzz_modifyOrder_sellEth(
        uint256 newASeed
    ) public {
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 newA = uint128(bound(newASeed, 1, 50 ether));
        vm.assume(newA != ETH_AMOUNT);

        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        uint256 makerBefore = _maker.balance;
        uint256 boardBefore = address(_board).balance;
        uint256 value = newA > ETH_AMOUNT ? uint256(newA - ETH_AMOUNT) : 0;

        vm.prank(_maker);
        _board.modifyOrder{value: value}(orderId, _amounts(snapshot), _modify(newA, AMOUNT_B));

        ISwapboard.Order memory after_ = _board.getOrder(orderId);
        assertEq(after_.availableA, newA);
        assertEq(after_.amountA, newA);
        assertEq(address(_board).balance, newA);
        if (newA > ETH_AMOUNT) {
            assertEq(makerBefore - _maker.balance, newA - ETH_AMOUNT);
            assertEq(address(_board).balance - boardBefore, newA - ETH_AMOUNT);
        } else {
            assertEq(_maker.balance - makerBefore, ETH_AMOUNT - newA);
            assertEq(boardBefore - address(_board).balance, ETH_AMOUNT - newA);
        }
    }

    // ============ modifyOrders ============

    /// @notice Tests modifyOrders aggregates ERC20 top-ups into one pull
    function test_modifyOrders_aggregatesSameToken_topUp() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), 10 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), 20 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        uint256[] memory ids = _board.createOrders(orders);

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 15 ether, AMOUNT_B);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 30 ether, AMOUNT_B);

        uint256 pullsBefore = _tf(_tokenA);
        uint256 makerBefore = _tokenA.balanceOf(_maker);
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_tf(_tokenA), pullsBefore + 1);
        assertEq(makerBefore - _tokenA.balanceOf(_maker), 15 ether);
        assertEq(_tokenA.balanceOf(address(_board)), 45 ether);
        assertEq(_board.getOrder(ids[0]).availableA, 15 ether);
        assertEq(_board.getOrder(ids[1]).availableA, 30 ether);
    }

    /// @notice Tests modifyOrders aggregates ERC20 refunds into one transfer
    function test_modifyOrders_aggregatesSameToken_refund() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), 40 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), 60 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        uint256[] memory ids = _board.createOrders(orders);

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 10 ether, AMOUNT_B);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 20 ether, AMOUNT_B);

        uint256 makerBefore = _tokenA.balanceOf(_maker);
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_tokenA.balanceOf(_maker) - makerBefore, 70 ether);
        assertEq(_tokenA.balanceOf(address(_board)), 30 ether);
        assertEq(_board.getOrder(ids[0]).availableA, 10 ether);
        assertEq(_board.getOrder(ids[1]).availableA, 20 ether);
    }

    /// @notice Tests modifyOrders nets same-token top-up against refund into one pull
    function test_modifyOrders_netsSameToken_topUpDominates() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), 10 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), 40 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        uint256[] memory ids = _board.createOrders(orders);

        // +20 on ids[0], -10 on ids[1] => net pull 10, no refund transfer
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 30 ether, AMOUNT_B);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 30 ether, AMOUNT_B);

        uint256 pullsBefore = _tf(_tokenA);
        uint256 makerBefore = _tokenA.balanceOf(_maker);
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_tf(_tokenA), pullsBefore + 1);
        assertEq(makerBefore - _tokenA.balanceOf(_maker), 10 ether);
        assertEq(_tokenA.balanceOf(address(_board)), 60 ether);
        assertEq(_board.getOrder(ids[0]).availableA, 30 ether);
        assertEq(_board.getOrder(ids[1]).availableA, 30 ether);
    }

    /// @notice Tests modifyOrders nets same-token top-up against refund into one refund
    function test_modifyOrders_netsSameToken_refundDominates() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), 10 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), 40 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        uint256[] memory ids = _board.createOrders(orders);

        // +5 on ids[0], -20 on ids[1] => net refund 15, no pull
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 15 ether, AMOUNT_B);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 20 ether, AMOUNT_B);

        uint256 pullsBefore = _tf(_tokenA);
        uint256 makerBefore = _tokenA.balanceOf(_maker);
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_tf(_tokenA), pullsBefore);
        assertEq(_tokenA.balanceOf(_maker) - makerBefore, 15 ether);
        assertEq(_tokenA.balanceOf(address(_board)), 35 ether);
        assertEq(_board.getOrder(ids[0]).availableA, 15 ether);
        assertEq(_board.getOrder(ids[1]).availableA, 20 ether);
    }

    /// @notice Tests equal same-token top-up and refund cancel with no ERC20 transfer
    function test_modifyOrders_netsSameToken_cancelsCompletely() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), 10 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), 40 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        uint256[] memory ids = _board.createOrders(orders);

        // +10 on ids[0], -10 on ids[1] => no pull, no refund
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 20 ether, AMOUNT_B);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 30 ether, AMOUNT_B);

        uint256 pullsBefore = _tf(_tokenA);
        uint256 makerBefore = _tokenA.balanceOf(_maker);
        uint256 boardBefore = _tokenA.balanceOf(address(_board));
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_tf(_tokenA), pullsBefore);
        assertEq(_tokenA.balanceOf(_maker), makerBefore);
        assertEq(_tokenA.balanceOf(address(_board)), boardBefore);
        assertEq(_board.getOrder(ids[0]).availableA, 20 ether);
        assertEq(_board.getOrder(ids[1]).availableA, 30 ether);
    }

    /// @notice Tests ETH top-up and refund net so msg.value is only the surplus
    function test_modifyOrders_netsEth_topUpDominates() public {
        vm.startPrank(_maker);
        uint256 id0 = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));
        uint256 id1 = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));

        // +0.75 ETH on id0, -0.25 ETH on id1 => msg.value 0.5, no ETH refund send
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(id0, _board.getOrder(id0), ETH_AMOUNT + 0.75 ether, AMOUNT_B);
        mods[1] = _modItem(id1, _board.getOrder(id1), ETH_AMOUNT - 0.25 ether, AMOUNT_B);

        uint256 makerBefore = _maker.balance;
        uint256 boardBefore = address(_board).balance;
        _board.modifyOrders{value: 0.5 ether}(mods);
        vm.stopPrank();

        assertEq(makerBefore - _maker.balance, 0.5 ether);
        assertEq(address(_board).balance, boardBefore + 0.5 ether);
        assertEq(_board.getOrder(id0).availableA, ETH_AMOUNT + 0.75 ether);
        assertEq(_board.getOrder(id1).availableA, ETH_AMOUNT - 0.25 ether);
    }

    /// @notice Tests equal ETH top-up and refund cancel with msg.value 0 and no send
    function test_modifyOrders_netsEth_cancelsCompletely() public {
        vm.startPrank(_maker);
        uint256 id0 = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));
        uint256 id1 = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));

        // +0.5 ETH on id0, -0.5 ETH on id1 => msg.value 0, no ETH movement
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(id0, _board.getOrder(id0), ETH_AMOUNT + 0.5 ether, AMOUNT_B);
        mods[1] = _modItem(id1, _board.getOrder(id1), ETH_AMOUNT - 0.5 ether, AMOUNT_B);

        uint256 makerBefore = _maker.balance;
        uint256 boardBefore = address(_board).balance;
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_maker.balance, makerBefore);
        assertEq(address(_board).balance, boardBefore);
        assertEq(_board.getOrder(id0).availableA, ETH_AMOUNT + 0.5 ether);
        assertEq(_board.getOrder(id1).availableA, ETH_AMOUNT - 0.5 ether);
    }

    /// @notice Tests netted ETH path reverts when msg.value is the gross top-up instead of the net
    function test_modifyOrders_netsEth_revert_msgValueIsGrossTopUp() public {
        vm.startPrank(_maker);
        uint256 id0 = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));
        uint256 id1 = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(id0, _board.getOrder(id0), ETH_AMOUNT + 0.75 ether, AMOUNT_B);
        mods[1] = _modItem(id1, _board.getOrder(id1), ETH_AMOUNT - 0.25 ether, AMOUNT_B);

        // Gross top-up is 0.75 ether; net required is 0.5 ether
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, 0.5 ether, 0.75 ether));
        _board.modifyOrders{value: 0.75 ether}(mods);
        vm.stopPrank();
    }

    /// @notice Tests three same-token legs: two top-ups and one refund net to a single pull
    function test_modifyOrders_netsSameToken_threeOrders_topUpDominates() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](3);
        orders[0] = _order(address(_tokenA), 10 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), 20 ether, address(_tokenB), AMOUNT_B);
        orders[2] = _order(address(_tokenA), 30 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        uint256[] memory ids = _board.createOrders(orders);

        // +10, +5, -8 => net pull 7
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](3);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 20 ether, AMOUNT_B);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 25 ether, AMOUNT_B);
        mods[2] = _modItem(ids[2], _board.getOrder(ids[2]), 22 ether, AMOUNT_B);

        uint256 pullsBefore = _tf(_tokenA);
        uint256 makerBefore = _tokenA.balanceOf(_maker);
        uint256 boardBefore = _tokenA.balanceOf(address(_board));
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_tf(_tokenA), pullsBefore + 1);
        assertEq(makerBefore - _tokenA.balanceOf(_maker), 7 ether);
        assertEq(_tokenA.balanceOf(address(_board)), boardBefore + 7 ether);
        assertEq(_board.getOrder(ids[0]).availableA, 20 ether);
        assertEq(_board.getOrder(ids[1]).availableA, 25 ether);
        assertEq(_board.getOrder(ids[2]).availableA, 22 ether);
    }

    /// @notice Tests three same-token legs: one top-up and two refunds net to a single refund
    function test_modifyOrders_netsSameToken_threeOrders_refundDominates() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](3);
        orders[0] = _order(address(_tokenA), 10 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), 40 ether, address(_tokenB), AMOUNT_B);
        orders[2] = _order(address(_tokenA), 50 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        uint256[] memory ids = _board.createOrders(orders);

        // +3, -10, -5 => net refund 12
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](3);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 13 ether, AMOUNT_B);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 30 ether, AMOUNT_B);
        mods[2] = _modItem(ids[2], _board.getOrder(ids[2]), 45 ether, AMOUNT_B);

        uint256 pullsBefore = _tf(_tokenA);
        uint256 makerBefore = _tokenA.balanceOf(_maker);
        uint256 boardBefore = _tokenA.balanceOf(address(_board));
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_tf(_tokenA), pullsBefore);
        assertEq(_tokenA.balanceOf(_maker) - makerBefore, 12 ether);
        assertEq(boardBefore - _tokenA.balanceOf(address(_board)), 12 ether);
        assertEq(_board.getOrder(ids[0]).availableA, 13 ether);
        assertEq(_board.getOrder(ids[1]).availableA, 30 ether);
        assertEq(_board.getOrder(ids[2]).availableA, 45 ether);
    }

    /// @notice Tests three same-token legs whose top-ups and refunds cancel exactly
    function test_modifyOrders_netsSameToken_threeOrders_cancelsCompletely() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](3);
        orders[0] = _order(address(_tokenA), 10 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), 20 ether, address(_tokenB), AMOUNT_B);
        orders[2] = _order(address(_tokenA), 40 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        uint256[] memory ids = _board.createOrders(orders);

        // +10, +5, -15 => cancel
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](3);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 20 ether, AMOUNT_B);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 25 ether, AMOUNT_B);
        mods[2] = _modItem(ids[2], _board.getOrder(ids[2]), 25 ether, AMOUNT_B);

        uint256 pullsBefore = _tf(_tokenA);
        uint256 makerBefore = _tokenA.balanceOf(_maker);
        uint256 boardBefore = _tokenA.balanceOf(address(_board));
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_tf(_tokenA), pullsBefore);
        assertEq(_tokenA.balanceOf(_maker), makerBefore);
        assertEq(_tokenA.balanceOf(address(_board)), boardBefore);
        assertEq(_board.getOrder(ids[0]).availableA, 20 ether);
        assertEq(_board.getOrder(ids[1]).availableA, 25 ether);
        assertEq(_board.getOrder(ids[2]).availableA, 25 ether);
    }

    /// @notice Tests refund-first then top-up ordering still nets to one pull
    function test_modifyOrders_netsSameToken_refundThenTopUp() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), 40 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), 10 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        uint256[] memory ids = _board.createOrders(orders);

        // Refund listed first: -10 then +25 => net pull 15
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 30 ether, AMOUNT_B);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 35 ether, AMOUNT_B);

        uint256 pullsBefore = _tf(_tokenA);
        uint256 makerBefore = _tokenA.balanceOf(_maker);
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_tf(_tokenA), pullsBefore + 1);
        assertEq(makerBefore - _tokenA.balanceOf(_maker), 15 ether);
        assertEq(_tokenA.balanceOf(address(_board)), 65 ether);
        assertEq(_board.getOrder(ids[0]).availableA, 30 ether);
        assertEq(_board.getOrder(ids[1]).availableA, 35 ether);
    }

    /// @notice Tests top-up-first then larger refund nets to one refund
    function test_modifyOrders_netsSameToken_topUpThenLargerRefund() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), 10 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), 50 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        uint256[] memory ids = _board.createOrders(orders);

        // +8 then -30 => net refund 22
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 18 ether, AMOUNT_B);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 20 ether, AMOUNT_B);

        uint256 pullsBefore = _tf(_tokenA);
        uint256 makerBefore = _tokenA.balanceOf(_maker);
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_tf(_tokenA), pullsBefore);
        assertEq(_tokenA.balanceOf(_maker) - makerBefore, 22 ether);
        assertEq(_tokenA.balanceOf(address(_board)), 38 ether);
        assertEq(_board.getOrder(ids[0]).availableA, 18 ether);
        assertEq(_board.getOrder(ids[1]).availableA, 20 ether);
    }

    /// @notice Tests many alternating same-token top-ups and refunds collapse to one net pull
    function test_modifyOrders_netsSameToken_alternatingLegs_topUpDominates() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](4);
        orders[0] = _order(address(_tokenA), 20 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), 20 ether, address(_tokenB), AMOUNT_B);
        orders[2] = _order(address(_tokenA), 20 ether, address(_tokenB), AMOUNT_B);
        orders[3] = _order(address(_tokenA), 20 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        uint256[] memory ids = _board.createOrders(orders);

        // +12, -3, +8, -5 => gross top 20, gross refund 8, net pull 12
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](4);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 32 ether, AMOUNT_B);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 17 ether, AMOUNT_B);
        mods[2] = _modItem(ids[2], _board.getOrder(ids[2]), 28 ether, AMOUNT_B);
        mods[3] = _modItem(ids[3], _board.getOrder(ids[3]), 15 ether, AMOUNT_B);

        uint256 pullsBefore = _tf(_tokenA);
        uint256 makerBefore = _tokenA.balanceOf(_maker);
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_tf(_tokenA), pullsBefore + 1);
        assertEq(makerBefore - _tokenA.balanceOf(_maker), 12 ether);
        assertEq(_tokenA.balanceOf(address(_board)), 92 ether);
        assertEq(_board.getOrder(ids[0]).availableA, 32 ether);
        assertEq(_board.getOrder(ids[1]).availableA, 17 ether);
        assertEq(_board.getOrder(ids[2]).availableA, 28 ether);
        assertEq(_board.getOrder(ids[3]).availableA, 15 ether);
    }

    /// @notice Tests many alternating same-token top-ups and refunds collapse to one net refund
    function test_modifyOrders_netsSameToken_alternatingLegs_refundDominates() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](4);
        orders[0] = _order(address(_tokenA), 20 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), 20 ether, address(_tokenB), AMOUNT_B);
        orders[2] = _order(address(_tokenA), 20 ether, address(_tokenB), AMOUNT_B);
        orders[3] = _order(address(_tokenA), 20 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        uint256[] memory ids = _board.createOrders(orders);

        // +4, -11, +2, -9 => gross top 6, gross refund 20, net refund 14
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](4);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 24 ether, AMOUNT_B);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 9 ether, AMOUNT_B);
        mods[2] = _modItem(ids[2], _board.getOrder(ids[2]), 22 ether, AMOUNT_B);
        mods[3] = _modItem(ids[3], _board.getOrder(ids[3]), 11 ether, AMOUNT_B);

        uint256 pullsBefore = _tf(_tokenA);
        uint256 makerBefore = _tokenA.balanceOf(_maker);
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_tf(_tokenA), pullsBefore);
        assertEq(_tokenA.balanceOf(_maker) - makerBefore, 14 ether);
        assertEq(_tokenA.balanceOf(address(_board)), 66 ether);
        assertEq(_board.getOrder(ids[0]).availableA, 24 ether);
        assertEq(_board.getOrder(ids[1]).availableA, 9 ether);
        assertEq(_board.getOrder(ids[2]).availableA, 22 ether);
        assertEq(_board.getOrder(ids[3]).availableA, 11 ether);
    }

    /// @notice Tests B-only change on one order does not disturb A netting on another
    function test_modifyOrders_netsSameToken_withAvailableBOnlySibling() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), 10 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), 40 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        uint256[] memory ids = _board.createOrders(orders);

        // ids[0]: A +20 (top-up), ids[1]: A -5 and B changes (refund) => net pull 15
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 30 ether, AMOUNT_B);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 35 ether, AMOUNT_B * 2);

        uint256 pullsBefore = _tf(_tokenA);
        uint256 makerBefore = _tokenA.balanceOf(_maker);
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_tf(_tokenA), pullsBefore + 1);
        assertEq(makerBefore - _tokenA.balanceOf(_maker), 15 ether);
        assertEq(_tokenA.balanceOf(address(_board)), 65 ether);
        assertEq(_board.getOrder(ids[0]).availableA, 30 ether);
        assertEq(_board.getOrder(ids[0]).availableB, AMOUNT_B);
        assertEq(_board.getOrder(ids[1]).availableA, 35 ether);
        assertEq(_board.getOrder(ids[1]).availableB, AMOUNT_B * 2);
    }

    /// @notice Tests distinct tokenA assets net independently in one batch
    function test_modifyOrders_netsIndependentTokens() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        _tokenB.approve(address(_board), type(uint256).max);

        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](4);
        // tokenA legs: 10 and 40
        orders[0] = _order(address(_tokenA), 10 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), 40 ether, address(_tokenB), AMOUNT_B);
        // tokenB legs: 100e6 and 400e6
        orders[2] = _order(address(_tokenB), 100e6, address(_tokenA), 1 ether);
        orders[3] = _order(address(_tokenB), 400e6, address(_tokenA), 1 ether);
        uint256[] memory ids = _board.createOrders(orders);

        // tokenA: +20 / -5 => net pull 15
        // tokenB: +50e6 / -200e6 => net refund 150e6
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](4);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 30 ether, AMOUNT_B);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 35 ether, AMOUNT_B);
        mods[2] = _modItem(ids[2], _board.getOrder(ids[2]), 150e6, 1 ether);
        mods[3] = _modItem(ids[3], _board.getOrder(ids[3]), 200e6, 1 ether);

        uint256 pullsABefore = _tf(_tokenA);
        uint256 pullsBBefore = _tf(_tokenB);
        uint256 makerABefore = _tokenA.balanceOf(_maker);
        uint256 makerBBefore = _tokenB.balanceOf(_maker);
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_tf(_tokenA), pullsABefore + 1);
        assertEq(_tf(_tokenB), pullsBBefore);
        assertEq(makerABefore - _tokenA.balanceOf(_maker), 15 ether);
        assertEq(_tokenB.balanceOf(_maker) - makerBBefore, 150e6);
        assertEq(_tokenA.balanceOf(address(_board)), 65 ether);
        assertEq(_tokenB.balanceOf(address(_board)), 350e6);
    }

    /// @notice Tests ETH refund dominates across two ETH orders
    function test_modifyOrders_netsEth_refundDominates() public {
        vm.startPrank(_maker);
        uint256 id0 = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));
        uint256 id1 = _board.createOrder{value: 2 ether}(_order(_eth, 2 ether, address(_tokenB), AMOUNT_B));

        // +0.2 ETH, -1.0 ETH => net refund 0.8, msg.value 0
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(id0, _board.getOrder(id0), ETH_AMOUNT + 0.2 ether, AMOUNT_B);
        mods[1] = _modItem(id1, _board.getOrder(id1), 1 ether, AMOUNT_B);

        uint256 makerBefore = _maker.balance;
        uint256 boardBefore = address(_board).balance;
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_maker.balance - makerBefore, 0.8 ether);
        assertEq(boardBefore - address(_board).balance, 0.8 ether);
        assertEq(_board.getOrder(id0).availableA, ETH_AMOUNT + 0.2 ether);
        assertEq(_board.getOrder(id1).availableA, 1 ether);
    }

    /// @notice Tests three ETH legs net to a single msg.value top-up
    function test_modifyOrders_netsEth_threeOrders_topUpDominates() public {
        vm.startPrank(_maker);
        uint256 id0 = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));
        uint256 id1 = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));
        uint256 id2 = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));

        // +0.5, +0.3, -0.4 => net pull 0.4
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](3);
        mods[0] = _modItem(id0, _board.getOrder(id0), ETH_AMOUNT + 0.5 ether, AMOUNT_B);
        mods[1] = _modItem(id1, _board.getOrder(id1), ETH_AMOUNT + 0.3 ether, AMOUNT_B);
        mods[2] = _modItem(id2, _board.getOrder(id2), ETH_AMOUNT - 0.4 ether, AMOUNT_B);

        uint256 makerBefore = _maker.balance;
        uint256 boardBefore = address(_board).balance;
        _board.modifyOrders{value: 0.4 ether}(mods);
        vm.stopPrank();

        assertEq(makerBefore - _maker.balance, 0.4 ether);
        assertEq(address(_board).balance, boardBefore + 0.4 ether);
        assertEq(_board.getOrder(id0).availableA, ETH_AMOUNT + 0.5 ether);
        assertEq(_board.getOrder(id1).availableA, ETH_AMOUNT + 0.3 ether);
        assertEq(_board.getOrder(id2).availableA, ETH_AMOUNT - 0.4 ether);
    }

    /// @notice Tests three ETH legs net to a single ETH refund
    function test_modifyOrders_netsEth_threeOrders_refundDominates() public {
        vm.startPrank(_maker);
        uint256 id0 = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));
        uint256 id1 = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));
        uint256 id2 = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));

        // +0.1, -0.4, -0.2 => net refund 0.5
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](3);
        mods[0] = _modItem(id0, _board.getOrder(id0), ETH_AMOUNT + 0.1 ether, AMOUNT_B);
        mods[1] = _modItem(id1, _board.getOrder(id1), ETH_AMOUNT - 0.4 ether, AMOUNT_B);
        mods[2] = _modItem(id2, _board.getOrder(id2), ETH_AMOUNT - 0.2 ether, AMOUNT_B);

        uint256 makerBefore = _maker.balance;
        uint256 boardBefore = address(_board).balance;
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_maker.balance - makerBefore, 0.5 ether);
        assertEq(boardBefore - address(_board).balance, 0.5 ether);
        assertEq(_board.getOrder(id0).availableA, ETH_AMOUNT + 0.1 ether);
        assertEq(_board.getOrder(id1).availableA, ETH_AMOUNT - 0.4 ether);
        assertEq(_board.getOrder(id2).availableA, ETH_AMOUNT - 0.2 ether);
    }

    /// @notice Tests ERC20 and ETH net independently when both have opposing legs
    function test_modifyOrders_netsEthAndErc20_independently() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);

        uint256 erc20Small = _board.createOrder(_order(address(_tokenA), 10 ether, address(_tokenB), AMOUNT_B));
        uint256 erc20Large = _board.createOrder(_order(address(_tokenA), 40 ether, address(_tokenB), AMOUNT_B));
        uint256 ethSmall = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));
        uint256 ethLarge = _board.createOrder{value: 2 ether}(_order(_eth, 2 ether, address(_tokenB), AMOUNT_B));

        // ERC20: +25 / -10 => net pull 15
        // ETH:   +0.25 / -1.0 => net refund 0.75, msg.value 0
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](4);
        mods[0] = _modItem(erc20Small, _board.getOrder(erc20Small), 35 ether, AMOUNT_B);
        mods[1] = _modItem(erc20Large, _board.getOrder(erc20Large), 30 ether, AMOUNT_B);
        mods[2] = _modItem(ethSmall, _board.getOrder(ethSmall), ETH_AMOUNT + 0.25 ether, AMOUNT_B);
        mods[3] = _modItem(ethLarge, _board.getOrder(ethLarge), 1 ether, AMOUNT_B);

        uint256 pullsBefore = _tf(_tokenA);
        uint256 makerTokenBefore = _tokenA.balanceOf(_maker);
        uint256 makerEthBefore = _maker.balance;
        uint256 boardEthBefore = address(_board).balance;
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_tf(_tokenA), pullsBefore + 1);
        assertEq(makerTokenBefore - _tokenA.balanceOf(_maker), 15 ether);
        assertEq(_maker.balance - makerEthBefore, 0.75 ether);
        assertEq(boardEthBefore - address(_board).balance, 0.75 ether);
        assertEq(_tokenA.balanceOf(address(_board)), 65 ether);
        assertEq(_board.getOrder(erc20Small).availableA, 35 ether);
        assertEq(_board.getOrder(erc20Large).availableA, 30 ether);
        assertEq(_board.getOrder(ethSmall).availableA, ETH_AMOUNT + 0.25 ether);
        assertEq(_board.getOrder(ethLarge).availableA, 1 ether);
    }

    /// @notice Tests ERC20 net refund with ETH net top-up in the same batch
    function test_modifyOrders_netsEthAndErc20_oppositeDirections() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);

        uint256 erc20Small = _board.createOrder(_order(address(_tokenA), 10 ether, address(_tokenB), AMOUNT_B));
        uint256 erc20Large = _board.createOrder(_order(address(_tokenA), 40 ether, address(_tokenB), AMOUNT_B));
        uint256 eth0 = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));
        uint256 eth1 = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));

        // ERC20: +5 / -20 => net refund 15
        // ETH:   +0.6 / -0.1 => net pull 0.5
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](4);
        mods[0] = _modItem(erc20Small, _board.getOrder(erc20Small), 15 ether, AMOUNT_B);
        mods[1] = _modItem(erc20Large, _board.getOrder(erc20Large), 20 ether, AMOUNT_B);
        mods[2] = _modItem(eth0, _board.getOrder(eth0), ETH_AMOUNT + 0.6 ether, AMOUNT_B);
        mods[3] = _modItem(eth1, _board.getOrder(eth1), ETH_AMOUNT - 0.1 ether, AMOUNT_B);

        uint256 pullsBefore = _tf(_tokenA);
        uint256 makerTokenBefore = _tokenA.balanceOf(_maker);
        uint256 makerEthBefore = _maker.balance;
        _board.modifyOrders{value: 0.5 ether}(mods);
        vm.stopPrank();

        assertEq(_tf(_tokenA), pullsBefore);
        assertEq(_tokenA.balanceOf(_maker) - makerTokenBefore, 15 ether);
        assertEq(makerEthBefore - _maker.balance, 0.5 ether);
        assertEq(_tokenA.balanceOf(address(_board)), 35 ether);
        assertEq(address(_board).balance, 2 ether + 0.5 ether);
        assertEq(_board.getOrder(erc20Small).availableA, 15 ether);
        assertEq(_board.getOrder(erc20Large).availableA, 20 ether);
        assertEq(_board.getOrder(eth0).availableA, ETH_AMOUNT + 0.6 ether);
        assertEq(_board.getOrder(eth1).availableA, ETH_AMOUNT - 0.1 ether);
    }

    /// @notice Property: two same-token modifies settle only the net availableA delta once
    function testFuzz_modifyOrders_netsSameToken(
        uint128 amount0,
        uint128 amount1,
        uint128 new0,
        uint128 new1
    ) public {
        // casting to 'uint128' is safe because bound upper limits fit in uint128
        // forge-lint: disable-next-line(unsafe-typecast)
        amount0 = uint128(bound(amount0, 1 ether, 80 ether));
        // forge-lint: disable-next-line(unsafe-typecast)
        amount1 = uint128(bound(amount1, 1 ether, 80 ether));
        // forge-lint: disable-next-line(unsafe-typecast)
        new0 = uint128(bound(new0, 1, 120 ether));
        // forge-lint: disable-next-line(unsafe-typecast)
        new1 = uint128(bound(new1, 1, 120 ether));
        vm.assume(new0 != amount0 && new1 != amount1);

        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), amount0, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), amount1, address(_tokenB), AMOUNT_B);
        _tokenA.mint(_maker, uint256(new0) + uint256(new1));

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        uint256[] memory ids = _board.createOrders(orders);

        (uint256 topUp, uint256 refund) = _netAvailableADeltas(amount0, new0, amount1, new1);
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), new0, AMOUNT_B);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), new1, AMOUNT_B);

        uint256 pullsBefore = _tf(_tokenA);
        uint256 makerBefore = _tokenA.balanceOf(_maker);
        uint256 boardBefore = _tokenA.balanceOf(address(_board));
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_board.getOrder(ids[0]).availableA, new0);
        assertEq(_board.getOrder(ids[1]).availableA, new1);
        _assertNettedErc20Balances(topUp, refund, pullsBefore, makerBefore, boardBefore);
    }

    /// @notice Property: two ETH modifies settle only the net availableA delta once
    function testFuzz_modifyOrders_netsEth(
        uint128 amount0,
        uint128 amount1,
        uint128 new0,
        uint128 new1
    ) public {
        // casting to 'uint128' is safe because bound upper limits fit in uint128
        // forge-lint: disable-next-line(unsafe-typecast)
        amount0 = uint128(bound(amount0, 0.1 ether, 5 ether));
        // forge-lint: disable-next-line(unsafe-typecast)
        amount1 = uint128(bound(amount1, 0.1 ether, 5 ether));
        // forge-lint: disable-next-line(unsafe-typecast)
        new0 = uint128(bound(new0, 0.01 ether, 8 ether));
        // forge-lint: disable-next-line(unsafe-typecast)
        new1 = uint128(bound(new1, 0.01 ether, 8 ether));
        vm.assume(new0 != amount0 && new1 != amount1);

        vm.deal(_maker, 50 ether);
        vm.startPrank(_maker);
        uint256 id0 = _board.createOrder{value: amount0}(_order(_eth, amount0, address(_tokenB), AMOUNT_B));
        uint256 id1 = _board.createOrder{value: amount1}(_order(_eth, amount1, address(_tokenB), AMOUNT_B));

        (uint256 topUp, uint256 refund) = _netAvailableADeltas(amount0, new0, amount1, new1);
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(id0, _board.getOrder(id0), new0, AMOUNT_B);
        mods[1] = _modItem(id1, _board.getOrder(id1), new1, AMOUNT_B);

        uint256 makerBefore = _maker.balance;
        uint256 boardBefore = address(_board).balance;
        uint256 value = topUp > refund ? topUp - refund : 0;
        _board.modifyOrders{value: value}(mods);
        vm.stopPrank();

        assertEq(_board.getOrder(id0).availableA, new0);
        assertEq(_board.getOrder(id1).availableA, new1);
        _assertNettedEthBalances(topUp, refund, makerBefore, boardBefore);
    }

    /// @notice Computes gross top-up and refund for two availableA changes
    function _netAvailableADeltas(
        uint128 amount0,
        uint128 new0,
        uint128 amount1,
        uint128 new1
    ) private pure returns (uint256 topUp, uint256 refund) {
        if (new0 > amount0) {
            topUp += uint256(new0) - uint256(amount0);
        } else {
            refund += uint256(amount0) - uint256(new0);
        }
        if (new1 > amount1) {
            topUp += uint256(new1) - uint256(amount1);
        } else {
            refund += uint256(amount1) - uint256(new1);
        }
    }

    /// @notice Asserts ERC20 maker/board balances match a netted modify settlement
    function _assertNettedErc20Balances(
        uint256 topUp,
        uint256 refund,
        uint256 pullsBefore,
        uint256 makerBefore,
        uint256 boardBefore
    ) private view {
        if (topUp > refund) {
            uint256 net = topUp - refund;
            assertEq(_tf(_tokenA), pullsBefore + 1);
            assertEq(makerBefore - _tokenA.balanceOf(_maker), net);
            assertEq(_tokenA.balanceOf(address(_board)), boardBefore + net);
        } else if (refund > topUp) {
            uint256 net = refund - topUp;
            assertEq(_tf(_tokenA), pullsBefore);
            assertEq(_tokenA.balanceOf(_maker) - makerBefore, net);
            assertEq(boardBefore - _tokenA.balanceOf(address(_board)), net);
        } else {
            assertEq(_tf(_tokenA), pullsBefore);
            assertEq(_tokenA.balanceOf(_maker), makerBefore);
            assertEq(_tokenA.balanceOf(address(_board)), boardBefore);
        }
    }

    /// @notice Asserts ETH maker/board balances match a netted modify settlement
    function _assertNettedEthBalances(
        uint256 topUp,
        uint256 refund,
        uint256 makerBefore,
        uint256 boardBefore
    ) private view {
        if (topUp > refund) {
            uint256 net = topUp - refund;
            assertEq(makerBefore - _maker.balance, net);
            assertEq(address(_board).balance, boardBefore + net);
        } else if (refund > topUp) {
            uint256 net = refund - topUp;
            assertEq(_maker.balance - makerBefore, net);
            assertEq(boardBefore - address(_board).balance, net);
        } else {
            assertEq(_maker.balance, makerBefore);
            assertEq(address(_board).balance, boardBefore);
        }
    }

    /// @notice Tests modifyOrders with mixed ETH and ERC20 tokenA
    function test_modifyOrders_mixedEthAndToken() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        uint256 erc20Id = _board.createOrder(_order(address(_tokenA), 50 ether, address(_tokenB), AMOUNT_B));
        uint256 ethId = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(erc20Id, _board.getOrder(erc20Id), 20 ether, AMOUNT_B);
        mods[1] = _modItem(ethId, _board.getOrder(ethId), ETH_AMOUNT + 0.5 ether, AMOUNT_B);

        uint256 makerTokenBefore = _tokenA.balanceOf(_maker);
        uint256 makerEthBefore = _maker.balance;
        _board.modifyOrders{value: 0.5 ether}(mods);
        vm.stopPrank();

        assertEq(_tokenA.balanceOf(_maker) - makerTokenBefore, 30 ether);
        assertEq(makerEthBefore - _maker.balance, 0.5 ether);
        assertEq(_tokenA.balanceOf(address(_board)), 20 ether);
        assertEq(address(_board).balance, ETH_AMOUNT + 0.5 ether);
        assertEq(_board.getOrder(erc20Id).availableA, 20 ether);
        assertEq(_board.getOrder(ethId).availableA, ETH_AMOUNT + 0.5 ether);
    }

    /// @notice Tests modifyOrders aggregates ETH top-ups into one msg.value check
    function test_modifyOrders_allEth_topsUp() public {
        vm.startPrank(_maker);
        uint256 id0 = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));
        uint256 id1 = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(id0, _board.getOrder(id0), ETH_AMOUNT + 0.25 ether, AMOUNT_B);
        mods[1] = _modItem(id1, _board.getOrder(id1), ETH_AMOUNT + 0.75 ether, AMOUNT_B);

        uint256 makerBefore = _maker.balance;
        _board.modifyOrders{value: 1 ether}(mods);
        vm.stopPrank();

        assertEq(makerBefore - _maker.balance, 1 ether);
        assertEq(address(_board).balance, 2 ether + 1 ether);
        assertEq(_board.getOrder(id0).availableA, ETH_AMOUNT + 0.25 ether);
        assertEq(_board.getOrder(id1).availableA, ETH_AMOUNT + 0.75 ether);
    }

    /// @notice Tests modifyOrders aggregates ETH refunds into one send
    function test_modifyOrders_allEth_refunds() public {
        vm.startPrank(_maker);
        uint256 id0 = _board.createOrder{value: 1 ether}(_order(_eth, 1 ether, address(_tokenB), AMOUNT_B));
        uint256 id1 = _board.createOrder{value: 1 ether}(_order(_eth, 1 ether, address(_tokenB), AMOUNT_B));

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(id0, _board.getOrder(id0), 0.4 ether, AMOUNT_B);
        mods[1] = _modItem(id1, _board.getOrder(id1), 0.3 ether, AMOUNT_B);

        uint256 makerBefore = _maker.balance;
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_maker.balance - makerBefore, 1.3 ether);
        assertEq(address(_board).balance, 0.7 ether);
    }

    /// @notice Tests empty modifyOrders reverts
    function test_modifyOrders_revert_empty() public {
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](0);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.modifyOrders(mods);
    }

    /// @notice Tests modifyOrders reverts when msg.value is too low for aggregated ETH top-ups
    function test_modifyOrders_revert_ethMismatch_tooLow() public {
        vm.startPrank(_maker);
        uint256 id0 = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));
        uint256 id1 = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(id0, _board.getOrder(id0), ETH_AMOUNT + 0.5 ether, AMOUNT_B);
        mods[1] = _modItem(id1, _board.getOrder(id1), ETH_AMOUNT + 0.5 ether, AMOUNT_B);

        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, 1 ether, 0.5 ether));
        _board.modifyOrders{value: 0.5 ether}(mods);
        vm.stopPrank();
    }

    /// @notice Tests modifyOrders reverts when msg.value is too high
    function test_modifyOrders_revert_ethMismatch_tooHigh() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](1);
        mods[0] = _modItem(orderId, _board.getOrder(orderId), AMOUNT_A / 2, AMOUNT_B);

        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, 0, 1 ether));
        _board.modifyOrders{value: 1 ether}(mods);
        vm.stopPrank();
    }

    /// @notice Tests a one-item modifyOrders matches modifyOrder accounting
    function test_modifyOrders_singleElement() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](1);
        mods[0] = _modItem(orderId, _board.getOrder(orderId), AMOUNT_A / 2, AMOUNT_B * 2);

        uint256 makerBefore = _tokenA.balanceOf(_maker);
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_tokenA.balanceOf(_maker) - makerBefore, AMOUNT_A / 2);
        assertEq(_board.getOrder(orderId).availableA, AMOUNT_A / 2);
        assertEq(_board.getOrder(orderId).availableB, AMOUNT_B * 2);
        assertEq(_board.getOrder(orderId).amountA, AMOUNT_A / 2);
        assertEq(_board.getOrder(orderId).amountB, AMOUNT_B * 2);
    }

    /// @notice Tests modifyOrders emits OrderModified for each order
    function test_modifyOrders_events() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        uint256[] memory ids = _board.createOrders(orders);

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), AMOUNT_A / 2, AMOUNT_B);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), AMOUNT_A / 4, AMOUNT_B);

        vm.expectEmit(true, false, false, true, address(_board));
        emit ISwapboard.OrderModified(ids[0], AMOUNT_A / 2, AMOUNT_B);
        vm.expectEmit(true, false, false, true, address(_board));
        emit ISwapboard.OrderModified(ids[1], AMOUNT_A / 4, AMOUNT_B);
        _board.modifyOrders(mods);
        vm.stopPrank();
    }

    /// @notice Tests modifyOrders reverts DuplicateOrderId
    function test_modifyOrders_revert_duplicateOrderId() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(orderId, snapshot, AMOUNT_A / 2, AMOUNT_B);
        mods[1] = _modItem(orderId, snapshot, AMOUNT_A / 4, AMOUNT_B);

        vm.expectRevert(abi.encodeWithSelector(ISwapboard.DuplicateOrderId.selector, orderId));
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_board.getOrder(orderId).availableA, AMOUNT_A);
    }

    /// @notice Tests modifyOrders reverts NotMaker on a later item without applying earlier legs
    function test_modifyOrders_revert_notMaker_laterItem() public {
        address maker2 = address(0x3);
        _tokenA.mint(maker2, AMOUNT_A);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 order0 = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        vm.startPrank(maker2);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 order1 = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(order0, _board.getOrder(order0), AMOUNT_A / 2, AMOUNT_B);
        mods[1] = _modItem(order1, _board.getOrder(order1), AMOUNT_A / 2, AMOUNT_B);

        vm.startPrank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotMaker.selector, order1, _maker, maker2));
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_board.getOrder(order0).availableA, AMOUNT_A);
        assertEq(_board.getOrder(order1).availableA, AMOUNT_A);
        assertEq(_tokenA.balanceOf(address(_board)), AMOUNT_A * 2);
    }

    /// @notice Tests modifyOrders reverts OrderNotFound on a later item
    function test_modifyOrders_revert_orderNotFound_laterItem() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(orderId, _board.getOrder(orderId), AMOUNT_A / 2, AMOUNT_B);
        mods[1] = ISwapboard.ModifyOrdersParams({
            orderId: 999,
            previousAmounts: ISwapboard.OrderAmounts({amountA: 1, amountB: 1, availableA: 1, availableB: 1}),
            updatedOrder: _modify(1, 1)
        });

        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, 999));
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_board.getOrder(orderId).availableA, AMOUNT_A);
    }

    /// @notice Tests modifyOrders reverts OrderNotActive when a filled order is included
    function test_modifyOrders_revert_orderNotActive_laterItem() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        uint256 order0 = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        uint256 order1 = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _fillOrder(order1, AMOUNT_A);
        vm.stopPrank();

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(order0, _board.getOrder(order0), AMOUNT_A / 2, AMOUNT_B);
        mods[1] = _modItem(order1, _board.getOrder(order1), AMOUNT_A / 2, AMOUNT_B);

        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, order1));
        _board.modifyOrders(mods);

        assertEq(_board.getOrder(order0).availableA, AMOUNT_A);
    }

    /// @notice Tests modifyOrders reverts NoChange when one item is unchanged
    function test_modifyOrders_revert_noChange_laterItem() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        uint256 order0 = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        uint256 order1 = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(order0, _board.getOrder(order0), AMOUNT_A / 2, AMOUNT_B);
        mods[1] = _modItem(order1, _board.getOrder(order1), AMOUNT_A, AMOUNT_B);

        vm.expectRevert(ISwapboard.NoChange.selector);
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_board.getOrder(order0).availableA, AMOUNT_A);
        assertEq(_board.getOrder(order1).availableA, AMOUNT_A);
    }

    /// @notice Tests modifyOrders ETH refund reverts when maker rejects ETH and leaves escrow intact
    function test_modifyOrders_revert_ethTransferFailed() public {
        ETHRejecter rejecter = new ETHRejecter();
        vm.deal(address(rejecter), 10 ether);

        vm.startPrank(address(rejecter));
        uint256 id0 = _board.createOrder{value: 1 ether}(_order(_eth, 1 ether, address(_tokenB), AMOUNT_B));
        uint256 id1 = _board.createOrder{value: 1 ether}(_order(_eth, 1 ether, address(_tokenB), AMOUNT_B));

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(id0, _board.getOrder(id0), 0.5 ether, AMOUNT_B);
        mods[1] = _modItem(id1, _board.getOrder(id1), 0.5 ether, AMOUNT_B);

        uint256 boardEthBefore = address(_board).balance;
        vm.expectRevert(ETHRejecter.RejectETH.selector);
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertTrue(_board.canFill(id0));
        assertTrue(_board.canFill(id1));
        assertEq(_board.getOrder(id0).availableA, 1 ether);
        assertEq(_board.getOrder(id1).availableA, 1 ether);
        assertEq(address(_board).balance, boardEthBefore);
    }

    /// @notice Tests modifyOrders then fills each resized order
    function test_modifyOrders_thenFillEach() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        uint256 order0 = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));
        uint256 order1 = _board.createOrder(_order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B));

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(order0, _board.getOrder(order0), AMOUNT_A / 2, AMOUNT_B / 5);
        mods[1] = _modItem(order1, _board.getOrder(order1), AMOUNT_A / 4, AMOUNT_B / 10);
        _board.modifyOrders(mods);
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _fillOrder(order0, AMOUNT_A / 2);
        _fillOrder(order1, AMOUNT_A / 4);
        vm.stopPrank();

        assertFalse(_board.canFill(order0));
        assertFalse(_board.canFill(order1));
        assertEq(_tokenA.balanceOf(address(_board)), 0);
    }

    /// @notice Tests netted top-up succeeds when allowance equals the net (not gross) pull
    function test_modifyOrders_netsSameToken_succeedsWithNetAllowance() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), 10 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), 40 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        uint256[] memory ids = _board.createOrders(orders);

        // +20 / -10 => net pull 10; gross top-up 20 would fail this allowance
        _tokenA.approve(address(_board), 10 ether);

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 30 ether, AMOUNT_B);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 30 ether, AMOUNT_B);

        uint256 makerBefore = _tokenA.balanceOf(_maker);
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(makerBefore - _tokenA.balanceOf(_maker), 10 ether);
        assertEq(_tokenA.balanceOf(address(_board)), 60 ether);
        assertEq(_tokenA.allowance(_maker, address(_board)), 0);
    }

    /// @notice Tests netted top-up succeeds when balance equals the net (not gross) pull
    function test_modifyOrders_netsSameToken_succeedsWithNetBalance() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), 10 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), 40 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        uint256[] memory ids = _board.createOrders(orders);

        uint256 leftover = _tokenA.balanceOf(_maker);
        assertTrue(_tokenA.transfer(address(0xdead), leftover - 10 ether));
        assertEq(_tokenA.balanceOf(_maker), 10 ether);

        // +20 / -10 => net pull 10; gross 20 would exceed balance
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 30 ether, AMOUNT_B);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 30 ether, AMOUNT_B);
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_tokenA.balanceOf(_maker), 0);
        assertEq(_tokenA.balanceOf(address(_board)), 60 ether);
    }

    /// @notice Tests netted top-up reverts when allowance is below the net pull
    function test_modifyOrders_revert_insufficientAllowance_belowNet() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), 10 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), 40 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        uint256[] memory ids = _board.createOrders(orders);
        _tokenA.approve(address(_board), 9 ether);

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 30 ether, AMOUNT_B);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 30 ether, AMOUNT_B);

        uint256 makerBefore = _tokenA.balanceOf(_maker);
        uint256 boardBefore = _tokenA.balanceOf(address(_board));
        vm.expectRevert(stdError.arithmeticError);
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_board.getOrder(ids[0]).availableA, 10 ether);
        assertEq(_board.getOrder(ids[1]).availableA, 40 ether);
        assertEq(_tokenA.balanceOf(_maker), makerBefore);
        assertEq(_tokenA.balanceOf(address(_board)), boardBefore);
    }

    /// @notice Tests netted top-up reverts when maker balance is below the net pull
    function test_modifyOrders_revert_insufficientBalance_belowNet() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), 10 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), 40 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        uint256[] memory ids = _board.createOrders(orders);

        uint256 leftover = _tokenA.balanceOf(_maker);
        assertTrue(_tokenA.transfer(address(0xdead), leftover - 9 ether));

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 30 ether, AMOUNT_B);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 30 ether, AMOUNT_B);

        uint256 boardBefore = _tokenA.balanceOf(address(_board));
        vm.expectRevert(stdError.arithmeticError);
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_board.getOrder(ids[0]).availableA, 10 ether);
        assertEq(_board.getOrder(ids[1]).availableA, 40 ether);
        assertEq(_tokenA.balanceOf(address(_board)), boardBefore);
        assertEq(_tokenA.balanceOf(_maker), 9 ether);
    }

    /// @notice Tests OrderStateMismatch on a later item leaves earlier legs unapplied
    function test_modifyOrders_revert_orderStateMismatch_laterItem() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), 10 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), 40 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        uint256[] memory ids = _board.createOrders(orders);

        ISwapboard.Order memory snap0 = _board.getOrder(ids[0]);
        ISwapboard.Order memory snap1 = _board.getOrder(ids[1]);
        ISwapboard.OrderAmounts memory stale1 = _amounts(snap1);
        stale1.availableA = snap1.availableA - 1;

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(ids[0], snap0, 30 ether, AMOUNT_B);
        mods[1] = ISwapboard.ModifyOrdersParams({
            orderId: ids[1], previousAmounts: stale1, updatedOrder: _modify(30 ether, AMOUNT_B)
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                ISwapboard.OrderStateMismatch.selector,
                ids[1],
                stale1.amountA,
                stale1.amountB,
                stale1.availableA,
                stale1.availableB,
                snap1.amountA,
                snap1.amountB,
                snap1.availableA,
                snap1.availableB
            )
        );
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_board.getOrder(ids[0]).availableA, 10 ether);
        assertEq(_board.getOrder(ids[1]).availableA, 40 ether);
        assertEq(_tokenA.balanceOf(address(_board)), 50 ether);
    }

    /// @notice Tests ZeroAmount when a later batch item sets availableA to 0
    function test_modifyOrders_revert_zeroAvailableA_laterItem() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), 10 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), 40 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        uint256[] memory ids = _board.createOrders(orders);

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 30 ether, AMOUNT_B);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 0, AMOUNT_B);

        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_board.getOrder(ids[0]).availableA, 10 ether);
        assertEq(_board.getOrder(ids[1]).availableA, 40 ether);
    }

    /// @notice Tests ZeroAmount when a later batch item sets availableB to 0
    function test_modifyOrders_revert_zeroAvailableB_laterItem() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), 10 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), 40 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        uint256[] memory ids = _board.createOrders(orders);

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 30 ether, AMOUNT_B);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 30 ether, 0);

        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_board.getOrder(ids[0]).availableA, 10 ether);
        assertEq(_board.getOrder(ids[1]).availableA, 40 ether);
    }

    /// @notice Tests FOT tokenA rejects the netted pull amount (not the gross top-up)
    function test_modifyOrders_revert_FOT_nettedTopUp() public {
        MockFOT fot = new MockFOT();
        fot.setFeePercent(0);
        fot.mint(_maker, 1000 ether);

        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(fot), 10 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(fot), 40 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        fot.approve(address(_board), type(uint256).max);
        uint256[] memory ids = _board.createOrders(orders);
        vm.stopPrank();

        fot.setFeePercent(5);

        // +20 / -10 => net pull 10; BalanceMismatch must quote 10, not 20
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 30 ether, AMOUNT_B);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 30 ether, AMOUNT_B);

        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.BalanceMismatch.selector, 10 ether, _fotNet(10 ether)));
        _board.modifyOrders(mods);

        assertEq(_board.getOrder(ids[0]).availableA, 10 ether);
        assertEq(_board.getOrder(ids[1]).availableA, 40 ether);
        assertEq(fot.balanceOf(address(_board)), 50 ether);
    }

    /// @notice Tests ERC20-only batch reverts when msg.value is non-zero
    function test_modifyOrders_revert_accidentalEth_erc20Only() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), 10 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), 40 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        uint256[] memory ids = _board.createOrders(orders);

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 30 ether, AMOUNT_B);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 30 ether, AMOUNT_B);

        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, 0, 1 ether));
        _board.modifyOrders{value: 1 ether}(mods);
        vm.stopPrank();

        assertEq(_board.getOrder(ids[0]).availableA, 10 ether);
        assertEq(_board.getOrder(ids[1]).availableA, 40 ether);
    }

    /// @notice Tests fully-netted ETH batch reverts when msg.value is non-zero
    function test_modifyOrders_netsEth_cancelsCompletely_revert_accidentalEth() public {
        vm.startPrank(_maker);
        uint256 id0 = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));
        uint256 id1 = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(id0, _board.getOrder(id0), ETH_AMOUNT + 0.5 ether, AMOUNT_B);
        mods[1] = _modItem(id1, _board.getOrder(id1), ETH_AMOUNT - 0.5 ether, AMOUNT_B);

        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, 0, 0.1 ether));
        _board.modifyOrders{value: 0.1 ether}(mods);
        vm.stopPrank();

        assertEq(_board.getOrder(id0).availableA, ETH_AMOUNT);
        assertEq(_board.getOrder(id1).availableA, ETH_AMOUNT);
    }

    /// @notice Tests ETH refund-dominates path reverts when msg.value is non-zero
    function test_modifyOrders_netsEth_refundDominates_revert_accidentalEth() public {
        vm.startPrank(_maker);
        uint256 id0 = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));
        uint256 id1 = _board.createOrder{value: 2 ether}(_order(_eth, 2 ether, address(_tokenB), AMOUNT_B));

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(id0, _board.getOrder(id0), ETH_AMOUNT + 0.2 ether, AMOUNT_B);
        mods[1] = _modItem(id1, _board.getOrder(id1), 1 ether, AMOUNT_B);

        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, 0, 0.2 ether));
        _board.modifyOrders{value: 0.2 ether}(mods);
        vm.stopPrank();

        assertEq(_board.getOrder(id0).availableA, ETH_AMOUNT);
        assertEq(_board.getOrder(id1).availableA, 2 ether);
    }

    /// @notice Tests three ETH legs whose top-ups and refunds cancel exactly
    function test_modifyOrders_netsEth_threeOrders_cancelsCompletely() public {
        vm.startPrank(_maker);
        uint256 id0 = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));
        uint256 id1 = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));
        uint256 id2 = _board.createOrder{value: ETH_AMOUNT}(_order(_eth, ETH_AMOUNT, address(_tokenB), AMOUNT_B));

        // +0.4, +0.2, -0.6 => cancel
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](3);
        mods[0] = _modItem(id0, _board.getOrder(id0), ETH_AMOUNT + 0.4 ether, AMOUNT_B);
        mods[1] = _modItem(id1, _board.getOrder(id1), ETH_AMOUNT + 0.2 ether, AMOUNT_B);
        mods[2] = _modItem(id2, _board.getOrder(id2), ETH_AMOUNT - 0.6 ether, AMOUNT_B);

        uint256 makerBefore = _maker.balance;
        uint256 boardBefore = address(_board).balance;
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_maker.balance, makerBefore);
        assertEq(address(_board).balance, boardBefore);
        assertEq(_board.getOrder(id0).availableA, ETH_AMOUNT + 0.4 ether);
        assertEq(_board.getOrder(id1).availableA, ETH_AMOUNT + 0.2 ether);
        assertEq(_board.getOrder(id2).availableA, ETH_AMOUNT - 0.6 ether);
    }

    /// @notice Tests availableB-only batch moves no tokenA and requires msg.value 0
    function test_modifyOrders_availableBOnly_noTokenMovement() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), 10 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), 40 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        uint256[] memory ids = _board.createOrders(orders);

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 10 ether, AMOUNT_B * 2);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 40 ether, AMOUNT_B / 2);

        uint256 pullsBefore = _tf(_tokenA);
        uint256 makerBefore = _tokenA.balanceOf(_maker);
        uint256 boardBefore = _tokenA.balanceOf(address(_board));
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_tf(_tokenA), pullsBefore);
        assertEq(_tokenA.balanceOf(_maker), makerBefore);
        assertEq(_tokenA.balanceOf(address(_board)), boardBefore);
        assertEq(_board.getOrder(ids[0]).availableA, 10 ether);
        assertEq(_board.getOrder(ids[0]).availableB, AMOUNT_B * 2);
        assertEq(_board.getOrder(ids[1]).availableA, 40 ether);
        assertEq(_board.getOrder(ids[1]).availableB, AMOUNT_B / 2);
    }

    /// @notice Tests DuplicateOrderId when a repeated id is not adjacent
    function test_modifyOrders_revert_duplicateOrderId_nonAdjacent() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), 10 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), 40 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        uint256[] memory ids = _board.createOrders(orders);

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](3);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 15 ether, AMOUNT_B);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 30 ether, AMOUNT_B);
        mods[2] = _modItem(ids[0], _board.getOrder(ids[0]), 20 ether, AMOUNT_B);

        vm.expectRevert(abi.encodeWithSelector(ISwapboard.DuplicateOrderId.selector, ids[0]));
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(_board.getOrder(ids[0]).availableA, 10 ether);
        assertEq(_board.getOrder(ids[1]).availableA, 40 ether);
    }

    /// @notice Tests batch modify preserves maker, tokens, and partialFillAllowed
    function test_modifyOrders_preserves_immutables() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _orderPartial(address(_tokenA), 10 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), 40 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        uint256[] memory ids = _board.createOrders(orders);

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 30 ether, AMOUNT_B / 2);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 30 ether, AMOUNT_B * 2);
        _board.modifyOrders(mods);
        vm.stopPrank();

        ISwapboard.Order memory after0 = _board.getOrder(ids[0]);
        ISwapboard.Order memory after1 = _board.getOrder(ids[1]);
        assertEq(after0.maker, _maker);
        assertEq(after1.maker, _maker);
        assertEq(after0.tokenA, address(_tokenA));
        assertEq(after0.tokenB, address(_tokenB));
        assertEq(after1.tokenA, address(_tokenA));
        assertEq(after1.tokenB, address(_tokenB));
        assertTrue(after0.partialFillAllowed);
        assertFalse(after1.partialFillAllowed);
        assertEq(after0.availableA, 30 ether);
        assertEq(after1.availableA, 30 ether);
    }

    /// @notice Tests batch modify after partial fills, then fills and cancels the new remainings
    function test_modifyOrders_afterPartialFill_thenFillAndCancel() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _orderPartial(address(_tokenA), 100 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _orderPartial(address(_tokenA), 100 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        uint256[] memory ids = _board.createOrders(orders);
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B * 2);
        _fillOrder(ids[0], 60 ether);
        _fillOrder(ids[1], 20 ether);
        vm.stopPrank();

        assertEq(_board.getOrder(ids[0]).availableA, 40 ether);
        assertEq(_board.getOrder(ids[1]).availableA, 80 ether);

        // +10 on ids[0], -30 on ids[1] => net refund 20
        vm.startPrank(_maker);
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 50 ether, AMOUNT_B / 5);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 50 ether, AMOUNT_B / 5);

        uint256 makerBefore = _tokenA.balanceOf(_maker);
        _board.modifyOrders(mods);
        assertEq(_tokenA.balanceOf(_maker) - makerBefore, 20 ether);
        assertEq(_board.getOrder(ids[0]).availableA, 50 ether);
        assertEq(_board.getOrder(ids[1]).availableA, 50 ether);

        uint256[] memory cancelIds = new uint256[](1);
        cancelIds[0] = ids[1];
        uint256 makerBeforeCancel = _tokenA.balanceOf(_maker);
        _board.cancelOrders(cancelIds);
        assertEq(_tokenA.balanceOf(_maker) - makerBeforeCancel, 50 ether);
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _fillOrder(ids[0], 50 ether);
        vm.stopPrank();

        assertFalse(_board.canFill(ids[0]));
        assertEq(_board.getOrder(ids[1]).maker, address(0));
        assertEq(_tokenA.balanceOf(address(_board)), 0);
    }

    /// @notice Sanity: MockRevertOnZeroERC20 reverts on zero-amount transfer / transferFrom
    function test_mockRevertOnZeroERC20_revertsOnZero() public {
        MockRevertOnZeroERC20 token = new MockRevertOnZeroERC20("ZeroRevert", "ZRV", 18);
        token.mint(_maker, 100 ether);

        vm.startPrank(_maker);
        vm.expectRevert(MockRevertOnZeroERC20.ZeroAmountTransfer.selector);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        token.transfer(_taker, 0);

        token.approve(msg.sender, type(uint256).max);
        vm.expectRevert(MockRevertOnZeroERC20.ZeroAmountTransfer.selector);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        token.transferFrom(msg.sender, _taker, 0);
        vm.stopPrank();
    }

    /// @notice Tests exact top-up/refund cancel with a token that reverts on zero transfers
    function test_modifyOrders_netsSameToken_cancelsCompletely_revertOnZeroToken() public {
        MockRevertOnZeroERC20 token = new MockRevertOnZeroERC20("ZeroRevert", "ZRV", 18);
        token.mint(_maker, 1000 ether);

        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(token), 10 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(token), 40 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        token.approve(address(_board), type(uint256).max);
        uint256[] memory ids = _board.createOrders(orders);

        // +10 / -10 => net 0; must not call transfer(0) / transferFrom(0)
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 20 ether, AMOUNT_B);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 30 ether, AMOUNT_B);

        uint256 makerBefore = token.balanceOf(_maker);
        uint256 boardBefore = token.balanceOf(address(_board));
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(token.balanceOf(_maker), makerBefore);
        assertEq(token.balanceOf(address(_board)), boardBefore);
        assertEq(_board.getOrder(ids[0]).availableA, 20 ether);
        assertEq(_board.getOrder(ids[1]).availableA, 30 ether);
    }

    /// @notice Tests availableB-only batch with a zero-reverting token does not touch tokenA
    function test_modifyOrders_availableBOnly_revertOnZeroToken() public {
        MockRevertOnZeroERC20 token = new MockRevertOnZeroERC20("ZeroRevert", "ZRV", 18);
        token.mint(_maker, 1000 ether);

        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(token), 10 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(token), 40 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        token.approve(address(_board), type(uint256).max);
        uint256[] memory ids = _board.createOrders(orders);

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 10 ether, AMOUNT_B * 2);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 40 ether, AMOUNT_B / 2);

        uint256 makerBefore = token.balanceOf(_maker);
        uint256 boardBefore = token.balanceOf(address(_board));
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(token.balanceOf(_maker), makerBefore);
        assertEq(token.balanceOf(address(_board)), boardBefore);
        assertEq(_board.getOrder(ids[0]).availableB, AMOUNT_B * 2);
        assertEq(_board.getOrder(ids[1]).availableB, AMOUNT_B / 2);
    }

    /// @notice Tests three-leg exact cancel with a zero-reverting token
    function test_modifyOrders_netsSameToken_threeOrders_cancelsCompletely_revertOnZeroToken() public {
        MockRevertOnZeroERC20 token = new MockRevertOnZeroERC20("ZeroRevert", "ZRV", 18);
        token.mint(_maker, 1000 ether);

        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](3);
        orders[0] = _order(address(token), 10 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(token), 20 ether, address(_tokenB), AMOUNT_B);
        orders[2] = _order(address(token), 40 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        token.approve(address(_board), type(uint256).max);
        uint256[] memory ids = _board.createOrders(orders);

        // +10, +5, -15 => cancel
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](3);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 20 ether, AMOUNT_B);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 25 ether, AMOUNT_B);
        mods[2] = _modItem(ids[2], _board.getOrder(ids[2]), 25 ether, AMOUNT_B);

        uint256 makerBefore = token.balanceOf(_maker);
        uint256 boardBefore = token.balanceOf(address(_board));
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(token.balanceOf(_maker), makerBefore);
        assertEq(token.balanceOf(address(_board)), boardBefore);
        assertEq(_board.getOrder(ids[0]).availableA, 20 ether);
        assertEq(_board.getOrder(ids[1]).availableA, 25 ether);
        assertEq(_board.getOrder(ids[2]).availableA, 25 ether);
    }

    /// @notice Tests netted top-up with a zero-reverting token still pulls the non-zero net
    function test_modifyOrders_netsSameToken_topUpDominates_revertOnZeroToken() public {
        MockRevertOnZeroERC20 token = new MockRevertOnZeroERC20("ZeroRevert", "ZRV", 18);
        token.mint(_maker, 1000 ether);

        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(token), 10 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(token), 40 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        token.approve(address(_board), type(uint256).max);
        uint256[] memory ids = _board.createOrders(orders);

        // +20 / -10 => net pull 10 (must transferFrom 10, never 0)
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 30 ether, AMOUNT_B);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 30 ether, AMOUNT_B);

        uint256 makerBefore = token.balanceOf(_maker);
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(makerBefore - token.balanceOf(_maker), 10 ether);
        assertEq(token.balanceOf(address(_board)), 60 ether);
        assertEq(_board.getOrder(ids[0]).availableA, 30 ether);
        assertEq(_board.getOrder(ids[1]).availableA, 30 ether);
    }

    /// @notice Tests netted refund with a zero-reverting token still sends the non-zero net
    function test_modifyOrders_netsSameToken_refundDominates_revertOnZeroToken() public {
        MockRevertOnZeroERC20 token = new MockRevertOnZeroERC20("ZeroRevert", "ZRV", 18);
        token.mint(_maker, 1000 ether);

        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(token), 10 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(token), 40 ether, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        token.approve(address(_board), type(uint256).max);
        uint256[] memory ids = _board.createOrders(orders);

        // +5 / -20 => net refund 15 (must transfer 15, never 0)
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 15 ether, AMOUNT_B);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 20 ether, AMOUNT_B);

        uint256 makerBefore = token.balanceOf(_maker);
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(token.balanceOf(_maker) - makerBefore, 15 ether);
        assertEq(token.balanceOf(address(_board)), 35 ether);
        assertEq(_board.getOrder(ids[0]).availableA, 15 ether);
        assertEq(_board.getOrder(ids[1]).availableA, 20 ether);
    }

    /// @notice Tests one token cancels exactly while another nets a pull; zero-revert only on cancel token
    function test_modifyOrders_mixedCancelAndPull_revertOnZeroToken() public {
        MockRevertOnZeroERC20 cancelToken = new MockRevertOnZeroERC20("ZeroRevert", "ZRV", 18);
        cancelToken.mint(_maker, 1000 ether);

        vm.startPrank(_maker);
        cancelToken.approve(address(_board), type(uint256).max);
        _tokenA.approve(address(_board), type(uint256).max);

        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](4);
        // cancelToken: 10 and 40 — will net-cancel
        orders[0] = _order(address(cancelToken), 10 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(cancelToken), 40 ether, address(_tokenB), AMOUNT_B);
        // tokenA: 10 and 40 — will net-pull 15
        orders[2] = _order(address(_tokenA), 10 ether, address(_tokenB), AMOUNT_B);
        orders[3] = _order(address(_tokenA), 40 ether, address(_tokenB), AMOUNT_B);
        uint256[] memory ids = _board.createOrders(orders);

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](4);
        // cancelToken +10 / -10 => no transfer
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 20 ether, AMOUNT_B);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 30 ether, AMOUNT_B);
        // tokenA +20 / -5 => net pull 15
        mods[2] = _modItem(ids[2], _board.getOrder(ids[2]), 30 ether, AMOUNT_B);
        mods[3] = _modItem(ids[3], _board.getOrder(ids[3]), 35 ether, AMOUNT_B);

        uint256 cancelMakerBefore = cancelToken.balanceOf(_maker);
        uint256 cancelBoardBefore = cancelToken.balanceOf(address(_board));
        uint256 tokenAMakerBefore = _tokenA.balanceOf(_maker);
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(cancelToken.balanceOf(_maker), cancelMakerBefore);
        assertEq(cancelToken.balanceOf(address(_board)), cancelBoardBefore);
        assertEq(tokenAMakerBefore - _tokenA.balanceOf(_maker), 15 ether);
        assertEq(_tokenA.balanceOf(address(_board)), 65 ether);
        assertEq(_board.getOrder(ids[0]).availableA, 20 ether);
        assertEq(_board.getOrder(ids[1]).availableA, 30 ether);
        assertEq(_board.getOrder(ids[2]).availableA, 30 ether);
        assertEq(_board.getOrder(ids[3]).availableA, 35 ether);
    }

    /// @notice Tests one token cancels exactly while another nets a refund; zero-revert only on cancel token
    function test_modifyOrders_mixedCancelAndRefund_revertOnZeroToken() public {
        MockRevertOnZeroERC20 cancelToken = new MockRevertOnZeroERC20("ZeroRevert", "ZRV", 18);
        cancelToken.mint(_maker, 1000 ether);

        vm.startPrank(_maker);
        cancelToken.approve(address(_board), type(uint256).max);
        _tokenA.approve(address(_board), type(uint256).max);

        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](4);
        orders[0] = _order(address(cancelToken), 10 ether, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(cancelToken), 40 ether, address(_tokenB), AMOUNT_B);
        orders[2] = _order(address(_tokenA), 10 ether, address(_tokenB), AMOUNT_B);
        orders[3] = _order(address(_tokenA), 40 ether, address(_tokenB), AMOUNT_B);
        uint256[] memory ids = _board.createOrders(orders);

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](4);
        // cancelToken +10 / -10 => no transfer
        mods[0] = _modItem(ids[0], _board.getOrder(ids[0]), 20 ether, AMOUNT_B);
        mods[1] = _modItem(ids[1], _board.getOrder(ids[1]), 30 ether, AMOUNT_B);
        // tokenA +5 / -20 => net refund 15
        mods[2] = _modItem(ids[2], _board.getOrder(ids[2]), 15 ether, AMOUNT_B);
        mods[3] = _modItem(ids[3], _board.getOrder(ids[3]), 20 ether, AMOUNT_B);

        uint256 cancelMakerBefore = cancelToken.balanceOf(_maker);
        uint256 cancelBoardBefore = cancelToken.balanceOf(address(_board));
        uint256 tokenAMakerBefore = _tokenA.balanceOf(_maker);
        _board.modifyOrders(mods);
        vm.stopPrank();

        assertEq(cancelToken.balanceOf(_maker), cancelMakerBefore);
        assertEq(cancelToken.balanceOf(address(_board)), cancelBoardBefore);
        assertEq(_tokenA.balanceOf(_maker) - tokenAMakerBefore, 15 ether);
        assertEq(_tokenA.balanceOf(address(_board)), 35 ether);
        assertEq(_board.getOrder(ids[0]).availableA, 20 ether);
        assertEq(_board.getOrder(ids[1]).availableA, 30 ether);
        assertEq(_board.getOrder(ids[2]).availableA, 15 ether);
        assertEq(_board.getOrder(ids[3]).availableA, 20 ether);
    }

    /// @notice Tests single modifyOrder availableB-only with a zero-reverting token
    function test_modifyOrder_availableBOnly_revertOnZeroToken() public {
        MockRevertOnZeroERC20 token = new MockRevertOnZeroERC20("ZeroRevert", "ZRV", 18);
        token.mint(_maker, 1000 ether);

        vm.startPrank(_maker);
        token.approve(address(_board), type(uint256).max);
        uint256 orderId = _board.createOrder(_order(address(token), 50 ether, address(_tokenB), AMOUNT_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        uint256 makerBefore = token.balanceOf(_maker);
        uint256 boardBefore = token.balanceOf(address(_board));
        _board.modifyOrder(orderId, _amounts(snapshot), _modify(50 ether, AMOUNT_B * 2));
        vm.stopPrank();

        assertEq(token.balanceOf(_maker), makerBefore);
        assertEq(token.balanceOf(address(_board)), boardBefore);
        ISwapboard.Order memory after_ = _board.getOrder(orderId);
        assertEq(after_.availableA, 50 ether);
        assertEq(after_.availableB, AMOUNT_B * 2);
        assertEq(after_.amountA, 50 ether);
        assertEq(after_.amountB, AMOUNT_B * 2);
    }
}
