// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec
// solhint-disable no-console
// solhint-disable gas-small-strings

import {Test, console2} from "forge-std/Test.sol";
import {Swapboard} from "../../src/Swapboard.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {SwapboardHandler} from "./Handler.sol";

/// @title SwapboardInvariantTest
/// @notice Invariant tests for Swapboard contract
/// @dev Tests protocol invariants that must hold across all state transitions
contract SwapboardInvariantTest is Test {
    Swapboard internal _board;
    MockERC20 internal _tokenA;
    MockERC20 internal _tokenB;
    SwapboardHandler internal _handler;

    /// @notice Deploys fixtures for each test
    function setUp() public {
        _board = new Swapboard();
        _tokenA = new MockERC20("Token A", "TKA", 18);
        _tokenB = new MockERC20("Token B", "TKB", 18);
        _handler = new SwapboardHandler(_board, _tokenA, _tokenB);

        // Target only the _handler for fuzzing
        targetContract(address(_handler));

        // Exclude _board from direct calls
        excludeContract(address(_board));
        excludeContract(address(_tokenA));
        excludeContract(address(_tokenB));
    }

    /// @notice Contract _tokenA balance must equal deposited minus withdrawn
    /// @dev This is the core solvency invariant
    function invariant_solvency() public view {
        uint256 actualBalance = _tokenA.balanceOf(address(_board));
        uint256 expectedBalance = _handler.getGhostTotalTokenADeposited() - _handler.getGhostTotalTokenAWithdrawn();

        assertEq(actualBalance, expectedBalance);
    }

    /// @notice Contract ETH balance must equal deposited minus withdrawn
    function invariant_ethSolvency() public view {
        uint256 actualBalance = address(_board).balance;
        uint256 expectedBalance = _handler.getGhostTotalEthDeposited() - _handler.getGhostTotalEthWithdrawn();

        assertEq(actualBalance, expectedBalance);
    }

    /// @notice Contract tokenA balance must equal sum of remaining escrow across all orders
    /// @dev Includes inactive-order dust left by floor rounding on partial fills
    function invariant_balanceEqualsActiveOrderSum() public view {
        uint256 actualBalance = _tokenA.balanceOf(address(_board));
        uint256 activeOrderSum = _handler.sumActiveOrderAmounts();

        assertEq(actualBalance, activeOrderSum);
    }

    /// @notice Contract ETH balance must equal sum of remaining ETH escrow across all orders
    function invariant_ethBalanceEqualsActiveOrderSum() public view {
        uint256 actualBalance = address(_board).balance;
        uint256 activeOrderSum = _handler.sumActiveEthOrderAmounts();

        assertEq(actualBalance, activeOrderSum);
    }

    /// @notice Orders created must equal filled + cancelled + active
    function invariant_orderAccounting() public view {
        uint256 created = _handler.getGhostOrdersCreated();
        uint256 filled = _handler.getGhostOrdersFilled();
        uint256 cancelled = _handler.getGhostOrdersCancelled();
        uint256 active = _handler.getGhostActiveOrders();

        assertEq(created, filled + cancelled + active);
    }

    /// @notice nextOrderId must equal total orders created
    function invariant_nextOrderIdConsistency() public view {
        assertEq(_board.getNextOrderId(), _handler.getGhostOrdersCreated());
    }

    /// @notice Active order count from ghost must match actual count
    function invariant_activeOrderCount() public view {
        uint256 ghostActive = _handler.getGhostActiveOrders();
        uint256 actualActive = _handler.countActiveOrders();

        assertEq(ghostActive, actualActive);
    }

    /// @notice Filled + cancelled orders must not exceed created orders
    function invariant_noOvercounting() public view {
        uint256 created = _handler.getGhostOrdersCreated();
        uint256 filled = _handler.getGhostOrdersFilled();
        uint256 cancelled = _handler.getGhostOrdersCancelled();

        assertLe(filled + cancelled, created);
    }

    /// @notice Original amountA/amountB never change; available never exceeds them
    /// @dev Also: active ⇒ both available > 0; inactive ⇒ at least one available is 0
    function invariant_amountAccounting() public view {
        _handler.assertAmountInvariants();
    }

    /// @notice Token balance should never be negative (implicit via uint256 but good sanity check)
    function invariant_nonNegativeBalance() public view {
        uint256 balance = _tokenA.balanceOf(address(_board));
        assertGe(balance, 0);
    }

    /// @notice Call summary for debugging
    function invariant_callSummary() public view {
        console2.log("--- Invariant Test Summary ---");
        console2.log("createOrder calls:", _handler.getCallsCreateOrder());
        console2.log("createOrderSellEth calls:", _handler.getCallsCreateOrderSellEth());
        console2.log("createOrderWantEth calls:", _handler.getCallsCreateOrderWantEth());
        console2.log("createOrderAllowPartial calls:", _handler.getCallsCreateOrderAllowPartial());
        console2.log("createOrders calls:", _handler.getCallsCreateOrders());
        console2.log("fillOrder calls:", _handler.getCallsFillOrder());
        console2.log("fillOrders calls:", _handler.getCallsFillOrders());
        console2.log("cancelOrder calls:", _handler.getCallsCancelOrder());
        console2.log("cancelOrders calls:", _handler.getCallsCancelOrders());
        console2.log("modifyOrder calls:", _handler.getCallsModifyOrder());
        console2.log("setPartialFillAllowed calls:", _handler.getCallsSetPartialFillAllowed());
        console2.log("Orders created:", _handler.getGhostOrdersCreated());
        console2.log("Orders filled:", _handler.getGhostOrdersFilled());
        console2.log("Orders cancelled:", _handler.getGhostOrdersCancelled());
        console2.log("Active orders:", _handler.getGhostActiveOrders());
        console2.log("Contract tokenA balance:", _tokenA.balanceOf(address(_board)));
        console2.log("Contract ETH balance:", address(_board).balance);
        console2.log("------------------------------");
    }
}
