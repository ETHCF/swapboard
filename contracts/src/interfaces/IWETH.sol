// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.33;

interface IWETH {
    function deposit() external payable;
    function withdraw(
        uint256 amount
    ) external;
}
