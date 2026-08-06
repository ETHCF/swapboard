// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.33;

// solhint-disable use-natspec

import {MockERC20} from "../../mocks/MockERC20.sol";

/// @title UpgradeableToken
/// @notice Simulates a token that can be upgraded to change behavior
contract UpgradeableToken is MockERC20 {
    bool private _isFeeOnTransfer;
    uint256 private _feePercent = 5;

    constructor() MockERC20("Upgradeable Token", "UPGRADE", 18) {}

    function getIsFeeOnTransfer() external view returns (bool) {
        return _isFeeOnTransfer;
    }

    function getFeePercent() external view returns (uint256) {
        return _feePercent;
    }

    function setFeeOnTransfer(
        bool enabled
    ) external {
        _isFeeOnTransfer = enabled;
    }

    function transfer(
        address to,
        uint256 amount
    ) public override returns (bool) {
        uint256 fee = _isFeeOnTransfer ? (amount * _feePercent) / 100 : 0;
        uint256 netAmount = amount - fee;
        _balanceOf[msg.sender] -= amount;
        _balanceOf[to] += netAmount;
        if (fee > 0) {
            _totalSupply -= fee;
        }
        emit Transfer(msg.sender, to, netAmount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        uint256 fee = _isFeeOnTransfer ? (amount * _feePercent) / 100 : 0;
        uint256 netAmount = amount - fee;
        _balanceOf[from] -= amount;
        _balanceOf[to] += netAmount;
        if (fee > 0) {
            _totalSupply -= fee;
        }
        emit Transfer(from, to, netAmount);
        return true;
    }
}
