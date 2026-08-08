// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

import {Script, console} from "forge-std/Script.sol";
import {Swapboard} from "../src/Swapboard.sol";

/// @title Deploy
/// @author Zak Cole (numbergroup.xyz) for Ethereum Community Foundation
/// @notice Foundry script to deploy Swapboard with a configured WETH address
contract Deploy is Script {
    /// @notice Deploys Swapboard using `WETH_ADDRESS` from the environment
    /// @return board The deployed Swapboard contract
    function run() external returns (Swapboard board) {
        address weth = vm.envAddress("WETH_ADDRESS");

        vm.startBroadcast();

        board = new Swapboard(weth);

        vm.stopBroadcast();

        // solhint-disable-next-line no-console
        console.log("Swapboard deployed at:", address(board));

        // solhint-disable-next-line no-console
        console.log("WETH address:", weth);
    }
}
