// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec
// solhint-disable no-console
// solhint-disable gas-small-strings

import {Test, console2} from "forge-std/Test.sol";
import {FillTestLib} from "./helpers/FillTestLib.sol";
import {OrderTestLib} from "./helpers/OrderTestLib.sol";
import {Swapboard} from "../src/Swapboard.sol";
import {ISwapboard} from "../src/interfaces/ISwapboard.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @title GasBenchmarks
/// @author Zak Cole (numbergroup.xyz) for Ethereum Community Foundation
/// @notice Gas consumption tests for optimization baseline
contract GasBenchmarks is Test {
    Swapboard internal _board;
    MockERC20 internal _tokenA;
    MockERC20 internal _tokenB;
    address internal _eth;

    // forge-lint: disable-start(function-init-state)
    address internal _maker = makeAddr("maker");
    address internal _taker = makeAddr("taker");
    // forge-lint: disable-end(function-init-state)

    uint128 private constant ORDER_A = 100 ether;
    uint128 private constant ORDER_B = 100 ether;
    uint128 private constant ETH_AMOUNT = 1 ether;
    uint8 private constant TOKEN_DECIMALS = 18;
    uint256 private constant MINT_AMOUNT = 1_000_000 ether;

    function _order() private view returns (ISwapboard.CreateOrderParams memory) {
        return OrderTestLib.order(address(_tokenA), ORDER_A, address(_tokenB), ORDER_B);
    }

    function _orderPartial() private view returns (ISwapboard.CreateOrderParams memory) {
        return OrderTestLib.orderPartial(address(_tokenA), ORDER_A, address(_tokenB), ORDER_B);
    }

    function _previousAmounts(
        ISwapboard.Order memory snapshot
    ) private pure returns (ISwapboard.OrderAmounts memory) {
        return ISwapboard.OrderAmounts({
            amountA: snapshot.amountA,
            amountB: snapshot.amountB,
            availableA: snapshot.availableA,
            availableB: snapshot.availableB
        });
    }

    function _modifyParams(
        uint256 orderId,
        ISwapboard.Order memory snapshot,
        uint128 availableA,
        uint128 availableB
    ) private pure returns (ISwapboard.ModifyOrdersParams memory) {
        return ISwapboard.ModifyOrdersParams({
            orderId: orderId,
            previousAmounts: _previousAmounts(snapshot),
            updatedOrder: ISwapboard.ModifyOrderParams({availableA: availableA, availableB: availableB})
        });
    }

    /// @notice Deploys Swapboard, tokens, and approvals for gas benchmarks
    function setUp() public {
        _board = new Swapboard();
        _eth = _board.getEth();
        _tokenA = new MockERC20("Token A", "TKA", TOKEN_DECIMALS);
        _tokenB = new MockERC20("Token B", "TKB", TOKEN_DECIMALS);

        _tokenA.mint(_maker, MINT_AMOUNT);
        _tokenB.mint(_maker, MINT_AMOUNT);
        _tokenB.mint(_taker, MINT_AMOUNT);
        _tokenA.mint(_taker, MINT_AMOUNT);
        vm.deal(_maker, 100 ether);
        vm.deal(_taker, 100 ether);

        vm.prank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        vm.prank(_maker);
        _tokenB.approve(address(_board), type(uint256).max);
        vm.prank(_taker);
        _tokenB.approve(address(_board), type(uint256).max);
        vm.prank(_taker);
        _tokenA.approve(address(_board), type(uint256).max);
    }

    /// @notice Benchmarks gas used by createOrder
    function test_gas_createOrder() public {
        vm.prank(_maker);
        uint256 gasBefore = gasleft();
        _board.createOrder(_order());
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("createOrder gas:", gasUsed);
        assertLt(gasUsed, 250_000);
    }

    /// @notice Benchmarks gas used by createOrders for three same-token orders
    function test_gas_createOrders() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](3);
        for (uint256 i = 0; i < 3; ++i) {
            orders[i] = _order();
        }

        vm.prank(_maker);
        uint256 gasBefore = gasleft();
        _board.createOrders(orders);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("createOrders(3) gas:", gasUsed);
        assertLt(gasUsed, 500_000);
    }

    /// @notice Benchmarks gas used by createOrders for three ETH-as-tokenA orders
    function test_gas_createOrders_sellEth() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](3);
        for (uint256 i = 0; i < 3; ++i) {
            orders[i] = OrderTestLib.order(_eth, ETH_AMOUNT, address(_tokenB), ORDER_B);
        }

        vm.prank(_maker);
        uint256 gasBefore = gasleft();
        _board.createOrders{value: ETH_AMOUNT * 3}(orders);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("createOrders sellEth(3) gas:", gasUsed);
        assertLt(gasUsed, 450_000);
    }

    /// @notice Benchmarks gas used by createOrder selling ETH as tokenA
    function test_gas_createOrder_sellEth() public {
        vm.prank(_maker);
        uint256 gasBefore = gasleft();
        _board.createOrder{value: ETH_AMOUNT}(OrderTestLib.order(_eth, ETH_AMOUNT, address(_tokenB), ORDER_B));
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("createOrder sellEth gas:", gasUsed);
        assertLt(gasUsed, 200_000);
    }

    /// @notice Benchmarks gas used by createOrder wanting ETH as tokenB
    function test_gas_createOrder_wantEth() public {
        vm.prank(_maker);
        uint256 gasBefore = gasleft();
        _board.createOrder(OrderTestLib.order(address(_tokenA), ORDER_A, _eth, ETH_AMOUNT));
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("createOrder wantEth gas:", gasUsed);
        assertLt(gasUsed, 250_000);
    }

    /// @notice Benchmarks gas used by fillOrder
    function test_gas_fillOrder() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder(_order());

        uint128 amountB = FillTestLib.quoteAmountB(_board.getOrder(orderId), ORDER_A);
        vm.startPrank(_taker);
        uint256 gasBefore = gasleft();
        FillTestLib.fill(_board, orderId, ORDER_A, amountB, 0);
        uint256 gasUsed = gasBefore - gasleft();
        vm.stopPrank();

        console2.log("fillOrder gas:", gasUsed);
        assertLt(gasUsed, 150_000);
    }

    /// @notice Benchmarks gas used by a partial fillOrder
    function test_gas_fillOrder_partial() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder(_orderPartial());

        uint128 amountB = FillTestLib.quoteAmountB(_board.getOrder(orderId), 40 ether);
        vm.startPrank(_taker);
        uint256 gasBefore = gasleft();
        _board.fillOrder(orderId, 40 ether, amountB, 0);
        uint256 gasUsed = gasBefore - gasleft();
        vm.stopPrank();

        console2.log("fillOrder partial gas:", gasUsed);
        assertLt(gasUsed, 155_000);
    }

    /// @notice Benchmarks gas used by fillOrders for three same-tokenB orders
    function test_gas_fillOrders() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](3);
        for (uint256 i = 0; i < 3; ++i) {
            orders[i] = _order();
        }

        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders(orders);

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](3);
        for (uint256 j = 0; j < 3; ++j) {
            fills[j] = FillTestLib.fillParams(_board.getOrder(ids[j]), ids[j], ORDER_A);
        }

        vm.prank(_taker);
        uint256 gasBefore = gasleft();
        _board.fillOrders(fills, 0);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("fillOrders(3) gas:", gasUsed);
        assertLt(gasUsed, 400_000);
    }

    /// @notice Benchmarks gas used by fillOrders paying ETH as tokenB
    function test_gas_fillOrders_payEth() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](3);
        for (uint256 i = 0; i < 3; ++i) {
            orders[i] = OrderTestLib.order(address(_tokenA), ORDER_A, _eth, ETH_AMOUNT);
        }

        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders(orders);

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](3);
        for (uint256 j = 0; j < 3; ++j) {
            fills[j] = FillTestLib.fillParams(_board.getOrder(ids[j]), ids[j], ORDER_A);
        }

        vm.prank(_taker);
        uint256 gasBefore = gasleft();
        _board.fillOrders{value: ETH_AMOUNT * 3}(fills, 0);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("fillOrders payEth(3) gas:", gasUsed);
        assertLt(gasUsed, 400_000);
    }

    /// @notice Benchmarks gas used by fillOrders receiving ETH as tokenA
    function test_gas_fillOrders_receiveEth() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](3);
        for (uint256 i = 0; i < 3; ++i) {
            orders[i] = OrderTestLib.order(_eth, ETH_AMOUNT, address(_tokenB), ORDER_B);
        }

        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders{value: ETH_AMOUNT * 3}(orders);

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](3);
        for (uint256 j = 0; j < 3; ++j) {
            fills[j] = FillTestLib.fillParams(_board.getOrder(ids[j]), ids[j], ETH_AMOUNT);
        }

        vm.prank(_taker);
        uint256 gasBefore = gasleft();
        _board.fillOrders(fills, 0);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("fillOrders receiveEth(3) gas:", gasUsed);
        assertLt(gasUsed, 400_000);
    }

    /// @notice Benchmarks gas used by fillOrder paying ETH as tokenB
    function test_gas_fillOrder_payEth() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder(OrderTestLib.order(address(_tokenA), ORDER_A, _eth, ETH_AMOUNT));

        vm.startPrank(_taker);
        uint256 gasBefore = gasleft();
        _board.fillOrder{value: ETH_AMOUNT}(orderId, ORDER_A, ETH_AMOUNT, 0);
        uint256 gasUsed = gasBefore - gasleft();
        vm.stopPrank();

        console2.log("fillOrder payEth gas:", gasUsed);
        assertLt(gasUsed, 150_000);
    }

    /// @notice Benchmarks gas used by fillOrder receiving ETH as tokenA
    function test_gas_fillOrder_receiveEth() public {
        vm.prank(_maker);
        uint256 orderId =
            _board.createOrder{value: ETH_AMOUNT}(OrderTestLib.order(_eth, ETH_AMOUNT, address(_tokenB), ORDER_B));

        vm.startPrank(_taker);
        uint256 gasBefore = gasleft();
        FillTestLib.fill(_board, orderId, ETH_AMOUNT, ORDER_B, 0);
        uint256 gasUsed = gasBefore - gasleft();
        vm.stopPrank();

        console2.log("fillOrder receiveEth gas:", gasUsed);
        assertLt(gasUsed, 150_000);
    }

    /// @notice Benchmarks gas used by fillOrderPaying
    function test_gas_fillOrderPaying() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder(_order());

        uint128 amountA = FillTestLib.quoteAmountA(_board.getOrder(orderId), ORDER_B);
        vm.startPrank(_taker);
        uint256 gasBefore = gasleft();
        FillTestLib.fillPaying(_board, orderId, ORDER_B, amountA, 0);
        uint256 gasUsed = gasBefore - gasleft();
        vm.stopPrank();

        console2.log("fillOrderPaying gas:", gasUsed);
        assertLt(gasUsed, 150_000);
    }

    /// @notice Benchmarks gas used by a partial fillOrderPaying
    function test_gas_fillOrderPaying_partial() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder(_orderPartial());

        uint128 payB = 40 ether;
        uint128 amountA = FillTestLib.quoteAmountA(_board.getOrder(orderId), payB);
        vm.startPrank(_taker);
        uint256 gasBefore = gasleft();
        _board.fillOrderPaying(orderId, payB, amountA, 0);
        uint256 gasUsed = gasBefore - gasleft();
        vm.stopPrank();

        console2.log("fillOrderPaying partial gas:", gasUsed);
        assertLt(gasUsed, 155_000);
    }

    /// @notice Benchmarks gas used by fillOrdersPaying for three same-tokenB orders
    function test_gas_fillOrdersPaying() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](3);
        for (uint256 i = 0; i < 3; ++i) {
            orders[i] = _order();
        }

        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders(orders);

        ISwapboard.FillOrderPayingParams[] memory fills = new ISwapboard.FillOrderPayingParams[](3);
        for (uint256 j = 0; j < 3; ++j) {
            fills[j] = FillTestLib.fillPayingParams(_board.getOrder(ids[j]), ids[j], ORDER_B);
        }

        vm.prank(_taker);
        uint256 gasBefore = gasleft();
        _board.fillOrdersPaying(fills, 0);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("fillOrdersPaying(3) gas:", gasUsed);
        assertLt(gasUsed, 400_000);
    }

    /// @notice Benchmarks gas used by fillOrdersPaying paying ETH as tokenB
    function test_gas_fillOrdersPaying_payEth() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](3);
        for (uint256 i = 0; i < 3; ++i) {
            orders[i] = OrderTestLib.order(address(_tokenA), ORDER_A, _eth, ETH_AMOUNT);
        }

        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders(orders);

        ISwapboard.FillOrderPayingParams[] memory fills = new ISwapboard.FillOrderPayingParams[](3);
        for (uint256 j = 0; j < 3; ++j) {
            fills[j] = FillTestLib.fillPayingParams(_board.getOrder(ids[j]), ids[j], ETH_AMOUNT);
        }

        vm.prank(_taker);
        uint256 gasBefore = gasleft();
        _board.fillOrdersPaying{value: ETH_AMOUNT * 3}(fills, 0);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("fillOrdersPaying payEth(3) gas:", gasUsed);
        assertLt(gasUsed, 400_000);
    }

    /// @notice Benchmarks gas used by fillOrdersPaying receiving ETH as tokenA
    function test_gas_fillOrdersPaying_receiveEth() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](3);
        for (uint256 i = 0; i < 3; ++i) {
            orders[i] = OrderTestLib.order(_eth, ETH_AMOUNT, address(_tokenB), ORDER_B);
        }

        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders{value: ETH_AMOUNT * 3}(orders);

        ISwapboard.FillOrderPayingParams[] memory fills = new ISwapboard.FillOrderPayingParams[](3);
        for (uint256 j = 0; j < 3; ++j) {
            fills[j] = FillTestLib.fillPayingParams(_board.getOrder(ids[j]), ids[j], ORDER_B);
        }

        vm.prank(_taker);
        uint256 gasBefore = gasleft();
        _board.fillOrdersPaying(fills, 0);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("fillOrdersPaying receiveEth(3) gas:", gasUsed);
        assertLt(gasUsed, 400_000);
    }

    /// @notice Benchmarks gas used by fillOrderPaying paying ETH as tokenB
    function test_gas_fillOrderPaying_payEth() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder(OrderTestLib.order(address(_tokenA), ORDER_A, _eth, ETH_AMOUNT));

        vm.startPrank(_taker);
        uint256 gasBefore = gasleft();
        _board.fillOrderPaying{value: ETH_AMOUNT}(orderId, ETH_AMOUNT, ORDER_A, 0);
        uint256 gasUsed = gasBefore - gasleft();
        vm.stopPrank();

        console2.log("fillOrderPaying payEth gas:", gasUsed);
        assertLt(gasUsed, 150_000);
    }

    /// @notice Benchmarks gas used by fillOrderPaying receiving ETH as tokenA
    function test_gas_fillOrderPaying_receiveEth() public {
        vm.prank(_maker);
        uint256 orderId =
            _board.createOrder{value: ETH_AMOUNT}(OrderTestLib.order(_eth, ETH_AMOUNT, address(_tokenB), ORDER_B));

        vm.startPrank(_taker);
        uint256 gasBefore = gasleft();
        FillTestLib.fillPaying(_board, orderId, ORDER_B, ETH_AMOUNT, 0);
        uint256 gasUsed = gasBefore - gasleft();
        vm.stopPrank();

        console2.log("fillOrderPaying receiveEth gas:", gasUsed);
        assertLt(gasUsed, 150_000);
    }

    /// @notice Benchmarks gas used by cancelOrder
    function test_gas_cancelOrder() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder(_order());

        vm.prank(_maker);
        uint256 gasBefore = gasleft();
        _board.cancelOrder(orderId);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("cancelOrder gas:", gasUsed);
        assertLt(gasUsed, 100_000);
    }

    /// @notice Benchmarks gas used by cancelOrder returning ETH escrow
    function test_gas_cancelOrder_returnEth() public {
        vm.prank(_maker);
        uint256 orderId =
            _board.createOrder{value: ETH_AMOUNT}(OrderTestLib.order(_eth, ETH_AMOUNT, address(_tokenB), ORDER_B));

        vm.prank(_maker);
        uint256 gasBefore = gasleft();
        _board.cancelOrder(orderId);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("cancelOrder returnEth gas:", gasUsed);
        assertLt(gasUsed, 100_000);
    }

    /// @notice Benchmarks gas used by modifyOrder when remaining amounts change
    function test_gas_modifyOrder() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder(_order());
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        ISwapboard.OrderAmounts memory previous = _previousAmounts(snapshot);
        ISwapboard.ModifyOrderParams memory updated =
            ISwapboard.ModifyOrderParams({availableA: ORDER_A, availableB: ORDER_B / 2});

        vm.prank(_maker);
        uint256 gasBefore = gasleft();
        _board.modifyOrder(orderId, previous, updated);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("modifyOrder gas:", gasUsed);
        assertLt(gasUsed, 100_000);
    }

    /// @notice Benchmarks gas used by modifyOrder topping up tokenA escrow
    function test_gas_modifyOrder_topUp() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder(_order());
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        ISwapboard.OrderAmounts memory previous = _previousAmounts(snapshot);
        ISwapboard.ModifyOrderParams memory updated =
            ISwapboard.ModifyOrderParams({availableA: ORDER_A + 50 ether, availableB: ORDER_B});

        vm.prank(_maker);
        uint256 gasBefore = gasleft();
        _board.modifyOrder(orderId, previous, updated);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("modifyOrder topUp gas:", gasUsed);
        assertLt(gasUsed, 120_000);
    }

    /// @notice Benchmarks gas used by modifyOrder refunding tokenA escrow
    function test_gas_modifyOrder_refund() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder(_order());
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        ISwapboard.OrderAmounts memory previous = _previousAmounts(snapshot);
        ISwapboard.ModifyOrderParams memory updated =
            ISwapboard.ModifyOrderParams({availableA: ORDER_A / 2, availableB: ORDER_B});

        vm.prank(_maker);
        uint256 gasBefore = gasleft();
        _board.modifyOrder(orderId, previous, updated);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("modifyOrder refund gas:", gasUsed);
        assertLt(gasUsed, 120_000);
    }

    /// @notice Benchmarks gas used by modifyOrder topping up ETH escrow
    function test_gas_modifyOrder_topUpEth() public {
        vm.prank(_maker);
        uint256 orderId =
            _board.createOrder{value: ETH_AMOUNT}(OrderTestLib.order(_eth, ETH_AMOUNT, address(_tokenB), ORDER_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        ISwapboard.OrderAmounts memory previous = _previousAmounts(snapshot);
        uint128 newA = ETH_AMOUNT + (ETH_AMOUNT / 2);
        ISwapboard.ModifyOrderParams memory updated =
            ISwapboard.ModifyOrderParams({availableA: newA, availableB: ORDER_B});

        vm.prank(_maker);
        uint256 gasBefore = gasleft();
        _board.modifyOrder{value: ETH_AMOUNT / 2}(orderId, previous, updated);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("modifyOrder topUpEth gas:", gasUsed);
        assertLt(gasUsed, 100_000);
    }

    /// @notice Benchmarks gas used by modifyOrder refunding ETH escrow
    function test_gas_modifyOrder_refundEth() public {
        vm.prank(_maker);
        uint256 orderId =
            _board.createOrder{value: ETH_AMOUNT}(OrderTestLib.order(_eth, ETH_AMOUNT, address(_tokenB), ORDER_B));
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        ISwapboard.OrderAmounts memory previous = _previousAmounts(snapshot);
        ISwapboard.ModifyOrderParams memory updated =
            ISwapboard.ModifyOrderParams({availableA: ETH_AMOUNT / 2, availableB: ORDER_B});

        vm.prank(_maker);
        uint256 gasBefore = gasleft();
        _board.modifyOrder(orderId, previous, updated);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("modifyOrder refundEth gas:", gasUsed);
        assertLt(gasUsed, 100_000);
    }

    /// @notice Benchmarks gas used by setPartialFillAllowed
    function test_gas_setPartialFillAllowed() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder(_order());

        vm.prank(_maker);
        uint256 gasBefore = gasleft();
        _board.setPartialFillAllowed(orderId, true);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("setPartialFillAllowed gas:", gasUsed);
        assertLt(gasUsed, 50_000);
    }

    /// @notice Benchmarks gas used by modifyOrders for three same-token shrinks
    function test_gas_modifyOrders() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](3);
        for (uint256 i = 0; i < 3; ++i) {
            orders[i] = _order();
        }

        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders(orders);

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](3);
        for (uint256 j = 0; j < 3; ++j) {
            mods[j] = _modifyParams(ids[j], _board.getOrder(ids[j]), ORDER_A / 2, ORDER_B);
        }

        vm.prank(_maker);
        uint256 gasBefore = gasleft();
        _board.modifyOrders(mods);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("modifyOrders gas:", gasUsed);
        assertLt(gasUsed, 250_000);
    }

    /// @notice Benchmarks gas used by modifyOrders when top-ups and refunds net to one pull
    function test_gas_modifyOrders_netting() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](3);
        orders[0] = _order();
        orders[1] = _order();
        orders[2] = _order();

        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders(orders);

        // +50, -25, -10 => net pull 15
        uint128[3] memory newAs = [ORDER_A + 50 ether, ORDER_A - 25 ether, ORDER_A - 10 ether];
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](3);
        for (uint256 j = 0; j < 3; ++j) {
            mods[j] = _modifyParams(ids[j], _board.getOrder(ids[j]), newAs[j], ORDER_B);
        }

        vm.prank(_maker);
        uint256 gasBefore = gasleft();
        _board.modifyOrders(mods);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("modifyOrders netting gas:", gasUsed);
        assertLt(gasUsed, 250_000);
    }

    /// @notice Benchmarks gas used by modifyOrders when top-ups and refunds net to one refund
    function test_gas_modifyOrders_netRefund() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](3);
        for (uint256 i = 0; i < 3; ++i) {
            orders[i] = _order();
        }

        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders(orders);

        // +10, -50, -25 => net refund 65
        uint128[3] memory newAs = [ORDER_A + 10 ether, ORDER_A - 50 ether, ORDER_A - 25 ether];
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](3);
        for (uint256 j = 0; j < 3; ++j) {
            mods[j] = _modifyParams(ids[j], _board.getOrder(ids[j]), newAs[j], ORDER_B);
        }

        vm.prank(_maker);
        uint256 gasBefore = gasleft();
        _board.modifyOrders(mods);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("modifyOrders netRefund gas:", gasUsed);
        assertLt(gasUsed, 250_000);
    }

    /// @notice Benchmarks gas used by modifyOrders when ETH top-ups and refunds net to one pull
    function test_gas_modifyOrders_ethNetting() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](3);
        for (uint256 i = 0; i < 3; ++i) {
            orders[i] = OrderTestLib.order(_eth, ETH_AMOUNT, address(_tokenB), ORDER_B);
        }

        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders{value: ETH_AMOUNT * 3}(orders);

        // +0.5, -0.25, -0.1 => net pull 0.15
        uint128[3] memory newAs = [ETH_AMOUNT + 0.5 ether, ETH_AMOUNT - 0.25 ether, ETH_AMOUNT - 0.1 ether];
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](3);
        for (uint256 j = 0; j < 3; ++j) {
            mods[j] = _modifyParams(ids[j], _board.getOrder(ids[j]), newAs[j], ORDER_B);
        }

        vm.prank(_maker);
        uint256 gasBefore = gasleft();
        _board.modifyOrders{value: 0.15 ether}(mods);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("modifyOrders ethNetting gas:", gasUsed);
        assertLt(gasUsed, 200_000);
    }

    /// @notice Benchmarks gas used by modifyOrders when ETH top-ups and refunds net to one refund
    function test_gas_modifyOrders_ethNetRefund() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](3);
        for (uint256 i = 0; i < 3; ++i) {
            orders[i] = OrderTestLib.order(_eth, ETH_AMOUNT, address(_tokenB), ORDER_B);
        }

        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders{value: ETH_AMOUNT * 3}(orders);

        // +0.1, -0.5, -0.25 => net refund 0.65
        uint128[3] memory newAs = [ETH_AMOUNT + 0.1 ether, ETH_AMOUNT - 0.5 ether, ETH_AMOUNT - 0.25 ether];
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](3);
        for (uint256 j = 0; j < 3; ++j) {
            mods[j] = _modifyParams(ids[j], _board.getOrder(ids[j]), newAs[j], ORDER_B);
        }

        vm.prank(_maker);
        uint256 gasBefore = gasleft();
        _board.modifyOrders(mods);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("modifyOrders ethNetRefund gas:", gasUsed);
        assertLt(gasUsed, 200_000);
    }

    /// @notice Benchmarks gas used by modifyOrders across two distinct tokenA assets
    function test_gas_modifyOrders_mixedTokens() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](4);
        orders[0] = OrderTestLib.order(address(_tokenA), ORDER_A, address(_tokenB), ORDER_B);
        orders[1] = OrderTestLib.order(address(_tokenA), ORDER_A, address(_tokenB), ORDER_B);
        orders[2] = OrderTestLib.order(address(_tokenB), ORDER_B, address(_tokenA), ORDER_A);
        orders[3] = OrderTestLib.order(address(_tokenB), ORDER_B, address(_tokenA), ORDER_A);

        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders(orders);

        // tokenA: +50 / -25 => net pull 25; tokenB: +10 / -50 => net refund 40
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](4);
        mods[0] = _modifyParams(ids[0], _board.getOrder(ids[0]), ORDER_A + 50 ether, ORDER_B);
        mods[1] = _modifyParams(ids[1], _board.getOrder(ids[1]), ORDER_A - 25 ether, ORDER_B);
        mods[2] = _modifyParams(ids[2], _board.getOrder(ids[2]), ORDER_B + 10 ether, ORDER_A);
        mods[3] = _modifyParams(ids[3], _board.getOrder(ids[3]), ORDER_B - 50 ether, ORDER_A);

        vm.prank(_maker);
        uint256 gasBefore = gasleft();
        _board.modifyOrders(mods);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("modifyOrders mixedTokens gas:", gasUsed);
        assertLt(gasUsed, 350_000);
    }

    /// @notice Benchmarks gas used by cancelOrders for three same-token orders
    function test_gas_cancelOrders() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](3);
        for (uint256 i = 0; i < 3; ++i) {
            orders[i] = _order();
        }

        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders(orders);

        vm.prank(_maker);
        uint256 gasBefore = gasleft();
        _board.cancelOrders(ids);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("cancelOrders(3) gas:", gasUsed);
        assertLt(gasUsed, 200_000);
    }

    /// @notice Benchmarks gas used by cancelOrders returning aggregated ETH escrow
    function test_gas_cancelOrders_returnEth() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](3);
        for (uint256 i = 0; i < 3; ++i) {
            orders[i] = OrderTestLib.order(_eth, ETH_AMOUNT, address(_tokenB), ORDER_B);
        }

        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders{value: ETH_AMOUNT * 3}(orders);

        vm.prank(_maker);
        uint256 gasBefore = gasleft();
        _board.cancelOrders(ids);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("cancelOrders returnEth(3) gas:", gasUsed);
        assertLt(gasUsed, 150_000);
    }

    /// @notice Benchmarks gas used by getOrder
    function test_gas_getOrder() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder(_order());

        uint256 gasBefore = gasleft();
        _board.getOrder(orderId);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("getOrder gas:", gasUsed);
        assertLt(gasUsed, 15_000);
    }

    /// @notice Benchmarks gas used by getOrders for 10 orders
    function test_gas_getOrders_10() public {
        for (uint256 i = 0; i < 10; ++i) {
            vm.prank(_maker);
            _board.createOrder(_order());
        }

        uint256[] memory ids = new uint256[](10);
        for (uint256 i = 0; i < 10; ++i) {
            ids[i] = i;
        }

        uint256 gasBefore = gasleft();
        _board.getOrders(ids);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("getOrders(10) gas:", gasUsed);
        assertLt(gasUsed, 140_000);
    }

    /// @notice Benchmarks gas used by getOrders for 100 orders
    function test_gas_getOrders_100() public {
        for (uint256 i = 0; i < 100; ++i) {
            vm.prank(_maker);
            _board.createOrder(_order());
        }

        uint256[] memory ids = new uint256[](100);
        for (uint256 i = 0; i < 100; ++i) {
            ids[i] = i;
        }

        uint256 gasBefore = gasleft();
        _board.getOrders(ids);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("getOrders(100) gas:", gasUsed);
        assertLt(gasUsed, 1_400_000);
    }

    /// @notice Benchmarks gas used by canFill
    function test_gas_canFill() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder(_order());

        uint256 gasBefore = gasleft();
        _board.canFill(orderId);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("canFill gas:", gasUsed);
        assertLt(gasUsed, 5000);
    }

    /// @notice Benchmarks gas used by getNextOrderId
    function test_gas_getNextOrderId() public {
        uint256 gasBefore = gasleft();
        _board.getNextOrderId();
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("getNextOrderId gas:", gasUsed);
        assertLt(gasUsed, 10_000);
    }

    /// @notice Benchmarks gas used by getEth
    function test_gas_getEth() public {
        uint256 gasBefore = gasleft();
        _board.getEth();
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("getEth gas:", gasUsed);
        assertLt(gasUsed, 10_000);
    }

    /// @notice Benchmarks gas used by version
    function test_gas_version() public {
        uint256 gasBefore = gasleft();
        _board.version();
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("version gas:", gasUsed);
        assertLt(gasUsed, 10_000);
    }
}
