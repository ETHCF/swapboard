// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.33;

// solhint-disable use-natspec

contract MockWETH {
    error InsufficientWETH();
    error ETHTransferFailed();

    string private _name = "Wrapped Ether";
    string private _symbol = "WETH";
    uint8 private _decimals = 18;
    uint256 private _totalSupply;

    mapping(address => uint256) private _balanceOf;
    mapping(address => mapping(address => uint256)) private _allowance;

    // solhint-disable-next-line gas-indexed-events
    event Transfer(address indexed from, address indexed to, uint256 amount);

    // solhint-disable-next-line gas-indexed-events
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    // solhint-disable-next-line gas-indexed-events
    event Deposit(address indexed dst, uint256 wad);

    // solhint-disable-next-line gas-indexed-events
    event Withdrawal(address indexed src, uint256 wad);

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

    function deposit() external payable {
        _balanceOf[msg.sender] += msg.value;
        _totalSupply += msg.value;
        emit Deposit(msg.sender, msg.value);
        emit Transfer(address(0), msg.sender, msg.value);
    }

    function withdraw(
        uint256 amount
    ) external {
        if (_balanceOf[msg.sender] < amount) {
            revert InsufficientWETH();
        }
        _balanceOf[msg.sender] -= amount;
        _totalSupply -= amount;
        emit Withdrawal(msg.sender, amount);
        emit Transfer(msg.sender, address(0), amount);
        (bool success,) = payable(msg.sender).call{value: amount}("");
        if (!success) {
            revert ETHTransferFailed();
        }
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
        _balanceOf[msg.sender] -= amount;
        _balanceOf[to] += amount;

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

        _balanceOf[from] -= amount;
        _balanceOf[to] += amount;

        emit Transfer(from, to, amount);

        return true;
    }

    // solhint-disable-next-line no-complex-fallback
    receive() external payable {
        _balanceOf[msg.sender] += msg.value;
        _totalSupply += msg.value;

        emit Deposit(msg.sender, msg.value);
        emit Transfer(address(0), msg.sender, msg.value);
    }
}
