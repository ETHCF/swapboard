// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec

import {MockERC20} from "./MockERC20.sol";

/// @title MockBlacklist
/// @notice Mock ERC20 with blacklist functionality (like USDC/USDT)
contract MockBlacklist is MockERC20 {
    error Blacklisted();

    mapping(address => bool) private _isBlacklisted;

    constructor() MockERC20("Blacklist Token", "BLACK", 18) {}

    modifier notBlacklisted(
        address account
    ) {
        if (_isBlacklisted[account]) {
            revert Blacklisted();
        }
        _;
    }

    function getIsBlacklisted(
        address account
    ) external view returns (bool) {
        return _isBlacklisted[account];
    }

    function blacklist(
        address account
    ) external {
        _isBlacklisted[account] = true;
    }

    function unblacklist(
        address account
    ) external {
        _isBlacklisted[account] = false;
    }

    function transfer(
        address to,
        uint256 amount
    ) public override notBlacklisted(msg.sender) notBlacklisted(to) returns (bool) {
        return super.transfer(to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override notBlacklisted(from) notBlacklisted(to) returns (bool) {
        return super.transferFrom(from, to, amount);
    }
}
