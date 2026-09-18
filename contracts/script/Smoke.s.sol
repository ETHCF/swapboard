// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

import {Script, console} from "forge-std/Script.sol";
import {ISwapboard} from "../src/interfaces/ISwapboard.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {SmokeTaker} from "./SmokeTaker.sol";

/// @title Smoke
/// @author Number Group (numbergroup.xyz) for Ethereum Community Foundation
/// @notice Drives every Swapboard v2 entry point against a live deployment
/// @dev Testnets only: deploys two throwaway, freely mintable ERC20s and trades them against
///      itself. The broadcaster is the maker of every order; a throwaway `SmokeTaker` it deploys
///      fills them, since the board rejects a maker filling their own order. Ends with two orders
///      left open so the subgraph and the UI have live orders to show.
///
///      CONTRACT_ADDRESS=0x... forge script script/Smoke.s.sol \
///          --rpc-url sepolia --account sepolia-deployer --broadcast
contract Smoke is Script {
    /// @notice ETH escrowed per native-ETH leg; small, since it only has to move
    uint128 internal constant ETH_LEG = 0.001 ether;

    /// @notice Board under test
    ISwapboard internal _board;

    /// @notice The board's native ETH sentinel
    address internal _eth;

    /// @notice Throwaway 18-decimal token
    MockERC20 internal _tokenA;

    /// @notice Throwaway 6-decimal token
    MockERC20 internal _tokenB;

    /// @notice Throwaway contract that takes the other side of every order
    SmokeTaker internal _taker;

    /// @notice Thrown when the board is not in the state a step should have left it in
    /// @param step The step that failed
    error SmokeCheckFailed(string step);

    /// @notice Runs every step against the board at CONTRACT_ADDRESS
    function run() external {
        _board = ISwapboard(vm.envAddress("CONTRACT_ADDRESS"));
        _eth = _board.getEth();

        vm.startBroadcast();
        (, address me,) = vm.readCallers();

        _tokenA = new MockERC20("Swapboard Smoke A", "SMKA", 18);
        _tokenB = new MockERC20("Swapboard Smoke B", "SMKB", 6);
        _tokenA.mint(me, 1_000_000e18);
        _tokenB.mint(me, 1_000_000e6);
        _tokenA.approve(address(_board), type(uint256).max);
        _tokenB.approve(address(_board), type(uint256).max);

        // The taker pays tokenB and is funded for the one order wanting ETH.
        _taker = new SmokeTaker{value: ETH_LEG}(_board);
        _tokenB.mint(address(_taker), 1_000_000e6);
        _taker.approve(_tokenB);

        _partialFillLifecycle();
        _nativeEth();
        _batches();
        (uint256 openErc20, uint256 openEth) = _leaveOpenOrders();

        vm.stopBroadcast();

        // solhint-disable no-console
        console.log("Smoke run complete against:", address(_board));
        console.log("SMKA (18 decimals, open mint):", address(_tokenA));
        console.log("SMKB (6 decimals, open mint):", address(_tokenB));
        console.log("Open SMKA->SMKB order:", openErc20);
        console.log("Open ETH->SMKB order:", openEth);
        // solhint-enable no-console
    }

    /// @notice One partially fillable ERC20 order through two partial fills, a reprice, a
    ///         partial-fill flag flip, and a cancel
    function _partialFillLifecycle() internal {
        uint256 id = _board.createOrder(_params(address(_tokenA), 100e18, address(_tokenB), 200e6, true));

        // At 2 SMKB per SMKA, each 50 SMKB payment buys 25 SMKA.
        _taker.fillOrder(id, 50e6, 25e18, 0);
        _taker.fillOrder(id, 50e6, 25e18, 0);
        ISwapboard.Order memory order = _board.getOrder(id);
        _check(order.availableA == 50e18 && order.availableB == 100e6, "partial fills");

        _board.modifyOrder(id, _amounts(order), ISwapboard.ModifyOrderParams({availableA: 60e18, availableB: 150e6}));
        order = _board.getOrder(id);
        _check(order.availableA == 60e18 && order.amountA == 60e18, "modifyOrder");

        _board.setPartialFillAllowed(id, false);
        _board.cancelOrder(id);
        _check(!_board.canFill(id), "cancelOrder");
    }

    /// @notice Native ETH on each side: sell ETH for a token, and sell a token for ETH
    function _nativeEth() internal {
        uint256 sellEth = _board.createOrder{value: ETH_LEG}(_params(_eth, ETH_LEG, address(_tokenB), 2e6, false));
        _taker.fillOrder(sellEth, 2e6, ETH_LEG, 0);
        _check(!_board.canFill(sellEth), "fill ETH-for-token");

        uint256 buyEth = _board.createOrder(_params(address(_tokenA), 10e18, _eth, ETH_LEG, false));
        _taker.fillOrder{value: ETH_LEG}(buyEth, ETH_LEG, 10e18, 0);
        _check(!_board.canFill(buyEth), "fill token-for-ETH");
    }

    /// @notice Every batch entry point, mixing ERC20 and native ETH legs
    function _batches() internal {
        ISwapboard.CreateOrderParams[] memory creates = new ISwapboard.CreateOrderParams[](3);
        creates[0] = _params(address(_tokenA), 10e18, address(_tokenB), 20e6, true);
        creates[1] = _params(address(_tokenA), 10e18, address(_tokenB), 30e6, false);
        creates[2] = _params(_eth, ETH_LEG, address(_tokenB), 5e6, true);
        uint256[] memory ids = _board.createOrders{value: ETH_LEG}(creates);

        // A partial fill and a full fill, paid as one SMKB pull.
        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = ISwapboard.FillOrderParams({orderId: ids[0], amountB: 10e6, minAmountA: 5e18});
        fills[1] = ISwapboard.FillOrderParams({orderId: ids[1], amountB: 30e6, minAmountA: 10e18});
        _taker.fillOrders(fills, 0);
        _check(_board.canFill(ids[0]) && !_board.canFill(ids[1]), "fillOrders");

        // Half of the ETH order, at 5 SMKB per ETH.
        ISwapboard.FillOrderParams[] memory ethFills = new ISwapboard.FillOrderParams[](1);
        ethFills[0] = ISwapboard.FillOrderParams({orderId: ids[2], amountB: 2.5e6, minAmountA: ETH_LEG / 2});
        _taker.fillOrders(ethFills, 0);
        _check(_board.getOrder(ids[2]).availableA == ETH_LEG / 2, "fillOrders (ETH payout)");

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](1);
        mods[0] = ISwapboard.ModifyOrdersParams({
            orderId: ids[0],
            previousAmounts: _amounts(_board.getOrder(ids[0])),
            updatedOrder: ISwapboard.ModifyOrderParams({availableA: 8e18, availableB: 16e6})
        });
        _board.modifyOrders(mods);
        _check(_board.getOrder(ids[0]).availableA == 8e18, "modifyOrders");

        uint256[] memory cancels = new uint256[](2);
        cancels[0] = ids[0];
        cancels[1] = ids[2];
        _board.cancelOrders(cancels);
        _check(!_board.canFill(ids[0]) && !_board.canFill(ids[2]), "cancelOrders");
    }

    /// @notice Leaves one partially fillable ERC20 order and one ETH order open
    /// @return erc20Order The open SMKA-for-SMKB order
    /// @return ethOrder The open ETH-for-SMKB order
    function _leaveOpenOrders() internal returns (uint256 erc20Order, uint256 ethOrder) {
        erc20Order = _board.createOrder(_params(address(_tokenA), 500e18, address(_tokenB), 1000e6, true));
        ethOrder = _board.createOrder{value: ETH_LEG}(_params(_eth, ETH_LEG, address(_tokenB), 3e6, false));
    }

    /// @notice Builds createOrder arguments
    /// @param tokenA Asset to sell
    /// @param amountA Amount of tokenA to escrow
    /// @param tokenB Asset wanted
    /// @param amountB Amount of tokenB wanted
    /// @param partialFillAllowed Whether the order may be filled in parts
    /// @return The createOrder arguments
    function _params(
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

    /// @notice Snapshots an order's amounts for modify race protection
    /// @param order The order as last read
    /// @return The four amounts modifyOrder checks against
    function _amounts(
        ISwapboard.Order memory order
    ) internal pure returns (ISwapboard.OrderAmounts memory) {
        return ISwapboard.OrderAmounts({
            amountA: order.amountA, amountB: order.amountB, availableA: order.availableA, availableB: order.availableB
        });
    }

    /// @notice Reverts the run when a step left the board in the wrong state
    /// @param ok Whether the step's postcondition held
    /// @param step The step being checked
    function _check(
        bool ok,
        string memory step
    ) internal pure {
        if (!ok) revert SmokeCheckFailed(step);
    }
}
