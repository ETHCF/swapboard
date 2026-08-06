// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.33;

// solhint-disable use-natspec

import {MockERC20} from "./MockERC20.sol";

contract MockWETH is MockERC20 {
    error InsufficientWETH();
    error ETHTransferFailed();

    // solhint-disable-next-line gas-indexed-events
    event Deposit(address indexed dst, uint256 wad);

    // solhint-disable-next-line gas-indexed-events
    event Withdrawal(address indexed src, uint256 wad);

    constructor() MockERC20("Wrapped Ether", "WETH", 18) {}

    function deposit() external payable {
        _mint(msg.sender, msg.value);

        emit Deposit(msg.sender, msg.value);
    }

    function withdraw(
        uint256 amount
    ) external {
        if (_balanceOf[msg.sender] < amount) {
            revert InsufficientWETH();
        }

        _burn(msg.sender, amount);

        emit Withdrawal(msg.sender, amount);

        (bool success,) = payable(msg.sender).call{value: amount}("");
        if (!success) {
            revert ETHTransferFailed();
        }
    }

    // solhint-disable-next-line no-complex-fallback
    receive() external payable {
        _mint(msg.sender, msg.value);

        emit Deposit(msg.sender, msg.value);
    }
}
