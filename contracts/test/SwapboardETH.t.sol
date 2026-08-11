// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec

import {Test} from "forge-std/Test.sol";
import {Swapboard} from "../src/Swapboard.sol";
import {ISwapboard} from "../src/interfaces/ISwapboard.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ETHRejecter} from "./mocks/ETHRejecter.sol";

/// @notice Unit tests for Swapboard native ETH support via the ETH sentinel
contract SwapboardETHTest is Test {
    Swapboard internal _board;
    MockERC20 internal _token;
    MockERC20 internal _tokenB;

    address internal _eth;
    address internal _maker = address(0x1);
    address internal _taker = address(0x2);

    uint256 private constant ETH_AMOUNT = 1 ether;
    uint256 private constant TOKEN_AMOUNT = 3000e6;

    /// @notice Deploys fixtures for each test
    function setUp() public {
        _board = new Swapboard();
        _eth = _board.getEth();
        _token = new MockERC20("USD Coin", "USDC", 6);
        _tokenB = new MockERC20("Dai", "DAI", 18);

        vm.deal(_maker, 100 ether);
        vm.deal(_taker, 100 ether);
        _token.mint(_maker, TOKEN_AMOUNT * 10);
        _token.mint(_taker, TOKEN_AMOUNT * 10);
    }

    // ============ createOrder with ETH as tokenA ============

    /// @notice Tests createOrder selling ETH
    function test_createOrder_sellEth() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_token), TOKEN_AMOUNT);

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertEq(order.maker, _maker);
        assertEq(order.tokenA, _eth);
        assertEq(order.amountA, ETH_AMOUNT);
        assertEq(order.tokenB, address(_token));
        assertEq(order.amountB, TOKEN_AMOUNT);
        assertTrue(order.active);
        assertEq(orderId, 0);
        assertEq(_board.getNextOrderId(), 1);
        assertEq(address(_board).balance, ETH_AMOUNT);
    }

    /// @notice Tests createOrder selling ETH reverts on overpayment
    function test_createOrder_sellEth_revert_amountMismatch_tooHigh() public {
        vm.prank(_maker);
        vm.expectRevert(
            abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, ETH_AMOUNT, ETH_AMOUNT + 0.5 ether)
        );
        _board.createOrder{value: ETH_AMOUNT + 0.5 ether}(_eth, ETH_AMOUNT, address(_token), TOKEN_AMOUNT);
    }

    /// @notice Tests createOrder selling ETH emits OrderCreated
    function test_createOrder_sellEth_event() public {
        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderCreated({
            orderId: 0, maker: _maker, tokenA: _eth, amountA: ETH_AMOUNT, tokenB: address(_token), amountB: TOKEN_AMOUNT
        });

        vm.prank(_maker);
        _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_token), TOKEN_AMOUNT);
    }

    /// @notice Tests createOrder selling ETH reverts on underpayment
    function test_createOrder_sellEth_revert_amountMismatch() public {
        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, ETH_AMOUNT, ETH_AMOUNT - 1));
        _board.createOrder{value: ETH_AMOUNT - 1}(_eth, ETH_AMOUNT, address(_token), TOKEN_AMOUNT);
    }

    /// @notice Tests createOrder selling ETH reverts on zero amount
    function test_createOrder_sellEth_revert_zeroAmount() public {
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.createOrder{value: 0}(_eth, 0, address(_token), TOKEN_AMOUNT);
    }

    /// @notice Tests createOrder selling ETH reverts on zero address tokenB
    function test_createOrder_sellEth_revert_zeroAddress() public {
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.ZeroAddress.selector);
        _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(0), TOKEN_AMOUNT);
    }

    /// @notice Tests createOrder selling ETH reverts when tokenB is also ETH
    function test_createOrder_sellEth_revert_sameToken() public {
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.SameToken.selector);
        _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, _eth, TOKEN_AMOUNT);
    }

    /// @notice Tests createOrder selling ETH reverts when tokenB is an EOA
    function test_createOrder_sellEth_revert_notAContract() public {
        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotAContract.selector, address(0xDEAD)));
        _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(0xDEAD), TOKEN_AMOUNT);
    }

    /// @notice Tests createOrder selling ETH assigns sequential IDs
    function test_createOrder_sellEth_sequentialIds() public {
        vm.startPrank(_maker);
        uint256 id0 = _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_token), TOKEN_AMOUNT);
        uint256 id1 = _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_token), TOKEN_AMOUNT);
        vm.stopPrank();

        assertEq(id0, 0);
        assertEq(id1, 1);
        assertEq(address(_board).balance, 2 * ETH_AMOUNT);
    }

    /// @notice Tests createOrder with ERC20 reverts if ETH is sent
    function test_createOrder_erc20_revert_accidentalEth() public {
        vm.startPrank(_maker);
        _token.approve(address(_board), TOKEN_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, 0, 1 ether));
        _board.createOrder{value: 1 ether}(address(_token), TOKEN_AMOUNT, address(_tokenB), 1 ether);
        vm.stopPrank();
    }

    // ============ fillOrder paying with ETH ============

    /// @notice Tests fillOrder when tokenB is ETH
    function test_fillOrder_payEth() public {
        vm.startPrank(_maker);
        _token.approve(address(_board), TOKEN_AMOUNT);
        uint256 orderId = _board.createOrder(address(_token), TOKEN_AMOUNT, _eth, ETH_AMOUNT);
        vm.stopPrank();

        uint256 makerEthBefore = _maker.balance;
        uint256 takerTokenBefore = _token.balanceOf(_taker);

        vm.prank(_taker);
        _board.fillOrder{value: ETH_AMOUNT}(orderId, 0);

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(_maker.balance, makerEthBefore + ETH_AMOUNT);
        assertEq(_token.balanceOf(_taker), takerTokenBefore + TOKEN_AMOUNT);
        assertEq(address(_board).balance, 0);
    }

    /// @notice Tests fillOrder paying ETH reverts on overpayment
    function test_fillOrder_payEth_revert_amountMismatch_tooHigh() public {
        vm.startPrank(_maker);
        _token.approve(address(_board), TOKEN_AMOUNT);
        uint256 orderId = _board.createOrder(address(_token), TOKEN_AMOUNT, _eth, ETH_AMOUNT);
        vm.stopPrank();

        vm.prank(_taker);
        vm.expectRevert(
            abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, ETH_AMOUNT, ETH_AMOUNT + 0.25 ether)
        );
        _board.fillOrder{value: ETH_AMOUNT + 0.25 ether}(orderId, 0);
    }

    /// @notice Tests fillOrder paying ETH emits OrderFilled
    function test_fillOrder_payEth_event() public {
        vm.startPrank(_maker);
        _token.approve(address(_board), TOKEN_AMOUNT);
        uint256 orderId = _board.createOrder(address(_token), TOKEN_AMOUNT, _eth, ETH_AMOUNT);
        vm.stopPrank();

        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderFilled({orderId: orderId, taker: _taker});

        vm.prank(_taker);
        _board.fillOrder{value: ETH_AMOUNT}(orderId, 0);
    }

    /// @notice Tests fillOrder paying ETH reverts on underpayment
    function test_fillOrder_payEth_revert_amountMismatch_tooLow() public {
        vm.startPrank(_maker);
        _token.approve(address(_board), TOKEN_AMOUNT);
        uint256 orderId = _board.createOrder(address(_token), TOKEN_AMOUNT, _eth, ETH_AMOUNT);
        vm.stopPrank();

        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, ETH_AMOUNT, ETH_AMOUNT - 1));
        _board.fillOrder{value: ETH_AMOUNT - 1}(orderId, 0);
    }

    /// @notice Tests fillOrder paying ETH reverts when order not found
    function test_fillOrder_payEth_revert_orderNotFound() public {
        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, 999));
        _board.fillOrder{value: ETH_AMOUNT}(999, 0);
    }

    /// @notice Tests fillOrder paying ETH reverts when order not active
    function test_fillOrder_payEth_revert_orderNotActive() public {
        vm.startPrank(_maker);
        _token.approve(address(_board), TOKEN_AMOUNT);
        uint256 orderId = _board.createOrder(address(_token), TOKEN_AMOUNT, _eth, ETH_AMOUNT);
        vm.stopPrank();

        vm.prank(_taker);
        _board.fillOrder{value: ETH_AMOUNT}(orderId, 0);

        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        _board.fillOrder{value: ETH_AMOUNT}(orderId, 0);
    }

    /// @notice Tests fillOrder paying ETH reverts after deadline
    function test_fillOrder_payEth_revert_deadlineExpired() public {
        vm.startPrank(_maker);
        _token.approve(address(_board), TOKEN_AMOUNT);
        uint256 orderId = _board.createOrder(address(_token), TOKEN_AMOUNT, _eth, ETH_AMOUNT);
        vm.stopPrank();

        vm.warp(1000);

        vm.prank(_taker);
        vm.expectRevert(ISwapboard.DeadlineExpired.selector);
        _board.fillOrder{value: ETH_AMOUNT}(orderId, 999);
    }

    /// @notice Tests fillOrder with ERC20 tokenB reverts if ETH is sent
    function test_fillOrder_erc20_revert_accidentalEth() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_token), TOKEN_AMOUNT);

        vm.startPrank(_taker);
        _token.approve(address(_board), TOKEN_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, 0, 0.1 ether));
        _board.fillOrder{value: 0.1 ether}(orderId, 0);
        vm.stopPrank();
    }

    // ============ cancelOrder returning ETH ============

    /// @notice Tests cancelOrder returns ETH to maker
    function test_cancelOrder_returnEth() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_token), TOKEN_AMOUNT);

        uint256 makerEthBefore = _maker.balance;

        vm.prank(_maker);
        _board.cancelOrder(orderId);

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(_maker.balance, makerEthBefore + ETH_AMOUNT);
        assertEq(address(_board).balance, 0);
    }

    /// @notice Tests cancelOrder returning ETH emits OrderCanceled
    function test_cancelOrder_returnEth_event() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_token), TOKEN_AMOUNT);

        vm.expectEmit(true, false, false, true);
        emit ISwapboard.OrderCanceled({orderId: orderId});

        vm.prank(_maker);
        _board.cancelOrder(orderId);
    }

    /// @notice Tests cancelOrder returning ETH reverts when not maker
    function test_cancelOrder_returnEth_revert_notMaker() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_token), TOKEN_AMOUNT);

        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotMaker.selector, orderId, _taker, _maker));
        _board.cancelOrder(orderId);
    }

    /// @notice Tests cancelOrder returning ETH reverts when order not found
    function test_cancelOrder_returnEth_revert_orderNotFound() public {
        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, 999));
        _board.cancelOrder(999);
    }

    /// @notice Tests cancelOrder returning ETH reverts when order not active
    function test_cancelOrder_returnEth_revert_orderNotActive() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_token), TOKEN_AMOUNT);

        vm.prank(_maker);
        _board.cancelOrder(orderId);

        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        _board.cancelOrder(orderId);
    }

    /// @notice Tests cancelOrder reverts when maker rejects ETH
    function test_cancelOrder_returnEth_revert_ethTransferFailed() public {
        ETHRejecter rejecter = new ETHRejecter();
        vm.deal(address(rejecter), 10 ether);

        vm.prank(address(rejecter));
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_token), TOKEN_AMOUNT);

        vm.prank(address(rejecter));
        vm.expectRevert(ETHRejecter.RejectETH.selector);
        _board.cancelOrder(orderId);
    }

    // ============ fillOrder receiving ETH ============

    /// @notice Tests fillOrder when tokenA is ETH
    function test_fillOrder_receiveEth() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_token), TOKEN_AMOUNT);

        uint256 takerEthBefore = _taker.balance;
        uint256 makerTokenBefore = _token.balanceOf(_maker);

        vm.startPrank(_taker);
        _token.approve(address(_board), TOKEN_AMOUNT);
        _board.fillOrder(orderId, 0);
        vm.stopPrank();

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertFalse(order.active);
        assertEq(_taker.balance, takerEthBefore + ETH_AMOUNT);
        assertEq(_token.balanceOf(_maker), makerTokenBefore + TOKEN_AMOUNT);
        assertEq(address(_board).balance, 0);
    }

    /// @notice Tests fillOrder receiving ETH emits OrderFilled
    function test_fillOrder_receiveEth_event() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_token), TOKEN_AMOUNT);

        vm.startPrank(_taker);
        _token.approve(address(_board), TOKEN_AMOUNT);

        vm.expectEmit(true, true, false, true);
        emit ISwapboard.OrderFilled({orderId: orderId, taker: _taker});
        _board.fillOrder(orderId, 0);
        vm.stopPrank();
    }

    /// @notice Tests fillOrder receiving ETH reverts when order not found
    function test_fillOrder_receiveEth_revert_orderNotFound() public {
        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotFound.selector, 999));
        _board.fillOrder(999, 0);
    }

    /// @notice Tests fillOrder receiving ETH reverts when order not active
    function test_fillOrder_receiveEth_revert_orderNotActive() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_token), TOKEN_AMOUNT);

        vm.startPrank(_taker);
        _token.approve(address(_board), TOKEN_AMOUNT);
        _board.fillOrder(orderId, 0);
        vm.stopPrank();

        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.OrderNotActive.selector, orderId));
        _board.fillOrder(orderId, 0);
    }

    /// @notice Tests fillOrder receiving ETH reverts when taker rejects ETH
    function test_fillOrder_receiveEth_revert_ethTransferFailed() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_token), TOKEN_AMOUNT);

        ETHRejecter rejecter = new ETHRejecter();
        _token.mint(address(rejecter), TOKEN_AMOUNT);

        vm.startPrank(address(rejecter));
        _token.approve(address(_board), TOKEN_AMOUNT);
        vm.expectRevert(ETHRejecter.RejectETH.selector);
        _board.fillOrder(orderId, 0);
        vm.stopPrank();
    }

    /// @notice Tests fillOrder receiving ETH reverts after deadline
    function test_fillOrder_receiveEth_revert_deadlineExpired() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_token), TOKEN_AMOUNT);

        vm.warp(1000);

        vm.startPrank(_taker);
        _token.approve(address(_board), TOKEN_AMOUNT);
        vm.expectRevert(ISwapboard.DeadlineExpired.selector);
        _board.fillOrder(orderId, 999);
        vm.stopPrank();
    }

    // ============ No receive() ============

    /// @notice Tests plain ETH transfers to the contract revert (no receive/fallback)
    function test_plainEthTransfer_reverts() public {
        vm.prank(_maker);
        vm.expectRevert();
        (bool success,) = address(_board).call{value: 1 ether}("");
        success; // silence unused if expectRevert somehow skipped
    }

    // ============ Round-trips ============

    /// @notice Tests full ETH sell then ERC20 fill
    function test_roundTrip_sellEth_fillWithToken() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_token), TOKEN_AMOUNT);

        uint256 takerEthBefore = _taker.balance;

        vm.startPrank(_taker);
        _token.approve(address(_board), TOKEN_AMOUNT);
        _board.fillOrder(orderId, 0);
        vm.stopPrank();

        assertEq(_taker.balance, takerEthBefore + ETH_AMOUNT);
        assertEq(address(_board).balance, 0);
    }

    /// @notice Tests ETH sell then cancel returns ETH
    function test_roundTrip_sellEth_cancel() public {
        uint256 makerEthBefore = _maker.balance;

        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ETH_AMOUNT}(_eth, ETH_AMOUNT, address(_token), TOKEN_AMOUNT);

        assertEq(_maker.balance, makerEthBefore - ETH_AMOUNT);

        vm.prank(_maker);
        _board.cancelOrder(orderId);

        assertEq(_maker.balance, makerEthBefore);
        assertEq(address(_board).balance, 0);
    }

    /// @notice Tests ERC20 sell filled with ETH
    function test_roundTrip_sellToken_fillWithEth() public {
        vm.startPrank(_maker);
        _token.approve(address(_board), TOKEN_AMOUNT);
        uint256 orderId = _board.createOrder(address(_token), TOKEN_AMOUNT, _eth, ETH_AMOUNT);
        vm.stopPrank();

        uint256 makerEthBefore = _maker.balance;
        uint256 takerTokenBefore = _token.balanceOf(_taker);

        vm.prank(_taker);
        _board.fillOrder{value: ETH_AMOUNT}(orderId, 0);

        assertEq(_maker.balance, makerEthBefore + ETH_AMOUNT);
        assertEq(_token.balanceOf(_taker), takerTokenBefore + TOKEN_AMOUNT);
    }

    /// @notice Tests multiple ETH sell orders can coexist
    function test_multipleEthOrders() public {
        vm.startPrank(_maker);
        uint256 id0 = _board.createOrder{value: 1 ether}(_eth, 1 ether, address(_token), TOKEN_AMOUNT);
        uint256 id1 = _board.createOrder{value: 2 ether}(_eth, 2 ether, address(_token), TOKEN_AMOUNT);
        uint256 id2 = _board.createOrder{value: 3 ether}(_eth, 3 ether, address(_token), TOKEN_AMOUNT);
        vm.stopPrank();

        assertEq(address(_board).balance, 6 ether);

        vm.prank(_maker);
        _board.cancelOrder(id1);

        assertEq(address(_board).balance, 4 ether);

        vm.startPrank(_taker);
        _token.approve(address(_board), TOKEN_AMOUNT);
        _board.fillOrder(id0, 0);
        vm.stopPrank();

        assertEq(address(_board).balance, 3 ether);
        assertTrue(_board.canFill(id2));
        assertFalse(_board.canFill(id0));
        assertFalse(_board.canFill(id1));
    }

    // ============ Fuzz tests ============

    /// @notice Fuzz tests createOrder selling ETH
    function testFuzz_createOrder_sellEth(
        uint256 ethAmount,
        uint256 amountB
    ) public {
        ethAmount = bound(ethAmount, 1, 100 ether);
        amountB = bound(amountB, 1, 1e30);

        vm.deal(_maker, ethAmount + 1 ether);

        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ethAmount}(_eth, ethAmount, address(_token), amountB);

        ISwapboard.Order memory order = _board.getOrder(orderId);
        assertEq(order.amountA, ethAmount);
        assertEq(order.amountB, amountB);
        assertEq(order.tokenA, _eth);
        assertEq(address(_board).balance, ethAmount);
    }

    /// @notice Fuzz tests createOrder selling ETH reverts on excess msg.value
    function testFuzz_createOrder_sellEth_revert_excess(
        uint256 ethAmount,
        uint256 excess
    ) public {
        ethAmount = bound(ethAmount, 1, 50 ether);
        excess = bound(excess, 1, 50 ether);

        vm.deal(_maker, ethAmount + excess);

        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, ethAmount, ethAmount + excess));
        _board.createOrder{value: ethAmount + excess}(_eth, ethAmount, address(_token), TOKEN_AMOUNT);
    }

    /// @notice Fuzz tests fillOrder paying with ETH
    function testFuzz_fillOrder_payEth(
        uint256 tokenAmount,
        uint256 ethAmount
    ) public {
        tokenAmount = bound(tokenAmount, 1, 1e30);
        ethAmount = bound(ethAmount, 1, 100 ether);

        _token.mint(_maker, tokenAmount);
        vm.deal(_taker, ethAmount + 1 ether);

        uint256 makerEthBefore = _maker.balance;
        uint256 takerTokenBefore = _token.balanceOf(_taker);

        vm.startPrank(_maker);
        _token.approve(address(_board), tokenAmount);
        uint256 orderId = _board.createOrder(address(_token), tokenAmount, _eth, ethAmount);
        vm.stopPrank();

        vm.prank(_taker);
        _board.fillOrder{value: ethAmount}(orderId, 0);

        assertEq(_maker.balance, makerEthBefore + ethAmount);
        assertEq(_token.balanceOf(_taker), takerTokenBefore + tokenAmount);
    }

    /// @notice Fuzz tests cancelOrder returning ETH
    function testFuzz_cancelOrder_returnEth(
        uint256 ethAmount
    ) public {
        ethAmount = bound(ethAmount, 1, 100 ether);
        vm.deal(_maker, ethAmount);

        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: ethAmount}(_eth, ethAmount, address(_token), TOKEN_AMOUNT);

        uint256 makerEthBefore = _maker.balance;

        vm.prank(_maker);
        _board.cancelOrder(orderId);

        assertEq(_maker.balance, makerEthBefore + ethAmount);
    }

    /// @notice Fuzz tests fillOrder receiving ETH
    function testFuzz_fillOrder_receiveEth(
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
        uint256 orderId = _board.createOrder{value: ethAmount}(_eth, ethAmount, address(_token), tokenAmount);

        vm.startPrank(_taker);
        _token.approve(address(_board), tokenAmount);
        _board.fillOrder(orderId, 0);
        vm.stopPrank();

        assertEq(_taker.balance, takerEthBefore + ethAmount);
        assertEq(_token.balanceOf(_maker), makerTokenBefore + tokenAmount);
    }

    /// @notice getEth returns the canonical ETH sentinel
    function test_getEth() public view {
        assertEq(_board.getEth(), 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    }
}
