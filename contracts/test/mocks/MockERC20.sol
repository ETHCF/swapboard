// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title MockERC20
/// @notice Shared ERC20 mock base used by test tokens
contract MockERC20 is IERC20 {
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    uint256 internal _totalSupply;
    mapping(address account => uint256 balance) internal _balanceOf;
    mapping(address owner => mapping(address spender => uint256 allowance)) internal _allowance;
    uint256 private _transferFromCalls;

    constructor(
        string memory initName,
        string memory initSymbol,
        uint8 initDecimals
    ) {
        _name = initName;
        _symbol = initSymbol;
        _decimals = initDecimals;
    }

    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view virtual returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(
        address account
    ) public view virtual returns (uint256) {
        return _balanceOf[account];
    }

    function allowance(
        address owner,
        address spender
    ) public view virtual returns (uint256) {
        return _allowance[owner][spender];
    }

    function getTransferFromCalls() external view returns (uint256) {
        return _transferFromCalls;
    }

    function mint(
        address to,
        uint256 amount
    ) public virtual {
        _mint(to, amount);
    }

    function burn(
        address from,
        uint256 amount
    ) public virtual {
        _burn(from, amount);
    }

    function approve(
        address spender,
        uint256 amount
    ) public virtual returns (bool) {
        _approve(msg.sender, spender, amount);

        return true;
    }

    function transfer(
        address to,
        uint256 amount
    ) public virtual returns (bool) {
        _transfer(msg.sender, to, amount);

        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual returns (bool) {
        ++_transferFromCalls;
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);

        return true;
    }

    function _mint(
        address to,
        uint256 amount
    ) internal virtual {
        _totalSupply += amount;
        _balanceOf[to] += amount;

        emit Transfer({from: address(0), to: to, value: amount});
    }

    function _burn(
        address from,
        uint256 amount
    ) internal virtual {
        _balanceOf[from] -= amount;
        _totalSupply -= amount;

        emit Transfer({from: from, to: address(0), value: amount});
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        _allowance[owner][spender] = amount;

        emit Approval({owner: owner, spender: spender, value: amount});
    }

    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        uint256 allowed = _allowance[owner][spender];
        if (allowed != type(uint256).max) {
            _allowance[owner][spender] = allowed - amount;
        }
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        _balanceOf[from] -= amount;
        _balanceOf[to] += amount;

        emit Transfer({from: from, to: to, value: amount});
    }
}
