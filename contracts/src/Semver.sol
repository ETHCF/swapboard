// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ISemver} from "./interfaces/ISemver.sol";

/// @title Semver
/// @author Zak Cole (numbergroup.xyz) for Ethereum Community Foundation
/// @notice Simple base contract for managing semantic version numbers
contract Semver is ISemver {
    /// @notice Contract major version number
    uint256 private immutable _MAJOR;

    /// @notice Contract minor version number
    uint256 private immutable _MINOR;

    /// @notice Contract patch version number
    uint256 private immutable _PATCH;

    /// @notice Sets the immutable semantic version components
    /// @param major Major version number
    /// @param minor Minor version number
    /// @param patch Patch version number
    constructor(
        uint256 major,
        uint256 minor,
        uint256 patch
    ) {
        _MAJOR = major;
        _MINOR = minor;
        _PATCH = patch;
    }

    /// @inheritdoc ISemver
    function version() external view returns (string memory) {
        return string(
            abi.encodePacked(Strings.toString(_MAJOR), ".", Strings.toString(_MINOR), ".", Strings.toString(_PATCH))
        );
    }
}
