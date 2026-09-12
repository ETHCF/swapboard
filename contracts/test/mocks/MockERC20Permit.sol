// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec

import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {MockERC20} from "./MockERC20.sol";

/// @title MockERC20Permit
/// @notice MockERC20 with EIP-2612 `permit`
contract MockERC20Permit is MockERC20, IERC20Permit {
    error PermitExpired();
    error InvalidSigner();

    bytes32 public constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    mapping(address owner => uint256 nonce) private _nonces;

    constructor(
        string memory initName,
        string memory initSymbol,
        uint8 initDecimals
    ) MockERC20(initName, initSymbol, initDecimals) {}

    /// @inheritdoc IERC20Permit
    function nonces(
        address owner
    ) external view returns (uint256) {
        return _nonces[owner];
    }

    /// @inheritdoc IERC20Permit
    /// @dev `DOMAIN_SEPARATOR` is the EIP-2612 name; mixedCase does not apply.
    // forge-lint: disable-next-line(mixed-case-function)
    function DOMAIN_SEPARATOR() public view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(this.name())),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    /// @inheritdoc IERC20Permit
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (block.timestamp > deadline) {
            revert PermitExpired();
        }

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR(),
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, _nonces[owner]++, deadline))
            )
        );
        // Mock permit: EIP-2612 does not require s-malleability checks.
        // forge-lint: disable-next-line(ecrecover)
        address recovered = ecrecover(digest, v, r, s);
        if (recovered == address(0) || recovered != owner) {
            revert InvalidSigner();
        }

        _approve(owner, spender, value);
    }
}
