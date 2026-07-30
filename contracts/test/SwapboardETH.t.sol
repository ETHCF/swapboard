// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.33;

// solhint-disable use-natspec

import {Test} from "forge-std/Test.sol";
import {Swapboard} from "../src/Swapboard.sol";
import {ISwapboard} from "../src/interfaces/ISwapboard.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockWETH} from "./mocks/MockWETH.sol";

/// @notice Contract that rejects ETH transfers
contract ETHRejecter {
    error RejectETH();

    receive() external payable {
        revert RejectETH();
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

    uint256 public constant ETH_AMOUNT = 1 ether;
    uint256 public constant TOKEN_AMOUNT = 3000e6;

    /// @notice Deploys fixtures for each test
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

    /// @notice Tests createOrderWithEth
    function test_createOrderWithEth() public {
        vm.prank(maker);
        uint256 orderId = board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT);

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

    /// @notice Tests createOrderWithEth wethBalance
    function test_createOrderWithEth_wethBalance() public {
        uint256 wethBefore = weth.balanceOf(address(board));

        vm.prank(maker);
        board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT);

        assertEq(weth.balanceOf(address(board)), wethBefore + ETH_AMOUNT);
    }

    /// @notice Tests createOrderWithEth event
    function test_createOrderWithEth_event() public {
        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderCreated(
            0, maker, address(weth), ETH_AMOUNT, address(token), TOKEN_AMOUNT
        );

        vm.prank(maker);
        board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT);
    }

    /// @notice Tests createOrderWithEth revert zeroETH
    function test_createOrderWithEth_revert_zeroETH() public {
        vm.prank(maker);
        vm.expectRevert(ISwapboard.ZeroETH.selector);
        board.createOrderWithEth{value: 0}(address(token), TOKEN_AMOUNT);
    }

    /// @notice Tests createOrderWithEth revert zeroAddress
    function test_createOrderWithEth_revert_zeroAddress() public {
        vm.prank(maker);
        vm.expectRevert(ISwapboard.ZeroAddress.selector);
        board.createOrderWithEth{value: ETH_AMOUNT}(address(0), TOKEN_AMOUNT);
    }

    /// @notice Tests createOrderWithEth revert zeroAmount
    function test_createOrderWithEth_revert_zeroAmount() public {
        vm.prank(maker);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        board.createOrderWithEth{value: ETH_AMOUNT}(address(token), 0);
    }

    /// @notice Tests createOrderWithEth revert sameToken
    function test_createOrderWithEth_revert_sameToken() public {
        vm.prank(maker);
        vm.expectRevert(ISwapboard.SameToken.selector);
        board.createOrderWithEth{value: ETH_AMOUNT}(address(weth), TOKEN_AMOUNT);
    }

    /// @notice Tests createOrderWithEth revert notAContract
    function test_createOrderWithEth_revert_notAContract() public {
        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotAContract.selector, address(0xDEAD)));
        board.createOrderWithEth{value: ETH_AMOUNT}(address(0xDEAD), TOKEN_AMOUNT);
    }

    /// @notice Tests createOrderWithEth sequentialIds
    function test_createOrderWithEth_sequentialIds() public {
        vm.startPrank(maker);
        uint256 id0 = board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT);
        uint256 id1 = board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT);
        vm.stopPrank();

        assertEq(id0, 0);
        assertEq(id1, 1);
    }

    // ============ fillOrderWithEth ============

    /// @notice Tests fillOrderWithEth
    function test_fillOrderWithEth() public {
        // Maker creates order: sells token, wants WETH
        vm.startPrank(maker);
        token.approve(address(board), TOKEN_AMOUNT);
        uint256 orderId = board.createOrder(address(token), TOKEN_AMOUNT, address(weth), ETH_AMOUNT);
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

    /// @notice Tests fillOrderWithEth event
    function test_fillOrderWithEth_event() public {
        vm.startPrank(maker);
        token.approve(address(board), TOKEN_AMOUNT);
        uint256 orderId = board.createOrder(address(token), TOKEN_AMOUNT, address(weth), ETH_AMOUNT);
        vm.stopPrank();

        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderFilled(orderId, taker);

        vm.prank(taker);
        board.fillOrderWithEth{value: ETH_AMOUNT}(orderId, 0);
    }

    /// @notice Tests fillOrderWithEth revert notWETH
    function test_fillOrderWithEth_revert_notWETH() public {
        // Order wants tokenB, not WETH
        vm.startPrank(maker);
        token.approve(address(board), TOKEN_AMOUNT);
        uint256 orderId = board.createOrder(address(token), TOKEN_AMOUNT, address(tokenB), 1 ether);
        vm.stopPrank();

        vm.prank(taker);
        vm.expectRevert(
            abi.encodeWithSelector(ISwapboard.NotWETH.selector, address(weth), address(tokenB))
        );
        board.fillOrderWithEth{value: 1 ether}(orderId, 0);
    }

    /// @notice Tests fillOrderWithEth revert amountMismatch tooLow
    function test_fillOrderWithEth_revert_amountMismatch_tooLow() public {
        vm.startPrank(maker);
        token.approve(address(board), TOKEN_AMOUNT);
        uint256 orderId = board.createOrder(address(token), TOKEN_AMOUNT, address(weth), ETH_AMOUNT);
        vm.stopPrank();

        vm.prank(taker);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISwapboard.ETHAmountMismatch.selector, ETH_AMOUNT, ETH_AMOUNT - 1
            )
        );
        board.fillOrderWithEth{value: ETH_AMOUNT - 1}(orderId, 0);
    }

    /// @notice Tests fillOrderWithEth revert amountMismatch tooHigh
    function test_fillOrderWithEth_revert_amountMismatch_tooHigh() public {
        vm.startPrank(maker);
        token.approve(address(board), TOKEN_AMOUNT);
        uint256 orderId = board.createOrder(address(token), TOKEN_AMOUNT, address(weth), ETH_AMOUNT);
        vm.stopPrank();

        vm.prank(taker);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISwapboard.ETHAmountMismatch.selector, ETH_AMOUNT, ETH_AMOUNT + 1
            )
        );
        board.fillOrderWithEth{value: ETH_AMOUNT + 1}(orderId, 0);
    }

    /// @notice Tests fillOrderWithEth revert orderNotFound
    function test_fillOrderWithEth_revert_orderNotFound() public {
        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, 999));
        board.fillOrderWithEth{value: ETH_AMOUNT}(999, 0);
    }

    /// @notice Tests fillOrderWithEth revert orderNotActive
    function test_fillOrderWithEth_revert_orderNotActive() public {
        vm.startPrank(maker);
        token.approve(address(board), TOKEN_AMOUNT);
        uint256 orderId = board.createOrder(address(token), TOKEN_AMOUNT, address(weth), ETH_AMOUNT);
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

    /// @notice Tests cancelOrderUnwrap
    function test_cancelOrderUnwrap() public {
        vm.prank(maker);
        uint256 orderId = board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT);

        uint256 makerEthBefore = maker.balance;

        vm.prank(maker);
        board.cancelOrderUnwrap(orderId);

        ISwapboard.Order memory order = board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(maker.balance, makerEthBefore + ETH_AMOUNT);
        assertEq(weth.balanceOf(address(board)), 0);
    }

    /// @notice Tests cancelOrderUnwrap event
    function test_cancelOrderUnwrap_event() public {
        vm.prank(maker);
        uint256 orderId = board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT);

        vm.expectEmit(true, false, false, true);
        emit ISwapboard.OrderCanceled(orderId);

        vm.prank(maker);
        board.cancelOrderUnwrap(orderId);
    }

    /// @notice Tests cancelOrderUnwrap revert notWETH
    function test_cancelOrderUnwrap_revert_notWETH() public {
        // Create a regular ERC20 order
        vm.startPrank(maker);
        token.approve(address(board), TOKEN_AMOUNT);
        uint256 orderId = board.createOrder(address(token), TOKEN_AMOUNT, address(weth), ETH_AMOUNT);
        vm.stopPrank();

        vm.prank(maker);
        vm.expectRevert(
            abi.encodeWithSelector(ISwapboard.NotWETH.selector, address(weth), address(token))
        );
        board.cancelOrderUnwrap(orderId);
    }

    /// @notice Tests cancelOrderUnwrap revert notMaker
    function test_cancelOrderUnwrap_revert_notMaker() public {
        vm.prank(maker);
        uint256 orderId = board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT);

        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotMaker.selector, orderId, taker, maker));
        board.cancelOrderUnwrap(orderId);
    }

    /// @notice Tests cancelOrderUnwrap revert orderNotFound
    function test_cancelOrderUnwrap_revert_orderNotFound() public {
        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, 999));
        board.cancelOrderUnwrap(999);
    }

    /// @notice Tests cancelOrderUnwrap revert orderNotActive
    function test_cancelOrderUnwrap_revert_orderNotActive() public {
        vm.prank(maker);
        uint256 orderId = board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT);

        vm.prank(maker);
        board.cancelOrderUnwrap(orderId);

        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        board.cancelOrderUnwrap(orderId);
    }

    /// @notice Tests cancelOrderUnwrap revert ethTransferFailed
    function test_cancelOrderUnwrap_revert_ethTransferFailed() public {
        ETHRejecter rejecter = new ETHRejecter();
        vm.deal(address(rejecter), 10 ether);

        vm.prank(address(rejecter));
        uint256 orderId = board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT);

        vm.prank(address(rejecter));
        vm.expectRevert(
            abi.encodeWithSelector(ISwapboard.ETHTransferFailed.selector, address(rejecter))
        );
        board.cancelOrderUnwrap(orderId);
    }

    // ============ fillOrderUnwrap ============

    /// @notice Tests fillOrderUnwrap
    function test_fillOrderUnwrap() public {
        // Maker creates WETH order
        vm.prank(maker);
        uint256 orderId = board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT);

        uint256 takerEthBefore = taker.balance;
        uint256 makerTokenBefore = token.balanceOf(maker);

        vm.startPrank(taker);
        token.approve(address(board), TOKEN_AMOUNT);
        board.fillOrderUnwrap(orderId, 0);
        vm.stopPrank();

        ISwapboard.Order memory order = board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(taker.balance, takerEthBefore + ETH_AMOUNT);
        assertEq(token.balanceOf(maker), makerTokenBefore + TOKEN_AMOUNT);
        assertEq(weth.balanceOf(address(board)), 0);
    }

    /// @notice Tests fillOrderUnwrap event
    function test_fillOrderUnwrap_event() public {
        vm.prank(maker);
        uint256 orderId = board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT);

        vm.startPrank(taker);
        token.approve(address(board), TOKEN_AMOUNT);

        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderFilled(orderId, taker);
        board.fillOrderUnwrap(orderId, 0);
        vm.stopPrank();
    }

    /// @notice Tests fillOrderUnwrap revert notWETH
    function test_fillOrderUnwrap_revert_notWETH() public {
        // Create a regular ERC20 order (tokenA is not WETH)
        vm.startPrank(maker);
        token.approve(address(board), TOKEN_AMOUNT);
        uint256 orderId = board.createOrder(address(token), TOKEN_AMOUNT, address(tokenB), 1 ether);
        vm.stopPrank();

        vm.prank(taker);
        vm.expectRevert(
            abi.encodeWithSelector(ISwapboard.NotWETH.selector, address(weth), address(token))
        );
        board.fillOrderUnwrap(orderId, 0);
    }

    /// @notice Tests fillOrderUnwrap revert orderNotFound
    function test_fillOrderUnwrap_revert_orderNotFound() public {
        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, 999));
        board.fillOrderUnwrap(999, 0);
    }

    /// @notice Tests fillOrderUnwrap revert orderNotActive
    function test_fillOrderUnwrap_revert_orderNotActive() public {
        vm.prank(maker);
        uint256 orderId = board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT);

        vm.startPrank(taker);
        token.approve(address(board), TOKEN_AMOUNT);
        board.fillOrderUnwrap(orderId, 0);
        vm.stopPrank();

        vm.prank(taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        board.fillOrderUnwrap(orderId, 0);
    }

    /// @notice Tests fillOrderUnwrap revert ethTransferFailed
    function test_fillOrderUnwrap_revert_ethTransferFailed() public {
        vm.prank(maker);
        uint256 orderId = board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT);

        ETHRejecter rejecter = new ETHRejecter();
        token.mint(address(rejecter), TOKEN_AMOUNT);

        // Approve from rejecter
        vm.startPrank(address(rejecter));
        token.approve(address(board), TOKEN_AMOUNT);
        vm.expectRevert(
            abi.encodeWithSelector(ISwapboard.ETHTransferFailed.selector, address(rejecter))
        );
        board.fillOrderUnwrap(orderId, 0);
        vm.stopPrank();
    }

    // ============ receive ============

    /// @notice Tests receive reverts when ETH is sent by a non-WETH caller
    function test_receive_revert_nonWETH() public {
        vm.prank(maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotWETH.selector, address(weth), maker));
        (bool success,) = address(board).call{value: 1 ether}("");
        // The call itself reverts inside the contract, but the vm.expectRevert
        // catches it before the success check
        success; // silence unused variable warning
    }

    // ============ Cross-function interop ============

    /// @notice Tests createWithEth fillNormal
    function test_createWithEth_fillNormal() public {
        // Create with ETH, fill with normal fillOrder (taker gets WETH)
        vm.prank(maker);
        uint256 orderId = board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT);

        uint256 takerWethBefore = weth.balanceOf(taker);

        vm.startPrank(taker);
        token.approve(address(board), TOKEN_AMOUNT);
        board.fillOrder(orderId, 0);
        vm.stopPrank();

        assertEq(weth.balanceOf(taker), takerWethBefore + ETH_AMOUNT);
    }

    /// @notice Tests createWithEth cancelNormal
    function test_createWithEth_cancelNormal() public {
        // Create with ETH, cancel with normal cancelOrder (maker gets WETH)
        vm.prank(maker);
        uint256 orderId = board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT);

        uint256 makerWethBefore = weth.balanceOf(maker);

        vm.prank(maker);
        board.cancelOrder(orderId);

        assertEq(weth.balanceOf(maker), makerWethBefore + ETH_AMOUNT);
    }

    /// @notice Tests createNormal fillWithEth
    function test_createNormal_fillWithEth() public {
        // Create normal order wanting WETH, fill with ETH
        vm.startPrank(maker);
        token.approve(address(board), TOKEN_AMOUNT);
        uint256 orderId = board.createOrder(address(token), TOKEN_AMOUNT, address(weth), ETH_AMOUNT);
        vm.stopPrank();

        uint256 makerWethBefore = weth.balanceOf(maker);
        uint256 takerTokenBefore = token.balanceOf(taker);

        vm.prank(taker);
        board.fillOrderWithEth{value: ETH_AMOUNT}(orderId, 0);

        assertEq(weth.balanceOf(maker), makerWethBefore + ETH_AMOUNT);
        assertEq(token.balanceOf(taker), takerTokenBefore + TOKEN_AMOUNT);
    }

    /// @notice Tests createWithEth fillUnwrap
    function test_createWithEth_fillUnwrap() public {
        // Full ETH round-trip: maker deposits ETH, taker receives ETH
        vm.prank(maker);
        uint256 orderId = board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT);

        uint256 takerEthBefore = taker.balance;

        vm.startPrank(taker);
        token.approve(address(board), TOKEN_AMOUNT);
        board.fillOrderUnwrap(orderId, 0);
        vm.stopPrank();

        assertEq(taker.balance, takerEthBefore + ETH_AMOUNT);
        assertEq(weth.balanceOf(address(board)), 0);
    }

    /// @notice Tests createWithEth cancelUnwrap
    function test_createWithEth_cancelUnwrap() public {
        // Full ETH round-trip: maker deposits ETH, maker cancels and gets ETH back
        uint256 makerEthBefore = maker.balance;

        vm.prank(maker);
        uint256 orderId = board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT);

        assertEq(maker.balance, makerEthBefore - ETH_AMOUNT);

        vm.prank(maker);
        board.cancelOrderUnwrap(orderId);

        assertEq(maker.balance, makerEthBefore);
        assertEq(weth.balanceOf(address(board)), 0);
    }

    /// @notice Tests multipleETHOrders
    function test_multipleETHOrders() public {
        vm.startPrank(maker);
        uint256 id0 = board.createOrderWithEth{value: 1 ether}(address(token), TOKEN_AMOUNT);
        uint256 id1 = board.createOrderWithEth{value: 2 ether}(address(token), TOKEN_AMOUNT);
        uint256 id2 = board.createOrderWithEth{value: 3 ether}(address(token), TOKEN_AMOUNT);
        vm.stopPrank();

        assertEq(weth.balanceOf(address(board)), 6 ether);

        // Cancel one
        vm.prank(maker);
        board.cancelOrderUnwrap(id1);

        assertEq(weth.balanceOf(address(board)), 4 ether);

        // Fill one
        vm.startPrank(taker);
        token.approve(address(board), TOKEN_AMOUNT);
        board.fillOrderUnwrap(id0, 0);
        vm.stopPrank();

        assertEq(weth.balanceOf(address(board)), 3 ether);

        // Remaining order still active
        assertTrue(board.canFill(id2));
        assertFalse(board.canFill(id0));
        assertFalse(board.canFill(id1));
    }

    // ============ Fuzz tests ============

    /// @notice Fuzz tests createOrderWithEth
    function testFuzz_createOrderWithEth(
        uint256 ethAmount,
        uint256 amountB
    ) public {
        ethAmount = bound(ethAmount, 1, 100 ether);
        amountB = bound(amountB, 1, 1e30);

        vm.deal(maker, ethAmount);

        vm.prank(maker);
        uint256 orderId = board.createOrderWithEth{value: ethAmount}(address(token), amountB);

        ISwapboard.Order memory order = board.getOrder(orderId);
        assertEq(order.amountA, ethAmount);
        assertEq(order.amountB, amountB);
        assertEq(order.tokenA, address(weth));
        assertEq(weth.balanceOf(address(board)), ethAmount);
    }

    /// @notice Fuzz tests fillOrderWithEth
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
        uint256 orderId = board.createOrder(address(token), tokenAmount, address(weth), ethAmount);
        vm.stopPrank();

        vm.prank(taker);
        board.fillOrderWithEth{value: ethAmount}(orderId, 0);

        assertEq(weth.balanceOf(maker), makerWethBefore + ethAmount);
        assertEq(token.balanceOf(taker), takerTokenBefore + tokenAmount);
    }

    /// @notice Fuzz tests cancelOrderUnwrap
    function testFuzz_cancelOrderUnwrap(
        uint256 ethAmount
    ) public {
        ethAmount = bound(ethAmount, 1, 100 ether);
        vm.deal(maker, ethAmount);

        vm.prank(maker);
        uint256 orderId = board.createOrderWithEth{value: ethAmount}(address(token), TOKEN_AMOUNT);

        uint256 makerEthBefore = maker.balance;

        vm.prank(maker);
        board.cancelOrderUnwrap(orderId);

        assertEq(maker.balance, makerEthBefore + ethAmount);
    }

    /// @notice Tests fillOrderWithEth revert deadlineExpired
    function test_fillOrderWithEth_revert_deadlineExpired() public {
        vm.startPrank(maker);
        token.approve(address(board), TOKEN_AMOUNT);
        uint256 orderId = board.createOrder(address(token), TOKEN_AMOUNT, address(weth), ETH_AMOUNT);
        vm.stopPrank();

        vm.warp(1000);

        vm.prank(taker);
        vm.expectRevert(ISwapboard.DeadlineExpired.selector);
        board.fillOrderWithEth{value: ETH_AMOUNT}(orderId, 999);
    }

    /// @notice Tests fillOrderUnwrap revert deadlineExpired
    function test_fillOrderUnwrap_revert_deadlineExpired() public {
        vm.prank(maker);
        uint256 orderId = board.createOrderWithEth{value: ETH_AMOUNT}(address(token), TOKEN_AMOUNT);

        vm.warp(1000);

        vm.startPrank(taker);
        token.approve(address(board), TOKEN_AMOUNT);
        vm.expectRevert(ISwapboard.DeadlineExpired.selector);
        board.fillOrderUnwrap(orderId, 999);
        vm.stopPrank();
    }

    /// @notice Fuzz tests fillOrderUnwrap
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
        uint256 orderId = board.createOrderWithEth{value: ethAmount}(address(token), tokenAmount);

        vm.startPrank(taker);
        token.approve(address(board), tokenAmount);
        board.fillOrderUnwrap(orderId, 0);
        vm.stopPrank();

        assertEq(taker.balance, takerEthBefore + ethAmount);
        assertEq(token.balanceOf(maker), makerTokenBefore + tokenAmount);
    }
}
