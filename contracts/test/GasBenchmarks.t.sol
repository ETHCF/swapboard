// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.33;

// solhint-disable use-natspec
// solhint-disable no-console
// solhint-disable gas-small-strings

import {Test, console2} from "forge-std/Test.sol";
import {Swapboard} from "../src/Swapboard.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockWETH} from "./mocks/MockWETH.sol";

/// @title GasBenchmarks
/// @author Zak Cole (numbergroup.xyz) for Ethereum Community Foundation
/// @notice Gas consumption tests for optimization baseline
contract GasBenchmarks is Test {
    Swapboard internal _board;
    MockERC20 internal _tokenA;
    MockERC20 internal _tokenB;
    MockWETH internal _mockWeth;

    address internal _maker = makeAddr("maker");
    address internal _taker = makeAddr("taker");

    /// @notice Deploys Swapboard, tokens, and approvals for gas benchmarks
    function setUp() public {
        _mockWeth = new MockWETH();
        _board = new Swapboard(address(_mockWeth));
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
        _board.createOrder(address(_tokenA), 100 ether, address(_tokenB), 100 ether);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("createOrder gas:", gasUsed);
        assertLt(gasUsed, 250_000, "createOrder exceeds gas ceiling");
    }

    /// @notice Benchmarks gas used by fillOrder
    function test_gas_fillOrder() public {
        vm.prank(_maker);
        uint256 orderId =
            _board.createOrder(address(_tokenA), 100 ether, address(_tokenB), 100 ether);

        vm.prank(_taker);
        uint256 gasBefore = gasleft();
        _board.fillOrder(orderId, 0);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("fillOrder gas:", gasUsed);
        assertLt(gasUsed, 150_000, "fillOrder exceeds gas ceiling");
    }

    /// @notice Benchmarks gas used by cancelOrder
    function test_gas_cancelOrder() public {
        vm.prank(_maker);
        uint256 orderId =
            _board.createOrder(address(_tokenA), 100 ether, address(_tokenB), 100 ether);

        vm.prank(_maker);
        uint256 gasBefore = gasleft();
        _board.cancelOrder(orderId);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("cancelOrder gas:", gasUsed);
        assertLt(gasUsed, 100_000, "cancelOrder exceeds gas ceiling");
    }

    /// @notice Benchmarks gas used by getOrder
    function test_gas_getOrder() public {
        vm.prank(_maker);
        uint256 orderId =
            _board.createOrder(address(_tokenA), 100 ether, address(_tokenB), 100 ether);

        uint256 gasBefore = gasleft();
        _board.getOrder(orderId);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("getOrder gas:", gasUsed);
        assertLt(gasUsed, 10_000, "getOrder exceeds gas ceiling");
    }

    /// @notice Benchmarks gas used by getOrders for 10 orders
    function test_gas_getOrders_10() public {
        for (uint256 i = 0; i < 10; ++i) {
            vm.prank(_maker);
            _board.createOrder(address(_tokenA), 100 ether, address(_tokenB), 100 ether);
        }

        uint256[] memory ids = new uint256[](10);
        for (uint256 i = 0; i < 10; ++i) {
            ids[i] = i;
        }

        uint256 gasBefore = gasleft();
        _board.getOrders(ids);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("getOrders(10) gas:", gasUsed);
        assertLt(gasUsed, 50_000, "getOrders(10) exceeds gas ceiling");
    }

    /// @notice Benchmarks gas used by getOrders for 100 orders
    function test_gas_getOrders_100() public {
        for (uint256 i = 0; i < 100; ++i) {
            vm.prank(_maker);
            _board.createOrder(address(_tokenA), 100 ether, address(_tokenB), 100 ether);
        }

        uint256[] memory ids = new uint256[](100);
        for (uint256 i = 0; i < 100; ++i) {
            ids[i] = i;
        }

        uint256 gasBefore = gasleft();
        _board.getOrders(ids);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("getOrders(100) gas:", gasUsed);
        assertLt(gasUsed, 500_000, "getOrders(100) exceeds gas ceiling");
    }

    /// @notice Benchmarks gas used by canFill
    function test_gas_canFill() public {
        vm.prank(_maker);
        uint256 orderId =
            _board.createOrder(address(_tokenA), 100 ether, address(_tokenB), 100 ether);

        uint256 gasBefore = gasleft();
        _board.canFill(orderId);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("canFill gas:", gasUsed);
        assertLt(gasUsed, 5000, "canFill exceeds gas ceiling");
    }
}
