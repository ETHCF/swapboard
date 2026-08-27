// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec

import {ISwapboard} from "../../src/interfaces/ISwapboard.sol";

/// @notice Shared create-order param builders for tests
library OrderTestLib {
    /// @notice Builds a non-partial order creation params struct
    function order(
        address tokenA,
        uint128 amountA,
        address tokenB,
        uint128 amountB
    ) internal pure returns (ISwapboard.CreateOrderParams memory) {
        return ISwapboard.CreateOrderParams({
            tokenA: tokenA, amountA: amountA, tokenB: tokenB, amountB: amountB, partialFillAllowed: false
        });
    }

    /// @notice Builds a partial-fill order creation params struct
    function orderPartial(
        address tokenA,
        uint128 amountA,
        address tokenB,
        uint128 amountB
    ) internal pure returns (ISwapboard.CreateOrderParams memory) {
        return ISwapboard.CreateOrderParams({
            tokenA: tokenA, amountA: amountA, tokenB: tokenB, amountB: amountB, partialFillAllowed: true
        });
    }
}
