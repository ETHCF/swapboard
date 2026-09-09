// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable func-visibility

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/// @dev User-defined value type for ERC20 addresses and the native ETH sentinel
type Token is address;

using SafeERC20 for IERC20;
using Address for address payable;

/// @dev Canonical placeholder address representing native ETH
address constant NATIVE_TOKEN_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

/// @dev Symbol used for the native token
string constant NATIVE_TOKEN_SYMBOL = "ETH";

/// @dev Decimals for the native token
uint8 constant NATIVE_TOKEN_DECIMALS = 18;

/// @dev Token value representing native ETH
Token constant NATIVE_TOKEN = Token.wrap(NATIVE_TOKEN_ADDRESS);

using {
    equal as ==,
    notEqual as !=,
    isNative,
    symbol,
    decimals,
    balanceOf,
    allowance,
    safeTransfer,
    safeTransferFrom,
    forceApprove,
    safeIncreaseAllowance,
    toIERC20
} for Token global;

/// @notice Returns whether two tokens are the same address
/// @param a Left token
/// @param b Right token
/// @return True if both unwrap to the same address
function equal(
    Token a,
    Token b
) pure returns (bool) {
    return Token.unwrap(a) == Token.unwrap(b);
}

/// @notice Returns whether two tokens differ
/// @param a Left token
/// @param b Right token
/// @return True if the unwrapped addresses differ
function notEqual(
    Token a,
    Token b
) pure returns (bool) {
    return Token.unwrap(a) != Token.unwrap(b);
}

/// @notice Returns whether `token` is the native ETH sentinel
/// @param token Token to check
/// @return True if `token` is `NATIVE_TOKEN`
function isNative(
    Token token
) pure returns (bool) {
    return token == NATIVE_TOKEN;
}

/// @notice Returns the symbol of the native token or ERC20
/// @param token Token to query
/// @return Token symbol string
function symbol(
    Token token
) view returns (string memory) {
    if (isNative(token)) {
        return NATIVE_TOKEN_SYMBOL;
    }
    return toERC20(token).symbol();
}

/// @notice Returns the decimals of the native token or ERC20
/// @param token Token to query
/// @return Token decimals
function decimals(
    Token token
) view returns (uint8) {
    if (isNative(token)) {
        return NATIVE_TOKEN_DECIMALS;
    }
    return toERC20(token).decimals();
}

/// @notice Returns the balance of the native token or ERC20
/// @param token Token to query
/// @param account Account whose balance is returned
/// @return Balance of `account`
function balanceOf(
    Token token,
    address account
) view returns (uint256) {
    if (isNative(token)) {
        return account.balance;
    }
    return toIERC20(token).balanceOf(account);
}

/// @notice Returns the ERC20 allowance; always 0 for the native token
/// @param token Token to query
/// @param owner Allowance owner
/// @param spender Allowance spender
/// @return Remaining allowance
function allowance(
    Token token,
    address owner,
    address spender
) view returns (uint256) {
    if (isNative(token)) {
        return 0;
    }
    return toIERC20(token).allowance(owner, spender);
}

/// @notice Transfers `amount` of the native token or ERC20 to `to`
/// @dev No-ops when `amount == 0` (some ERC20s revert on zero). Native ETH uses `sendValue`
///      (forwards all gas) so contract recipients can run `receive`/`fallback`.
/// @param token Token to transfer
/// @param to Recipient
/// @param amount Amount to transfer
function safeTransfer(
    Token token,
    address to,
    uint256 amount
) {
    if (amount == 0) {
        return;
    }
    if (isNative(token)) {
        payable(to).sendValue(amount);
    } else {
        toIERC20(token).safeTransfer(to, amount);
    }
}

/// @notice Transfers `amount` of ERC20 from `from` to `to` via allowance
/// @dev No-ops when `amount == 0` or when `token` is native ETH
/// @param token Token to transfer
/// @param from Holder
/// @param to Recipient
/// @param amount Amount to transfer
function safeTransferFrom(
    Token token,
    address from,
    address to,
    uint256 amount
) {
    if (amount == 0 || isNative(token)) {
        return;
    }
    toIERC20(token).safeTransferFrom(from, to, amount);
}

/// @notice Force-approves `spender` for `amount`; no-op for native ETH
/// @param token Token to approve
/// @param spender Spender
/// @param amount Allowance amount
function forceApprove(
    Token token,
    address spender,
    uint256 amount
) {
    if (isNative(token)) {
        return;
    }
    toIERC20(token).forceApprove(spender, amount);
}

/// @notice Increases allowance for `spender`; no-op for native ETH
/// @param token Token to approve
/// @param spender Spender
/// @param amount Amount to add to the current allowance
function safeIncreaseAllowance(
    Token token,
    address spender,
    uint256 amount
) {
    if (isNative(token)) {
        return;
    }
    toIERC20(token).safeIncreaseAllowance(spender, amount);
}

/// @notice Unwraps `token` as IERC20
/// @param token Token to unwrap
/// @return IERC20 interface for `token`
function toIERC20(
    Token token
) pure returns (IERC20) {
    return IERC20(Token.unwrap(token));
}

/// @notice Unwraps `token` as ERC20
/// @param token Token to unwrap
/// @return ERC20 interface for `token`
function toERC20(
    Token token
) pure returns (ERC20) {
    return ERC20(Token.unwrap(token));
}
