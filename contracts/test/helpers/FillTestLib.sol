// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec

import {ISwapboard} from "../../src/interfaces/ISwapboard.sol";

/// @notice Shared fill quoting helpers for tests
library FillTestLib {
    /// @notice Quotes the floored tokenA receive for a fill driven by tokenB paid
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

    /// @notice Quotes the tokenB actually pulled for a fill driven by tokenB paid
    /// @dev Floored tokenA may cost less than `amountB`; only the ceiled cost of that receive is paid.
    function quoteFillPayingAmountB(
        ISwapboard.Order memory order,
        uint128 amountB
    ) internal pure returns (uint128) {
        return quoteAmountB(order, quoteAmountA(order, amountB));
    }

    /// @notice Quotes the tokenA actually received for a fill driven by tokenA requested
    /// @dev Ceiled tokenB may buy more than `amountA`; that extra is paid out.
    function quoteFillAmountA(
        ISwapboard.Order memory order,
        uint128 amountA
    ) internal pure returns (uint128) {
        return quoteAmountA(order, quoteAmountB(order, amountA));
    }

    /// @notice Builds fill-paying params with the requested tokenB as the maximum
    function fillPayingParams(
        ISwapboard.Order memory,
        uint256 orderId,
        uint128 amountB
    ) internal pure returns (ISwapboard.FillOrderPayingParams memory) {
        return ISwapboard.FillOrderPayingParams({orderId: orderId, amountB: amountB, maxAmountB: amountB});
    }

    /// @notice Fills an order paying requested amountB with an explicit maximum amountB and deadline
    function fillPaying(
        ISwapboard board,
        uint256 orderId,
        uint128 amountB,
        uint128 maxAmountB,
        uint256 deadline
    ) internal {
        board.fillOrderPaying(orderId, amountB, maxAmountB, deadline);
    }

    /// @notice Fills an order paying requested amountB with an explicit maximum amountB
    function fillPaying(
        ISwapboard board,
        uint256 orderId,
        uint128 amountB,
        uint128 maxAmountB
    ) internal {
        fillPaying(board, orderId, amountB, maxAmountB, 0);
    }

    /// @notice Fills an order paying requested amountB using that amount as maxAmountB
    function fillPaying(
        ISwapboard board,
        uint256 orderId,
        uint128 amountB
    ) internal {
        fillPaying(board, orderId, amountB, amountB, 0);
    }

    /// @notice Fills paying using a pre-fetched order snapshot and deadline
    function fillPaying(
        ISwapboard board,
        ISwapboard.Order memory,
        uint256 orderId,
        uint128 amountB,
        uint256 deadline
    ) internal {
        fillPaying(board, orderId, amountB, amountB, deadline);
    }

    /// @notice Fills paying using a pre-fetched order snapshot (safe after `vm.expectRevert`)
    function fillPaying(
        ISwapboard board,
        ISwapboard.Order memory order,
        uint256 orderId,
        uint128 amountB
    ) internal {
        fillPaying(board, order, orderId, amountB, 0);
    }

    /// @notice Fills paying native ETH as tokenB with a deadline
    /// @dev `msg.value` is `amountB`; does not fetch the order (safe after `vm.expectRevert`)
    // forge-lint: disable-next-item(internal-function-used-once)
    function fillPayingEth(
        ISwapboard board,
        uint256 orderId,
        uint128 amountB,
        uint256 deadline
    ) internal {
        board.fillOrderPaying{value: amountB}(orderId, amountB, amountB, deadline);
    }

    /// @notice Fills paying native ETH as tokenB
    function fillPayingEth(
        ISwapboard board,
        uint256 orderId,
        uint128 amountB
    ) internal {
        fillPayingEth(board, orderId, amountB, 0);
    }

    /// @notice Quotes the ceiled tokenB payment for a fill against current order liquidity
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

    /// @notice Builds fill params with the requested tokenA as the minimum
    function fillParams(
        ISwapboard.Order memory,
        uint256 orderId,
        uint128 amountA
    ) internal pure returns (ISwapboard.FillOrderParams memory) {
        return ISwapboard.FillOrderParams({orderId: orderId, amountA: amountA, minAmountA: amountA});
    }

    /// @notice Fills an order with an explicit minimum amountA and deadline
    function fill(
        ISwapboard board,
        uint256 orderId,
        uint128 amountA,
        uint128 minAmountA,
        uint256 deadline
    ) internal {
        board.fillOrder(orderId, amountA, minAmountA, deadline);
    }

    /// @notice Fills an order with an explicit minimum amountA (no order fetch; safe after `vm.expectRevert`)
    function fill(
        ISwapboard board,
        uint256 orderId,
        uint128 amountA,
        uint128 minAmountA
    ) internal {
        fill(board, orderId, amountA, minAmountA, 0);
    }

    /// @notice Fills an order using the requested amountA as the minimum
    function fill(
        ISwapboard board,
        uint256 orderId,
        uint128 amountA
    ) internal {
        fill(board, orderId, amountA, amountA, 0);
    }

    /// @notice Fills using a pre-fetched order snapshot and deadline
    function fill(
        ISwapboard board,
        ISwapboard.Order memory,
        uint256 orderId,
        uint128 amountA,
        uint256 deadline
    ) internal {
        fill(board, orderId, amountA, amountA, deadline);
    }

    /// @notice Fills using a pre-fetched order snapshot (no extra `getOrder`; safe after `vm.expectRevert`)
    // forge-lint: disable-next-item(internal-function-used-once)
    function fill(
        ISwapboard board,
        ISwapboard.Order memory order,
        uint256 orderId,
        uint128 amountA
    ) internal {
        fill(board, order, orderId, amountA, 0);
    }

    /// @notice Fills an order paying native ETH as tokenB with a deadline
    /// @dev `msg.value` is `value`; does not fetch the order (safe after `vm.expectRevert`)
    function fillPayEth(
        ISwapboard board,
        uint256 orderId,
        uint128 amountA,
        uint128 value,
        uint256 deadline
    ) internal {
        board.fillOrder{value: value}(orderId, amountA, amountA, deadline);
    }

    /// @notice Fills an order paying native ETH as tokenB
    function fillPayEth(
        ISwapboard board,
        uint256 orderId,
        uint128 amountA,
        uint128 value
    ) internal {
        fillPayEth(board, orderId, amountA, value, 0);
    }
}
