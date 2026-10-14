// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec

import {Test} from "forge-std/Test.sol";
import {Seed} from "../script/Seed.s.sol";
import {Swapboard} from "../src/Swapboard.sol";
import {ISwapboard} from "../src/interfaces/ISwapboard.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @notice Runs the Seed script against a fresh board
/// @dev Calls seed() directly rather than run(): the environment is process-wide, and
///      SmokeTest sets CONTRACT_ADDRESS from a parallel thread.
contract SeedTest is Test {
    Swapboard internal _board;

    function setUp() public {
        _board = new Swapboard();
        vm.deal(DEFAULT_SENDER, 1 ether);
    }

    /// @notice Every order is left open, five want ETH, and the ETH legs escrow exactly 0.006
    function test_seed_postsOpenOrdersWithEthLegs() public {
        uint256[] memory ids = new Seed().seed(_board, address(0), address(0));

        assertEq(ids.length, 10);
        uint256 wantEth;
        uint256 sellEth;
        for (uint256 i = 0; i < ids.length; ++i) {
            assertTrue(_board.canFill(ids[i]));
            ISwapboard.Order memory order = _board.getOrder(ids[i]);
            if (order.tokenB == _board.getEth()) ++wantEth;
            if (order.tokenA == _board.getEth()) ++sellEth;
        }
        assertEq(wantEth, 5);
        assertEq(sellEth, 3);
        assertEq(address(_board).balance, 0.006 ether);
    }

    /// @notice Given tokens are reused rather than redeployed
    function test_seed_reusesGivenTokens() public {
        MockERC20 tokenA = new MockERC20("A", "A", 18);
        MockERC20 tokenB = new MockERC20("B", "B", 6);

        uint256[] memory ids = new Seed().seed(_board, address(tokenA), address(tokenB));

        assertEq(_board.getOrder(ids[0]).tokenA, address(tokenA));
        assertEq(_board.getOrder(ids[2]).tokenA, address(tokenB));
    }
}
