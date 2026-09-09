// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {
    Token,
    NATIVE_TOKEN,
    NATIVE_TOKEN_ADDRESS,
    NATIVE_TOKEN_SYMBOL,
    NATIVE_TOKEN_DECIMALS,
    toIERC20,
    toERC20
} from "../src/token/Token.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockRevertOnZeroERC20} from "./mocks/MockRevertOnZeroERC20.sol";
import {ETHRejecter} from "./mocks/ETHRejecter.sol";

/// @notice Unit tests for the Token user-defined value type helpers
contract TokenTest is Test {
    MockERC20 internal _token;
    MockRevertOnZeroERC20 internal _zeroRevert;
    address internal _alice = address(0xA11CE);
    address internal _bob = address(0xB0B);

    function setUp() public {
        _token = new MockERC20("Token", "TKN", 18);
        _zeroRevert = new MockRevertOnZeroERC20("ZeroRevert", "ZRV", 18);
        _token.mint(_alice, 100 ether);
        _token.mint(address(this), 100 ether);
        _zeroRevert.mint(address(this), 100 ether);
        vm.deal(address(this), 100 ether);
        vm.deal(_alice, 10 ether);
    }

    // ─── constants / identity ───────────────────────────────────────────────

    function test_native_constants() public pure {
        assertEq(NATIVE_TOKEN_ADDRESS, 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
        assertEq(Token.unwrap(NATIVE_TOKEN), NATIVE_TOKEN_ADDRESS);
        assertTrue(NATIVE_TOKEN.isNative());
        assertEq(NATIVE_TOKEN_SYMBOL, "ETH");
        assertEq(NATIVE_TOKEN_DECIMALS, 18);
    }

    function test_wrap_unwrap_roundtrip() public view {
        Token t = Token.wrap(address(_token));
        assertEq(Token.unwrap(t), address(_token));
        assertEq(address(toIERC20(t)), address(_token));
        assertEq(address(toERC20(t)), address(_token));
    }

    function test_equal_and_notequal() public view {
        Token a = Token.wrap(address(_token));
        Token b = Token.wrap(address(_token));
        Token c = NATIVE_TOKEN;
        assertTrue(a == b);
        assertTrue(a != c);
        assertTrue(c == NATIVE_TOKEN);
        assertFalse(a == c);
        assertFalse(a != b);
    }

    function test_isNative() public view {
        assertTrue(NATIVE_TOKEN.isNative());
        assertFalse(Token.wrap(address(_token)).isNative());
        assertFalse(Token.wrap(address(0)).isNative());
    }

    // ─── metadata ───────────────────────────────────────────────────────────

    function test_symbol_decimals_erc20() public view {
        Token t = Token.wrap(address(_token));
        assertEq(t.symbol(), "TKN");
        assertEq(t.decimals(), 18);
    }

    function test_symbol_decimals_native() public view {
        assertEq(NATIVE_TOKEN.symbol(), NATIVE_TOKEN_SYMBOL);
        assertEq(NATIVE_TOKEN.decimals(), NATIVE_TOKEN_DECIMALS);
    }

    // ─── balanceOf / allowance ──────────────────────────────────────────────

    function test_balanceOf_erc20_and_native() public view {
        assertEq(Token.wrap(address(_token)).balanceOf(_alice), 100 ether);
        assertEq(NATIVE_TOKEN.balanceOf(address(this)), 100 ether);
        assertEq(NATIVE_TOKEN.balanceOf(_alice), 10 ether);
    }

    function test_allowance_erc20_and_native() public {
        vm.prank(_alice);
        _token.approve(_bob, 5 ether);
        assertEq(Token.wrap(address(_token)).allowance(_alice, _bob), 5 ether);
        assertEq(NATIVE_TOKEN.allowance(_alice, _bob), 0);
        assertEq(NATIVE_TOKEN.allowance(_alice, address(this)), 0);
    }

    // ─── safeTransfer ───────────────────────────────────────────────────────

    function test_safeTransfer_erc20() public {
        Token t = Token.wrap(address(_token));
        vm.prank(_alice);
        t.safeTransfer(_bob, 10 ether);
        assertEq(t.balanceOf(_bob), 10 ether);
        assertEq(t.balanceOf(_alice), 90 ether);
    }

    function test_safeTransfer_erc20_zeroAmount_noop() public {
        Token t = Token.wrap(address(_zeroRevert));
        uint256 before_ = t.balanceOf(address(this));
        t.safeTransfer(_bob, 0);
        assertEq(t.balanceOf(address(this)), before_);
        assertEq(t.balanceOf(_bob), 0);
    }

    function test_safeTransfer_native() public {
        uint256 bobBefore = _bob.balance;
        uint256 selfBefore = address(this).balance;
        NATIVE_TOKEN.safeTransfer(_bob, 1 ether);
        assertEq(_bob.balance, bobBefore + 1 ether);
        assertEq(address(this).balance, selfBefore - 1 ether);
    }

    function test_safeTransfer_native_zeroAmount_noop() public {
        uint256 before_ = address(this).balance;
        NATIVE_TOKEN.safeTransfer(_bob, 0);
        assertEq(address(this).balance, before_);
        assertEq(_bob.balance, 0);
    }

    function test_safeTransfer_native_revert_whenRecipientRejects() public {
        ETHRejecter rejecter = new ETHRejecter();
        vm.expectRevert();
        NATIVE_TOKEN.safeTransfer(address(rejecter), 1 ether);
    }

    function testFuzz_safeTransfer_erc20(
        uint256 amount
    ) public {
        amount = bound(amount, 0, 100 ether);
        Token t = Token.wrap(address(_token));
        uint256 aliceBefore = t.balanceOf(_alice);
        uint256 bobBefore = t.balanceOf(_bob);

        vm.prank(_alice);
        t.safeTransfer(_bob, amount);

        assertEq(t.balanceOf(_alice), aliceBefore - amount);
        assertEq(t.balanceOf(_bob), bobBefore + amount);
    }

    function testFuzz_safeTransfer_native(
        uint256 amount
    ) public {
        amount = bound(amount, 0, address(this).balance);
        uint256 bobBefore = _bob.balance;
        uint256 selfBefore = address(this).balance;

        NATIVE_TOKEN.safeTransfer(_bob, amount);

        assertEq(_bob.balance, bobBefore + amount);
        assertEq(address(this).balance, selfBefore - amount);
    }

    // ─── safeTransferFrom ───────────────────────────────────────────────────

    function test_safeTransferFrom_erc20() public {
        Token t = Token.wrap(address(_token));
        vm.prank(_alice);
        _token.approve(address(this), 7 ether);
        t.safeTransferFrom(_alice, _bob, 7 ether);
        assertEq(t.balanceOf(_bob), 7 ether);
    }

    function test_safeTransferFrom_zeroAmount_noop() public {
        Token t = Token.wrap(address(_zeroRevert));
        _zeroRevert.approve(address(this), type(uint256).max);
        uint256 before_ = t.balanceOf(address(this));
        t.safeTransferFrom(address(this), _bob, 0);
        assertEq(t.balanceOf(address(this)), before_);
        assertEq(t.balanceOf(_bob), 0);
    }

    function test_safeTransferFrom_native_noop() public {
        uint256 before_ = address(this).balance;
        NATIVE_TOKEN.safeTransferFrom(address(this), _bob, 1 ether);
        assertEq(address(this).balance, before_);
        assertEq(_bob.balance, 0);
    }

    function test_safeTransferFrom_native_zeroAmount_noop() public {
        uint256 before_ = address(this).balance;
        NATIVE_TOKEN.safeTransferFrom(address(this), _bob, 0);
        assertEq(address(this).balance, before_);
    }

    function testFuzz_safeTransferFrom_erc20(
        uint256 amount
    ) public {
        amount = bound(amount, 0, 50 ether);
        Token t = Token.wrap(address(_token));

        vm.prank(_alice);
        _token.approve(address(this), amount);

        uint256 aliceBefore = t.balanceOf(_alice);
        uint256 bobBefore = t.balanceOf(_bob);
        t.safeTransferFrom(_alice, _bob, amount);
        assertEq(t.balanceOf(_alice), aliceBefore - amount);
        assertEq(t.balanceOf(_bob), bobBefore + amount);
    }

    // ─── approvals ──────────────────────────────────────────────────────────

    function test_forceApprove_erc20() public {
        Token t = Token.wrap(address(_token));
        t.forceApprove(_bob, 3 ether);
        assertEq(t.allowance(address(this), _bob), 3 ether);
        t.forceApprove(_bob, 1 ether);
        assertEq(t.allowance(address(this), _bob), 1 ether);
        // overwrite non-zero → non-zero and clear (USDT-safe via forceApprove)
        t.forceApprove(_bob, 9 ether);
        assertEq(t.allowance(address(this), _bob), 9 ether);
        t.forceApprove(_bob, 0);
        assertEq(t.allowance(address(this), _bob), 0);
    }

    function test_safeIncreaseAllowance_erc20() public {
        Token t = Token.wrap(address(_token));
        t.forceApprove(_bob, 3 ether);
        t.safeIncreaseAllowance(_bob, 2 ether);
        assertEq(t.allowance(address(this), _bob), 5 ether);
    }

    function test_approves_native_noop() public {
        NATIVE_TOKEN.forceApprove(_bob, 1 ether);
        NATIVE_TOKEN.safeIncreaseAllowance(_bob, 1 ether);
        assertEq(NATIVE_TOKEN.allowance(address(this), _bob), 0);
    }

    // ─── conversions ────────────────────────────────────────────────────────

    function test_toIERC20_toERC20() public view {
        Token t = Token.wrap(address(_token));
        IERC20 i = toIERC20(t);
        ERC20 e = toERC20(t);
        assertEq(address(i), address(_token));
        assertEq(address(e), address(_token));
        assertEq(e.name(), "Token");
    }
}
