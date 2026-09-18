// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec

import {Test} from "forge-std/Test.sol";
import {Swapboard} from "../../src/Swapboard.sol";
import {ISwapboard} from "../../src/interfaces/ISwapboard.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {OrderTestLib} from "./OrderTestLib.sol";

/// @notice Shared actors / amounts / order helpers for EIP-2612 and Permit2 suites
abstract contract SwapboardTwoPartyTest is Test {
    uint256 internal constant _MAKER_PK = 0xA11CE;
    uint256 internal constant _TAKER_PK = 0xB0B;
    uint128 internal constant _AMOUNT_A = 100 ether;
    uint128 internal constant _AMOUNT_B = 250_000e6;

    Swapboard internal _board;
    MockERC20 internal _tokenA;
    MockERC20 internal _tokenB;
    MockERC20 internal _tokenC;

    address internal _maker;
    address internal _taker;
    address internal _eth;

    /// @notice Deploys board and funds maker/taker with ETH
    function _setUpActors() internal {
        _board = new Swapboard();
        _eth = _board.getEth();
        _maker = vm.addr(_MAKER_PK);
        _taker = vm.addr(_TAKER_PK);
        vm.deal(_maker, 100 ether);
        vm.deal(_taker, 100 ether);
    }

    /// @notice Mints the standard maker/taker balances for the three test tokens
    function _mintStandardBalances() internal {
        _tokenA.mint(_maker, _AMOUNT_A * 10);
        _tokenC.mint(_maker, _AMOUNT_A * 10);
        _tokenB.mint(_taker, _AMOUNT_B * 10);
        _tokenC.mint(_taker, _AMOUNT_B * 10);
    }

    /// @notice Creates an order after approving tokenA to the board
    function _createApproved(
        ISwapboard.CreateOrderParams memory order
    ) internal returns (uint256 orderId) {
        vm.prank(_maker);
        _tokenA.approve(address(_board), _AMOUNT_A);
        vm.prank(_maker);
        orderId = _board.createOrder(order);
    }

    function _ethWanted() internal view returns (ISwapboard.CreateOrderParams memory) {
        return OrderTestLib.order(address(_tokenA), _AMOUNT_A, _eth, _AMOUNT_A);
    }

    function _tokenCWanted() internal view returns (ISwapboard.CreateOrderParams memory) {
        return OrderTestLib.order(address(_tokenA), _AMOUNT_A, address(_tokenC), _AMOUNT_B);
    }

    function _assertFilled() internal view {
        assertEq(_tokenA.balanceOf(_taker), _AMOUNT_A);
        assertEq(_tokenB.balanceOf(_maker), _AMOUNT_B);
    }

    function _single(
        ISwapboard.CreateOrderParams memory order
    ) internal pure returns (ISwapboard.CreateOrderParams[] memory orders) {
        orders = new ISwapboard.CreateOrderParams[](1);
        orders[0] = order;
    }

    function _amounts(
        ISwapboard.Order memory order
    ) internal pure returns (ISwapboard.OrderAmounts memory) {
        return ISwapboard.OrderAmounts({
            amountA: order.amountA, amountB: order.amountB, availableA: order.availableA, availableB: order.availableB
        });
    }
}
