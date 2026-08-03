// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.33;

// solhint-disable use-natspec

/// @title UpgradeableToken
/// @notice Simulates a token that can be upgraded to change behavior
contract UpgradeableToken {
    string public name = "Upgradeable Token";
    string public symbol = "UPGRADE";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    bool public isFeeOnTransfer;
    uint256 public feePercent = 5;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // solhint-disable-next-line gas-indexed-events
    event Transfer(address indexed from, address indexed to, uint256 amount);

    // solhint-disable-next-line gas-indexed-events
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    function setFeeOnTransfer(
        bool _enabled
    ) external {
        isFeeOnTransfer = _enabled;
    }

    function mint(
        address to,
        uint256 amount
    ) external {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(
        address spender,
        uint256 amount
    ) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(
        address to,
        uint256 amount
    ) external returns (bool) {
        uint256 fee = isFeeOnTransfer ? (amount * feePercent) / 100 : 0;
        uint256 netAmount = amount - fee;
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += netAmount;
        if (fee > 0) {
            totalSupply -= fee;
        }
        emit Transfer(msg.sender, to, netAmount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        uint256 fee = isFeeOnTransfer ? (amount * feePercent) / 100 : 0;
        uint256 netAmount = amount - fee;
        balanceOf[from] -= amount;
        balanceOf[to] += netAmount;
        if (fee > 0) {
            totalSupply -= fee;
        }
        emit Transfer(from, to, netAmount);
        return true;
    }
}
