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
        uint256 orderId = board.createOrder{value: 1 ether}(
            ISwapboard.CreateOrderParams({
                tokenA: eth, amountA: 1 ether, tokenB: address(token), amountB: 100e6, partialFillAllowed: false
            })
        );

        ISwapboard.Order memory order = board.getOrder(orderId);
        assertEq(order.maker, maker);
        assertEq(order.tokenA, eth);
        assertEq(order.amountA, 1 ether);
        assertEq(order.tokenB, address(token));
        assertEq(order.amountB, 100e6);
        assertEq(order.availableA, 1 ether);
        assertEq(order.availableB, 100e6);
        assertTrue(order.active);
        assertEq(board.getNextOrderId(), 1);
        assertEq(address(board).balance, 1 ether);
    }

    /// @notice Deployed Swapboard can fill and cancel ETH sell orders
    function test_run_deployedBoardFillAndCancelEthOrders() public {
        Swapboard board = _deploy.run();
        MockERC20 token = new MockERC20("Token", "TKN", 6);
        address eth = board.getEth();
        address maker = makeAddr("maker");
        address taker = makeAddr("taker");

        vm.deal(maker, 3 ether);
        token.mint(taker, 200e6);

        vm.startPrank(maker);
        uint256 fillId = board.createOrder{value: 1 ether}(
            ISwapboard.CreateOrderParams({
                tokenA: eth, amountA: 1 ether, tokenB: address(token), amountB: 100e6, partialFillAllowed: false
            })
        );
        uint256 cancelId = board.createOrder{value: 1 ether}(
            ISwapboard.CreateOrderParams({
                tokenA: eth, amountA: 1 ether, tokenB: address(token), amountB: 100e6, partialFillAllowed: false
            })
        );
        vm.stopPrank();

        assertEq(address(board).balance, 2 ether);

        vm.startPrank(taker);
        token.approve(address(board), 100e6);
        board.fillOrder(fillId, 1 ether, 0);
        vm.stopPrank();

        assertFalse(board.canFill(fillId));
        assertEq(taker.balance, 1 ether);
        assertEq(token.balanceOf(maker), 100e6);
        assertEq(address(board).balance, 1 ether);

        uint256 makerEthBefore = maker.balance;
        vm.prank(maker);
        board.cancelOrder(cancelId);

        assertFalse(board.canFill(cancelId));
        assertEq(maker.balance, makerEthBefore + 1 ether);
        assertEq(address(board).balance, 0);
    }

    /// @notice Deployed Swapboard can fill ERC20 orders paid in ETH
    function test_run_deployedBoardFillWantEthOrder() public {
        Swapboard board = _deploy.run();
        MockERC20 token = new MockERC20("Token", "TKN", 6);
        address eth = board.getEth();
        address maker = makeAddr("maker");
        address taker = makeAddr("taker");

        token.mint(maker, 100e6);
        vm.deal(taker, 1 ether);

        vm.startPrank(maker);
        token.approve(address(board), 100e6);
        uint256 orderId = board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(token), amountA: 100e6, tokenB: eth, amountB: 1 ether, partialFillAllowed: false
            })
        );
        vm.stopPrank();

        uint256 makerEthBefore = maker.balance;

        vm.prank(taker);
        board.fillOrder{value: 1 ether}(orderId, 100e6, 0);

        assertFalse(board.canFill(orderId));
        assertEq(maker.balance, makerEthBefore + 1 ether);
        assertEq(token.balanceOf(taker), 100e6);
        assertEq(address(board).balance, 0);
    }
}
