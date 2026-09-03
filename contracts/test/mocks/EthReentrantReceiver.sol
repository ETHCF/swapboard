// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec

import {Swapboard} from "../../src/Swapboard.sol";
import {MockERC20} from "./MockERC20.sol";
import {ISwapboard} from "../../src/interfaces/ISwapboard.sol";

/// @title EthReentrantReceiver
/// @notice Receives ETH and attempts to reenter Swapboard (blocked by nonReentrant)
// forge-lint: disable-next-item(locked-ether)
contract EthReentrantReceiver {
    enum Attack {
        None,
        Fill,
        FillOrders,
        Cancel,
        CancelOrders,
        Create,
        Modify
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
    // forge-lint: disable-next-item(reentrancy-no-eth)
    // forge-lint: disable-next-item(cyclomatic-complexity)
    receive() external payable {
        if (_attacking || _attack == Attack.None) {
            return;
        }

        _attacking = true;

        if (_attack == Attack.Fill) {
            try _BOARD.fillOrder(_orderId, 1, 1, 0) {} catch {}
        } else if (_attack == Attack.FillOrders) {
            ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](1);
            fills[0] = ISwapboard.FillOrderParams({orderId: _orderId, amountA: 1, minAmountB: 1});
            try _BOARD.fillOrders(fills, 0) {} catch {}
        } else if (_attack == Attack.Cancel) {
            try _BOARD.cancelOrder(_orderId) {} catch {}
        } else if (_attack == Attack.CancelOrders) {
            uint256[] memory ids = new uint256[](1);
            ids[0] = _orderId;
            try _BOARD.cancelOrders(ids) {} catch {}
        } else if (_attack == Attack.Create) {
            try _BOARD.createOrder{value: 0}(
                ISwapboard.CreateOrderParams({
                    tokenA: address(_TOKEN), amountA: 1, tokenB: address(_TOKEN), amountB: 1, partialFillAllowed: false
                })
            ) {}
                catch {}
        } else if (_attack == Attack.Modify) {
            ISwapboard.Order memory order = _BOARD.getOrder(_orderId);
            ISwapboard.OrderAmounts memory previous = ISwapboard.OrderAmounts({
                amountA: order.amountA,
                amountB: order.amountB,
                availableA: order.availableA,
                availableB: order.availableB
            });
            ISwapboard.ModifyOrderParams memory updated = ISwapboard.ModifyOrderParams({availableA: 1, availableB: 1});
            try _BOARD.modifyOrder(_orderId, previous, updated) {} catch {}
        }

        _attacking = false;
    }
}
