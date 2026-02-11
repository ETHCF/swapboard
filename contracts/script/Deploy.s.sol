// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.33;

import {Script, console} from "forge-std/Script.sol";
import {Swapboard} from "../src/Swapboard.sol";

contract Deploy is Script {
    function run() external returns (Swapboard board) {
        address weth = vm.envAddress("WETH_ADDRESS");

        vm.startBroadcast();

        board = new Swapboard(weth);

        vm.stopBroadcast();

        console.log("Swapboard deployed at:", address(board));
        console.log("WETH address:", weth);
    }
}
