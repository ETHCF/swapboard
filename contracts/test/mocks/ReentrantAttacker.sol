// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Swapboard} from "../../src/Swapboard.sol";

/// @title ReentrantAttacker
/// @notice Mock ERC20 that attempts reentrancy on transfer
contract ReentrantAttacker {
    string public name = "Reentrant Token";
    string public symbol = "REENT";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    Swapboard public immutable board;
    string public attackType;
    uint256 public orderId;
    address public attacker;
    bool public attacking;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    constructor(
        address _board,
        string memory _attackType
    ) {
        board = Swapboard(_board);
        attackType = _attackType;
    }

    function setOrderId(
        uint256 _orderId
    ) external {
        orderId = _orderId;
    }

    function setAttacker(
        address _attacker
    ) external {
        attacker = _attacker;
    }

    function mint(
        address to,
        uint256 amount
    ) external {
        totalSupply += amount;
        balanceOf[to] += amount;
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
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
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
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);

        // Attempt reentrancy on transferFrom (during createOrder)
        _attemptReentrancy();

        return true;
    }

    function _attemptReentrancy() internal {
        if (attacking) return; // Prevent infinite loop
        attacking = true;

        if (keccak256(bytes(attackType)) == keccak256(bytes("fill"))) {
            // Try to fill the same order again
            try board.fillOrder(orderId) {} catch {}
        } else if (keccak256(bytes(attackType)) == keccak256(bytes("cancel"))) {
            // Try to cancel the same order again
            try board.cancelOrder(orderId) {} catch {}
        }

        attacking = false;
    }
}
