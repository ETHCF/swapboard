// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec

import {Test} from "forge-std/Test.sol";
import {Smoke} from "../script/Smoke.s.sol";
import {Swapboard} from "../src/Swapboard.sol";

/// @notice Runs the Smoke script against a fresh board
contract SmokeTest is Test {
    /// @notice Every step passes its checks and leaves exactly the two open orders behind
    function test_run_leavesOnlyTheTwoOpenOrders() public {
        Swapboard board = new Swapboard();
        vm.setEnv("CONTRACT_ADDRESS", vm.toString(address(board)));
        vm.deal(DEFAULT_SENDER, 1 ether);

        new Smoke().run();

        assertEq(board.getNextOrderId(), 8);
        for (uint256 id = 0; id < 6; ++id) {
            assertFalse(board.canFill(id));
        }
        assertTrue(board.canFill(6));
        assertTrue(board.canFill(7));
        // Only the open ETH order still holds ETH.
        assertEq(address(board).balance, 0.001 ether);
    }
}
