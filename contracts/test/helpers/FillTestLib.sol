// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec

import {ISwapboard} from "../../src/interfaces/ISwapboard.sol";

/// @notice Shared fill quoting helpers for tests
library FillTestLib {
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

    /// @notice Builds fill params with the quoted tokenB payment as the minimum
    function fillParams(
        ISwapboard.Order memory order,
        uint256 orderId,
        uint128 amountA
    ) internal pure returns (ISwapboard.FillOrderParams memory) {
        return
            ISwapboard.FillOrderParams({orderId: orderId, amountA: amountA, minAmountB: quoteAmountB(order, amountA)});
    }

    /// @notice Fills an order with an explicit minimum amountB and deadline
    function fill(
        ISwapboard board,
        uint256 orderId,
        uint128 amountA,
        uint128 minAmountB,
        uint256 deadline
    ) internal {
        board.fillOrder(orderId, amountA, minAmountB, deadline);
    }

    /// @notice Fills an order with an explicit minimum amountB (no order fetch; safe after `vm.expectRevert`)
    function fill(
        ISwapboard board,
        uint256 orderId,
        uint128 amountA,
        uint128 minAmountB
    ) internal {
        fill(board, orderId, amountA, minAmountB, 0);
    }

    /// @notice Fills an order using the quoted payment as the minimum amountB
    function fill(
        ISwapboard board,
        uint256 orderId,
        uint128 amountA
    ) internal {
        ISwapboard.Order memory order = board.getOrder(orderId);
        fill(board, orderId, amountA, quoteAmountB(order, amountA), 0);
    }

    /// @notice Fills using a pre-fetched order snapshot and deadline
    // forge-lint: disable-next-item(internal-function-used-once)
    function fill(
        ISwapboard board,
        ISwapboard.Order memory order,
        uint256 orderId,
        uint128 amountA,
        uint256 deadline
    ) internal {
        fill(board, orderId, amountA, quoteAmountB(order, amountA), deadline);
    }

    /// @notice Fills using a pre-fetched order snapshot (no extra `getOrder`; safe after `vm.expectRevert`)
    // forge-lint: disable-next-item(internal-function-used-once)
    function fill(
        ISwapboard board,
        ISwapboard.Order memory order,
        uint256 orderId,
        uint128 amountA
    ) internal {
        fill(board, orderId, amountA, quoteAmountB(order, amountA), 0);
    }

    /// @notice Fills an order paying native ETH as tokenB with a deadline
    /// @dev Sends `minAmountB` as `msg.value`; use when minimum equals the quoted payment
    function fillPayEth(
        ISwapboard board,
        uint256 orderId,
        uint128 amountA,
        uint128 minAmountB,
        uint256 deadline
    ) internal {
        board.fillOrder{value: minAmountB}(orderId, amountA, minAmountB, deadline);
    }

    /// @notice Fills paying ETH when `minAmountB` may be below the quoted payment
    // forge-lint: disable-next-item(internal-function-used-once)
    function fillPayEthQuoted(
        ISwapboard board,
        uint256 orderId,
        uint128 amountA,
        uint128 minAmountB,
        uint256 deadline
    ) internal {
        uint128 quotedB = quoteAmountB(board.getOrder(orderId), amountA);
        board.fillOrder{value: quotedB}(orderId, amountA, minAmountB, deadline);
    }

    /// @notice Fills an order paying native ETH as tokenB
    function fillPayEth(
        ISwapboard board,
        uint256 orderId,
        uint128 amountA,
        uint128 minAmountB
    ) internal {
        fillPayEth(board, orderId, amountA, minAmountB, 0);
    }

    /// @notice Fills paying ETH when `minAmountB` may be below the quoted payment
    function fillPayEthQuoted(
        ISwapboard board,
        uint256 orderId,
        uint128 amountA,
        uint128 minAmountB
    ) internal {
        fillPayEthQuoted(board, orderId, amountA, minAmountB, 0);
    }
}
