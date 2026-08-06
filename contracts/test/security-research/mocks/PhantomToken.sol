// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec

import {MockERC20} from "../../mocks/MockERC20.sol";

/// @title PhantomToken
/// @notice Token that lies about transfers - returns true but doesn't transfer
contract PhantomToken is MockERC20 {
    constructor() MockERC20("Phantom Token", "PHANTOM", 18) {}

    function transfer(
        address,
        uint256
    ) public pure override returns (bool) {
        // Lies about transfer - returns true but doesn't transfer
        return true;
    }

    function transferFrom(
        address,
        address,
        uint256
    ) public pure override returns (bool) {
        // Lies about transfer - returns true but doesn't transfer
        return true;
    }
}
