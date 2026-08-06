// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.33;

// solhint-disable use-natspec

/// @title MockERC20
/// @notice Shared ERC20 mock base used by test tokens
contract MockERC20 {
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    uint256 internal _totalSupply;
    mapping(address => uint256) internal _balanceOf;
    mapping(address => mapping(address => uint256)) internal _allowance;

    // solhint-disable-next-line gas-indexed-events
    event Transfer(address indexed from, address indexed to, uint256 amount);

    // solhint-disable-next-line gas-indexed-events
    event Approval(address indexed owner, address indexed spender, uint256 amount);

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

        emit Transfer(address(0), to, amount);
    }

    function _burn(
        address from,
        uint256 amount
    ) internal virtual {
        _balanceOf[from] -= amount;
        _totalSupply -= amount;

        emit Transfer(from, address(0), amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        _allowance[owner][spender] = amount;

        emit Approval(owner, spender, amount);
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

        emit Transfer(from, to, amount);
    }
}
