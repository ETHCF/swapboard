// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.33;

// solhint-disable use-natspec

/// @title NegativeRebaseToken
/// @notice Token that can decrease in balance (like stETH during slashing)
contract NegativeRebaseToken {
    error InsufficientShares();
    error InsufficientAllowance();

    string public name = "Negative Rebase Token";
    string public symbol = "NREBASE";
    uint8 public decimals = 18;

    uint256 internal _totalShares;
    uint256 internal _rebaseMultiplier = 100; // 100 = 1x

    mapping(address => uint256) internal _shares;
    mapping(address => mapping(address => uint256)) public allowance;

    // solhint-disable-next-line gas-indexed-events
    event Transfer(address indexed from, address indexed to, uint256 amount);

    // solhint-disable-next-line gas-indexed-events
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    function totalSupply() external view returns (uint256) {
        return (_totalShares * _rebaseMultiplier) / 100;
    }

    function balanceOf(
        address account
    ) external view returns (uint256) {
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
    ) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            if (allowed < amount) {
                revert InsufficientAllowance();
            }
            allowance[from][msg.sender] = allowed - amount;
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
