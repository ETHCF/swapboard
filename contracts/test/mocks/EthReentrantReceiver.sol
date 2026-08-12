// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec

import {Swapboard} from "../../src/Swapboard.sol";
import {MockERC20} from "./MockERC20.sol";

/// @title EthReentrantReceiver
/// @notice Receives ETH and attempts to reenter Swapboard (blocked by nonReentrant)
contract EthReentrantReceiver {
    enum Attack {
        None,
        Fill,
        Cancel,
        Create
    }

    Swapboard private immutable _BOARD;
    MockERC20 private immutable _TOKEN;
    Attack private _attack;
    uint256 private _orderId;
    bool private _attacking;

    constructor(
        Swapboard board,
        MockERC20 token
    ) {
        _BOARD = board;
        _TOKEN = token;
    }

    function configure(
        Attack attack,
        uint256 orderId
    ) external {
        _attack = attack;
        _orderId = orderId;
    }

    // solhint-disable no-complex-fallback
    receive() external payable {
        if (_attacking || _attack == Attack.None) {
            return;
        }

        _attacking = true;

        if (_attack == Attack.Fill) {
            try _BOARD.fillOrder(_orderId, 0) {} catch {}
        } else if (_attack == Attack.Cancel) {
            try _BOARD.cancelOrder(_orderId) {} catch {}
        } else if (_attack == Attack.Create) {
            try _BOARD.createOrder{value: 0}(address(_TOKEN), 1, address(_TOKEN), 1, false) {} catch {}
        }

        _attacking = false;
    }
}
