// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec

import {Test} from "forge-std/Test.sol";
import {FillTestLib} from "./helpers/FillTestLib.sol";
import {OrderTestLib} from "./helpers/OrderTestLib.sol";
import {Deploy} from "../script/Deploy.s.sol";
import {Swapboard} from "../src/Swapboard.sol";
import {ISwapboard} from "../src/interfaces/ISwapboard.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockPermit2} from "./mocks/MockPermit2.sol";

/// @notice Unit tests for the Deploy script
contract DeployTest is Test {
    address private constant _PERMIT2_ADDR = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    Deploy internal _deploy;

    /// @notice Deploys the script contract and the Permit2 dependency it checks for
    function setUp() public {
        _deploy = new Deploy();

        MockPermit2 impl = new MockPermit2();
        vm.etch(_PERMIT2_ADDR, address(impl).code);
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

    /// @notice run aborts when the canonical Permit2 has no code on the target chain
    function test_run_revert_permit2NotDeployed() public {
        vm.etch(_PERMIT2_ADDR, "");

        vm.expectRevert(abi.encodeWithSelector(Deploy.Permit2NotDeployed.selector, _PERMIT2_ADDR));
        _deploy.run();
    }

    /// @notice Deployed Swapboard accepts ETH sell orders via the ETH sentinel
    function test_run_deployedBoardAcceptsEthOrders() public {
        Swapboard board = _deploy.run();
        MockERC20 token = new MockERC20("Token", "TKN", 6);
        address eth = board.getEth();
        address maker = makeAddr("maker");

        vm.deal(maker, 1 ether);

        vm.prank(maker);
        uint256 orderId = board.createOrder{value: 1 ether}(OrderTestLib.order(eth, 1 ether, address(token), 100e6));

        ISwapboard.Order memory order = board.getOrder(orderId);
        assertEq(order.maker, maker);
        assertEq(order.tokenA, eth);
        assertEq(order.amountA, 1 ether);
        assertEq(order.tokenB, address(token));
        assertEq(order.amountB, 100e6);
        assertEq(order.availableA, 1 ether);
        assertEq(order.availableB, 100e6);
        assertNotEq(order.maker, address(0));
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
        uint256 fillId = board.createOrder{value: 1 ether}(OrderTestLib.order(eth, 1 ether, address(token), 100e6));
        uint256 cancelId = board.createOrder{value: 1 ether}(OrderTestLib.order(eth, 1 ether, address(token), 100e6));
        vm.stopPrank();

        assertEq(address(board).balance, 2 ether);

        vm.startPrank(taker);
        token.approve(address(board), 100e6);
        uint256 tokenPullsBefore = token.getTransferFromCalls();
        FillTestLib.fill(board, fillId, 1 ether);
        vm.stopPrank();

        assertFalse(board.canFill(fillId));
        assertEq(board.getOrder(fillId).availableA, 0);
        assertEq(token.getTransferFromCalls(), tokenPullsBefore + 1);
        assertEq(taker.balance, 1 ether);
        assertEq(token.balanceOf(maker), 100e6);
        assertEq(address(board).balance, 1 ether);

        uint256 makerEthBefore = maker.balance;
        vm.prank(maker);
        board.cancelOrder(cancelId, address(0));

        assertFalse(board.canFill(cancelId));
        assertEq(board.getOrder(cancelId).availableA, 0);
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
        uint256 orderId = board.createOrder(OrderTestLib.order(address(token), 100e6, eth, 1 ether));
        vm.stopPrank();

        assertEq(token.getTransferFromCalls(), 1);

        uint256 makerEthBefore = maker.balance;
        uint256 tokenPullsBefore = token.getTransferFromCalls();

        vm.startPrank(taker);
        FillTestLib.fillPayEth(board, orderId, 100e6, 1 ether);
        vm.stopPrank();

        assertFalse(board.canFill(orderId));
        assertEq(board.getOrder(orderId).availableA, 0);
        assertEq(token.getTransferFromCalls(), tokenPullsBefore);
        assertEq(maker.balance, makerEthBefore + 1 ether);
        assertEq(token.balanceOf(taker), 100e6);
        assertEq(address(board).balance, 0);
    }
}
