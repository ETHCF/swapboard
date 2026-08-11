// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

import {Script, console} from "forge-std/Script.sol";
import {Swapboard} from "../src/Swapboard.sol";

/// @title Deploy
/// @author Zak Cole (numbergroup.xyz) for Ethereum Community Foundation
/// @notice Foundry script to deploy Swapboard
contract Deploy is Script {
    /// @notice Deploys Swapboard
    /// @return board The deployed Swapboard contract
    function run() external returns (Swapboard board) {
        vm.startBroadcast();

        board = new Swapboard();

        vm.stopBroadcast();

        // solhint-disable-next-line no-console
        console.log("Swapboard deployed at:", address(board));

        // solhint-disable-next-line no-console
        console.log("ETH sentinel:", board.getEth());
    }
}
