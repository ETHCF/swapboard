// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import {Script, console} from "forge-std/Script.sol";
import {OTCBoard} from "../src/OTCBoard.sol";

contract Deploy is Script {
    function run() external returns (OTCBoard board) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        board = new OTCBoard();

        vm.stopBroadcast();

        console.log("OTCBoard deployed at:", address(board));
    }
}
