// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

import {Script, console} from "forge-std/Script.sol";
import {ISwapboard} from "../src/interfaces/ISwapboard.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";

/// @title Seed
/// @author Number Group (numbergroup.xyz) for Ethereum Community Foundation
/// @notice Fills a testnet board with a spread of open orders for UI testing
/// @dev Testnets only. Reuses freely mintable tokens (e.g. the Smoke run's SMKA/SMKB) when
///      SEED_TOKEN_A / SEED_TOKEN_B are set, and deploys fresh ones otherwise. Posts one
///      createOrders batch: tokens for ETH (purchasable with ETH), ETH for tokens, and token for
///      token, mixing partial-fill and all-or-nothing orders.
///
///      CONTRACT_ADDRESS=0x... SEED_TOKEN_A=0x... SEED_TOKEN_B=0x... forge script script/Seed.s.sol \
///          --rpc-url sepolia --account sepolia-deployer --broadcast
contract Seed is Script {
    /// @notice ETH escrowed by the ETH-selling orders, in total
    uint256 internal constant ETH_ESCROW = 0.006 ether;

    /// @notice Number of orders posted
    uint256 internal constant ORDER_COUNT = 10;

    /// @notice Seeds the board at CONTRACT_ADDRESS with the tokens named in the environment
    /// @return ids Identifiers of the posted orders, in the order _orders lists them
    function run() external returns (uint256[] memory ids) {
        return seed(
            ISwapboard(vm.envAddress("CONTRACT_ADDRESS")),
            vm.envOr("SEED_TOKEN_A", address(0)),
            vm.envOr("SEED_TOKEN_B", address(0))
        );
    }

    /// @notice Posts the orders, deploying whichever token is not given
    /// @param board Board to seed
    /// @param tokenA Mintable 18-decimal token to reuse, or zero to deploy one
    /// @param tokenB Mintable 6-decimal token to reuse, or zero to deploy one
    /// @return ids Identifiers of the posted orders, in the order _orders lists them
    function seed(
        ISwapboard board,
        address tokenA,
        address tokenB
    ) public returns (uint256[] memory ids) {
        vm.startBroadcast();
        (, address me,) = vm.readCallers();

        if (tokenA == address(0)) tokenA = address(new MockERC20("Swapboard Smoke A", "SMKA", 18));
        if (tokenB == address(0)) tokenB = address(new MockERC20("Swapboard Smoke B", "SMKB", 6));
        MockERC20(tokenA).mint(me, 10_000e18);
        MockERC20(tokenB).mint(me, 10_000e6);
        MockERC20(tokenA).approve(address(board), type(uint256).max);
        MockERC20(tokenB).approve(address(board), type(uint256).max);

        ids = board.createOrders{value: ETH_ESCROW}(_orders(tokenA, tokenB, board.getEth()));

        vm.stopBroadcast();

        // solhint-disable no-console
        console.log("Seeded board:", address(board));
        console.log("SMKA:", tokenA);
        console.log("SMKB:", tokenB);
        console.log("Order ids:", ids[0], "to", ids[ids.length - 1]);
        // solhint-enable no-console
    }

    /// @notice The orders to post; the ETH-selling legs must sum to ETH_ESCROW
    /// @param tokenA 18-decimal token
    /// @param tokenB 6-decimal token
    /// @param eth The board's native ETH sentinel
    /// @return orders createOrders arguments
    function _orders(
        address tokenA,
        address tokenB,
        address eth
    ) internal pure returns (ISwapboard.CreateOrderParams[] memory orders) {
        orders = new ISwapboard.CreateOrderParams[](ORDER_COUNT);

        // Purchasable with ETH.
        orders[0] = _order(tokenA, 1000e18, eth, 0.01 ether, true);
        orders[1] = _order(tokenA, 250e18, eth, 0.005 ether, false);
        orders[2] = _order(tokenB, 5000e6, eth, 0.02 ether, true);
        orders[3] = _order(tokenB, 100e6, eth, 0.0005 ether, false);
        orders[4] = _order(tokenA, 10e18, eth, 0.0001 ether, true);

        // Selling ETH: 0.002 + 0.001 + 0.003 = ETH_ESCROW.
        orders[5] = _order(eth, 0.002 ether, tokenB, 5e6, true);
        orders[6] = _order(eth, 0.001 ether, tokenA, 1e18, false);
        orders[7] = _order(eth, 0.003 ether, tokenA, 1000e18, true);

        // Token for token.
        orders[8] = _order(tokenB, 200e6, tokenA, 100e18, true);
        orders[9] = _order(tokenA, 50e18, tokenB, 120e6, false);
    }

    /// @notice Builds createOrder arguments
    /// @param tokenA Asset to sell
    /// @param amountA Amount of tokenA to escrow
    /// @param tokenB Asset wanted
    /// @param amountB Amount of tokenB wanted
    /// @param partialFillAllowed Whether the order may be filled in parts
    /// @return The createOrder arguments
    function _order(
        address tokenA,
        uint128 amountA,
        address tokenB,
        uint128 amountB,
        bool partialFillAllowed
    ) internal pure returns (ISwapboard.CreateOrderParams memory) {
        return ISwapboard.CreateOrderParams({
            tokenA: tokenA, amountA: amountA, tokenB: tokenB, amountB: amountB, partialFillAllowed: partialFillAllowed
        });
    }
}
