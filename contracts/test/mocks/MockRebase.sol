// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec

import {MockERC20} from "./MockERC20.sol";

/// @title MockRebase
/// @notice Mock ERC20 with rebasing functionality (like stETH, AMPL)
contract MockRebase is MockERC20 {
    uint256 private _totalShares;
    uint256 private _rebaseMultiplier = 100; // 100 = 1x, 110 = 1.1x

    mapping(address account => uint256 shares) private _shares;

    // solhint-disable-next-line gas-indexed-events
    event Rebase(uint256 newMultiplier);

    constructor() MockERC20("Rebase Token", "REBASE", 18) {}

    function totalSupply() public view override returns (uint256) {
        return (_totalShares * _rebaseMultiplier) / 100;
    }

    function balanceOf(
        address account
    ) public view override returns (uint256) {
        return (_shares[account] * _rebaseMultiplier) / 100;
    }

    /// @notice Rebase all balances
    /// @param newMultiplier Percentage multiplier (100 = 1x, 110 = 1.1x, 90 = 0.9x)
    function rebase(
        uint256 newMultiplier
    ) external {
        _rebaseMultiplier = newMultiplier;

        emit Rebase({newMultiplier: newMultiplier});
    }

    function mint(
        address to,
        uint256 amount
    ) public override {
        uint256 shares = (amount * 100) / _rebaseMultiplier;

        _totalShares += shares;
        _shares[to] += shares;

        emit Transfer({from: address(0), to: to, amount: amount});
    }

    function transfer(
        address to,
        uint256 amount
    ) public override returns (bool) {
        uint256 sharesToTransfer = (amount * 100) / _rebaseMultiplier;

        _shares[msg.sender] -= sharesToTransfer;
        _shares[to] += sharesToTransfer;

        emit Transfer({from: msg.sender, to: to, amount: amount});

        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        _spendAllowance(from, msg.sender, amount);

        uint256 sharesToTransfer = (amount * 100) / _rebaseMultiplier;

        _shares[from] -= sharesToTransfer;
        _shares[to] += sharesToTransfer;

        emit Transfer({from: from, to: to, amount: amount});

        return true;
    }
}
