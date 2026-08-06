// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.33;

// solhint-disable use-natspec

import {MockERC20} from "../../mocks/MockERC20.sol";

/// @title NegativeRebaseToken
/// @notice Token that can decrease in balance (like stETH during slashing)
contract NegativeRebaseToken is MockERC20 {
    error InsufficientShares();
    error InsufficientAllowance();

    uint256 private _totalShares;
    uint256 private _rebaseMultiplier = 100; // 100 = 1x

    mapping(address => uint256) private _shares;

    constructor() MockERC20("Negative Rebase Token", "NREBASE", 18) {}

    function totalSupply() public view override returns (uint256) {
        return (_totalShares * _rebaseMultiplier) / 100;
    }

    function balanceOf(
        address account
    ) public view override returns (uint256) {
        return (_shares[account] * _rebaseMultiplier) / 100;
    }

    function rebase(
        uint256 newMultiplier
    ) external {
        _rebaseMultiplier = newMultiplier;
    }

    function mint(
        address to,
        uint256 amount
    ) public override {
        uint256 shares = (amount * 100) / _rebaseMultiplier;
        _totalShares += shares;
        _shares[to] += shares;
        emit Transfer(address(0), to, amount);
    }

    function transfer(
        address to,
        uint256 amount
    ) public override returns (bool) {
        uint256 sharesToTransfer = (amount * 100) / _rebaseMultiplier;
        if (_shares[msg.sender] < sharesToTransfer) {
            revert InsufficientShares();
        }
        _shares[msg.sender] -= sharesToTransfer;
        _shares[to] += sharesToTransfer;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        uint256 allowed = _allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < amount) {
                revert InsufficientAllowance();
            }
            _allowance[from][msg.sender] = allowed - amount;
        }
        uint256 sharesToTransfer = (amount * 100) / _rebaseMultiplier;
        if (_shares[from] < sharesToTransfer) {
            revert InsufficientShares();
        }
        _shares[from] -= sharesToTransfer;
        _shares[to] += sharesToTransfer;
        emit Transfer(from, to, amount);
        return true;
    }
}
