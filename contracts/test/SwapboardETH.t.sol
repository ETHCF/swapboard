// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.33;

// solhint-disable use-natspec

import {Test} from "forge-std/Test.sol";
import {Swapboard} from "../src/Swapboard.sol";
import {ISwapboard} from "../src/interfaces/ISwapboard.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockWETH} from "./mocks/MockWETH.sol";
import {ETHRejecter} from "./mocks/ETHRejecter.sol";

/// @notice Unit tests for Swapboard native ETH support
contract SwapboardETHTest is Test {
    Swapboard internal _board;
    MockWETH internal _weth;
    MockERC20 internal _token;
    MockERC20 internal _tokenB;

    address internal _maker = address(0x1);
    address internal _taker = address(0x2);

    uint256 private constant ETH_AMOUNT = 1 ether;
    uint256 private constant TOKEN_AMOUNT = 3000e6;

    /// @notice Deploys fixtures for each test
    function setUp() public {
        _weth = new MockWETH();
        _board = new Swapboard(address(_weth));
        _token = new MockERC20("USD Coin", "USDC", 6);
        _tokenB = new MockERC20("Dai", "DAI", 18);

        vm.deal(_maker, 100 ether);
        vm.deal(_taker, 100 ether);
        _token.mint(_maker, TOKEN_AMOUNT * 10);
        _token.mint(_taker, TOKEN_AMOUNT * 10);
    }

    // ============ createOrderWithEth ============

    /// @notice Tests createOrderWithEth
    function test_createOrderWithEth() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrderWithEth{value: ETH_AMOUNT}(address(_token), TOKEN_AMOUNT);

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertEq(order.maker, _maker);
        assertEq(order.tokenA, address(_weth));
        assertEq(order.amountA, ETH_AMOUNT);
        assertEq(order.tokenB, address(_token));
        assertEq(order.amountB, TOKEN_AMOUNT);
        assertTrue(order.active);
        assertEq(orderId, 0);
        assertEq(_board.nextOrderId(), 1);
    }

    /// @notice Tests createOrderWithEth wethBalance
    function test_createOrderWithEth_wethBalance() public {
        uint256 wethBefore = _weth.balanceOf(address(_board));

        vm.prank(_maker);
        _board.createOrderWithEth{value: ETH_AMOUNT}(address(_token), TOKEN_AMOUNT);

        assertEq(_weth.balanceOf(address(_board)), wethBefore + ETH_AMOUNT);
    }

    /// @notice Tests createOrderWithEth event
    function test_createOrderWithEth_event() public {
        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderCreated(
            0, _maker, address(_weth), ETH_AMOUNT, address(_token), TOKEN_AMOUNT
        );

        vm.prank(_maker);
        _board.createOrderWithEth{value: ETH_AMOUNT}(address(_token), TOKEN_AMOUNT);
    }

    /// @notice Tests createOrderWithEth revert zeroETH
    function test_createOrderWithEth_revert_zeroETH() public {
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.ZeroETH.selector);
        _board.createOrderWithEth{value: 0}(address(_token), TOKEN_AMOUNT);
    }

    /// @notice Tests createOrderWithEth revert zeroAddress
    function test_createOrderWithEth_revert_zeroAddress() public {
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.ZeroAddress.selector);
        _board.createOrderWithEth{value: ETH_AMOUNT}(address(0), TOKEN_AMOUNT);
    }

    /// @notice Tests createOrderWithEth revert zeroAmount
    function test_createOrderWithEth_revert_zeroAmount() public {
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.createOrderWithEth{value: ETH_AMOUNT}(address(_token), 0);
    }

    /// @notice Tests createOrderWithEth revert sameToken
    function test_createOrderWithEth_revert_sameToken() public {
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.SameToken.selector);
        _board.createOrderWithEth{value: ETH_AMOUNT}(address(_weth), TOKEN_AMOUNT);
    }

    /// @notice Tests createOrderWithEth revert notAContract
    function test_createOrderWithEth_revert_notAContract() public {
        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotAContract.selector, address(0xDEAD)));
        _board.createOrderWithEth{value: ETH_AMOUNT}(address(0xDEAD), TOKEN_AMOUNT);
    }

    /// @notice Tests createOrderWithEth sequentialIds
    function test_createOrderWithEth_sequentialIds() public {
        vm.startPrank(_maker);
        uint256 id0 = _board.createOrderWithEth{value: ETH_AMOUNT}(address(_token), TOKEN_AMOUNT);
        uint256 id1 = _board.createOrderWithEth{value: ETH_AMOUNT}(address(_token), TOKEN_AMOUNT);
        vm.stopPrank();

        assertEq(id0, 0);
        assertEq(id1, 1);
    }

    // ============ fillOrderWithEth ============

    /// @notice Tests fillOrderWithEth
    function test_fillOrderWithEth() public {
        // Maker creates order: sells _token, wants WETH
        vm.startPrank(_maker);
        _token.approve(address(_board), TOKEN_AMOUNT);
        uint256 orderId = _board.createOrder(address(_token), TOKEN_AMOUNT, address(_weth), ETH_AMOUNT);
        vm.stopPrank();

        uint256 makerWethBefore = _weth.balanceOf(_maker);
        uint256 takerTokenBefore = _token.balanceOf(_taker);

        vm.prank(_taker);
        _board.fillOrderWithEth{value: ETH_AMOUNT}(orderId, 0);

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(_weth.balanceOf(_maker), makerWethBefore + ETH_AMOUNT);
        assertEq(_token.balanceOf(_taker), takerTokenBefore + TOKEN_AMOUNT);
    }

    /// @notice Tests fillOrderWithEth event
    function test_fillOrderWithEth_event() public {
        vm.startPrank(_maker);
        _token.approve(address(_board), TOKEN_AMOUNT);
        uint256 orderId = _board.createOrder(address(_token), TOKEN_AMOUNT, address(_weth), ETH_AMOUNT);
        vm.stopPrank();

        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderFilled(orderId, _taker);

        vm.prank(_taker);
        _board.fillOrderWithEth{value: ETH_AMOUNT}(orderId, 0);
    }

    /// @notice Tests fillOrderWithEth revert notWETH
    function test_fillOrderWithEth_revert_notWETH() public {
        // Order wants _tokenB, not WETH
        vm.startPrank(_maker);
        _token.approve(address(_board), TOKEN_AMOUNT);
        uint256 orderId = _board.createOrder(address(_token), TOKEN_AMOUNT, address(_tokenB), 1 ether);
        vm.stopPrank();

        vm.prank(_taker);
        vm.expectRevert(
            abi.encodeWithSelector(ISwapboard.NotWETH.selector, address(_weth), address(_tokenB))
        );
        _board.fillOrderWithEth{value: 1 ether}(orderId, 0);
    }

    /// @notice Tests fillOrderWithEth revert amountMismatch tooLow
    function test_fillOrderWithEth_revert_amountMismatch_tooLow() public {
        vm.startPrank(_maker);
        _token.approve(address(_board), TOKEN_AMOUNT);
        uint256 orderId = _board.createOrder(address(_token), TOKEN_AMOUNT, address(_weth), ETH_AMOUNT);
        vm.stopPrank();

        vm.prank(_taker);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISwapboard.ETHAmountMismatch.selector, ETH_AMOUNT, ETH_AMOUNT - 1
            )
        );
        _board.fillOrderWithEth{value: ETH_AMOUNT - 1}(orderId, 0);
    }

    /// @notice Tests fillOrderWithEth revert amountMismatch tooHigh
    function test_fillOrderWithEth_revert_amountMismatch_tooHigh() public {
        vm.startPrank(_maker);
        _token.approve(address(_board), TOKEN_AMOUNT);
        uint256 orderId = _board.createOrder(address(_token), TOKEN_AMOUNT, address(_weth), ETH_AMOUNT);
        vm.stopPrank();

        vm.prank(_taker);
        vm.expectRevert(
            abi.encodeWithSelector(
                ISwapboard.ETHAmountMismatch.selector, ETH_AMOUNT, ETH_AMOUNT + 1
            )
        );
        _board.fillOrderWithEth{value: ETH_AMOUNT + 1}(orderId, 0);
    }

    /// @notice Tests fillOrderWithEth revert orderNotFound
    function test_fillOrderWithEth_revert_orderNotFound() public {
        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, 999));
        _board.fillOrderWithEth{value: ETH_AMOUNT}(999, 0);
    }

    /// @notice Tests fillOrderWithEth revert orderNotActive
    function test_fillOrderWithEth_revert_orderNotActive() public {
        vm.startPrank(_maker);
        _token.approve(address(_board), TOKEN_AMOUNT);
        uint256 orderId = _board.createOrder(address(_token), TOKEN_AMOUNT, address(_weth), ETH_AMOUNT);
        vm.stopPrank();

        // Fill once
        vm.prank(_taker);
        _board.fillOrderWithEth{value: ETH_AMOUNT}(orderId, 0);

        // Try to fill again
        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        _board.fillOrderWithEth{value: ETH_AMOUNT}(orderId, 0);
    }

    // ============ cancelOrderUnwrap ============

    /// @notice Tests cancelOrderUnwrap
    function test_cancelOrderUnwrap() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrderWithEth{value: ETH_AMOUNT}(address(_token), TOKEN_AMOUNT);

        uint256 makerEthBefore = _maker.balance;

        vm.prank(_maker);
        _board.cancelOrderUnwrap(orderId);

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(_maker.balance, makerEthBefore + ETH_AMOUNT);
        assertEq(_weth.balanceOf(address(_board)), 0);
    }

    /// @notice Tests cancelOrderUnwrap event
    function test_cancelOrderUnwrap_event() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrderWithEth{value: ETH_AMOUNT}(address(_token), TOKEN_AMOUNT);

        vm.expectEmit(true, false, false, true);
        emit ISwapboard.OrderCanceled(orderId);

        vm.prank(_maker);
        _board.cancelOrderUnwrap(orderId);
    }

    /// @notice Tests cancelOrderUnwrap revert notWETH
    function test_cancelOrderUnwrap_revert_notWETH() public {
        // Create a regular ERC20 order
        vm.startPrank(_maker);
        _token.approve(address(_board), TOKEN_AMOUNT);
        uint256 orderId = _board.createOrder(address(_token), TOKEN_AMOUNT, address(_weth), ETH_AMOUNT);
        vm.stopPrank();

        vm.prank(_maker);
        vm.expectRevert(
            abi.encodeWithSelector(ISwapboard.NotWETH.selector, address(_weth), address(_token))
        );
        _board.cancelOrderUnwrap(orderId);
    }

    /// @notice Tests cancelOrderUnwrap revert notMaker
    function test_cancelOrderUnwrap_revert_notMaker() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrderWithEth{value: ETH_AMOUNT}(address(_token), TOKEN_AMOUNT);

        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotMaker.selector, orderId, _taker, _maker));
        _board.cancelOrderUnwrap(orderId);
    }

    /// @notice Tests cancelOrderUnwrap revert orderNotFound
    function test_cancelOrderUnwrap_revert_orderNotFound() public {
        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, 999));
        _board.cancelOrderUnwrap(999);
    }

    /// @notice Tests cancelOrderUnwrap revert orderNotActive
    function test_cancelOrderUnwrap_revert_orderNotActive() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrderWithEth{value: ETH_AMOUNT}(address(_token), TOKEN_AMOUNT);

        vm.prank(_maker);
        _board.cancelOrderUnwrap(orderId);

        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        _board.cancelOrderUnwrap(orderId);
    }

    /// @notice Tests cancelOrderUnwrap revert ethTransferFailed
    function test_cancelOrderUnwrap_revert_ethTransferFailed() public {
        ETHRejecter rejecter = new ETHRejecter();
        vm.deal(address(rejecter), 10 ether);

        vm.prank(address(rejecter));
        uint256 orderId = _board.createOrderWithEth{value: ETH_AMOUNT}(address(_token), TOKEN_AMOUNT);

        vm.prank(address(rejecter));
        vm.expectRevert(
            abi.encodeWithSelector(ISwapboard.ETHTransferFailed.selector, address(rejecter))
        );
        _board.cancelOrderUnwrap(orderId);
    }

    // ============ fillOrderUnwrap ============

    /// @notice Tests fillOrderUnwrap
    function test_fillOrderUnwrap() public {
        // Maker creates WETH order
        vm.prank(_maker);
        uint256 orderId = _board.createOrderWithEth{value: ETH_AMOUNT}(address(_token), TOKEN_AMOUNT);

        uint256 takerEthBefore = _taker.balance;
        uint256 makerTokenBefore = _token.balanceOf(_maker);

        vm.startPrank(_taker);
        _token.approve(address(_board), TOKEN_AMOUNT);
        _board.fillOrderUnwrap(orderId, 0);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(_taker.balance, takerEthBefore + ETH_AMOUNT);
        assertEq(_token.balanceOf(_maker), makerTokenBefore + TOKEN_AMOUNT);
        assertEq(_weth.balanceOf(address(_board)), 0);
    }

    /// @notice Tests fillOrderUnwrap event
    function test_fillOrderUnwrap_event() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrderWithEth{value: ETH_AMOUNT}(address(_token), TOKEN_AMOUNT);

        vm.startPrank(_taker);
        _token.approve(address(_board), TOKEN_AMOUNT);

        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderFilled(orderId, _taker);
        _board.fillOrderUnwrap(orderId, 0);
        vm.stopPrank();
    }

    /// @notice Tests fillOrderUnwrap revert notWETH
    function test_fillOrderUnwrap_revert_notWETH() public {
        // Create a regular ERC20 order (tokenA is not WETH)
        vm.startPrank(_maker);
        _token.approve(address(_board), TOKEN_AMOUNT);
        uint256 orderId = _board.createOrder(address(_token), TOKEN_AMOUNT, address(_tokenB), 1 ether);
        vm.stopPrank();

        vm.prank(_taker);
        vm.expectRevert(
            abi.encodeWithSelector(ISwapboard.NotWETH.selector, address(_weth), address(_token))
        );
        _board.fillOrderUnwrap(orderId, 0);
    }

    /// @notice Tests fillOrderUnwrap revert orderNotFound
    function test_fillOrderUnwrap_revert_orderNotFound() public {
        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, 999));
        _board.fillOrderUnwrap(999, 0);
    }

    /// @notice Tests fillOrderUnwrap revert orderNotActive
    function test_fillOrderUnwrap_revert_orderNotActive() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrderWithEth{value: ETH_AMOUNT}(address(_token), TOKEN_AMOUNT);

        vm.startPrank(_taker);
        _token.approve(address(_board), TOKEN_AMOUNT);
        _board.fillOrderUnwrap(orderId, 0);
        vm.stopPrank();

        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        _board.fillOrderUnwrap(orderId, 0);
    }

    /// @notice Tests fillOrderUnwrap revert ethTransferFailed
    function test_fillOrderUnwrap_revert_ethTransferFailed() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrderWithEth{value: ETH_AMOUNT}(address(_token), TOKEN_AMOUNT);

        ETHRejecter rejecter = new ETHRejecter();
        _token.mint(address(rejecter), TOKEN_AMOUNT);

        // Approve from rejecter
        vm.startPrank(address(rejecter));
        _token.approve(address(_board), TOKEN_AMOUNT);
        vm.expectRevert(
            abi.encodeWithSelector(ISwapboard.ETHTransferFailed.selector, address(rejecter))
        );
        _board.fillOrderUnwrap(orderId, 0);
        vm.stopPrank();
    }

    // ============ receive ============

    /// @notice Tests receive reverts when ETH is sent by a non-WETH caller
    function test_receive_revert_nonWETH() public {
        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotWETH.selector, address(_weth), _maker));
        (bool success,) = address(_board).call{value: 1 ether}("");
        // The call itself reverts inside the contract, but the vm.expectRevert
        // catches it before the success check
        success; // silence unused variable warning
    }

    // ============ Cross-function interop ============

    /// @notice Tests createWithEth fillNormal
    function test_createWithEth_fillNormal() public {
        // Create with ETH, fill with normal fillOrder (_taker gets WETH)
        vm.prank(_maker);
        uint256 orderId = _board.createOrderWithEth{value: ETH_AMOUNT}(address(_token), TOKEN_AMOUNT);

        uint256 takerWethBefore = _weth.balanceOf(_taker);

        vm.startPrank(_taker);
        _token.approve(address(_board), TOKEN_AMOUNT);
        _board.fillOrder(orderId, 0);
        vm.stopPrank();

        assertEq(_weth.balanceOf(_taker), takerWethBefore + ETH_AMOUNT);
    }

    /// @notice Tests createWithEth cancelNormal
    function test_createWithEth_cancelNormal() public {
        // Create with ETH, cancel with normal cancelOrder (_maker gets WETH)
        vm.prank(_maker);
        uint256 orderId = _board.createOrderWithEth{value: ETH_AMOUNT}(address(_token), TOKEN_AMOUNT);

        uint256 makerWethBefore = _weth.balanceOf(_maker);

        vm.prank(_maker);
        _board.cancelOrder(orderId);

        assertEq(_weth.balanceOf(_maker), makerWethBefore + ETH_AMOUNT);
    }

    /// @notice Tests createNormal fillWithEth
    function test_createNormal_fillWithEth() public {
        // Create normal order wanting WETH, fill with ETH
        vm.startPrank(_maker);
        _token.approve(address(_board), TOKEN_AMOUNT);
        uint256 orderId = _board.createOrder(address(_token), TOKEN_AMOUNT, address(_weth), ETH_AMOUNT);
        vm.stopPrank();

        uint256 makerWethBefore = _weth.balanceOf(_maker);
        uint256 takerTokenBefore = _token.balanceOf(_taker);

        vm.prank(_taker);
        _board.fillOrderWithEth{value: ETH_AMOUNT}(orderId, 0);

        assertEq(_weth.balanceOf(_maker), makerWethBefore + ETH_AMOUNT);
        assertEq(_token.balanceOf(_taker), takerTokenBefore + TOKEN_AMOUNT);
    }

    /// @notice Tests createWithEth fillUnwrap
    function test_createWithEth_fillUnwrap() public {
        // Full ETH round-trip: _maker deposits ETH, _taker receives ETH
        vm.prank(_maker);
        uint256 orderId = _board.createOrderWithEth{value: ETH_AMOUNT}(address(_token), TOKEN_AMOUNT);

        uint256 takerEthBefore = _taker.balance;

        vm.startPrank(_taker);
        _token.approve(address(_board), TOKEN_AMOUNT);
        _board.fillOrderUnwrap(orderId, 0);
        vm.stopPrank();

        assertEq(_taker.balance, takerEthBefore + ETH_AMOUNT);
        assertEq(_weth.balanceOf(address(_board)), 0);
    }

    /// @notice Tests createWithEth cancelUnwrap
    function test_createWithEth_cancelUnwrap() public {
        // Full ETH round-trip: _maker deposits ETH, _maker cancels and gets ETH back
        uint256 makerEthBefore = _maker.balance;

        vm.prank(_maker);
        uint256 orderId = _board.createOrderWithEth{value: ETH_AMOUNT}(address(_token), TOKEN_AMOUNT);

        assertEq(_maker.balance, makerEthBefore - ETH_AMOUNT);

        vm.prank(_maker);
        _board.cancelOrderUnwrap(orderId);

        assertEq(_maker.balance, makerEthBefore);
        assertEq(_weth.balanceOf(address(_board)), 0);
    }

    /// @notice Tests multipleETHOrders
    function test_multipleETHOrders() public {
        vm.startPrank(_maker);
        uint256 id0 = _board.createOrderWithEth{value: 1 ether}(address(_token), TOKEN_AMOUNT);
        uint256 id1 = _board.createOrderWithEth{value: 2 ether}(address(_token), TOKEN_AMOUNT);
        uint256 id2 = _board.createOrderWithEth{value: 3 ether}(address(_token), TOKEN_AMOUNT);
        vm.stopPrank();

        assertEq(_weth.balanceOf(address(_board)), 6 ether);

        // Cancel one
        vm.prank(_maker);
        _board.cancelOrderUnwrap(id1);

        assertEq(_weth.balanceOf(address(_board)), 4 ether);

        // Fill one
        vm.startPrank(_taker);
        _token.approve(address(_board), TOKEN_AMOUNT);
        _board.fillOrderUnwrap(id0, 0);
        vm.stopPrank();

        assertEq(_weth.balanceOf(address(_board)), 3 ether);

        // Remaining order still active
        assertTrue(_board.canFill(id2));
        assertFalse(_board.canFill(id0));
        assertFalse(_board.canFill(id1));
    }

    // ============ Fuzz tests ============

    /// @notice Fuzz tests createOrderWithEth
    function testFuzz_createOrderWithEth(
        uint256 ethAmount,
        uint256 amountB
    ) public {
        ethAmount = bound(ethAmount, 1, 100 ether);
        amountB = bound(amountB, 1, 1e30);

        vm.deal(_maker, ethAmount);

        vm.prank(_maker);
        uint256 orderId = _board.createOrderWithEth{value: ethAmount}(address(_token), amountB);

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertEq(order.amountA, ethAmount);
        assertEq(order.amountB, amountB);
        assertEq(order.tokenA, address(_weth));
        assertEq(_weth.balanceOf(address(_board)), ethAmount);
    }

    /// @notice Fuzz tests fillOrderWithEth
    function testFuzz_fillOrderWithEth(
        uint256 tokenAmount,
        uint256 ethAmount
    ) public {
        tokenAmount = bound(tokenAmount, 1, 1e30);
        ethAmount = bound(ethAmount, 1, 100 ether);

        _token.mint(_maker, tokenAmount);
        vm.deal(_taker, ethAmount);

        uint256 makerWethBefore = _weth.balanceOf(_maker);
        uint256 takerTokenBefore = _token.balanceOf(_taker);

        vm.startPrank(_maker);
        _token.approve(address(_board), tokenAmount);
        uint256 orderId = _board.createOrder(address(_token), tokenAmount, address(_weth), ethAmount);
        vm.stopPrank();

        vm.prank(_taker);
        _board.fillOrderWithEth{value: ethAmount}(orderId, 0);

        assertEq(_weth.balanceOf(_maker), makerWethBefore + ethAmount);
        assertEq(_token.balanceOf(_taker), takerTokenBefore + tokenAmount);
    }

    /// @notice Fuzz tests cancelOrderUnwrap
    function testFuzz_cancelOrderUnwrap(
        uint256 ethAmount
    ) public {
        ethAmount = bound(ethAmount, 1, 100 ether);
        vm.deal(_maker, ethAmount);

        vm.prank(_maker);
        uint256 orderId = _board.createOrderWithEth{value: ethAmount}(address(_token), TOKEN_AMOUNT);

        uint256 makerEthBefore = _maker.balance;

        vm.prank(_maker);
        _board.cancelOrderUnwrap(orderId);

        assertEq(_maker.balance, makerEthBefore + ethAmount);
    }

    /// @notice Tests fillOrderWithEth revert deadlineExpired
    function test_fillOrderWithEth_revert_deadlineExpired() public {
        vm.startPrank(_maker);
        _token.approve(address(_board), TOKEN_AMOUNT);
        uint256 orderId = _board.createOrder(address(_token), TOKEN_AMOUNT, address(_weth), ETH_AMOUNT);
        vm.stopPrank();

        vm.warp(1000);

        vm.prank(_taker);
        vm.expectRevert(ISwapboard.DeadlineExpired.selector);
        _board.fillOrderWithEth{value: ETH_AMOUNT}(orderId, 999);
    }

    /// @notice Tests fillOrderUnwrap revert deadlineExpired
    function test_fillOrderUnwrap_revert_deadlineExpired() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrderWithEth{value: ETH_AMOUNT}(address(_token), TOKEN_AMOUNT);

        vm.warp(1000);

        vm.startPrank(_taker);
        _token.approve(address(_board), TOKEN_AMOUNT);
        vm.expectRevert(ISwapboard.DeadlineExpired.selector);
        _board.fillOrderUnwrap(orderId, 999);
        vm.stopPrank();
    }

    /// @notice Fuzz tests fillOrderUnwrap
    function testFuzz_fillOrderUnwrap(
        uint256 ethAmount,
        uint256 tokenAmount
    ) public {
        ethAmount = bound(ethAmount, 1, 100 ether);
        tokenAmount = bound(tokenAmount, 1, 1e30);

        vm.deal(_maker, ethAmount);
        _token.mint(_taker, tokenAmount);

        uint256 takerEthBefore = _taker.balance;
        uint256 makerTokenBefore = _token.balanceOf(_maker);

        vm.prank(_maker);
        uint256 orderId = _board.createOrderWithEth{value: ethAmount}(address(_token), tokenAmount);

        vm.startPrank(_taker);
        _token.approve(address(_board), tokenAmount);
        _board.fillOrderUnwrap(orderId, 0);
        vm.stopPrank();

        assertEq(_taker.balance, takerEthBefore + ethAmount);
        assertEq(_token.balanceOf(_maker), makerTokenBefore + tokenAmount);
    }
}
