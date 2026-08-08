// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

/// @title ISemver
/// @notice Interface for contracts that expose a semantic version string
interface ISemver {
    /// @notice Returns the full semver contract version
    /// @return Semver contract version as a string (e.g. "1.2.3")
    function version() external view returns (string memory);
}
