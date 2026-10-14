// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec

import {MockERC20} from "./MockERC20.sol";

/// @title MockRevertOnZeroERC20
/// @notice ERC20 that reverts on zero-amount `transfer` / `transferFrom` (some mainnet tokens do this)
contract MockRevertOnZeroERC20 is MockERC20 {
    error ZeroAmountTransfer();

    constructor(
        string memory initName,
        string memory initSymbol,
        uint8 initDecimals
    ) MockERC20(initName, initSymbol, initDecimals) {}

    function transfer(
        address to,
        uint256 amount
    ) public override returns (bool) {
        if (amount == 0) {
            revert ZeroAmountTransfer();
        }

        return super.transfer(to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        if (amount == 0) {
            revert ZeroAmountTransfer();
        }

        return super.transferFrom(from, to, amount);
    }
}
