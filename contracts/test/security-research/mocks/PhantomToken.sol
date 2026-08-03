// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.33;

// solhint-disable use-natspec

/// @title PhantomToken
/// @notice Token that lies about transfers - returns true but doesn't transfer
contract PhantomToken {
    string public name = "Phantom Token";
    string public symbol = "PHANTOM";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    // solhint-disable-next-line gas-indexed-events
    event Transfer(address indexed from, address indexed to, uint256 amount);

    // solhint-disable-next-line gas-indexed-events
    event Approval(address indexed owner, address indexed spender, uint256 amount);

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
        address,
        uint256
    ) external pure returns (bool) {
        // Lies about transfer - returns true but doesn't transfer
        return true;
    }

    function transferFrom(
        address,
        address,
        uint256
    ) external pure returns (bool) {
        // Lies about transfer - returns true but doesn't transfer
        return true;
    }
}
