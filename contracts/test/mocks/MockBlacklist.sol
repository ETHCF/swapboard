// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.33;

// solhint-disable use-natspec

/// @title MockBlacklist
/// @notice Mock ERC20 with blacklist functionality (like USDC/USDT)
contract MockBlacklist {
    error Blacklisted();

    string public name = "Blacklist Token";
    string public symbol = "BLACK";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => bool) public isBlacklisted;

    // solhint-disable-next-line gas-indexed-events
    event Transfer(address indexed from, address indexed to, uint256 amount);

    // solhint-disable-next-line gas-indexed-events
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    modifier notBlacklisted(
        address account
    ) {
        if (isBlacklisted[account]) {
            revert Blacklisted();
        }
        _;
    }

    function blacklist(
        address account
    ) external {
        isBlacklisted[account] = true;
    }

    function unblacklist(
        address account
    ) external {
        isBlacklisted[account] = false;
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
    ) external notBlacklisted(msg.sender) notBlacklisted(to) returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external notBlacklisted(from) notBlacklisted(to) returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - amount;
        }
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}
