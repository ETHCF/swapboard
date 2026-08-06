// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.33;

// solhint-disable use-natspec

/// @title MockRebase
/// @notice Mock ERC20 with rebasing functionality (like stETH, AMPL)
contract MockRebase {
    string private _name = "Rebase Token";
    string private _symbol = "REBASE";
    uint8 private _decimals = 18;

    uint256 private _totalShares;
    uint256 private _totalSupply;
    uint256 private _rebaseMultiplier = 100; // 100 = 1x, 110 = 1.1x

    mapping(address => uint256) private _shares;
    mapping(address => mapping(address => uint256)) private _allowance;

    // solhint-disable-next-line gas-indexed-events
    event Transfer(address indexed from, address indexed to, uint256 amount);

    // solhint-disable-next-line gas-indexed-events
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    // solhint-disable-next-line gas-indexed-events
    event Rebase(uint256 newMultiplier);

    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function totalSupply() external view returns (uint256) {
        return (_totalShares * _rebaseMultiplier) / 100;
    }

    function balanceOf(
        address account
    ) external view returns (uint256) {
        return (_shares[account] * _rebaseMultiplier) / 100;
    }

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256) {
        return _allowance[owner][spender];
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
        _allowance[msg.sender][spender] = amount;
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
        uint256 allowed = _allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            _allowance[from][msg.sender] = allowed - amount;
        }
        uint256 sharesToTransfer = (amount * 100) / _rebaseMultiplier;
        _shares[from] -= sharesToTransfer;
        _shares[to] += sharesToTransfer;
        emit Transfer(from, to, amount);
        return true;
    }
}
