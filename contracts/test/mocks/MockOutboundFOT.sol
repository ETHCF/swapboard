// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec

import {MockERC20} from "./MockERC20.sol";

/// @title MockOutboundFOT
/// @notice Exact transferFrom (no fee); 5% fee only on transfer (outbound payout)
contract MockOutboundFOT is MockERC20 {
    uint256 private _feePercent = 5;

    constructor() MockERC20("Outbound Fee On Transfer", "OFOT", 18) {}

    function getFeePercent() external view returns (uint256) {
        return _feePercent;
    }

    function transfer(
        address to,
        uint256 amount
    ) public override returns (bool) {
        uint256 fee = (amount * _feePercent) / 100;
        uint256 netAmount = amount - fee;

        _balanceOf[msg.sender] -= amount;
        _balanceOf[to] += netAmount;
        _totalSupply -= fee;

        emit Transfer({from: msg.sender, to: to, amount: netAmount});

        return true;
    }
}
