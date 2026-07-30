// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.33;

// solhint-disable use-natspec
// solhint-disable no-console

import {Test, console2} from "forge-std/Test.sol";
import {Swapboard} from "../src/Swapboard.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockWETH} from "./mocks/MockWETH.sol";

/// @title GasBenchmarks
/// @author Zak Cole (numbergroup.xyz) for Ethereum Community Foundation
/// @notice Gas consumption tests for optimization baseline
contract GasBenchmarks is Test {
    Swapboard public board;
    MockERC20 public tokenA;
    MockERC20 public tokenB;
    MockWETH public mockWeth;

    address public maker = makeAddr("maker");
    address public taker = makeAddr("taker");

    /// @notice Deploys Swapboard, tokens, and approvals for gas benchmarks
    function setUp() public {
        mockWeth = new MockWETH();
        board = new Swapboard(address(mockWeth));
        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);

        tokenA.mint(maker, 1_000_000 ether);
        tokenB.mint(taker, 1_000_000 ether);

        vm.prank(maker);
        tokenA.approve(address(board), type(uint256).max);
        vm.prank(taker);
        tokenB.approve(address(board), type(uint256).max);
    }

    /// @notice Benchmarks gas used by createOrder
    function test_gas_createOrder() public {
        vm.prank(maker);
        uint256 gasBefore = gasleft();
        board.createOrder(address(tokenA), 100 ether, address(tokenB), 100 ether);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("createOrder gas:", gasUsed);
        assertLt(gasUsed, 250_000, "createOrder exceeds gas ceiling");
    }

    /// @notice Benchmarks gas used by fillOrder
    function test_gas_fillOrder() public {
        vm.prank(maker);
        uint256 orderId = board.createOrder(address(tokenA), 100 ether, address(tokenB), 100 ether);

        vm.prank(taker);
        uint256 gasBefore = gasleft();
        board.fillOrder(orderId, 0);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("fillOrder gas:", gasUsed);
        assertLt(gasUsed, 150_000, "fillOrder exceeds gas ceiling");
    }

    /// @notice Benchmarks gas used by cancelOrder
    function test_gas_cancelOrder() public {
        vm.prank(maker);
        uint256 orderId = board.createOrder(address(tokenA), 100 ether, address(tokenB), 100 ether);

        vm.prank(maker);
        uint256 gasBefore = gasleft();
        board.cancelOrder(orderId);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("cancelOrder gas:", gasUsed);
        assertLt(gasUsed, 100_000, "cancelOrder exceeds gas ceiling");
    }

    /// @notice Benchmarks gas used by getOrder
    function test_gas_getOrder() public {
        vm.prank(maker);
        uint256 orderId = board.createOrder(address(tokenA), 100 ether, address(tokenB), 100 ether);

        uint256 gasBefore = gasleft();
        board.getOrder(orderId);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("getOrder gas:", gasUsed);
        assertLt(gasUsed, 10_000, "getOrder exceeds gas ceiling");
    }

    /// @notice Benchmarks gas used by getOrders for 10 orders
    function test_gas_getOrders_10() public {
        for (uint256 i = 0; i < 10; ++i) {
            vm.prank(maker);
            board.createOrder(address(tokenA), 100 ether, address(tokenB), 100 ether);
        }

        uint256[] memory ids = new uint256[](10);
        for (uint256 i = 0; i < 10; ++i) {
            ids[i] = i;
        }

        uint256 gasBefore = gasleft();
        board.getOrders(ids);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("getOrders(10) gas:", gasUsed);
        assertLt(gasUsed, 50_000, "getOrders(10) exceeds gas ceiling");
    }

    /// @notice Benchmarks gas used by getOrders for 100 orders
    function test_gas_getOrders_100() public {
        for (uint256 i = 0; i < 100; ++i) {
            vm.prank(maker);
            board.createOrder(address(tokenA), 100 ether, address(tokenB), 100 ether);
        }

        uint256[] memory ids = new uint256[](100);
        for (uint256 i = 0; i < 100; ++i) {
            ids[i] = i;
        }

        uint256 gasBefore = gasleft();
        board.getOrders(ids);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("getOrders(100) gas:", gasUsed);
        assertLt(gasUsed, 500_000, "getOrders(100) exceeds gas ceiling");
    }

    /// @notice Benchmarks gas used by canFill
    function test_gas_canFill() public {
        vm.prank(maker);
        uint256 orderId = board.createOrder(address(tokenA), 100 ether, address(tokenB), 100 ether);

        uint256 gasBefore = gasleft();
        board.canFill(orderId);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("canFill gas:", gasUsed);
        assertLt(gasUsed, 5000, "canFill exceeds gas ceiling");
    }
}
