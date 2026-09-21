// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec

import {MockERC20} from "./MockERC20.sol";

/// @title MockRebaseOnTransfer
/// @notice Share-based token that rebases during `transfer` / `transferFrom`
/// @dev After moving `amount`, all balances are scaled to 95%. Recipient delta is therefore
///      5% short of `amount`, which `_transferExactFrom` rejects via `BalanceMismatch`.
contract MockRebaseOnTransfer is MockERC20 {
    uint256 private _totalShares;
    uint256 private _rebaseMultiplier = 100;
    bool private _rebaseOnTransfer = true;
    uint256 private _transferRebasePercent = 95;

    mapping(address account => uint256 shares) private _shares;

    constructor() MockERC20("Rebase On Transfer", "ROT", 18) {}

    function getRebaseOnTransfer() external view returns (bool) {
        return _rebaseOnTransfer;
    }

    function setRebaseOnTransfer(
        bool enabled
    ) external {
        _rebaseOnTransfer = enabled;
    }

    function totalSupply() public view override returns (uint256) {
        return (_totalShares * _rebaseMultiplier) / 100;
    }

    function balanceOf(
        address account
    ) public view override returns (uint256) {
        return (_shares[account] * _rebaseMultiplier) / 100;
    }

    function mint(
        address to,
        uint256 amount
    ) public override {
        uint256 shares = (amount * 100) / _rebaseMultiplier;

        _totalShares += shares;
        _shares[to] += shares;

        emit Transfer({from: address(0), to: to, value: amount});
    }

    function transfer(
        address to,
        uint256 amount
    ) public override returns (bool) {
        _move(msg.sender, to, amount);

        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _move(from, to, amount);

        return true;
    }

    function _move(
        address from,
        address to,
        uint256 amount
    ) private {
        uint256 sharesToTransfer = (amount * 100) / _rebaseMultiplier;

        _shares[from] -= sharesToTransfer;
        _shares[to] += sharesToTransfer;

        emit Transfer({from: from, to: to, value: amount});

        if (_rebaseOnTransfer) {
            _rebaseMultiplier = (_rebaseMultiplier * _transferRebasePercent) / 100;
        }
    }
}
