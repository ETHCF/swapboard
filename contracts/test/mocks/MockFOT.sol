// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.33;

// solhint-disable use-natspec

contract MockFOT {
    string private _name = "Fee On Transfer";
    string private _symbol = "FOT";
    uint8 private _decimals = 18;
    uint256 private _totalSupply;
    uint256 private _feePercent = 5;

    mapping(address => uint256) private _balanceOf;
    mapping(address => mapping(address => uint256)) private _allowance;

    // solhint-disable-next-line gas-indexed-events
    event Transfer(address indexed from, address indexed to, uint256 amount);

    // solhint-disable-next-line gas-indexed-events
    event Approval(address indexed owner, address indexed spender, uint256 amount);

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
        return _totalSupply;
    }

    function getFeePercent() external view returns (uint256) {
        return _feePercent;
    }

    function balanceOf(
        address account
    ) external view returns (uint256) {
        return _balanceOf[account];
    }

    function allowance(
        address owner,
        address spender
    ) external view returns (uint256) {
        return _allowance[owner][spender];
    }

    function mint(
        address to,
        uint256 amount
    ) external {
        _totalSupply += amount;
        _balanceOf[to] += amount;
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
        uint256 fee = (amount * _feePercent) / 100;
        uint256 netAmount = amount - fee;
        _balanceOf[msg.sender] -= amount;
        _balanceOf[to] += netAmount;
        _totalSupply -= fee;
        emit Transfer(msg.sender, to, netAmount);
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
        uint256 fee = (amount * _feePercent) / 100;
        uint256 netAmount = amount - fee;
        _balanceOf[from] -= amount;
        _balanceOf[to] += netAmount;
        _totalSupply -= fee;
        emit Transfer(from, to, netAmount);
        return true;
    }
}
