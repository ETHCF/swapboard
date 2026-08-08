// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec

/// @title ETHRejecter
/// @notice Contract that rejects ETH transfers
contract ETHRejecter {
    error RejectETH();

    receive() external payable {
        revert RejectETH();
    }
}
