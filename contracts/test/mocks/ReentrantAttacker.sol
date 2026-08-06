// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec

import {MockERC20} from "./MockERC20.sol";
import {Swapboard} from "../../src/Swapboard.sol";

/// @title ReentrantAttacker
/// @notice Mock ERC20 that attempts reentrancy on transfer
contract ReentrantAttacker is MockERC20 {
    Swapboard private immutable _BOARD;
    string private _attackType;
    uint256 private _orderId;
    address private _attacker;
    bool private _attacking;

    constructor(
        address board,
        string memory attackType
    ) MockERC20("Reentrant Token", "REENT", 18) {
        _BOARD = Swapboard(payable(board));
        _attackType = attackType;
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

    function transfer(
        address to,
        uint256 amount
    ) public override returns (bool) {
        super.transfer(to, amount);

        _attemptReentrancy();

        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        super.transferFrom(from, to, amount);

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
