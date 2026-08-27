// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec

import {MockERC20} from "./MockERC20.sol";
import {Swapboard} from "../../src/Swapboard.sol";
import {ISwapboard} from "../../src/interfaces/ISwapboard.sol";

/// @title ReentrantAttacker
/// @notice Mock ERC20 that attempts reentrancy on transfer
contract ReentrantAttacker is MockERC20 {
    Swapboard private immutable _BOARD;
    string private _attackType;
    uint256 private _orderId;
    address private _attacker;
    address private _tokenB;
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

    function setTokenB(
        address tokenB
    ) external {
        _tokenB = tokenB;
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
            try _BOARD.fillOrder(_orderId, 1, 0) {} catch {}
        } else if (keccak256(bytes(_attackType)) == keccak256(bytes("fillOrders"))) {
            ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](1);
            fills[0] = ISwapboard.FillOrderParams({orderId: _orderId, amountA: 1});
            try _BOARD.fillOrders(fills, 0) {} catch {}
        } else if (keccak256(bytes(_attackType)) == keccak256(bytes("cancel"))) {
            // Try to cancel the same order again
            try _BOARD.cancelOrder(_orderId) {} catch {}
        } else if (keccak256(bytes(_attackType)) == keccak256(bytes("cancelOrders"))) {
            uint256[] memory ids = new uint256[](1);
            ids[0] = _orderId;
            try _BOARD.cancelOrders(ids) {} catch {}
        } else if (keccak256(bytes(_attackType)) == keccak256(bytes("createOrders"))) {
            ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](1);
            orders[0] = ISwapboard.CreateOrderParams({
                tokenA: address(this), amountA: 1, tokenB: _tokenB, amountB: 1, partialFillAllowed: false
            });
            try _BOARD.createOrders(orders) {} catch {}
        }

        _attacking = false;
    }
}
