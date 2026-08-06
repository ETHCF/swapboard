// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.33;

// solhint-disable use-natspec

import {MockERC20} from "./MockERC20.sol";

/// @title MockPausable
/// @notice Mock ERC20 with pause functionality
contract MockPausable is MockERC20 {
    error Paused();

    bool private _paused;

    constructor() MockERC20("Pausable Token", "PAUSE", 18) {}

    modifier whenNotPaused() {
        if (_paused) {
            revert Paused();
        }
        _;
    }

    function getPaused() external view returns (bool) {
        return _paused;
    }

    function pause() external {
        _paused = true;
    }

    function unpause() external {
        _paused = false;
    }

    function transfer(
        address to,
        uint256 amount
    ) public override whenNotPaused returns (bool) {
        return super.transfer(to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override whenNotPaused returns (bool) {
        return super.transferFrom(from, to, amount);
    }
}
