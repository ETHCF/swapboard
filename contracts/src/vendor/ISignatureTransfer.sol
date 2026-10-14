// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// solhint-disable use-natspec

/// @title ISignatureTransfer
/// @notice Minimal Permit2 SignatureTransfer surface used by Swapboard
/// @dev Canonical Permit2: `0x000000000022D473030F116dDEE9F6B43aC78BA3`
interface ISignatureTransfer {
    /// @notice Token and max amount signed for a transfer
    struct TokenPermissions {
        address token;
        uint256 amount;
    }

    /// @notice Signed Permit2 transfer authorization
    struct PermitTransferFrom {
        TokenPermissions permitted;
        uint256 nonce;
        uint256 deadline;
    }

    /// @notice Spender-chosen recipient and pull amount
    struct SignatureTransferDetails {
        address to;
        uint256 requestedAmount;
    }

    /// @notice Transfers `requestedAmount` of the permitted token from `owner` to `to`
    /// @dev `msg.sender` is the spender (must match the signed spender). Reverts if
    ///      `requestedAmount` exceeds the signed amount or the signature is invalid.
    /// @param permit Signed Permit2 transfer authorization
    /// @param transferDetails Recipient and requested amount
    /// @param owner Token owner who signed the permit
    /// @param signature EIP-712 signature bytes
    function permitTransferFrom(
        PermitTransferFrom memory permit,
        SignatureTransferDetails memory transferDetails,
        address owner,
        bytes memory signature
    ) external;
}
