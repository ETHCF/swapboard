// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {Swapboard} from "../src/Swapboard.sol";
import {ISwapboard} from "../src/interfaces/ISwapboard.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockWETH} from "./mocks/MockWETH.sol";

/// @notice Contract that rejects ETH transfers
contract ETHRejecter {
    receive() external payable {
        revert("no ETH");
    }
}

/// @notice Unit tests for Swapboard native ETH support
contract SwapboardETHTest is Test {
    Swapboard public board;
    MockWETH public weth;
    MockERC20 public token;
    MockERC20 public tokenB;

    address public maker = address(0x1);
    address public taker = address(0x2);

    uint256 constant ETH_AMOUNT = 1 ether;
    uint256 constant TOKEN_AMOUNT = 3000e6;

    function setUp() public {
        weth = new MockWETH();
        board = new Swapboard(address(weth));
        token = new MockERC20("USD Coin", "USDC", 6);
        tokenB = new MockERC20("Dai", "DAI", 18);

        vm.deal(maker, 100 ether);
        vm.deal(taker, 100 ether);
        token.mint(maker, TOKEN_AMOUNT * 10);
        token.mint(taker, TOKEN_AMOUNT * 10);
    }

    // ============ createOrderWithEth ============

    function test_createOrderWithEth() public {
        vm.prank(maker);
        uint256 orderId =
            board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, false);

        ISwapboard.Order memory order = board.getOrder(orderId);
        assertEq(order.maker, maker);
        assertEq(order.tokenA, address(weth));
        assertEq(order.amountA, ETH_AMOUNT);
        assertEq(order.tokenB, address(token));
        assertEq(order.amountB, TOKEN_AMOUNT);
        assertTrue(order.active);
        assertEq(orderId, 0);
        assertEq(board.nextOrderId(), 1);
    }

    function test_createOrderWithEth_wethBalance() public {
        uint256 wethBefore = weth.balanceOf(address(board));

        vm.prank(maker);
        board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, false);

        assertEq(weth.balanceOf(address(board)), wethBefore + ETH_AMOUNT);
    }

    function test_createOrderWithEth_event() public {
        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderCreated(
            0, maker, address(weth), ETH_AMOUNT, address(token), TOKEN_AMOUNT, false
        );

        vm.prank(maker);
        board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, false);
    }

    function test_createOrderWithEth_revert_zeroETH() public {
        vm.prank(maker);
        vm.expectRevert(ISwapboard.ZeroETH.selector);
        board.createOrderWithEth{value: 0}(address(token), TOKEN_AMOUNT, false);
    }

    function test_createOrderWithEth_revert_zeroAddress() public {
        vm.prank(maker);
        vm.expectRevert(ISwapboard.ZeroAddress.selector);
        board.createOrderWithEth{value: ETH_AMOUNT}(address(0), TOKEN_AMOUNT, false);
    }

    function test_createOrderWithEth_revert_zeroAmount() public {
        vm.prank(maker);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        board.createOrderWithEth{value: ETH_AMOUNT}(address(token), 0, false);
    }

    function test_createOrderWithEth_revert_sameToken() public {
        vm.prank(maker);
        vm.expectRevert(ISwapboard.SameToken.selector);
        board.createOrderWithEth{value: ETH_AMOUNT}(address(weth), TOKEN_AMOUNT, false);
    }

    function test_createOrderWithEth_revert_notAContract() public {
        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotAContract.selector, address(0xDEAD)));
        board.createOrderWithEth{value: ETH_AMOUNT}(address(0xDEAD), TOKEN_AMOUNT, false);
    }

    function test_createOrderWithEth_sequentialIds() public {
        vm.startPrank(maker);
        uint256 id0 =
            board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, false);
        uint256 id1 =
            board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, false);
        vm.stopPrank();

        assertEq(id0, 0);
        assertEq(id1, 1);
    }

    // ============ fillOrderWithEth ============

    function test_fillOrderWithEth() public {
        // Maker creates order: sells token, wants WETH
        vm.startPrank(maker);
        token.approve(address(board), TOKEN_AMOUNT);
        uint256 orderId =
            board.createOrder(address(token), TOKEN_AMOUNT, address(weth), ETH_AMOUNT, false);
        vm.stopPrank();

        uint256 makerWethBefore = weth.balanceOf(maker);
        uint256 takerTokenBefore = token.balanceOf(taker);

        vm.prank(taker);
        board.fillOrderWithEth{value: ETH_AMOUNT}(orderId, 0);

        ISwapboard.Order memory order = board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(weth.balanceOf(maker), makerWethBefore + ETH_AMOUNT);
        assertEq(token.balanceOf(taker), takerTokenBefore + TOKEN_AMOUNT);
    }

    function test_fillOrderWithEth_event() public {
        vm.startPrank(maker);
        token.approve(address(board), TOKEN_AMOUNT);
        uint256 orderId =
            board.createOrder(address(token), TOKEN_AMOUNT, address(weth), ETH_AMOUNT, false);
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit ISwapboard.OrderFilled(
            orderId, taker, maker, address(token), TOKEN_AMOUNT, address(weth), ETH_AMOUNT
        );

        vm.prank(taker);
        board.fillOrderWithEth{value: ETH_AMOUNT}(orderId, 0);
    }

    function test_fillOrderWithEth_revert_notWETH() public {
        // Order wants tokenB, not WETH
        vm.startPrank(maker);
        token.approve(address(board), TOKEN_AMOUNT);
        uint256 orderId =
            board.createOrder(address(token), TOKEN_AMOUNT, address(tokenB), 1 ether, false);
        vm.stopPrank();

        vm.prank(taker);
        vm.expectRevert(
            abi.encodeWithSelector(ISwapboard.NotWETH.selector, address(weth), address(tokenB))
        );
        board.fillOrderWithEth{value: 1 ether}(orderId, 0);
    }

    function test_fillOrderWithEth_revert_partialNotAllowed() public {
        vm.startPrank(maker);
        token.approve(address(board), TOKEN_AMOUNT);
        uint256 orderId =
            board.createOrder(address(token), TOKEN_AMOUNT, address(weth), ETH_AMOUNT, false);
        vm.stopPrank();

        // msg.value < amountB on a non-partial order reverts
        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.PartialFillNotAllowed.selector, orderId));
        board.fillOrderWithEth{value: ETH_AMOUNT - 1}(orderId, 0);
    }

    function test_fillOrderWithEth_revert_amountMismatch_tooHigh() public {
        vm.startPrank(maker);
        token.approve(address(board), TOKEN_AMOUNT);
        uint256 orderId =
            board.createOrder(address(token), TOKEN_AMOUNT, address(weth), ETH_AMOUNT, false);
        vm.stopPrank();

        vm.prank(taker);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISwapboard.ETHAmountMismatch.selector, ETH_AMOUNT, ETH_AMOUNT + 1
            )
        );
        board.fillOrderWithEth{value: ETH_AMOUNT + 1}(orderId, 0);
    }

    function test_fillOrderWithEth_revert_orderNotFound() public {
        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, 999));
        board.fillOrderWithEth{value: ETH_AMOUNT}(999, 0);
    }

    function test_fillOrderWithEth_revert_orderNotActive() public {
        vm.startPrank(maker);
        token.approve(address(board), TOKEN_AMOUNT);
        uint256 orderId =
            board.createOrder(address(token), TOKEN_AMOUNT, address(weth), ETH_AMOUNT, false);
        vm.stopPrank();

        // Fill once
        vm.prank(taker);
        board.fillOrderWithEth{value: ETH_AMOUNT}(orderId, 0);

        // Try to fill again
        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        board.fillOrderWithEth{value: ETH_AMOUNT}(orderId, 0);
    }

    // ============ cancelOrderUnwrap ============

    function test_cancelOrderUnwrap() public {
        vm.prank(maker);
        uint256 orderId =
            board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, false);

        uint256 makerEthBefore = maker.balance;

        vm.prank(maker);
        board.cancelOrderUnwrap(orderId);

        ISwapboard.Order memory order = board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(maker.balance, makerEthBefore + ETH_AMOUNT);
        assertEq(weth.balanceOf(address(board)), 0);
    }

    function test_cancelOrderUnwrap_event() public {
        vm.prank(maker);
        uint256 orderId =
            board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, false);

        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderCanceled(orderId, maker, address(weth), ETH_AMOUNT);

        vm.prank(maker);
        board.cancelOrderUnwrap(orderId);
    }

    function test_cancelOrderUnwrap_revert_notWETH() public {
        // Create a regular ERC20 order
        vm.startPrank(maker);
        token.approve(address(board), TOKEN_AMOUNT);
        uint256 orderId =
            board.createOrder(address(token), TOKEN_AMOUNT, address(weth), ETH_AMOUNT, false);
        vm.stopPrank();

        vm.prank(maker);
        vm.expectRevert(
            abi.encodeWithSelector(ISwapboard.NotWETH.selector, address(weth), address(token))
        );
        board.cancelOrderUnwrap(orderId);
    }

    function test_cancelOrderUnwrap_revert_notMaker() public {
        vm.prank(maker);
        uint256 orderId =
            board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, false);

        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotMaker.selector, orderId, taker, maker));
        board.cancelOrderUnwrap(orderId);
    }

    function test_cancelOrderUnwrap_revert_orderNotFound() public {
        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, 999));
        board.cancelOrderUnwrap(999);
    }

    function test_cancelOrderUnwrap_revert_orderNotActive() public {
        vm.prank(maker);
        uint256 orderId =
            board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, false);

        vm.prank(maker);
        board.cancelOrderUnwrap(orderId);

        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        board.cancelOrderUnwrap(orderId);
    }

    function test_cancelOrderUnwrap_revert_ethTransferFailed() public {
        ETHRejecter rejecter = new ETHRejecter();
        vm.deal(address(rejecter), 10 ether);

        vm.prank(address(rejecter));
        uint256 orderId =
            board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, false);

        vm.prank(address(rejecter));
        vm.expectRevert(
            abi.encodeWithSelector(ISwapboard.ETHTransferFailed.selector, address(rejecter))
        );
        board.cancelOrderUnwrap(orderId);
    }

    // ============ cancelOrdersUnwrap ============

    function test_cancelOrdersUnwrap_basic() public {
        vm.startPrank(maker);
        uint256 id0 = board.createOrderWithEth{value: 1 ether}(address(token), TOKEN_AMOUNT, false);
        uint256 id1 = board.createOrderWithEth{value: 2 ether}(address(token), TOKEN_AMOUNT, false);
        uint256 id2 = board.createOrderWithEth{value: 3 ether}(address(token), TOKEN_AMOUNT, false);

        uint256 makerEthBefore = maker.balance;

        uint256[] memory ids = new uint256[](3);
        ids[0] = id0;
        ids[1] = id1;
        ids[2] = id2;
        board.cancelOrdersUnwrap(ids);
        vm.stopPrank();

        assertFalse(board.getOrder(id0).active);
        assertFalse(board.getOrder(id1).active);
        assertFalse(board.getOrder(id2).active);
        assertEq(maker.balance, makerEthBefore + 6 ether);
        assertEq(weth.balanceOf(address(board)), 0);
    }

    function test_cancelOrdersUnwrap_empty() public {
        uint256[] memory ids = new uint256[](0);
        board.cancelOrdersUnwrap(ids);
    }

    function test_cancelOrdersUnwrap_events() public {
        vm.startPrank(maker);
        uint256 id0 = board.createOrderWithEth{value: 1 ether}(address(token), TOKEN_AMOUNT, false);
        uint256 id1 = board.createOrderWithEth{value: 2 ether}(address(token), TOKEN_AMOUNT, false);

        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderCanceled(id0, maker, address(weth), 1 ether);
        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderCanceled(id1, maker, address(weth), 2 ether);

        uint256[] memory ids = new uint256[](2);
        ids[0] = id0;
        ids[1] = id1;
        board.cancelOrdersUnwrap(ids);
        vm.stopPrank();
    }

    function test_cancelOrdersUnwrap_revert_notWETH() public {
        vm.startPrank(maker);
        token.approve(address(board), TOKEN_AMOUNT);
        uint256 id0 =
            board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, false);
        uint256 id1 =
            board.createOrder(address(token), TOKEN_AMOUNT, address(weth), ETH_AMOUNT, false);

        uint256[] memory ids = new uint256[](2);
        ids[0] = id0;
        ids[1] = id1;

        vm.expectRevert(
            abi.encodeWithSelector(ISwapboard.NotWETH.selector, address(weth), address(token))
        );
        board.cancelOrdersUnwrap(ids);
        vm.stopPrank();
    }

    function test_cancelOrdersUnwrap_revert_notMaker() public {
        vm.startPrank(maker);
        uint256 id0 =
            board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, false);
        vm.stopPrank();

        uint256[] memory ids = new uint256[](1);
        ids[0] = id0;

        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotMaker.selector, id0, taker, maker));
        board.cancelOrdersUnwrap(ids);
    }

    function test_cancelOrdersUnwrap_atomic_reverts() public {
        vm.startPrank(maker);
        uint256 id0 = board.createOrderWithEth{value: 1 ether}(address(token), TOKEN_AMOUNT, false);
        uint256 id1 = board.createOrderWithEth{value: 2 ether}(address(token), TOKEN_AMOUNT, false);
        board.cancelOrderUnwrap(id1); // pre-cancel id1

        uint256[] memory ids = new uint256[](2);
        ids[0] = id0;
        ids[1] = id1;

        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, id1));
        board.cancelOrdersUnwrap(ids);
        vm.stopPrank();

        // id0 should still be active (atomic rollback)
        assertTrue(board.getOrder(id0).active);
    }

    function test_cancelOrdersUnwrap_afterPartialFill() public {
        vm.startPrank(maker);
        uint256 id0 =
            board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, true);
        uint256 id1 =
            board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, false);
        vm.stopPrank();

        // Partially fill id0
        uint256 halfToken = TOKEN_AMOUNT / 2;
        vm.startPrank(taker);
        token.approve(address(board), halfToken);
        board.fillOrder(id0, 0, halfToken);
        vm.stopPrank();

        uint256 remainingWeth = board.getOrder(id0).amountA;
        uint256 makerEthBefore = maker.balance;

        vm.startPrank(maker);
        uint256[] memory ids = new uint256[](2);
        ids[0] = id0;
        ids[1] = id1;
        board.cancelOrdersUnwrap(ids);
        vm.stopPrank();

        assertEq(maker.balance, makerEthBefore + remainingWeth + ETH_AMOUNT);
    }

    // ============ fillOrderUnwrap ============

    function test_fillOrderUnwrap() public {
        // Maker creates WETH order
        vm.prank(maker);
        uint256 orderId =
            board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, false);

        uint256 takerEthBefore = taker.balance;
        uint256 makerTokenBefore = token.balanceOf(maker);

        vm.startPrank(taker);
        token.approve(address(board), TOKEN_AMOUNT);
        board.fillOrderUnwrap(orderId, 0, 0);
        vm.stopPrank();

        ISwapboard.Order memory order = board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(taker.balance, takerEthBefore + ETH_AMOUNT);
        assertEq(token.balanceOf(maker), makerTokenBefore + TOKEN_AMOUNT);
        assertEq(weth.balanceOf(address(board)), 0);
    }

    function test_fillOrderUnwrap_event() public {
        vm.prank(maker);
        uint256 orderId =
            board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, false);

        vm.startPrank(taker);
        token.approve(address(board), TOKEN_AMOUNT);

        vm.expectEmit(true, true, true, true);
        emit ISwapboard.OrderFilled(
            orderId, taker, maker, address(weth), ETH_AMOUNT, address(token), TOKEN_AMOUNT
        );
        board.fillOrderUnwrap(orderId, 0, 0);
        vm.stopPrank();
    }

    function test_fillOrderUnwrap_revert_notWETH() public {
        // Create a regular ERC20 order (tokenA is not WETH)
        vm.startPrank(maker);
        token.approve(address(board), TOKEN_AMOUNT);
        uint256 orderId =
            board.createOrder(address(token), TOKEN_AMOUNT, address(tokenB), 1 ether, false);
        vm.stopPrank();

        vm.prank(taker);
        vm.expectRevert(
            abi.encodeWithSelector(ISwapboard.NotWETH.selector, address(weth), address(token))
        );
        board.fillOrderUnwrap(orderId, 0, 0);
    }

    function test_fillOrderUnwrap_revert_orderNotFound() public {
        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, 999));
        board.fillOrderUnwrap(999, 0, 0);
    }

    function test_fillOrderUnwrap_revert_orderNotActive() public {
        vm.prank(maker);
        uint256 orderId =
            board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, false);

        vm.startPrank(taker);
        token.approve(address(board), TOKEN_AMOUNT);
        board.fillOrderUnwrap(orderId, 0, 0);
        vm.stopPrank();

        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        board.fillOrderUnwrap(orderId, 0, 0);
    }

    function test_fillOrderUnwrap_revert_ethTransferFailed() public {
        vm.prank(maker);
        uint256 orderId =
            board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, false);

        ETHRejecter rejecter = new ETHRejecter();
        token.mint(address(rejecter), TOKEN_AMOUNT);

        // Approve from rejecter
        vm.startPrank(address(rejecter));
        token.approve(address(board), TOKEN_AMOUNT);
        vm.expectRevert(
            abi.encodeWithSelector(ISwapboard.ETHTransferFailed.selector, address(rejecter))
        );
        board.fillOrderUnwrap(orderId, 0, 0);
        vm.stopPrank();
    }

    // ============ receive ============

    function test_receive_revert_nonWETH() public {
        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotWETH.selector, address(weth), maker));
        (bool success,) = address(board).call{value: 1 ether}("");
        // The call itself reverts inside the contract, but the vm.expectRevert
        // catches it before the success check
        success; // silence unused variable warning
    }

    // ============ Cross-function interop ============

    function test_createWithEth_fillNormal() public {
        // Create with ETH, fill with normal fillOrder (taker gets WETH)
        vm.prank(maker);
        uint256 orderId =
            board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, false);

        uint256 takerWethBefore = weth.balanceOf(taker);

        vm.startPrank(taker);
        token.approve(address(board), TOKEN_AMOUNT);
        board.fillOrder(orderId, 0, 0);
        vm.stopPrank();

        assertEq(weth.balanceOf(taker), takerWethBefore + ETH_AMOUNT);
    }

    function test_createWithEth_cancelNormal() public {
        // Create with ETH, cancel with normal cancelOrder (maker gets WETH)
        vm.prank(maker);
        uint256 orderId =
            board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, false);

        uint256 makerWethBefore = weth.balanceOf(maker);

        vm.prank(maker);
        board.cancelOrder(orderId);

        assertEq(weth.balanceOf(maker), makerWethBefore + ETH_AMOUNT);
    }

    function test_createNormal_fillWithEth() public {
        // Create normal order wanting WETH, fill with ETH
        vm.startPrank(maker);
        token.approve(address(board), TOKEN_AMOUNT);
        uint256 orderId =
            board.createOrder(address(token), TOKEN_AMOUNT, address(weth), ETH_AMOUNT, false);
        vm.stopPrank();

        uint256 makerWethBefore = weth.balanceOf(maker);
        uint256 takerTokenBefore = token.balanceOf(taker);

        vm.prank(taker);
        board.fillOrderWithEth{value: ETH_AMOUNT}(orderId, 0);

        assertEq(weth.balanceOf(maker), makerWethBefore + ETH_AMOUNT);
        assertEq(token.balanceOf(taker), takerTokenBefore + TOKEN_AMOUNT);
    }

    function test_createWithEth_fillUnwrap() public {
        // Full ETH round-trip: maker deposits ETH, taker receives ETH
        vm.prank(maker);
        uint256 orderId =
            board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, false);

        uint256 takerEthBefore = taker.balance;

        vm.startPrank(taker);
        token.approve(address(board), TOKEN_AMOUNT);
        board.fillOrderUnwrap(orderId, 0, 0);
        vm.stopPrank();

        assertEq(taker.balance, takerEthBefore + ETH_AMOUNT);
        assertEq(weth.balanceOf(address(board)), 0);
    }

    function test_createWithEth_cancelUnwrap() public {
        // Full ETH round-trip: maker deposits ETH, maker cancels and gets ETH back
        uint256 makerEthBefore = maker.balance;

        vm.prank(maker);
        uint256 orderId =
            board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, false);

        assertEq(maker.balance, makerEthBefore - ETH_AMOUNT);

        vm.prank(maker);
        board.cancelOrderUnwrap(orderId);

        assertEq(maker.balance, makerEthBefore);
        assertEq(weth.balanceOf(address(board)), 0);
    }

    function test_multipleETHOrders() public {
        vm.startPrank(maker);
        uint256 id0 = board.createOrderWithEth{value: 1 ether}(address(token), TOKEN_AMOUNT, false);
        uint256 id1 = board.createOrderWithEth{value: 2 ether}(address(token), TOKEN_AMOUNT, false);
        uint256 id2 = board.createOrderWithEth{value: 3 ether}(address(token), TOKEN_AMOUNT, false);
        vm.stopPrank();

        assertEq(weth.balanceOf(address(board)), 6 ether);

        // Cancel one
        vm.prank(maker);
        board.cancelOrderUnwrap(id1);

        assertEq(weth.balanceOf(address(board)), 4 ether);

        // Fill one
        vm.startPrank(taker);
        token.approve(address(board), TOKEN_AMOUNT);
        board.fillOrderUnwrap(id0, 0, 0);
        vm.stopPrank();

        assertEq(weth.balanceOf(address(board)), 3 ether);

        // Remaining order still active
        assertTrue(board.canFill(id2));
        assertFalse(board.canFill(id0));
        assertFalse(board.canFill(id1));
    }

    // ============ Fuzz tests ============

    function testFuzz_createOrderWithEth(
        uint256 ethAmount,
        uint256 amountB
    ) public {
        ethAmount = bound(ethAmount, 1, 100 ether);
        amountB = bound(amountB, 1, 1e30);

        vm.deal(maker, ethAmount);

        vm.prank(maker);
        uint256 orderId = board.createOrderWithEth{value: ethAmount}(address(token), amountB, false);

        ISwapboard.Order memory order = board.getOrder(orderId);
        assertEq(order.amountA, ethAmount);
        assertEq(order.amountB, amountB);
        assertEq(order.tokenA, address(weth));
        assertEq(weth.balanceOf(address(board)), ethAmount);
    }

    function testFuzz_fillOrderWithEth(
        uint256 tokenAmount,
        uint256 ethAmount
    ) public {
        tokenAmount = bound(tokenAmount, 1, 1e30);
        ethAmount = bound(ethAmount, 1, 100 ether);

        token.mint(maker, tokenAmount);
        vm.deal(taker, ethAmount);

        uint256 makerWethBefore = weth.balanceOf(maker);
        uint256 takerTokenBefore = token.balanceOf(taker);

        vm.startPrank(maker);
        token.approve(address(board), tokenAmount);
        uint256 orderId =
            board.createOrder(address(token), tokenAmount, address(weth), ethAmount, false);
        vm.stopPrank();

        vm.prank(taker);
        board.fillOrderWithEth{value: ethAmount}(orderId, 0);

        assertEq(weth.balanceOf(maker), makerWethBefore + ethAmount);
        assertEq(token.balanceOf(taker), takerTokenBefore + tokenAmount);
    }

    function testFuzz_cancelOrderUnwrap(
        uint256 ethAmount
    ) public {
        ethAmount = bound(ethAmount, 1, 100 ether);
        vm.deal(maker, ethAmount);

        vm.prank(maker);
        uint256 orderId =
            board.createOrderWithEth{value: ethAmount}(address(token), TOKEN_AMOUNT, false);

        uint256 makerEthBefore = maker.balance;

        vm.prank(maker);
        board.cancelOrderUnwrap(orderId);

        assertEq(maker.balance, makerEthBefore + ethAmount);
    }

    function test_fillOrderWithEth_revert_deadlineExpired() public {
        vm.startPrank(maker);
        token.approve(address(board), TOKEN_AMOUNT);
        uint256 orderId =
            board.createOrder(address(token), TOKEN_AMOUNT, address(weth), ETH_AMOUNT, false);
        vm.stopPrank();

        vm.warp(1000);

        vm.prank(taker);
        vm.expectRevert(ISwapboard.DeadlineExpired.selector);
        board.fillOrderWithEth{value: ETH_AMOUNT}(orderId, 999);
    }

    function test_fillOrderUnwrap_revert_deadlineExpired() public {
        vm.prank(maker);
        uint256 orderId =
            board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, false);

        vm.warp(1000);

        vm.startPrank(taker);
        token.approve(address(board), TOKEN_AMOUNT);
        vm.expectRevert(ISwapboard.DeadlineExpired.selector);
        board.fillOrderUnwrap(orderId, 999, 0);
        vm.stopPrank();
    }

    function testFuzz_fillOrderUnwrap(
        uint256 ethAmount,
        uint256 tokenAmount
    ) public {
        ethAmount = bound(ethAmount, 1, 100 ether);
        tokenAmount = bound(tokenAmount, 1, 1e30);

        vm.deal(maker, ethAmount);
        token.mint(taker, tokenAmount);

        uint256 takerEthBefore = taker.balance;
        uint256 makerTokenBefore = token.balanceOf(maker);

        vm.prank(maker);
        uint256 orderId =
            board.createOrderWithEth{value: ethAmount}(address(token), tokenAmount, false);

        vm.startPrank(taker);
        token.approve(address(board), tokenAmount);
        board.fillOrderUnwrap(orderId, 0, 0);
        vm.stopPrank();

        assertEq(taker.balance, takerEthBefore + ethAmount);
        assertEq(token.balanceOf(maker), makerTokenBefore + tokenAmount);
    }

    // ============ Partial Fill + ETH Interactions ============

    function test_partialFill_thenCancelUnwrap() public {
        // Create ETH order (WETH as tokenA), partial-fillable
        vm.prank(maker);
        uint256 orderId =
            board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, true);

        // Partial fill half
        uint256 halfToken = TOKEN_AMOUNT / 2;
        vm.startPrank(taker);
        token.approve(address(board), halfToken);
        board.fillOrder(orderId, 0, halfToken);
        vm.stopPrank();

        ISwapboard.Order memory order = board.getOrder(orderId);
        uint256 remainingWeth = order.amountA;
        uint256 makerEthBefore = maker.balance;

        // Maker cancels and unwraps remaining WETH to ETH
        vm.prank(maker);
        board.cancelOrderUnwrap(orderId);

        assertEq(maker.balance, makerEthBefore + remainingWeth);
        assertFalse(board.getOrder(orderId).active);
    }

    function test_partialFill_thenFillOrderWithEth() public {
        // Create order: maker sells token, wants WETH as tokenB, partial-fillable
        vm.startPrank(maker);
        token.approve(address(board), TOKEN_AMOUNT);
        uint256 orderId =
            board.createOrder(address(token), TOKEN_AMOUNT, address(weth), ETH_AMOUNT, true);
        vm.stopPrank();

        // Partial fill half via ERC20 WETH path
        uint256 halfEth = ETH_AMOUNT / 2;
        vm.deal(taker, ETH_AMOUNT);
        vm.startPrank(taker);
        weth.deposit{value: halfEth}();
        weth.approve(address(board), halfEth);
        board.fillOrder(orderId, 0, halfEth);
        vm.stopPrank();

        ISwapboard.Order memory order = board.getOrder(orderId);
        uint256 remainEth = order.amountB;

        // Fill the rest with native ETH via fillOrderWithEth
        vm.prank(taker);
        board.fillOrderWithEth{value: remainEth}(orderId, 0);

        assertFalse(board.getOrder(orderId).active);
    }

    function test_partialFill_thenFillOrderUnwrap() public {
        // Create ETH order (WETH as tokenA), partial-fillable
        vm.prank(maker);
        uint256 orderId =
            board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, true);

        // Partial fill half
        uint256 halfToken = TOKEN_AMOUNT / 2;
        vm.startPrank(taker);
        token.approve(address(board), halfToken);
        board.fillOrder(orderId, 0, halfToken);
        vm.stopPrank();

        ISwapboard.Order memory order = board.getOrder(orderId);
        uint256 remainToken = order.amountB;
        uint256 remainWeth = order.amountA;
        uint256 takerEthBefore = taker.balance;

        // Fill the rest via fillOrderUnwrap — taker pays token, receives ETH
        vm.startPrank(taker);
        token.approve(address(board), remainToken);
        board.fillOrderUnwrap(orderId, 0, 0);
        vm.stopPrank();

        assertFalse(board.getOrder(orderId).active);
        assertEq(taker.balance, takerEthBefore + remainWeth);
    }

    function test_createOrderWithEth_partialFillFlag() public {
        vm.prank(maker);
        uint256 orderId =
            board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, true);

        ISwapboard.Order memory order = board.getOrder(orderId);
        assertTrue(order.partialFill);
        assertTrue(order.active);
        assertEq(order.tokenA, address(weth));
    }

    function test_fillOrderWithEth_partialFill() public {
        // Maker sells token, wants WETH, allows partial fills
        vm.startPrank(maker);
        token.approve(address(board), TOKEN_AMOUNT);
        uint256 orderId =
            board.createOrder(address(token), TOKEN_AMOUNT, address(weth), ETH_AMOUNT, true);
        vm.stopPrank();

        uint256 halfEth = ETH_AMOUNT / 2;
        uint256 expectedToken = (halfEth * TOKEN_AMOUNT) / ETH_AMOUNT;
        uint256 takerTokenBefore = token.balanceOf(taker);

        vm.prank(taker);
        board.fillOrderWithEth{value: halfEth}(orderId, 0);

        ISwapboard.Order memory order = board.getOrder(orderId);
        assertTrue(order.active);
        assertEq(order.amountB, ETH_AMOUNT - halfEth);
        assertEq(token.balanceOf(taker), takerTokenBefore + expectedToken);
        assertEq(weth.balanceOf(maker), halfEth);
    }

    function test_fillOrderWithEth_partialFill_event() public {
        vm.startPrank(maker);
        token.approve(address(board), TOKEN_AMOUNT);
        uint256 orderId =
            board.createOrder(address(token), TOKEN_AMOUNT, address(weth), ETH_AMOUNT, true);
        vm.stopPrank();

        uint256 halfEth = ETH_AMOUNT / 2;
        uint256 expectedToken = (halfEth * TOKEN_AMOUNT) / ETH_AMOUNT;

        vm.expectEmit(true, true, true, true);
        emit ISwapboard.OrderPartiallyFilled(
            orderId,
            taker,
            maker,
            address(token),
            expectedToken,
            address(weth),
            halfEth,
            TOKEN_AMOUNT - expectedToken,
            ETH_AMOUNT - halfEth
        );

        vm.prank(taker);
        board.fillOrderWithEth{value: halfEth}(orderId, 0);
    }

    function test_fillOrderWithEth_revert_zeroValue() public {
        vm.startPrank(maker);
        token.approve(address(board), TOKEN_AMOUNT);
        uint256 orderId =
            board.createOrder(address(token), TOKEN_AMOUNT, address(weth), ETH_AMOUNT, true);
        vm.stopPrank();

        vm.prank(taker);
        vm.expectRevert(ISwapboard.ZeroETH.selector);
        board.fillOrderWithEth{value: 0}(orderId, 0);
    }

    function test_fillOrderWithEth_zeroValue_cannotDrainWeth() public {
        // Prove that msg.value == 0 cannot drain WETH held for other orders
        vm.prank(maker);
        uint256 wethOrderId =
            board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, false);

        // Contract now holds 1 ETH as WETH from the above order
        assertEq(weth.balanceOf(address(board)), ETH_AMOUNT);

        // Create another order that wants WETH
        vm.startPrank(maker);
        token.approve(address(board), TOKEN_AMOUNT);
        uint256 targetOrderId =
            board.createOrder(address(token), TOKEN_AMOUNT, address(weth), ETH_AMOUNT, true);
        vm.stopPrank();

        // Attempt free fill with msg.value == 0
        vm.prank(taker);
        vm.expectRevert(ISwapboard.ZeroETH.selector);
        board.fillOrderWithEth{value: 0}(targetOrderId, 0);

        // WETH order is untouched
        assertTrue(board.getOrder(wethOrderId).active);
        assertEq(weth.balanceOf(address(board)), ETH_AMOUNT);
    }

    function test_fillOrderUnwrap_partialFill() public {
        // Maker sells ETH (WETH), wants token, allows partial fills
        vm.prank(maker);
        uint256 orderId =
            board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, true);

        uint256 halfToken = TOKEN_AMOUNT / 2;
        uint256 expectedEth = (halfToken * ETH_AMOUNT) / TOKEN_AMOUNT;
        uint256 takerEthBefore = taker.balance;

        vm.startPrank(taker);
        token.approve(address(board), halfToken);
        board.fillOrderUnwrap(orderId, 0, halfToken);
        vm.stopPrank();

        ISwapboard.Order memory order = board.getOrder(orderId);
        assertTrue(order.active);
        assertEq(order.amountB, TOKEN_AMOUNT - halfToken);
        assertEq(order.amountA, ETH_AMOUNT - expectedEth);
        assertEq(taker.balance, takerEthBefore + expectedEth);
    }

    function test_fillOrderUnwrap_partialFill_event() public {
        vm.prank(maker);
        uint256 orderId =
            board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, true);

        uint256 halfToken = TOKEN_AMOUNT / 2;
        uint256 expectedEth = (halfToken * ETH_AMOUNT) / TOKEN_AMOUNT;

        vm.startPrank(taker);
        token.approve(address(board), halfToken);

        vm.expectEmit(true, true, true, true);
        emit ISwapboard.OrderPartiallyFilled(
            orderId,
            taker,
            maker,
            address(weth),
            expectedEth,
            address(token),
            halfToken,
            ETH_AMOUNT - expectedEth,
            TOKEN_AMOUNT - halfToken
        );
        board.fillOrderUnwrap(orderId, 0, halfToken);
        vm.stopPrank();
    }

    function test_fillOrderUnwrap_revert_partialNotAllowed() public {
        vm.prank(maker);
        uint256 orderId =
            board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, false);

        uint256 halfToken = TOKEN_AMOUNT / 2;
        vm.startPrank(taker);
        token.approve(address(board), halfToken);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.PartialFillNotAllowed.selector, orderId));
        board.fillOrderUnwrap(orderId, 0, halfToken);
        vm.stopPrank();
    }

    function test_fillOrderUnwrap_fullFillViaZero() public {
        vm.prank(maker);
        uint256 orderId =
            board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, false);

        uint256 takerEthBefore = taker.balance;

        vm.startPrank(taker);
        token.approve(address(board), TOKEN_AMOUNT);
        board.fillOrderUnwrap(orderId, 0, 0);
        vm.stopPrank();

        assertFalse(board.getOrder(orderId).active);
        assertEq(taker.balance, takerEthBefore + ETH_AMOUNT);
    }

    function test_fillOrderWithEth_sequentialPartialFills() public {
        // Maker sells token, wants WETH, allows partial fills
        vm.startPrank(maker);
        token.approve(address(board), TOKEN_AMOUNT);
        uint256 orderId =
            board.createOrder(address(token), TOKEN_AMOUNT, address(weth), ETH_AMOUNT, true);
        vm.stopPrank();

        uint256 quarterEth = ETH_AMOUNT / 4;

        // Four partial fills of 0.25 ETH each
        for (uint256 i = 0; i < 4; i++) {
            vm.prank(taker);
            board.fillOrderWithEth{value: quarterEth}(orderId, 0);
        }

        assertFalse(board.getOrder(orderId).active);
        assertEq(weth.balanceOf(maker), ETH_AMOUNT);
    }

    function test_fillOrderUnwrap_partialFill_thenCancel() public {
        vm.prank(maker);
        uint256 orderId =
            board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, true);

        // Partial fill half
        uint256 halfToken = TOKEN_AMOUNT / 2;
        vm.startPrank(taker);
        token.approve(address(board), halfToken);
        board.fillOrderUnwrap(orderId, 0, halfToken);
        vm.stopPrank();

        ISwapboard.Order memory order = board.getOrder(orderId);
        uint256 remainingWeth = order.amountA;
        uint256 makerEthBefore = maker.balance;

        // Maker cancels, gets remaining ETH back
        vm.prank(maker);
        board.cancelOrderUnwrap(orderId);

        assertFalse(board.getOrder(orderId).active);
        assertEq(maker.balance, makerEthBefore + remainingWeth);
    }

    function test_fillOrderWithEth_fullFillOnPartialOrder() public {
        // msg.value == amountB on a partial-fill-enabled order does a full fill
        vm.startPrank(maker);
        token.approve(address(board), TOKEN_AMOUNT);
        uint256 orderId =
            board.createOrder(address(token), TOKEN_AMOUNT, address(weth), ETH_AMOUNT, true);
        vm.stopPrank();

        uint256 takerTokenBefore = token.balanceOf(taker);

        vm.prank(taker);
        board.fillOrderWithEth{value: ETH_AMOUNT}(orderId, 0);

        assertFalse(board.getOrder(orderId).active);
        assertEq(token.balanceOf(taker), takerTokenBefore + TOKEN_AMOUNT);
        assertEq(weth.balanceOf(maker), ETH_AMOUNT);
    }

    function testFuzz_fillOrderWithEth_partial(
        uint256 ethAmount,
        uint256 tokenAmount,
        uint256 fillEth
    ) public {
        ethAmount = bound(ethAmount, 2, 10 ether);
        tokenAmount = bound(tokenAmount, 2, 1e12);
        fillEth = bound(fillEth, 1, ethAmount);

        token.mint(maker, tokenAmount);
        vm.deal(taker, fillEth);

        vm.startPrank(maker);
        token.approve(address(board), tokenAmount);
        uint256 orderId =
            board.createOrder(address(token), tokenAmount, address(weth), ethAmount, true);
        vm.stopPrank();

        uint256 expectedToken;
        if (fillEth >= ethAmount) {
            expectedToken = tokenAmount;
        } else {
            expectedToken = (fillEth * tokenAmount) / ethAmount;
            if (expectedToken == 0) {
                vm.prank(taker);
                vm.expectRevert(ISwapboard.ZeroFillAmount.selector);
                board.fillOrderWithEth{value: fillEth}(orderId, 0);
                return;
            }
        }

        uint256 takerTokenBefore = token.balanceOf(taker);
        uint256 makerWethBefore = weth.balanceOf(maker);

        vm.prank(taker);
        board.fillOrderWithEth{value: fillEth}(orderId, 0);

        assertEq(token.balanceOf(taker) - takerTokenBefore, expectedToken);
        assertEq(weth.balanceOf(maker) - makerWethBefore, fillEth);
    }

    function testFuzz_fillOrderUnwrap_partial(
        uint256 ethAmount,
        uint256 tokenAmount,
        uint256 fillToken
    ) public {
        ethAmount = bound(ethAmount, 2, 10 ether);
        tokenAmount = bound(tokenAmount, 2, 1e12);
        fillToken = bound(fillToken, 1, tokenAmount);

        token.mint(taker, fillToken);
        vm.deal(maker, ethAmount);

        vm.prank(maker);
        uint256 orderId =
            board.createOrderWithEth{value: ethAmount}(address(token), tokenAmount, true);

        uint256 expectedEth;
        if (fillToken >= tokenAmount) {
            expectedEth = ethAmount;
        } else {
            expectedEth = (fillToken * ethAmount) / tokenAmount;
            if (expectedEth == 0) {
                vm.startPrank(taker);
                token.approve(address(board), fillToken);
                vm.expectRevert(ISwapboard.ZeroFillAmount.selector);
                board.fillOrderUnwrap(orderId, 0, fillToken);
                vm.stopPrank();
                return;
            }
        }

        uint256 takerEthBefore = taker.balance;
        uint256 makerTokenBefore = token.balanceOf(maker);

        vm.startPrank(taker);
        token.approve(address(board), fillToken);
        board.fillOrderUnwrap(orderId, 0, fillToken);
        vm.stopPrank();

        assertEq(taker.balance - takerEthBefore, expectedEth);
        assertEq(token.balanceOf(maker) - makerTokenBefore, fillToken);
    }

    // ============ Zeroed state after full fill ============

    function test_fullFill_zerosAmounts() public {
        vm.startPrank(maker);
        token.approve(address(board), TOKEN_AMOUNT);
        uint256 orderId =
            board.createOrder(address(token), TOKEN_AMOUNT, address(weth), ETH_AMOUNT, false);
        vm.stopPrank();

        vm.prank(taker);
        board.fillOrderWithEth{value: ETH_AMOUNT}(orderId, 0);

        ISwapboard.Order memory order = board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(order.amountA, 0);
        assertEq(order.amountB, 0);
    }

    function test_fullFillUnwrap_zerosAmounts() public {
        vm.prank(maker);
        uint256 orderId =
            board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, false);

        vm.startPrank(taker);
        token.approve(address(board), TOKEN_AMOUNT);
        board.fillOrderUnwrap(orderId, 0, 0);
        vm.stopPrank();

        ISwapboard.Order memory order = board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(order.amountA, 0);
        assertEq(order.amountB, 0);
    }

    // ============ Early active check on ETH paths ============

    function test_fillOrderWithEth_revert_cancelledOrder_givesActiveError() public {
        vm.startPrank(maker);
        token.approve(address(board), TOKEN_AMOUNT);
        uint256 orderId =
            board.createOrder(address(token), TOKEN_AMOUNT, address(weth), ETH_AMOUNT, false);
        board.cancelOrder(orderId);
        vm.stopPrank();

        // Should revert with OrderNotActive, not ETHAmountMismatch or other
        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        board.fillOrderWithEth{value: ETH_AMOUNT}(orderId, 0);
    }

    function test_fillOrderUnwrap_revert_cancelledOrder_givesActiveError() public {
        vm.prank(maker);
        uint256 orderId =
            board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT, false);

        vm.prank(maker);
        board.cancelOrderUnwrap(orderId);

        vm.startPrank(taker);
        token.approve(address(board), TOKEN_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        board.fillOrderUnwrap(orderId, 0, 0);
        vm.stopPrank();
    }
}
