// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.33;

// solhint-disable use-natspec

import {Swapboard} from "../../src/Swapboard.sol";

/// @title ReentrantAttacker
/// @notice Mock ERC20 that attempts reentrancy on transfer
contract ReentrantAttacker {
    string private _name = "Reentrant Token";
    string private _symbol = "REENT";
    uint8 private _decimals = 18;
    uint256 private _totalSupply;

    mapping(address => uint256) private _balanceOf;
    mapping(address => mapping(address => uint256)) private _allowance;

    Swapboard private immutable _BOARD;
    string private _attackType;
    uint256 private _orderId;
    address private _attacker;
    bool private _attacking;

    // solhint-disable-next-line gas-indexed-events
    event Transfer(address indexed from, address indexed to, uint256 amount);

    // solhint-disable-next-line gas-indexed-events
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    constructor(
        address board,
        string memory attackType
    ) {
        _BOARD = Swapboard(payable(board));
        _attackType = attackType;
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

    function getBoard() external view returns (Swapboard) {
        return _BOARD;
    }

    function getAttackType() external view returns (string memory) {
        return _attackType;
    }

    function getOrderId() external view returns (uint256) {
        return _orderId;
    }

    function getAttacker() external view returns (address) {
        return _attacker;
    }

    function getAttacking() external view returns (bool) {
        return _attacking;
    }

    function setOrderId(
        uint256 orderId
    ) external {
        _orderId = orderId;
    }

    function setAttacker(
        address attacker
    ) external {
        _attacker = attacker;
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
        _balanceOf[msg.sender] -= amount;
        _balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);

        // Attempt reentrancy on transfer
        _attemptReentrancy();

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

        // Attempt reentrancy on transferFrom (during createOrder)
        _attemptReentrancy();

        return true;
    }

    function _attemptReentrancy() internal {
        if (_attacking) {
            // Prevent infinite loop
            return;
        }
        _attacking = true;

        if (keccak256(bytes(_attackType)) == keccak256(bytes("fill"))) {
            // Try to fill the same order again
            try _BOARD.fillOrder(_orderId, 0) {} catch {}
        } else if (keccak256(bytes(_attackType)) == keccak256(bytes("cancel"))) {
            // Try to cancel the same order again
            try _BOARD.cancelOrder(_orderId) {} catch {}
        }

        _attacking = false;
    }
}
