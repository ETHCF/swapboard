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
import {stdStorage, StdStorage} from "forge-std/StdStorage.sol";
import {Swapboard} from "../src/Swapboard.sol";
import {ISwapboard} from "../src/interfaces/ISwapboard.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockFOT} from "./mocks/MockFOT.sol";
import {ETHRejecter} from "./mocks/ETHRejecter.sol";

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
        uint256 order0 = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
        assertEq(order0, 0);
        assertEq(_board.getNextOrderId(), 1);

        uint256 order1 = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();

        assertEq(order1, 1);
        assertEq(_board.getNextOrderId(), 2);
    }

    /// @notice getOrder returns full order details for an existing order
    function test_getOrder() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
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

        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
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

        assertEq(_tokenA.balanceOf(address(_board)), AMOUNT_A);
        assertEq(_tokenA.balanceOf(_maker), AMOUNT_A * 10 - AMOUNT_A);
    }

    /// @notice Tests createOrder stores partialFillAllowed=true
    function test_createOrder_partialFillAllowed_true() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: true
            })
        );
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertTrue(order.partialFillAllowed);
        assertTrue(order.active);
    }

    /// @notice Tests createOrder stores partialFillAllowed=false
    function test_createOrder_partialFillAllowed_false() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();

        assertFalse(_board.getOrder(orderId).partialFillAllowed);
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

        _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: true
            })
        );
        vm.stopPrank();
    }

    /// @notice Tests ETH sell order stores partialFillAllowed
    function test_createOrder_sellEth_partialFillAllowed_true() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth,
                amountA: ETH_AMOUNT,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: true
            })
        );

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertTrue(order.partialFillAllowed);
        assertEq(order.tokenA, _eth);
        assertEq(order.amountA, ETH_AMOUNT);
    }

    /// @notice Tests createOrder revert zeroAddress _tokenA
    function test_createOrder_revert_zeroAddress_tokenA() public {
        vm.startPrank(_maker);
        vm.expectRevert(ISwapboard.ZeroAddress.selector);
        _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(0),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();
    }

    /// @notice Tests createOrder revert zeroAddress _tokenB
    function test_createOrder_revert_zeroAddress_tokenB() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        vm.expectRevert(ISwapboard.ZeroAddress.selector);
        _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(0),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();
    }

    /// @notice Tests createOrder revert zeroAmount amountA
    function test_createOrder_revert_zeroAmount_amountA() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: 0,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();
    }

    /// @notice Tests createOrder revert zeroAmount amountB
    function test_createOrder_revert_zeroAmount_amountB() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: 0,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();
    }

    /// @notice Tests createOrder revert sameToken
    function test_createOrder_revert_sameToken() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        vm.expectRevert(ISwapboard.SameToken.selector);
        _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenA),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();
    }

    /// @notice Tests createOrder revert notAContract _tokenA
    function test_createOrder_revert_notAContract_tokenA() public {
        vm.startPrank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotAContract.selector, address(0x999)));
        _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(0x999),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();
    }

    /// @notice Tests createOrder revert notAContract _tokenB
    function test_createOrder_revert_notAContract_tokenB() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotAContract.selector, address(0x999)));
        _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(0x999),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();
    }

    /// @notice Tests createOrder revert FOT
    function test_createOrder_revert_FOT() public {
        MockFOT fot = new MockFOT();
        fot.mint(_maker, 1000 ether);

        vm.startPrank(_maker);
        fot.approve(address(_board), 100 ether);

        vm.expectRevert(abi.encodeWithSelector(ISwapboard.BalanceMismatch.selector, 100 ether, 95 ether));
        _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(fot),
                amountA: 100 ether,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();
    }

    /// @notice Tests fillOrder
    function test_fillOrder() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _board.fillOrder(orderId, AMOUNT_A, 0);
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
        _board.fillOrder(999, 1, 0);
        vm.stopPrank();
    }

    /// @notice Tests fillOrder revert orderNotActive
    function test_fillOrder_revert_orderNotActive() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _board.fillOrder(orderId, AMOUNT_A, 0);

        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        _board.fillOrder(orderId, AMOUNT_A, 0);
        vm.stopPrank();
    }

    /// @notice Tests cancelOrder
    function test_cancelOrder() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );

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

    /// @notice Tests cancelOrder revert orderNotFound after a prior cancel
    function test_cancelOrder_revert_orderNotFound_afterCancel() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
        _board.cancelOrder(orderId);

        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, orderId));
        _board.cancelOrder(orderId);
        vm.stopPrank();
    }

    /// @notice Tests cancelOrder revert notMaker
    function test_cancelOrder_revert_notMaker() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
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
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();

        assertTrue(_board.canFill(orderId));
    }

    /// @notice Tests canFill false notActive
    function test_canFill_false_notActive() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
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

        uint256 order0 = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
        uint256 order1 = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B * 2,
                partialFillAllowed: false
            })
        );
        uint256 order2 = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B * 3,
                partialFillAllowed: false
            })
        );
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

        uint256 order0 = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
        uint256 order1 = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B * 2,
                partialFillAllowed: false
            })
        );
        uint256 order2 = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B * 3,
                partialFillAllowed: false
            })
        );
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

        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
        _board.fillOrder(orderId, AMOUNT_A, 0);
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
            amountB: AMOUNT_B,
            partialFillAllowed: false
        });

        _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();
    }

    /// @notice Tests events orderFilled
    function test_events_orderFilled() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);

        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderFilled({orderId: orderId, taker: _taker, amountA: AMOUNT_A, amountB: AMOUNT_B});

        _board.fillOrder(orderId, AMOUNT_A, 0);
        vm.stopPrank();
    }

    /// @notice Tests events orderCanceled
    function test_events_orderCanceled() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );

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
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: amountA,
                tokenB: address(_tokenB),
                amountB: amountB,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertEq(order.amountA, amountA);
        assertEq(order.amountB, amountB);
        assertEq(order.availableA, amountA);
        assertEq(order.availableB, amountB);
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
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: amountA,
                tokenB: address(_tokenB),
                amountB: amountB,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), amountB);
        _board.fillOrder(orderId, amountA, 0);
        vm.stopPrank();

        assertEq(_tokenA.balanceOf(_taker), takerTokenABefore + amountA);
        assertEq(_tokenB.balanceOf(_maker), makerTokenBBefore + amountB);
    }

    /// @notice Tests fillOrder revert deadlineExpired
    function test_fillOrder_revert_deadlineExpired() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();

        vm.warp(1000);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        vm.expectRevert(ISwapboard.DeadlineExpired.selector);
        _board.fillOrder(orderId, AMOUNT_A, 999);
        vm.stopPrank();
    }

    /// @notice Tests fillOrder deadlineZero noExpiry
    function test_fillOrder_deadlineZero_noExpiry() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();

        vm.warp(type(uint256).max);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _board.fillOrder(orderId, AMOUNT_A, 0);
        vm.stopPrank();

        assertFalse(_board.getOrder(orderId).active);
    }

    /// @notice Tests fillOrder succeeds when block.timestamp equals deadline
    function test_fillOrder_deadlineEqual_succeeds() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();

        uint256 deadline = 1000;
        vm.warp(deadline);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _board.fillOrder(orderId, AMOUNT_A, deadline);
        vm.stopPrank();

        assertFalse(_board.getOrder(orderId).active);
    }

    // ============ createOrder with ETH as tokenA ============

    /// @notice Tests createOrder selling ETH
    function test_createOrder_sellEth() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth,
                amountA: ETH_AMOUNT,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );

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
        _board.createOrder{value: ETH_AMOUNT + 0.5 ether}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth,
                amountA: ETH_AMOUNT,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
    }

    /// @notice Tests createOrder selling ETH reverts on underpayment
    function test_createOrder_sellEth_revert_amountMismatch() public {
        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, ETH_AMOUNT, ETH_AMOUNT - 1));
        _board.createOrder{value: ETH_AMOUNT - 1}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth,
                amountA: ETH_AMOUNT,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
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
        _board.createOrder{value: ETH_AMOUNT}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth,
                amountA: ETH_AMOUNT,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
    }

    /// @notice Tests createOrder selling ETH reverts on zero amount
    function test_createOrder_sellEth_revert_zeroAmount() public {
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.createOrder{value: 0}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth, amountA: 0, tokenB: address(_tokenB), amountB: AMOUNT_B, partialFillAllowed: false
            })
        );
    }

    /// @notice Tests createOrder selling ETH reverts on zero amountB
    function test_createOrder_sellEth_revert_zeroAmount_amountB() public {
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.createOrder{value: ETH_AMOUNT}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth, amountA: ETH_AMOUNT, tokenB: address(_tokenB), amountB: 0, partialFillAllowed: false
            })
        );
    }

    /// @notice Tests createOrder selling ETH reverts on zero address tokenB
    function test_createOrder_sellEth_revert_zeroAddress() public {
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.ZeroAddress.selector);
        _board.createOrder{value: ETH_AMOUNT}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth, amountA: ETH_AMOUNT, tokenB: address(0), amountB: AMOUNT_B, partialFillAllowed: false
            })
        );
    }

    /// @notice Tests createOrder selling ETH reverts when tokenB is also ETH
    function test_createOrder_sellEth_revert_sameToken() public {
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.SameToken.selector);
        _board.createOrder{value: ETH_AMOUNT}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth, amountA: ETH_AMOUNT, tokenB: _eth, amountB: AMOUNT_B, partialFillAllowed: false
            })
        );
    }

    /// @notice Tests createOrder selling ETH reverts when tokenB is an EOA
    function test_createOrder_sellEth_revert_notAContract() public {
        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotAContract.selector, address(0xDEAD)));
        _board.createOrder{value: ETH_AMOUNT}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth,
                amountA: ETH_AMOUNT,
                tokenB: address(0xDEAD),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
    }

    /// @notice Tests createOrder selling ETH assigns sequential IDs
    function test_createOrder_sellEth_sequentialIds() public {
        vm.startPrank(_maker);
        uint256 id0 = _board.createOrder{value: ETH_AMOUNT}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth,
                amountA: ETH_AMOUNT,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
        uint256 id1 = _board.createOrder{value: ETH_AMOUNT}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth,
                amountA: ETH_AMOUNT,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
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
        _board.createOrder{value: 1 ether}(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenB),
                amountA: AMOUNT_B,
                tokenB: address(_tokenA),
                amountB: 1 ether,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();
    }

    /// @notice Tests createOrder wanting ETH reverts if ETH is sent on create
    function test_createOrder_wantEth_revert_accidentalEth() public {
        vm.startPrank(_maker);
        _tokenB.approve(address(_board), AMOUNT_B);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, 0, 1 ether));
        _board.createOrder{value: 1 ether}(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenB),
                amountA: AMOUNT_B,
                tokenB: _eth,
                amountB: ETH_AMOUNT,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();
    }

    /// @notice Tests maker can self-fill an ETH sell order
    function test_selfFill_sellEth() public {
        uint256 makerEthBefore = _maker.balance;
        uint256 makerTokenBefore = _tokenB.balanceOf(_maker);

        vm.startPrank(_maker);
        _tokenB.approve(address(_board), AMOUNT_B);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth,
                amountA: ETH_AMOUNT,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
        _board.fillOrder(orderId, ETH_AMOUNT, 0);
        vm.stopPrank();

        assertFalse(_board.canFill(orderId));
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
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenB),
                amountA: AMOUNT_B,
                tokenB: _eth,
                amountB: ETH_AMOUNT,
                partialFillAllowed: false
            })
        );
        _board.fillOrder{value: ETH_AMOUNT}(orderId, AMOUNT_B, 0);
        vm.stopPrank();

        assertFalse(_board.canFill(orderId));
        assertEq(_tokenB.balanceOf(_maker), makerTokenBefore);
        assertEq(_maker.balance, makerEthBefore);
    }

    /// @notice Tests ETH sell order views: getOrder, canFill, getOrders
    function test_views_sellEthOrder() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth,
                amountA: ETH_AMOUNT,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );

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
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenB),
                amountA: AMOUNT_B,
                tokenB: _eth,
                amountB: ETH_AMOUNT,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();

        uint256 makerEthBefore = _maker.balance;
        uint256 takerTokenBefore = _tokenB.balanceOf(_taker);

        vm.prank(_taker);
        _board.fillOrder{value: ETH_AMOUNT}(orderId, AMOUNT_B, 0);

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
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenB),
                amountA: AMOUNT_B,
                tokenB: _eth,
                amountB: ETH_AMOUNT,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();

        vm.prank(_taker);
        vm.expectRevert(
            abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, ETH_AMOUNT, ETH_AMOUNT + 0.25 ether)
        );
        _board.fillOrder{value: ETH_AMOUNT + 0.25 ether}(orderId, AMOUNT_B, 0);
    }

    /// @notice Tests fillOrder paying ETH emits OrderFilled
    function test_fillOrder_payEth_event() public {
        vm.startPrank(_maker);
        _tokenB.approve(address(_board), AMOUNT_B);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenB),
                amountA: AMOUNT_B,
                tokenB: _eth,
                amountB: ETH_AMOUNT,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();

        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderFilled({orderId: orderId, taker: _taker, amountA: AMOUNT_B, amountB: ETH_AMOUNT});

        vm.prank(_taker);
        _board.fillOrder{value: ETH_AMOUNT}(orderId, AMOUNT_B, 0);
    }

    /// @notice Tests fillOrder paying ETH reverts on underpayment
    function test_fillOrder_payEth_revert_amountMismatch_tooLow() public {
        vm.startPrank(_maker);
        _tokenB.approve(address(_board), AMOUNT_B);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenB),
                amountA: AMOUNT_B,
                tokenB: _eth,
                amountB: ETH_AMOUNT,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();

        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, ETH_AMOUNT, ETH_AMOUNT - 1));
        _board.fillOrder{value: ETH_AMOUNT - 1}(orderId, AMOUNT_B, 0);
    }

    /// @notice Tests fillOrder paying ETH reverts when order not found
    function test_fillOrder_payEth_revert_orderNotFound() public {
        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, 999));
        _board.fillOrder{value: ETH_AMOUNT}(999, ETH_AMOUNT, 0);
    }

    /// @notice Tests fillOrder paying ETH reverts when order not active
    function test_fillOrder_payEth_revert_orderNotActive() public {
        vm.startPrank(_maker);
        _tokenB.approve(address(_board), AMOUNT_B);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenB),
                amountA: AMOUNT_B,
                tokenB: _eth,
                amountB: ETH_AMOUNT,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();

        vm.prank(_taker);
        _board.fillOrder{value: ETH_AMOUNT}(orderId, AMOUNT_B, 0);

        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        _board.fillOrder{value: ETH_AMOUNT}(orderId, AMOUNT_B, 0);
    }

    /// @notice Tests fillOrder paying ETH reverts after deadline
    function test_fillOrder_payEth_revert_deadlineExpired() public {
        vm.startPrank(_maker);
        _tokenB.approve(address(_board), AMOUNT_B);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenB),
                amountA: AMOUNT_B,
                tokenB: _eth,
                amountB: ETH_AMOUNT,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();

        vm.warp(1000);

        vm.prank(_taker);
        vm.expectRevert(ISwapboard.DeadlineExpired.selector);
        _board.fillOrder{value: ETH_AMOUNT}(orderId, AMOUNT_B, 999);
    }

    /// @notice Tests fillOrder paying ETH succeeds when timestamp equals deadline
    function test_fillOrder_payEth_deadlineEqual_succeeds() public {
        vm.startPrank(_maker);
        _tokenB.approve(address(_board), AMOUNT_B);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenB),
                amountA: AMOUNT_B,
                tokenB: _eth,
                amountB: ETH_AMOUNT,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();

        uint256 deadline = 1000;
        vm.warp(deadline);

        vm.prank(_taker);
        _board.fillOrder{value: ETH_AMOUNT}(orderId, AMOUNT_B, deadline);

        assertFalse(_board.canFill(orderId));
    }

    /// @notice Tests fillOrder with ERC20 tokenB reverts if ETH is sent
    function test_fillOrder_erc20_revert_accidentalEth() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, 0, 0.1 ether));
        _board.fillOrder{value: 0.1 ether}(orderId, AMOUNT_A, 0);
        vm.stopPrank();
    }

    // ============ cancelOrder returning ETH ============

    /// @notice Tests cancelOrder returns ETH to maker
    function test_cancelOrder_returnEth() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth,
                amountA: ETH_AMOUNT,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );

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
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth,
                amountA: ETH_AMOUNT,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );

        vm.expectEmit(true, false, false, true);
        emit ISwapboard.OrderCanceled({orderId: orderId});

        vm.prank(_maker);
        _board.cancelOrder(orderId);
    }

    /// @notice Tests cancelOrder returning ETH reverts when not maker
    function test_cancelOrder_returnEth_revert_notMaker() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth,
                amountA: ETH_AMOUNT,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );

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
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth,
                amountA: ETH_AMOUNT,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );

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
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth,
                amountA: ETH_AMOUNT,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );

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
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenB),
                amountA: AMOUNT_B,
                tokenB: _eth,
                amountB: ETH_AMOUNT,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();

        uint256 boardTokenBefore = _tokenB.balanceOf(address(_board));
        uint256 takerEthBefore = _taker.balance;

        vm.prank(_taker);
        vm.expectRevert(ETHRejecter.RejectETH.selector);
        _board.fillOrder{value: ETH_AMOUNT}(orderId, AMOUNT_B, 0);

        assertTrue(_board.canFill(orderId));
        assertEq(_tokenB.balanceOf(address(_board)), boardTokenBefore);
        assertEq(_taker.balance, takerEthBefore);
    }

    // ============ fillOrder receiving ETH ============

    /// @notice Tests fillOrder when tokenA is ETH
    function test_fillOrder_receiveEth() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth,
                amountA: ETH_AMOUNT,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );

        uint256 takerEthBefore = _taker.balance;
        uint256 makerTokenBefore = _tokenB.balanceOf(_maker);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _board.fillOrder(orderId, ETH_AMOUNT, 0);
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
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth,
                amountA: ETH_AMOUNT,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);

        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderFilled({orderId: orderId, taker: _taker, amountA: ETH_AMOUNT, amountB: AMOUNT_B});
        _board.fillOrder(orderId, ETH_AMOUNT, 0);
        vm.stopPrank();
    }

    /// @notice Tests fillOrder receiving ETH reverts when order not found
    function test_fillOrder_receiveEth_revert_orderNotFound() public {
        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, 999));
        _board.fillOrder(999, 1, 0);
    }

    /// @notice Tests fillOrder receiving ETH reverts when order not active
    function test_fillOrder_receiveEth_revert_orderNotActive() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth,
                amountA: ETH_AMOUNT,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _board.fillOrder(orderId, ETH_AMOUNT, 0);
        vm.stopPrank();

        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        _board.fillOrder(orderId, ETH_AMOUNT, 0);
    }

    /// @notice Tests fillOrder receiving ETH reverts when taker rejects ETH and leaves escrow intact
    function test_fillOrder_receiveEth_revert_ethTransferFailed() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth,
                amountA: ETH_AMOUNT,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );

        ETHRejecter rejecter = new ETHRejecter();
        _tokenB.mint(address(rejecter), AMOUNT_B);

        uint256 boardEthBefore = address(_board).balance;
        uint256 makerTokenBefore = _tokenB.balanceOf(_maker);

        vm.startPrank(address(rejecter));
        _tokenB.approve(address(_board), AMOUNT_B);
        vm.expectRevert(ETHRejecter.RejectETH.selector);
        _board.fillOrder(orderId, ETH_AMOUNT, 0);
        vm.stopPrank();

        assertTrue(_board.canFill(orderId));
        assertEq(address(_board).balance, boardEthBefore);
        assertEq(_tokenB.balanceOf(_maker), makerTokenBefore);
    }

    /// @notice Tests fillOrder receiving ETH reverts after deadline
    function test_fillOrder_receiveEth_revert_deadlineExpired() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth,
                amountA: ETH_AMOUNT,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );

        vm.warp(1000);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        vm.expectRevert(ISwapboard.DeadlineExpired.selector);
        _board.fillOrder(orderId, ETH_AMOUNT, 999);
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
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth,
                amountA: ETH_AMOUNT,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );

        uint256 takerEthBefore = _taker.balance;

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _board.fillOrder(orderId, ETH_AMOUNT, 0);
        vm.stopPrank();

        assertEq(_taker.balance, takerEthBefore + ETH_AMOUNT);
        assertEq(address(_board).balance, 0);
    }

    /// @notice Tests ETH sell then cancel returns ETH
    function test_roundTrip_sellEth_cancel() public {
        uint256 makerEthBefore = _maker.balance;

        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth,
                amountA: ETH_AMOUNT,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );

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
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenB),
                amountA: AMOUNT_B,
                tokenB: _eth,
                amountB: ETH_AMOUNT,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();

        uint256 makerEthBefore = _maker.balance;
        uint256 takerTokenBefore = _tokenB.balanceOf(_taker);

        vm.prank(_taker);
        _board.fillOrder{value: ETH_AMOUNT}(orderId, AMOUNT_B, 0);

        assertEq(_maker.balance, makerEthBefore + ETH_AMOUNT);
        assertEq(_tokenB.balanceOf(_taker), takerTokenBefore + AMOUNT_B);
    }

    /// @notice Tests multiple ETH sell orders can coexist
    function test_multipleEthOrders() public {
        vm.startPrank(_maker);
        uint256 id0 = _board.createOrder{value: 1 ether}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth, amountA: 1 ether, tokenB: address(_tokenB), amountB: AMOUNT_B, partialFillAllowed: false
            })
        );
        uint256 id1 = _board.createOrder{value: 2 ether}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth, amountA: 2 ether, tokenB: address(_tokenB), amountB: AMOUNT_B, partialFillAllowed: false
            })
        );
        uint256 id2 = _board.createOrder{value: 3 ether}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth, amountA: 3 ether, tokenB: address(_tokenB), amountB: AMOUNT_B, partialFillAllowed: false
            })
        );
        vm.stopPrank();

        assertEq(address(_board).balance, 6 ether);

        vm.prank(_maker);
        _board.cancelOrder(id1);

        assertEq(address(_board).balance, 4 ether);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _board.fillOrder(id0, 1 ether, 0);
        vm.stopPrank();

        assertEq(address(_board).balance, 3 ether);
        assertTrue(_board.canFill(id2));
        assertFalse(_board.canFill(id0));
        assertFalse(_board.canFill(id1));
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
        uint256 orderId = _board.createOrder{value: ethAmount}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth, amountA: ethAmount, tokenB: address(_tokenB), amountB: amountB, partialFillAllowed: false
            })
        );

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
        _board.createOrder{value: ethAmount + excess}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth,
                amountA: ethAmount,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
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
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenB),
                amountA: tokenAmount,
                tokenB: _eth,
                amountB: ethAmount,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();

        vm.prank(_taker);
        _board.fillOrder{value: ethAmount}(orderId, tokenAmount, 0);

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
        uint256 orderId = _board.createOrder{value: ethAmount}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth,
                amountA: ethAmount,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );

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
        uint256 orderId = _board.createOrder{value: ethAmount}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth,
                amountA: ethAmount,
                tokenB: address(_tokenB),
                amountB: tokenAmount,
                partialFillAllowed: false
            })
        );

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), tokenAmount);
        _board.fillOrder(orderId, ethAmount, 0);
        vm.stopPrank();

        assertEq(_taker.balance, takerEthBefore + ethAmount);
        assertEq(_tokenB.balanceOf(_maker), makerTokenBefore + tokenAmount);
    }

    // ============ Partial fills ============

    /// @notice Tests fillOrder reverts when partial fills are disabled and amountA is not the full remaining
    function test_fillOrder_revert_partialFillNotAllowed() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.PartialFillNotAllowed.selector, orderId));
        _board.fillOrder(orderId, AMOUNT_A / 2, 0);
        vm.stopPrank();

        assertTrue(_board.canFill(orderId));
        assertEq(_board.getOrder(orderId).amountA, AMOUNT_A);
    }

    /// @notice Tests fillOrder reverts when requested amountA exceeds remaining
    function test_fillOrder_revert_fillAmountTooHigh() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: true
            })
        );
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.FillAmountTooHigh.selector, orderId, AMOUNT_A + 1, AMOUNT_A));
        _board.fillOrder(orderId, AMOUNT_A + 1, 0);
        vm.stopPrank();
    }

    /// @notice Tests fillOrder reverts on zero amountA
    function test_fillOrder_revert_zeroAmountA() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: true
            })
        );
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.fillOrder(orderId, 0, 0);
        vm.stopPrank();
    }

    /// @notice Tests fillOrder reverts ZeroAmount when quoted tokenB payment rounds to 0
    /// @dev Unreachable via normal fills (availableB=0 implies inactive). Force availableB=0 while
    ///      keeping the order active so the ceil branch returns amountBIn=0.
    function test_fillOrder_revert_zeroAmountBIn() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: true
            })
        );
        vm.stopPrank();

        // Order.availableB is struct field depth 8 (maker=0 … availableA=7, availableB=8).
        _stdstore.enable_packed_slots().target(address(_board)).sig(_board.getOrder.selector).with_key(orderId)
            .depth(8).checked_write(uint256(0));

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertEq(order.availableB, 0);
        assertTrue(order.active);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        // Partial fill: ceil((1 * 0 + availableA - 1) / availableA) == 0 → ZeroAmount
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.fillOrder(orderId, 1, 0);
        vm.stopPrank();
    }

    /// @notice Tests ceil payment can exhaust amountB while leaving tokenA dust
    function test_fillOrder_partial_ceilExhaustsAmountBWithDust() public {
        uint128 amountA = 100;
        uint128 amountB = 1;

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), amountA);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: amountA,
                tokenB: address(_tokenB),
                amountB: amountB,
                partialFillAllowed: true
            })
        );
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), amountB);
        _board.fillOrder(orderId, 1, 0);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(order.amountA, 100);
        assertEq(order.amountB, 1);
        assertEq(order.availableB, 0);
        // Dust remaining tokenA after amountB exhausted is expected (not worth gas to refund).
        assertEq(order.availableA, 99);
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
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: amountA,
                tokenB: address(_tokenB),
                amountB: amountB,
                partialFillAllowed: true
            })
        );
        vm.stopPrank();

        uint256 takerABefore = _tokenA.balanceOf(_taker);
        uint256 makerBBefore = _tokenB.balanceOf(_maker);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), expectedBIn);
        _board.fillOrder(orderId, fillA, 0);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertTrue(order.active);
        assertEq(order.amountA, amountA);
        assertEq(order.amountB, amountB);
        assertEq(order.availableA, amountA - fillA);
        assertEq(order.availableB, amountB - expectedBIn);
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
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: amountA,
                tokenB: address(_tokenB),
                amountB: amountB,
                partialFillAllowed: true
            })
        );
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), amountB);
        _board.fillOrder(orderId, 25 ether, 0);
        _board.fillOrder(orderId, 25 ether, 0);
        _board.fillOrder(orderId, 25 ether, 0);
        _board.fillOrder(orderId, 25 ether, 0);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(order.amountA, amountA);
        assertEq(order.amountB, amountB);
        assertEq(order.availableA, 0);
        assertEq(order.availableB, 0);
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
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: amountA,
                tokenB: address(_tokenB),
                amountB: amountB,
                partialFillAllowed: true
            })
        );
        vm.stopPrank();

        uint256 takerABefore = _tokenA.balanceOf(_taker);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), expectedBIn);
        _board.fillOrder(orderId, fillA, 0);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertTrue(order.active);
        assertEq(order.amountA, amountA);
        assertEq(order.amountB, amountB);
        assertEq(order.availableA, amountA - fillA);
        assertEq(order.availableB, amountB - expectedBIn);
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
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: amountA,
                tokenB: address(_tokenB),
                amountB: amountB,
                partialFillAllowed: true
            })
        );
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), expectedBIn);
        _board.fillOrder(orderId, fillA, 0);
        vm.stopPrank();

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
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: amountA,
                tokenB: address(_tokenB),
                amountB: amountB,
                partialFillAllowed: true
            })
        );
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), expectedBIn);
        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderFilled({orderId: orderId, taker: _taker, amountA: fillA, amountB: expectedBIn});
        _board.fillOrder(orderId, fillA, 0);
        vm.stopPrank();
    }

    /// @notice Tests ETH sell order can be partially filled by requesting amountA ETH
    function test_fillOrder_partial_receiveEth() public {
        uint128 ethAmount = 4 ether;
        uint128 tokenAmount = 400e6;
        uint128 fillA = 1 ether;
        uint256 expectedBIn = (uint256(fillA) * uint256(tokenAmount) + uint256(ethAmount) - 1) / uint256(ethAmount);

        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ethAmount}(
            ISwapboard.CreateOrderParams({
                tokenA: _eth,
                amountA: ethAmount,
                tokenB: address(_tokenB),
                amountB: tokenAmount,
                partialFillAllowed: true
            })
        );

        uint256 takerEthBefore = _taker.balance;

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), expectedBIn);
        _board.fillOrder(orderId, fillA, 0);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertTrue(order.active);
        assertEq(order.amountA, ethAmount);
        assertEq(order.amountB, tokenAmount);
        assertEq(order.availableA, ethAmount - fillA);
        assertEq(order.availableB, tokenAmount - expectedBIn);
        assertEq(_taker.balance, takerEthBefore + fillA);
        assertEq(address(_board).balance, ethAmount - fillA);
    }

    /// @notice Tests want-ETH order can be partially filled with exact ceiled msg.value
    function test_fillOrder_partial_payEth() public {
        uint128 tokenAmount = 400e6;
        uint128 ethAmount = 4 ether;
        uint128 fillA = 100e6;
        uint256 expectedEthIn = (uint256(fillA) * uint256(ethAmount) + uint256(tokenAmount) - 1) / uint256(tokenAmount);

        vm.startPrank(_maker);
        _tokenB.approve(address(_board), tokenAmount);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenB),
                amountA: tokenAmount,
                tokenB: _eth,
                amountB: ethAmount,
                partialFillAllowed: true
            })
        );
        vm.stopPrank();

        uint256 makerEthBefore = _maker.balance;
        uint256 takerTokenBefore = _tokenB.balanceOf(_taker);

        vm.prank(_taker);
        _board.fillOrder{value: expectedEthIn}(orderId, fillA, 0);

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
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenB),
                amountA: AMOUNT_B,
                tokenB: _eth,
                amountB: ETH_AMOUNT,
                partialFillAllowed: true
            })
        );
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertTrue(order.partialFillAllowed);
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
        uint256 expectedEthIn = (uint256(fillA) * uint256(ethAmount) + uint256(tokenAmount) - 1) / uint256(tokenAmount);

        vm.startPrank(_maker);
        _tokenB.approve(address(_board), tokenAmount);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenB),
                amountA: tokenAmount,
                tokenB: _eth,
                amountB: ethAmount,
                partialFillAllowed: true
            })
        );
        vm.stopPrank();

        vm.prank(_taker);
        vm.expectRevert(
            abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, expectedEthIn, expectedEthIn - 1)
        );
        _board.fillOrder{value: expectedEthIn - 1}(orderId, fillA, 0);
    }

    /// @notice Tests FillAmountTooHigh uses remaining availableA after a prior partial fill
    function test_fillOrder_partial_then_revert_fillAmountTooHigh() public {
        uint128 amountA = 100 ether;
        uint128 amountB = 4e6;
        uint128 fillA = 25 ether;

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), amountA);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: amountA,
                tokenB: address(_tokenB),
                amountB: amountB,
                partialFillAllowed: true
            })
        );
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), amountB);
        _board.fillOrder(orderId, fillA, 0);

        uint128 remainingA = _board.getOrder(orderId).availableA;
        assertEq(remainingA, amountA - fillA);

        vm.expectRevert(
            abi.encodeWithSelector(ISwapboard.FillAmountTooHigh.selector, orderId, remainingA + 1, remainingA)
        );
        _board.fillOrder(orderId, remainingA + 1, 0);
        vm.stopPrank();
    }

    /// @notice Tests a partial fill then an exact remaining fill completes the order
    function test_fillOrder_partial_thenExactRemainingCompletes() public {
        uint128 amountA = 100 ether;
        uint128 amountB = 4e6;
        uint128 fillA1 = 40 ether;

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), amountA);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: amountA,
                tokenB: address(_tokenB),
                amountB: amountB,
                partialFillAllowed: true
            })
        );
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), amountB);
        _board.fillOrder(orderId, fillA1, 0);

        uint128 remainingA = _board.getOrder(orderId).availableA;
        _board.fillOrder(orderId, remainingA, 0);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(order.amountA, amountA);
        assertEq(order.amountB, amountB);
        assertEq(order.availableA, 0);
        assertEq(order.availableB, 0);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
    }

    /// @notice Tests partial fill reverts when deadline has expired
    function test_fillOrder_partial_revert_deadlineExpired() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: true
            })
        );
        vm.stopPrank();

        vm.warp(1000);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        vm.expectRevert(ISwapboard.DeadlineExpired.selector);
        _board.fillOrder(orderId, AMOUNT_A / 2, 999);
        vm.stopPrank();

        assertTrue(_board.canFill(orderId));
        assertEq(_board.getOrder(orderId).availableA, AMOUNT_A);
    }

    /// @notice Tests FOT tokenB on a partial fill: maker receives less, available still decrements fully
    function test_fillOrder_partial_fotTokenB_makerReceivesLess() public {
        MockFOT fotB = new MockFOT();
        uint128 amountA = 100 ether;
        uint128 amountB = 100 ether;
        uint128 fillA = 40 ether;
        uint256 expectedBIn = (uint256(fillA) * uint256(amountB) + uint256(amountA) - 1) / uint256(amountA);

        fotB.mint(_taker, 1000 ether);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), amountA);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: amountA,
                tokenB: address(fotB),
                amountB: amountB,
                partialFillAllowed: true
            })
        );
        vm.stopPrank();

        uint256 makerFotBefore = fotB.balanceOf(_maker);
        uint256 takerABefore = _tokenA.balanceOf(_taker);

        vm.startPrank(_taker);
        fotB.approve(address(_board), expectedBIn);
        _board.fillOrder(orderId, fillA, 0);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertTrue(order.active);
        assertEq(order.availableA, amountA - fillA);
        assertEq(order.availableB, amountB - expectedBIn);
        // 5% FOT fee on the transferred amountBIn
        assertEq(fotB.balanceOf(_maker) - makerFotBefore, (expectedBIn * 95) / 100);
        assertEq(_tokenA.balanceOf(_taker) - takerABefore, fillA);
    }

    /// @notice Tests getOrders reflects original vs available after a partial fill
    function test_getOrders_afterPartialFill() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        uint256 order0 = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: true
            })
        );
        uint256 order1 = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B * 2,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();

        uint128 fillA = AMOUNT_A / 4;
        uint256 expectedBIn = (uint256(fillA) * uint256(AMOUNT_B) + uint256(AMOUNT_A) - 1) / uint256(AMOUNT_A);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), expectedBIn);
        _board.fillOrder(order0, fillA, 0);
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
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: true
            })
        );
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
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: amountA,
                tokenB: address(_tokenB),
                amountB: amountB,
                partialFillAllowed: true
            })
        );
        vm.stopPrank();

        uint256 takerABefore = _tokenA.balanceOf(_taker);
        uint256 makerBBefore = _tokenB.balanceOf(_maker);

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), amountBIn);
        _board.fillOrder(orderId, fillA, 0);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertEq(order.amountA, amountA);
        assertEq(order.amountB, amountB);
        assertEq(order.availableA, amountA - fillA);
        assertEq(order.availableB, amountB - amountBIn);
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
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: amountA,
                tokenB: address(_tokenB),
                amountB: amountB,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), amountB);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.PartialFillNotAllowed.selector, orderId));
        _board.fillOrder(orderId, fillA, 0);
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
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: amountA,
                tokenB: address(_tokenB),
                amountB: amountB,
                partialFillAllowed: true
            })
        );
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), amountB);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.FillAmountTooHigh.selector, orderId, requested, amountA));
        _board.fillOrder(orderId, requested, 0);
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
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: amountA,
                tokenB: address(_tokenB),
                amountB: amountB,
                partialFillAllowed: true
            })
        );
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), amountB);
        _board.fillOrder(orderId, fillA1, 0);
        _board.fillOrder(orderId, fillA2, 0);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(order.amountA, amountA);
        assertEq(order.amountB, amountB);
        assertEq(order.availableA, 0);
        assertEq(order.availableB, 0);
        assertEq(fillA1 + fillA2, amountA);
        assertEq(bIn1 + bIn2, amountB);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
    }

    /// @notice Tests createOrder(CreateOrderParams) deposits tokenA
    function test_createOrder_struct() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: true
            })
        );
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
        assertEq(_tokenA.getTransferFromCalls(), 1);
    }

    /// @notice Tests createOrders assigns sequential ids and stores each order
    function test_createOrders() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = ISwapboard.CreateOrderParams({
            tokenA: address(_tokenA),
            amountA: AMOUNT_A,
            tokenB: address(_tokenB),
            amountB: AMOUNT_B,
            partialFillAllowed: false
        });
        orders[1] = ISwapboard.CreateOrderParams({
            tokenA: address(_tokenB),
            amountA: AMOUNT_B,
            tokenB: address(_tokenA),
            amountB: AMOUNT_A,
            partialFillAllowed: true
        });

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
        assertEq(_tokenA.getTransferFromCalls(), 1);
        assertEq(_tokenB.getTransferFromCalls(), 1);
        assertEq(_tokenA.balanceOf(address(_board)), AMOUNT_A);
        assertEq(_tokenB.balanceOf(address(_board)), AMOUNT_B);
    }

    /// @notice Tests repeated tokenA is pulled once for the aggregated amount
    function test_createOrders_aggregatesSameToken() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](3);
        orders[0] = ISwapboard.CreateOrderParams({
            tokenA: address(_tokenA),
            amountA: 10 ether,
            tokenB: address(_tokenB),
            amountB: AMOUNT_B,
            partialFillAllowed: false
        });
        orders[1] = ISwapboard.CreateOrderParams({
            tokenA: address(_tokenA),
            amountA: 25 ether,
            tokenB: address(_tokenB),
            amountB: AMOUNT_B,
            partialFillAllowed: true
        });
        orders[2] = ISwapboard.CreateOrderParams({
            tokenA: address(_tokenA),
            amountA: 5 ether,
            tokenB: address(_tokenB),
            amountB: AMOUNT_B,
            partialFillAllowed: false
        });

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), 40 ether);
        uint256[] memory ids = _board.createOrders(orders);
        vm.stopPrank();

        assertEq(ids.length, 3);
        assertEq(_tokenA.getTransferFromCalls(), 1);
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
        for (uint256 i; i < 9; ++i) {
            address tokenB = tokens[i] == address(_tokenA) ? address(_tokenB) : address(_tokenA);
            orders[i] = ISwapboard.CreateOrderParams({
                tokenA: tokens[i], amountA: amounts[i], tokenB: tokenB, amountB: 1e6, partialFillAllowed: false
            });
        }

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), 14 ether);
        _tokenB.approve(address(_board), 14e6);
        uint256[] memory ids = _board.createOrders{value: 0.3 ether}(orders);
        vm.stopPrank();

        assertEq(ids.length, 9);
        assertEq(_tokenA.getTransferFromCalls(), 1);
        assertEq(_tokenB.getTransferFromCalls(), 1);
        assertEq(_tokenA.balanceOf(address(_board)), 14 ether);
        assertEq(_tokenB.balanceOf(address(_board)), 14e6);
        assertEq(address(_board).balance, 0.3 ether);
        for (uint256 i; i < 9; ++i) {
            assertEq(_board.getOrder(ids[i]).tokenA, tokens[i]);
            assertEq(_board.getOrder(ids[i]).availableA, amounts[i]);
        }
    }

    /// @notice Tests ETH deposits are summed and ERC20 still aggregates
    function test_createOrders_mixedEthAndToken() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](3);
        orders[0] = ISwapboard.CreateOrderParams({
            tokenA: address(_tokenA),
            amountA: AMOUNT_A,
            tokenB: address(_tokenB),
            amountB: AMOUNT_B,
            partialFillAllowed: false
        });
        orders[1] = ISwapboard.CreateOrderParams({
            tokenA: _eth, amountA: 1 ether, tokenB: address(_tokenB), amountB: AMOUNT_B, partialFillAllowed: false
        });
        orders[2] = ISwapboard.CreateOrderParams({
            tokenA: address(_tokenA), amountA: AMOUNT_A, tokenB: _eth, amountB: ETH_AMOUNT, partialFillAllowed: true
        });

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        uint256[] memory ids = _board.createOrders{value: 1 ether}(orders);
        vm.stopPrank();

        assertEq(ids.length, 3);
        assertEq(_tokenA.getTransferFromCalls(), 1);
        assertEq(_tokenA.balanceOf(address(_board)), AMOUNT_A * 2);
        assertEq(address(_board).balance, 1 ether);
        assertEq(_board.getOrder(ids[1]).tokenA, _eth);
        assertEq(_board.getOrder(ids[2]).tokenB, _eth);
    }

    /// @notice Tests an all-ETH batch pulls no ERC20 and checks total msg.value
    function test_createOrders_allEth() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = ISwapboard.CreateOrderParams({
            tokenA: _eth, amountA: 1 ether, tokenB: address(_tokenB), amountB: AMOUNT_B, partialFillAllowed: false
        });
        orders[1] = ISwapboard.CreateOrderParams({
            tokenA: _eth, amountA: 2 ether, tokenB: address(_tokenA), amountB: AMOUNT_A, partialFillAllowed: true
        });

        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders{value: 3 ether}(orders);

        assertEq(ids.length, 2);
        assertEq(_tokenA.getTransferFromCalls(), 0);
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
        orders[0] = ISwapboard.CreateOrderParams({
            tokenA: _eth, amountA: 1 ether, tokenB: address(_tokenB), amountB: AMOUNT_B, partialFillAllowed: false
        });
        orders[1] = ISwapboard.CreateOrderParams({
            tokenA: _eth, amountA: 1 ether, tokenB: address(_tokenA), amountB: AMOUNT_A, partialFillAllowed: false
        });

        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, 2 ether, 1 ether));

        _board.createOrders{value: 1 ether}(orders);
    }

    /// @notice Tests accidental ETH on an ERC20-only batch reverts
    function test_createOrders_revert_accidentalEth() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = ISwapboard.CreateOrderParams({
            tokenA: address(_tokenA),
            amountA: AMOUNT_A,
            tokenB: address(_tokenB),
            amountB: AMOUNT_B,
            partialFillAllowed: false
        });
        orders[1] = ISwapboard.CreateOrderParams({
            tokenA: address(_tokenA),
            amountA: AMOUNT_A,
            tokenB: address(_tokenB),
            amountB: AMOUNT_B,
            partialFillAllowed: false
        });

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, 0, 1 ether));
        _board.createOrders{value: 1 ether}(orders);
        vm.stopPrank();

        assertEq(_tokenA.getTransferFromCalls(), 0);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
    }

    /// @notice Tests aggregated ETH above msg.value reverts
    function test_createOrders_revert_ethMismatch_tooHigh() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](1);
        orders[0] = ISwapboard.CreateOrderParams({
            tokenA: _eth, amountA: 1 ether, tokenB: address(_tokenB), amountB: AMOUNT_B, partialFillAllowed: false
        });

        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, 1 ether, 2 ether));
        _board.createOrders{value: 2 ether}(orders);
    }

    /// @notice Tests createOrders reverts on a zero amount in the batch
    function test_createOrders_revert_zeroAmount() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = ISwapboard.CreateOrderParams({
            tokenA: address(_tokenA),
            amountA: AMOUNT_A,
            tokenB: address(_tokenB),
            amountB: AMOUNT_B,
            partialFillAllowed: false
        });
        orders[1] = ISwapboard.CreateOrderParams({
            tokenA: address(_tokenA),
            amountA: 0,
            tokenB: address(_tokenB),
            amountB: AMOUNT_B,
            partialFillAllowed: false
        });

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.createOrders(orders);
        vm.stopPrank();

        assertEq(_tokenA.getTransferFromCalls(), 0);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
    }

    /// @notice Tests createOrders validates each order before pulling
    function test_createOrders_revert_sameToken() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = ISwapboard.CreateOrderParams({
            tokenA: address(_tokenA),
            amountA: AMOUNT_A,
            tokenB: address(_tokenB),
            amountB: AMOUNT_B,
            partialFillAllowed: false
        });
        orders[1] = ISwapboard.CreateOrderParams({
            tokenA: address(_tokenA),
            amountA: AMOUNT_A,
            tokenB: address(_tokenA),
            amountB: AMOUNT_B,
            partialFillAllowed: false
        });

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        vm.expectRevert(ISwapboard.SameToken.selector);
        _board.createOrders(orders);
        vm.stopPrank();

        assertEq(_tokenA.getTransferFromCalls(), 0);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
    }

    /// @notice Tests aggregated FOT pull rejects the combined amount
    function test_createOrders_revert_fotAggregated() public {
        MockFOT fot = new MockFOT();
        fot.mint(_maker, 100 ether);

        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = ISwapboard.CreateOrderParams({
            tokenA: address(fot),
            amountA: 40 ether,
            tokenB: address(_tokenB),
            amountB: AMOUNT_B,
            partialFillAllowed: false
        });
        orders[1] = ISwapboard.CreateOrderParams({
            tokenA: address(fot),
            amountA: 60 ether,
            tokenB: address(_tokenB),
            amountB: AMOUNT_B,
            partialFillAllowed: false
        });

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
        orders[0] = ISwapboard.CreateOrderParams({
            tokenA: address(_tokenA),
            amountA: AMOUNT_A,
            tokenB: address(_tokenB),
            amountB: AMOUNT_B,
            partialFillAllowed: false
        });
        orders[1] = ISwapboard.CreateOrderParams({
            tokenA: address(_tokenA),
            amountA: AMOUNT_A,
            tokenB: address(_tokenB),
            amountB: AMOUNT_B,
            partialFillAllowed: true
        });

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
    }

    /// @notice Tests a struct-created order can be filled
    function test_createOrder_struct_thenFill() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: AMOUNT_A,
                tokenB: address(_tokenB),
                amountB: AMOUNT_B,
                partialFillAllowed: false
            })
        );
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _board.fillOrder(orderId, AMOUNT_A, 0);
        vm.stopPrank();

        assertFalse(_board.getOrder(orderId).active);
        assertEq(_tokenA.balanceOf(_taker), AMOUNT_A * 10 + AMOUNT_A);
        assertEq(_tokenB.balanceOf(_maker), AMOUNT_B * 10 + AMOUNT_B);
    }

    function _order(
        address tokenA,
        uint128 amountA,
        address tokenB,
        uint128 amountB
    ) private pure returns (ISwapboard.CreateOrderParams memory) {
        return ISwapboard.CreateOrderParams({
            tokenA: tokenA, amountA: amountA, tokenB: tokenB, amountB: amountB, partialFillAllowed: false
        });
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

        assertEq(_tokenA.getTransferFromCalls(), 0);
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

        assertEq(_tokenA.getTransferFromCalls(), 0);
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

        assertEq(_tokenA.getTransferFromCalls(), 0);
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

        assertEq(_tokenA.getTransferFromCalls(), 0);
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
        assertEq(_tokenA.getTransferFromCalls(), 2);
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

        assertEq(_tokenA.getTransferFromCalls(), 1);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
        assertEq(address(_board).balance, 0);
        assertEq(_tokenA.balanceOf(_maker), makerABefore);
        assertEq(_maker.balance, makerEthBefore);
        assertFalse(_board.canFill(ids[0]));
        assertFalse(_board.canFill(ids[1]));
    }

    /// @notice Tests aggregated pull reverts when allowance is below the summed amount
    function test_createOrders_revert_insufficientAllowance() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);

        uint256 makerABefore = _tokenA.balanceOf(_maker);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A);
        vm.expectRevert();
        _board.createOrders(orders);
        vm.stopPrank();

        assertEq(_tokenA.getTransferFromCalls(), 0);
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
        assertEq(_tokenA.getTransferFromCalls(), 1);
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

        assertEq(_tokenA.getTransferFromCalls(), 1);
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

        assertEq(_tokenA.getTransferFromCalls(), 0);
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

        assertEq(_tokenA.getTransferFromCalls(), 0);
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
        vm.expectRevert();
        _board.createOrders(orders);
        vm.stopPrank();

        assertEq(_tokenA.getTransferFromCalls(), 0);
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

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B * 2);
        _board.fillOrder(ids[0], AMOUNT_A, 0);
        _board.fillOrder(ids[1], AMOUNT_A, 0);
        vm.stopPrank();

        assertFalse(_board.canFill(ids[0]));
        assertFalse(_board.canFill(ids[1]));
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
        assertEq(_tokenA.getTransferFromCalls(), 0);
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
        for (uint256 i; i < 3; ++i) {
            assertFalse(_board.canFill(ids[i]));
        }
    }

    /// @notice Tests empty cancelOrders reverts
    function test_cancelOrders_revert_empty() public {
        uint256[] memory orderIds = new uint256[](0);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.cancelOrders(orderIds);
    }

    /// @notice Tests cancelOrders reverts NotMaker on a later item without refunding
    function test_cancelOrders_revert_notMaker_laterItem() public {
        vm.startPrank(_maker);
        _tokenA.approve(address(_board), AMOUNT_A * 2);
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        orders[1] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);
        uint256[] memory ids = _board.createOrders(orders);
        vm.stopPrank();

        uint256[] memory cancelIds = new uint256[](2);
        cancelIds[0] = ids[0];
        cancelIds[1] = ids[1];

        vm.startPrank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotMaker.selector, ids[0], _taker, _maker));
        _board.cancelOrders(cancelIds);
        vm.stopPrank();

        assertTrue(_board.canFill(ids[0]));
        assertTrue(_board.canFill(ids[1]));
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
        _board.fillOrder(ids[0], AMOUNT_A, 0);
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
        orders[0] = ISwapboard.CreateOrderParams({
            tokenA: address(_tokenA),
            amountA: amountA,
            tokenB: address(_tokenB),
            amountB: AMOUNT_B,
            partialFillAllowed: true
        });
        orders[1] = _order(address(_tokenA), AMOUNT_A, address(_tokenB), AMOUNT_B);

        vm.startPrank(_maker);
        _tokenA.approve(address(_board), amountA + AMOUNT_A);
        uint256[] memory ids = _board.createOrders(orders);
        vm.stopPrank();

        vm.startPrank(_taker);
        _tokenB.approve(address(_board), AMOUNT_B);
        _board.fillOrder(ids[0], fillA, 0);
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

        for (uint256 i; i < 2; ++i) {
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
}
