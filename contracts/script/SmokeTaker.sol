// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

import {ISwapboard} from "../src/interfaces/ISwapboard.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";

/// @title SmokeTaker
/// @author Number Group (numbergroup.xyz) for Ethereum Community Foundation
/// @notice Takes the other side of the Smoke script's orders
/// @dev The board rejects a maker filling their own order (`SelfFill`), and a smoke run has one
///      broadcaster. The broadcaster stays the maker and deploys one of these to fill against:
///      it holds the tokenB it pays with, and keeps whatever tokenA it is paid.
contract SmokeTaker {
    /// @notice Board every fill is forwarded to
    ISwapboard private immutable _BOARD;

    /// @notice Funds the taker's ETH tokenB payments
    /// @param board Board every fill is forwarded to
    constructor(
        ISwapboard board
    ) payable {
        _BOARD = board;
    }

    /// @notice Accepts ETH tokenA payouts
    receive() external payable {}

    /// @notice Lets the board pull an ERC20 tokenB without limit
    /// @param token Token this taker pays with
    function approve(
        MockERC20 token
    ) external {
        token.approve(address(_BOARD), type(uint256).max);
    }

    /// @notice Fills one order by exact tokenB sent
    /// @param orderId The order to fill
    /// @param amountB Exact amount of tokenB to send
    /// @param minAmountA Minimum amount of tokenA to accept
    /// @param deadline Unix timestamp after which the fill reverts (0 = no deadline)
    function fillOrder(
        uint256 orderId,
        uint128 amountB,
        uint128 minAmountA,
        uint256 deadline
    ) external payable {
        _BOARD.fillOrder{value: msg.value}(orderId, amountB, minAmountA, deadline, address(0));
    }

    /// @notice Fills several orders by exact tokenB sent
    /// @param fills Fill arguments in execution order
    /// @param deadline Unix timestamp after which the batch reverts (0 = no deadline)
    function fillOrders(
        ISwapboard.FillOrderParams[] calldata fills,
        uint256 deadline
    ) external payable {
        _BOARD.fillOrders{value: msg.value}(fills, deadline, address(0));
    }
}
