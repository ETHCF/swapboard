// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec
// solhint-disable no-console
// solhint-disable gas-small-strings

import {Test, console2} from "forge-std/Test.sol";
import {FillTestLib} from "./helpers/FillTestLib.sol";
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

    address internal _maker = makeAddr("maker");
    address internal _taker = makeAddr("taker");

    /// @notice Deploys Swapboard, tokens, and approvals for gas benchmarks
    function setUp() public {
        _board = new Swapboard();
        _tokenA = new MockERC20("Token A", "TKA", 18);
        _tokenB = new MockERC20("Token B", "TKB", 18);

        _tokenA.mint(_maker, 1_000_000 ether);
        _tokenB.mint(_taker, 1_000_000 ether);

        vm.prank(_maker);
        _tokenA.approve(address(_board), type(uint256).max);
        vm.prank(_taker);
        _tokenB.approve(address(_board), type(uint256).max);
    }

    /// @notice Benchmarks gas used by createOrder
    function test_gas_createOrder() public {
        vm.prank(_maker);
        uint256 gasBefore = gasleft();
        _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: 100 ether,
                tokenB: address(_tokenB),
                amountB: 100 ether,
                partialFillAllowed: false
            })
        );
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("createOrder gas:", gasUsed);
        assertLt(gasUsed, 250_000);
    }

    /// @notice Benchmarks gas used by createOrders for three same-token orders
    function test_gas_createOrders() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](3);
        for (uint256 i; i < 3; ++i) {
            orders[i] = ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: 100 ether,
                tokenB: address(_tokenB),
                amountB: 100 ether,
                partialFillAllowed: false
            });
        }

        vm.prank(_maker);
        uint256 gasBefore = gasleft();
        _board.createOrders(orders);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("createOrders(3) gas:", gasUsed);
        assertLt(gasUsed, 500_000);
    }

    /// @notice Benchmarks gas used by fillOrder
    function test_gas_fillOrder() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: 100 ether,
                tokenB: address(_tokenB),
                amountB: 100 ether,
                partialFillAllowed: false
            })
        );

        uint128 amountB = FillTestLib.quoteAmountB(_board.getOrder(orderId), 100 ether);
        vm.startPrank(_taker);
        uint256 gasBefore = gasleft();
        _board.fillOrder(orderId, 100 ether, amountB, 0);
        uint256 gasUsed = gasBefore - gasleft();
        vm.stopPrank();

        console2.log("fillOrder gas:", gasUsed);
        assertLt(gasUsed, 150_000);
    }

    /// @notice Benchmarks gas used by a partial fillOrder
    function test_gas_fillOrder_partial() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: 100 ether,
                tokenB: address(_tokenB),
                amountB: 100 ether,
                partialFillAllowed: true
            })
        );

        uint128 amountB = FillTestLib.quoteAmountB(_board.getOrder(orderId), 40 ether);
        vm.startPrank(_taker);
        uint256 gasBefore = gasleft();
        _board.fillOrder(orderId, 40 ether, amountB, 0);
        uint256 gasUsed = gasBefore - gasleft();
        vm.stopPrank();

        console2.log("fillOrder partial gas:", gasUsed);
        assertLt(gasUsed, 150_000);
    }

    /// @notice Benchmarks gas used by fillOrders for three same-tokenB orders
    function test_gas_fillOrders() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](3);
        for (uint256 i; i < 3; ++i) {
            orders[i] = ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: 100 ether,
                tokenB: address(_tokenB),
                amountB: 100 ether,
                partialFillAllowed: false
            });
        }

        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders(orders);

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](3);
        for (uint256 j; j < 3; ++j) {
            fills[j] = FillTestLib.fillParams(_board.getOrder(ids[j]), ids[j], 100 ether);
        }

        vm.prank(_taker);
        uint256 gasBefore = gasleft();
        _board.fillOrders(fills, 0);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("fillOrders(3) gas:", gasUsed);
        assertLt(gasUsed, 400_000);
    }

    /// @notice Benchmarks gas used by cancelOrder
    function test_gas_cancelOrder() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: 100 ether,
                tokenB: address(_tokenB),
                amountB: 100 ether,
                partialFillAllowed: false
            })
        );

        vm.prank(_maker);
        uint256 gasBefore = gasleft();
        _board.cancelOrder(orderId);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("cancelOrder gas:", gasUsed);
        assertLt(gasUsed, 100_000);
    }

    /// @notice Benchmarks gas used by cancelOrders for three same-token orders
    function test_gas_cancelOrders() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](3);
        for (uint256 i; i < 3; ++i) {
            orders[i] = ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: 100 ether,
                tokenB: address(_tokenB),
                amountB: 100 ether,
                partialFillAllowed: false
            });
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

    /// @notice Benchmarks gas used by getOrder
    function test_gas_getOrder() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: 100 ether,
                tokenB: address(_tokenB),
                amountB: 100 ether,
                partialFillAllowed: false
            })
        );

        uint256 gasBefore = gasleft();
        _board.getOrder(orderId);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("getOrder gas:", gasUsed);
        assertLt(gasUsed, 10_000);
    }

    /// @notice Benchmarks gas used by getOrders for 10 orders
    function test_gas_getOrders_10() public {
        for (uint256 i = 0; i < 10; ++i) {
            vm.prank(_maker);
            _board.createOrder(
                ISwapboard.CreateOrderParams({
                    tokenA: address(_tokenA),
                    amountA: 100 ether,
                    tokenB: address(_tokenB),
                    amountB: 100 ether,
                    partialFillAllowed: false
                })
            );
        }

        uint256[] memory ids = new uint256[](10);
        for (uint256 i = 0; i < 10; ++i) {
            ids[i] = i;
        }

        uint256 gasBefore = gasleft();
        _board.getOrders(ids);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("getOrders(10) gas:", gasUsed);
        assertLt(gasUsed, 70_000);
    }

    /// @notice Benchmarks gas used by getOrders for 100 orders
    function test_gas_getOrders_100() public {
        for (uint256 i = 0; i < 100; ++i) {
            vm.prank(_maker);
            _board.createOrder(
                ISwapboard.CreateOrderParams({
                    tokenA: address(_tokenA),
                    amountA: 100 ether,
                    tokenB: address(_tokenB),
                    amountB: 100 ether,
                    partialFillAllowed: false
                })
            );
        }

        uint256[] memory ids = new uint256[](100);
        for (uint256 i = 0; i < 100; ++i) {
            ids[i] = i;
        }

        uint256 gasBefore = gasleft();
        _board.getOrders(ids);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("getOrders(100) gas:", gasUsed);
        assertLt(gasUsed, 700_000);
    }

    /// @notice Benchmarks gas used by canFill
    function test_gas_canFill() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: 100 ether,
                tokenB: address(_tokenB),
                amountB: 100 ether,
                partialFillAllowed: false
            })
        );

        uint256 gasBefore = gasleft();
        _board.canFill(orderId);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("canFill gas:", gasUsed);
        assertLt(gasUsed, 5000);
    }
}
