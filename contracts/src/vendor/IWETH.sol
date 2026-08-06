// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.33;

/// @title IWETH
/// @author
/// @notice Minimal interface for Wrapped Ether (WETH)
interface IWETH {
    /// @notice Deposit ETH and receive WETH
    function deposit() external payable;

    /// @notice Withdraw ETH by burning WETH
    /// @param amount Amount of WETH to unwrap
    function withdraw(
        uint256 amount
    ) external;
}
