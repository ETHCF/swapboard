// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Script, console} from "forge-std/Script.sol";
import {Swapboard} from "../src/Swapboard.sol";

contract Deploy is Script {
    function run() external returns (Swapboard board) {
        vm.startBroadcast();

        board = new Swapboard();

        vm.stopBroadcast();

        console.log("Swapboard deployed at:", address(board));
    }
}
