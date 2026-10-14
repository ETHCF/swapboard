// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

import {Script, console} from "forge-std/Script.sol";
import {Swapboard} from "../src/Swapboard.sol";

/// @title Deploy
/// @author Zak Cole (numbergroup.xyz) for Ethereum Community Foundation
/// @notice Foundry script to deploy Swapboard
/// @dev Swapboard hardcodes the canonical Permit2 singleton. On a chain where Permit2 is not
///      deployed the Permit2 overloads revert with empty returndata, which is hard to diagnose
///      after launch, so `run` aborts when that address has no code.
contract Deploy is Script {
    /// @notice Canonical Permit2 SignatureTransfer singleton expected by Swapboard
    address private constant _PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    /// @notice Thrown when Permit2 has no code on the target chain
    /// @param permit2 The canonical Permit2 address that was checked
    error Permit2NotDeployed(address permit2);

    /// @notice Deploys Swapboard, aborting when Permit2 is missing on the target chain
    /// @return board The deployed Swapboard contract
    function run() external returns (Swapboard board) {
        if (_PERMIT2.code.length == 0) {
            revert Permit2NotDeployed(_PERMIT2);
        }

        // solhint-disable-next-line no-console
        console.log("Permit2 found at:", _PERMIT2);

        vm.startBroadcast();

        board = new Swapboard();

        vm.stopBroadcast();

        // solhint-disable-next-line no-console
        console.log("Swapboard deployed at:", address(board));

        // solhint-disable-next-line no-console
        console.log("ETH sentinel:", board.getEth());
    }
}
