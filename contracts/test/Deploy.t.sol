// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../script/Deploy.s.sol";
import {Swapboard} from "../src/Swapboard.sol";
import {ISwapboard} from "../src/interfaces/ISwapboard.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @notice Unit tests for the Deploy script
contract DeployTest is Test {
    Deploy internal _deploy;

    /// @notice Deploys the script contract for each test
    function setUp() public {
        _deploy = new Deploy();
    }

    /// @notice run deploys a usable Swapboard at version 2.0.0
    function test_run_deploysSwapboard() public {
        Swapboard board = _deploy.run();

        assertTrue(address(board).code.length > 0);
        assertEq(board.version(), "2.0.0");
        assertEq(board.getEth(), 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
        assertEq(board.getNextOrderId(), 0);
        assertFalse(board.canFill(0));
    }

    /// @notice run can be called repeatedly and returns distinct deployments
    function test_run_deploysIndependentInstances() public {
        Swapboard board0 = _deploy.run();
        Swapboard board1 = _deploy.run();

        assertTrue(address(board0) != address(board1));
        assertEq(board0.getNextOrderId(), 0);
        assertEq(board1.getNextOrderId(), 0);
    }

    /// @notice Deployed Swapboard accepts ETH sell orders via the ETH sentinel
    function test_run_deployedBoardAcceptsEthOrders() public {
        Swapboard board = _deploy.run();
        MockERC20 token = new MockERC20("Token", "TKN", 6);
        address eth = board.getEth();
        address maker = makeAddr("maker");

        vm.deal(maker, 1 ether);

        vm.prank(maker);
        uint256 orderId = board.createOrder{value: 1 ether}(eth, 1 ether, address(token), 100e6);

        ISwapboard.Order memory order = board.getOrder(orderId);
        assertEq(order.maker, maker);
        assertEq(order.tokenA, eth);
        assertEq(order.amountA, 1 ether);
        assertEq(order.tokenB, address(token));
        assertEq(order.amountB, 100e6);
        assertTrue(order.active);
        assertEq(board.getNextOrderId(), 1);
        assertEq(address(board).balance, 1 ether);
    }
}
