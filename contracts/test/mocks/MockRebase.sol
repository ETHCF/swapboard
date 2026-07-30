// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.33;

// solhint-disable use-natspec

/// @title MockRebase
/// @notice Mock ERC20 with rebasing functionality (like stETH, AMPL)
contract MockRebase {
    string public name = "Rebase Token";
    string public symbol = "REBASE";
    uint8 public decimals = 18;

    uint256 internal _totalShares;
    uint256 internal _totalSupply;
    uint256 internal _rebaseMultiplier = 100; // 100 = 1x, 110 = 1.1x

    mapping(address => uint256) internal _shares;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event Rebase(uint256 newMultiplier);

    function totalSupply() external view returns (uint256) {
        return (_totalShares * _rebaseMultiplier) / 100;
    }

    function balanceOf(
        address account
    ) external view returns (uint256) {
        return (_shares[account] * _rebaseMultiplier) / 100;
    }

    /// @notice Rebase all balances
    /// @param newMultiplier Percentage multiplier (100 = 1x, 110 = 1.1x, 90 = 0.9x)
    function rebase(
        uint256 newMultiplier
    ) external {
        _rebaseMultiplier = newMultiplier;
        emit Rebase(newMultiplier);
    }

    function mint(
        address to,
        uint256 amount
    ) external {
        uint256 shares = (amount * 100) / _rebaseMultiplier;
        _totalShares += shares;
        _shares[to] += shares;
        emit Transfer(address(0), to, amount);
    }

    function approve(
        address spender,
        uint256 amount
    ) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(
        address to,
        uint256 amount
    ) external returns (bool) {
        uint256 sharesToTransfer = (amount * 100) / _rebaseMultiplier;
        _shares[msg.sender] -= sharesToTransfer;
        _shares[to] += sharesToTransfer;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        uint256 sharesToTransfer = (amount * 100) / _rebaseMultiplier;
        _shares[from] -= sharesToTransfer;
        _shares[to] += sharesToTransfer;
        emit Transfer(from, to, amount);
        return true;
    }
}
