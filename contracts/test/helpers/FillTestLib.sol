// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec

import {ISwapboard} from "../../src/interfaces/ISwapboard.sol";

/// @notice Shared fill quoting helpers for tests
library FillTestLib {
    /// @notice Quotes the floored tokenA receive for an exact-tokenB fill
    function quoteAmountA(
        ISwapboard.Order memory order,
        uint128 amountB
    ) internal pure returns (uint128) {
        if (order.availableB == 0) {
            return 0;
        }
        if (amountB == order.availableB) {
            return order.availableA;
        }

        // Floor of uint128 values; result is < order.availableA when amountB < availableB.
        // forge-lint: disable-next-item(unsafe-typecast)
        return uint128((uint256(amountB) * uint256(order.availableA)) / uint256(order.availableB));
    }

    /// @notice Quotes the ceiled tokenB payment for an exact-tokenA fill
    function quoteAmountB(
        ISwapboard.Order memory order,
        uint128 amountA
    ) internal pure returns (uint128) {
        if (order.availableA == 0) {
            return 0;
        }
        if (amountA == order.availableA) {
            return order.availableB;
        }

        // Ceil of uint128 values; result is <= order.availableB.
        // forge-lint: disable-next-item(unsafe-typecast)
        return uint128(
            (uint256(amountA) * uint256(order.availableB) + uint256(order.availableA) - 1) / uint256(order.availableA)
        );
    }

    /// @notice Alias: tokenA received for a tokenA-sized fill (floor of the ceiled tokenB)
    function quoteFillAmountA(
        ISwapboard.Order memory order,
        uint128 amountA
    ) internal pure returns (uint128) {
        return quoteAmountA(order, quoteAmountB(order, amountA));
    }

    /// @notice Builds fill params from a tokenA size (converted to exact tokenB)
    function fillParams(
        ISwapboard.Order memory order,
        uint256 orderId,
        uint128 amountA
    ) internal pure returns (ISwapboard.FillOrderParams memory) {
        uint128 amountB = quoteAmountB(order, amountA);
        if (amountB == 0) {
            return ISwapboard.FillOrderParams({orderId: orderId, amountB: amountA, minAmountA: 0});
        }
        return
            ISwapboard.FillOrderParams({orderId: orderId, amountB: amountB, minAmountA: quoteAmountA(order, amountB)});
    }

    /// @notice Fills an order sending exact amountB with an explicit minimum amountA and deadline
    function fill(
        ISwapboard board,
        uint256 orderId,
        uint128 amountB,
        uint128 minAmountA,
        uint256 deadline
    ) internal {
        board.fillOrder(orderId, amountB, minAmountA, deadline);
    }

    /// @notice Fills an order sending exact amountB with an explicit minimum amountA
    function fill(
        ISwapboard board,
        uint256 orderId,
        uint128 amountB,
        uint128 minAmountA
    ) internal {
        fill(board, orderId, amountB, minAmountA, 0);
    }

    /// @notice Fills from a tokenA size (converted to exact tokenB)
    function fill(
        ISwapboard board,
        uint256 orderId,
        uint128 amountA
    ) internal {
        ISwapboard.Order memory order = board.getOrder(orderId);
        fill(board, order, orderId, amountA, 0);
    }

    /// @notice Fills from a tokenA size using a pre-fetched order snapshot and deadline
    function fill(
        ISwapboard board,
        ISwapboard.Order memory order,
        uint256 orderId,
        uint128 amountA,
        uint256 deadline
    ) internal {
        uint128 amountB = quoteAmountB(order, amountA);
        if (amountB == 0) {
            fill(board, orderId, amountA, 0, deadline);
            return;
        }
        fill(board, orderId, amountB, quoteAmountA(order, amountB), deadline);
    }

    /// @notice Fills using a pre-fetched order snapshot (no extra `getOrder`; safe after `vm.expectRevert`)
    // forge-lint: disable-next-item(internal-function-used-once)
    function fill(
        ISwapboard board,
        ISwapboard.Order memory order,
        uint256 orderId,
        uint128 amountB
    ) internal {
        fill(board, order, orderId, amountB, 0);
    }

    /// @notice Fills an order paying native ETH as tokenB with a deadline
    /// @dev `msg.value` is `value`; does not fetch the order (safe after `vm.expectRevert`)
    function fillPayEth(
        ISwapboard board,
        uint256 orderId,
        uint128,
        uint128 value,
        uint256 deadline
    ) internal {
        board.fillOrder{value: value}(orderId, value, 0, deadline);
    }

    /// @notice Fills an order paying native ETH as tokenB
    function fillPayEth(
        ISwapboard board,
        uint256 orderId,
        uint128 amountB,
        uint128 value
    ) internal {
        fillPayEth(board, orderId, amountB, value, 0);
    }

}
