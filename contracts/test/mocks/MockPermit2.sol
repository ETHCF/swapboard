// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec
// solhint-disable gas-small-strings
// solhint-disable gas-calldata-parameters
// solhint-disable no-inline-assembly

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISignatureTransfer} from "../../src/vendor/ISignatureTransfer.sol";

/// @title MockPermit2
/// @notice Minimal Permit2 SignatureTransfer mock for tests (etch at the canonical address)
contract MockPermit2 is ISignatureTransfer {
    error SignatureExpired();
    error InvalidSigner();
    error InvalidAmount(uint256 maxAmount);
    error InvalidNonce();
    error TransferFailed();

    bytes32 public constant TOKEN_PERMISSIONS_TYPEHASH = keccak256("TokenPermissions(address token,uint256 amount)");

    bytes32 public constant PERMIT_TRANSFER_FROM_TYPEHASH = keccak256(
        abi.encodePacked(
            "PermitTransferFrom(TokenPermissions permitted,address spender,uint256 nonce,uint256 deadline)",
            "TokenPermissions(address token,uint256 amount)"
        )
    );

    mapping(address owner => mapping(uint256 word => uint256 bitmap)) public nonceBitmap;

    /// @inheritdoc ISignatureTransfer
    function permitTransferFrom(
        PermitTransferFrom memory permit,
        SignatureTransferDetails memory transferDetails,
        address owner,
        bytes memory signature
    ) external {
        if (block.timestamp > permit.deadline) {
            revert SignatureExpired();
        }
        if (transferDetails.requestedAmount > permit.permitted.amount) {
            revert InvalidAmount(permit.permitted.amount);
        }

        _useUnorderedNonce(owner, permit.nonce);

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        PERMIT_TRANSFER_FROM_TYPEHASH,
                        keccak256(
                            abi.encode(TOKEN_PERMISSIONS_TYPEHASH, permit.permitted.token, permit.permitted.amount)
                        ),
                        msg.sender,
                        permit.nonce,
                        permit.deadline
                    )
                )
            )
        );

        address recovered = _recover(digest, signature);
        if (recovered == address(0) || recovered != owner) {
            revert InvalidSigner();
        }

        if (transferDetails.requestedAmount != 0) {
            bool ok = IERC20(permit.permitted.token)
                .transferFrom(owner, transferDetails.to, transferDetails.requestedAmount);
            if (!ok) {
                revert TransferFailed();
            }
        }
    }

    /// @dev `DOMAIN_SEPARATOR` matches EIP-712 naming used by real Permit2.
    // forge-lint: disable-next-line(mixed-case-function)
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Permit2")),
                block.chainid,
                address(this)
            )
        );
    }

    function _useUnorderedNonce(
        address owner,
        uint256 nonce
    ) private {
        // Unordered nonce: high 248 bits select the bitmap word; low 8 bits select the bit.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 wordPos = uint248(nonce >> 8);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 bitPos = uint8(nonce);
        uint256 bit = uint256(1) << bitPos;
        uint256 bitmap = nonceBitmap[owner][wordPos];
        if (bitmap & bit != 0) {
            revert InvalidNonce();
        }
        nonceBitmap[owner][wordPos] = bitmap | bit;
    }

    function _recover(
        bytes32 digest,
        bytes memory signature
    ) private pure returns (address) {
        if (signature.length != 65) {
            return address(0);
        }
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly ("memory-safe") {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }
        // Mock Permit2: EIP-2612-style recovery without s-malleability checks.
        // forge-lint: disable-next-line(ecrecover)
        return ecrecover(digest, v, r, s);
    }
}
