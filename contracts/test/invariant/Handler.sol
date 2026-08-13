// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec

import {Test} from "forge-std/Test.sol";
import {Swapboard} from "../../src/Swapboard.sol";
import {ISwapboard} from "../../src/interfaces/ISwapboard.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @title SwapboardHandler
/// @notice Handler contract for invariant testing of Swapboard
/// @dev Tracks ghost variables for accounting invariants
contract SwapboardHandler is Test {
    Swapboard internal _board;
    MockERC20 internal _tokenA;
    MockERC20 internal _tokenB;
    address private immutable _ETH;

    // Ghost variables for tracking state
    uint256 private _ghostTotalTokenADeposited;
    uint256 private _ghostTotalTokenAWithdrawn;
    uint256 private _ghostTotalEthDeposited;
    uint256 private _ghostTotalEthWithdrawn;
    uint256 private _ghostOrdersCreated;
    uint256 private _ghostOrdersFilled;
    uint256 private _ghostOrdersCancelled;
    uint256 private _ghostActiveOrders;

    // Track individual order amounts for precise accounting
    mapping(uint256 orderId => uint256 amount) private _ghostOrderAmounts;
    mapping(uint256 orderId => bool active) private _ghostOrderActive;

    // Actors
    address[] internal _actors;
    address internal _currentActor;

    // Counters for call tracking
    uint256 private _callsCreateOrder;
    uint256 private _callsCreateOrderSellEth;
    uint256 private _callsCreateOrderWantEth;
    uint256 private _callsCreateOrderAllowPartial;
    uint256 private _callsFillOrder;
    uint256 private _callsCancelOrder;

    modifier useActor(
        uint256 actorIndexSeed
    ) {
        _currentActor = _actors[bound(actorIndexSeed, 0, _actors.length - 1)];
        vm.startPrank(_currentActor);
        _;
        vm.stopPrank();
    }

    constructor(
        Swapboard board,
        MockERC20 tokenA,
        MockERC20 tokenB
    ) {
        _board = board;
        _tokenA = tokenA;
        _tokenB = tokenB;
        _ETH = board.getEth();

        // Setup actors
        _actors.push(address(0x1001));
        _actors.push(address(0x1002));
        _actors.push(address(0x1003));
        _actors.push(address(0x1004));
        _actors.push(address(0x1005));

        // Mint tokens and ETH to all actors
        for (uint256 i = 0; i < _actors.length; ++i) {
            _tokenA.mint(_actors[i], 1_000_000 ether);
            _tokenB.mint(_actors[i], 1_000_000 ether);
            vm.deal(_actors[i], 1000 ether);

            vm.prank(_actors[i]);
            _tokenA.approve(address(_board), type(uint256).max);

            vm.prank(_actors[i]);
            _tokenB.approve(address(_board), type(uint256).max);
        }
    }

    function getGhostTotalTokenADeposited() external view returns (uint256) {
        return _ghostTotalTokenADeposited;
    }

    function getGhostTotalTokenAWithdrawn() external view returns (uint256) {
        return _ghostTotalTokenAWithdrawn;
    }

    function getGhostTotalEthDeposited() external view returns (uint256) {
        return _ghostTotalEthDeposited;
    }

    function getGhostTotalEthWithdrawn() external view returns (uint256) {
        return _ghostTotalEthWithdrawn;
    }

    function getGhostOrdersCreated() external view returns (uint256) {
        return _ghostOrdersCreated;
    }

    function getGhostOrdersFilled() external view returns (uint256) {
        return _ghostOrdersFilled;
    }

    function getGhostOrdersCancelled() external view returns (uint256) {
        return _ghostOrdersCancelled;
    }

    function getGhostActiveOrders() external view returns (uint256) {
        return _ghostActiveOrders;
    }

    function getGhostOrderAmounts(
        uint256 orderId
    ) external view returns (uint256) {
        return _ghostOrderAmounts[orderId];
    }

    function getGhostOrderActive(
        uint256 orderId
    ) external view returns (bool) {
        return _ghostOrderActive[orderId];
    }

    function getCallsCreateOrder() external view returns (uint256) {
        return _callsCreateOrder;
    }

    function getCallsCreateOrderSellEth() external view returns (uint256) {
        return _callsCreateOrderSellEth;
    }

    function getCallsCreateOrderWantEth() external view returns (uint256) {
        return _callsCreateOrderWantEth;
    }

    function getCallsCreateOrderAllowPartial() external view returns (uint256) {
        return _callsCreateOrderAllowPartial;
    }

    function getCallsFillOrder() external view returns (uint256) {
        return _callsFillOrder;
    }

    function getCallsCancelOrder() external view returns (uint256) {
        return _callsCancelOrder;
    }

    /// @notice Creates a new ERC20/ERC20 order with bounded amounts
    function createOrder(
        uint256 actorSeed,
        uint256 amountA,
        uint256 amountB
    ) external useActor(actorSeed) {
        amountA = bound(amountA, 1, 1000 ether);
        amountB = bound(amountB, 1, 1000 ether);

        uint256 balanceBefore = _tokenA.balanceOf(_currentActor);
        if (balanceBefore < amountA) {
            return; // Skip if insufficient balance
        }

        ++_callsCreateOrder;

        // casting to 'uint128' is safe because amounts are bounded well below uint128.max
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountA128 = uint128(amountA);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountB128 = uint128(amountB);
        uint256 orderId = _board.createOrder(address(_tokenA), amountA128, address(_tokenB), amountB128, false);

        _ghostTotalTokenADeposited += amountA;
        ++_ghostOrdersCreated;
        ++_ghostActiveOrders;
        _ghostOrderAmounts[orderId] = amountA;
        _ghostOrderActive[orderId] = true;
    }

    /// @notice Creates an ETH sell order (tokenA = ETH)
    function createOrderSellEth(
        uint256 actorSeed,
        uint256 amountA,
        uint256 amountB
    ) external useActor(actorSeed) {
        amountA = bound(amountA, 1, 10 ether);
        amountB = bound(amountB, 1, 1000 ether);

        if (_currentActor.balance < amountA) {
            return;
        }

        ++_callsCreateOrderSellEth;

        // casting to 'uint128' is safe because amounts are bounded well below uint128.max
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountA128 = uint128(amountA);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountB128 = uint128(amountB);
        uint256 orderId = _board.createOrder{value: amountA}(_ETH, amountA128, address(_tokenB), amountB128, false);

        _ghostTotalEthDeposited += amountA;
        ++_ghostOrdersCreated;
        ++_ghostActiveOrders;
        _ghostOrderAmounts[orderId] = amountA;
        _ghostOrderActive[orderId] = true;
    }

    /// @notice Creates an order wanting ETH payment (tokenB = ETH)
    function createOrderWantEth(
        uint256 actorSeed,
        uint256 amountA,
        uint256 amountB
    ) external useActor(actorSeed) {
        amountA = bound(amountA, 1, 1000 ether);
        amountB = bound(amountB, 1, 10 ether);

        if (_tokenA.balanceOf(_currentActor) < amountA) {
            return;
        }

        ++_callsCreateOrderWantEth;

        // casting to 'uint128' is safe because amounts are bounded well below uint128.max
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountA128 = uint128(amountA);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountB128 = uint128(amountB);
        uint256 orderId = _board.createOrder(address(_tokenA), amountA128, _ETH, amountB128, false);

        _ghostTotalTokenADeposited += amountA;
        ++_ghostOrdersCreated;
        ++_ghostActiveOrders;
        _ghostOrderAmounts[orderId] = amountA;
        _ghostOrderActive[orderId] = true;
    }

    /// @notice Creates an ERC20/ERC20 order that allows partial fills
    function createOrderAllowPartial(
        uint256 actorSeed,
        uint256 amountA,
        uint256 amountB
    ) external useActor(actorSeed) {
        amountA = bound(amountA, 1, 1000 ether);
        amountB = bound(amountB, 1, 1000 ether);

        if (_tokenA.balanceOf(_currentActor) < amountA) {
            return;
        }

        ++_callsCreateOrderAllowPartial;

        // casting to 'uint128' is safe because amounts are bounded well below uint128.max
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountA128 = uint128(amountA);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountB128 = uint128(amountB);
        uint256 orderId = _board.createOrder(address(_tokenA), amountA128, address(_tokenB), amountB128, true);

        _ghostTotalTokenADeposited += amountA;
        ++_ghostOrdersCreated;
        ++_ghostActiveOrders;
        _ghostOrderAmounts[orderId] = amountA;
        _ghostOrderActive[orderId] = true;
    }

    /// @notice Fills an existing order (full or partial when allowed)
    function fillOrder(
        uint256 actorSeed,
        uint256 orderIdSeed,
        uint256 fillAmountSeed
    ) external useActor(actorSeed) {
        uint256 nextId = _board.getNextOrderId();
        if (nextId == 0) {
            return; // No orders exist
        }

        uint256 orderId = bound(orderIdSeed, 0, nextId - 1);
        ISwapboard.Order memory order = _board.getOrder(orderId);

        if (!order.active) {
            return; // Order not active
        }

        uint256 fillA = order.amountA;
        if (order.partialFillAllowed) {
            fillA = bound(fillAmountSeed, 1, order.amountA);
        }

        uint256 amountBIn =
            fillA == order.amountA ? order.amountB : (fillA * order.amountB + order.amountA - 1) / order.amountA;
        if (amountBIn == 0 || !_actorCanPayTokenB(order.tokenB, amountBIn)) {
            return;
        }

        ++_callsFillOrder;

        // casting to 'uint128' is safe because fillA is at most order.amountA (uint128)
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 fillA128 = uint128(fillA);
        if (order.tokenB == _ETH) {
            _board.fillOrder{value: amountBIn}(orderId, fillA128, 0);
        } else {
            _board.fillOrder(orderId, fillA128, 0);
        }

        _recordFillGhosts(order, orderId, fillA);
    }

    /// @notice Returns whether the current actor can pay `amount` of `tokenB`
    function _actorCanPayTokenB(
        address tokenB,
        uint256 amount
    ) private view returns (bool) {
        if (tokenB == _ETH) {
            return !(_currentActor.balance < amount);
        }
        return !(_tokenB.balanceOf(_currentActor) < amount);
    }

    /// @notice Updates ghost accounting after a successful fill
    function _recordFillGhosts(
        ISwapboard.Order memory order,
        uint256 orderId,
        uint256 fillA
    ) private {
        if (order.tokenA == _ETH) {
            _ghostTotalEthWithdrawn += fillA;
        } else if (order.tokenA == address(_tokenA)) {
            _ghostTotalTokenAWithdrawn += fillA;
        }

        if (!_board.canFill(orderId)) {
            ++_ghostOrdersFilled;
            --_ghostActiveOrders;
            _ghostOrderActive[orderId] = false;
        } else {
            _ghostOrderAmounts[orderId] = order.amountA - fillA;
        }
    }

    /// @notice Cancels an order (only by maker)
    function cancelOrder(
        uint256 orderIdSeed
    ) external {
        uint256 nextId = _board.getNextOrderId();
        if (nextId == 0) {
            return;
        }

        uint256 orderId = bound(orderIdSeed, 0, nextId - 1);
        ISwapboard.Order memory order = _board.getOrder(orderId);

        if (!order.active) {
            return;
        }

        // Only maker can cancel
        vm.prank(order.maker);

        ++_callsCancelOrder;

        _board.cancelOrder(orderId);

        if (order.tokenA == _ETH) {
            _ghostTotalEthWithdrawn += order.amountA;
        } else if (order.tokenA == address(_tokenA)) {
            _ghostTotalTokenAWithdrawn += order.amountA;
        }

        ++_ghostOrdersCancelled;
        --_ghostActiveOrders;
        _ghostOrderActive[orderId] = false;
    }

    /// @notice View function to get contract token balance
    function getContractTokenABalance() external view returns (uint256) {
        return _tokenA.balanceOf(address(_board));
    }

    /// @notice Calculate expected contract balance from ghost vars
    function getExpectedContractBalance() external view returns (uint256) {
        return _ghostTotalTokenADeposited - _ghostTotalTokenAWithdrawn;
    }

    /// @notice Count active orders by iterating
    function countActiveOrders() external view returns (uint256 count) {
        uint256 nextId = _board.getNextOrderId();

        for (uint256 i = 0; i < nextId; ++i) {
            if (_board.canFill(i)) {
                ++count;
            }
        }
    }

    /// @notice Sum of remaining ERC20 tokenA escrow across all orders (incl. inactive dust)
    function sumActiveOrderAmounts() external view returns (uint256 total) {
        uint256 nextId = _board.getNextOrderId();

        for (uint256 i = 0; i < nextId; ++i) {
            ISwapboard.Order memory order = _board.getOrder(i);
            if (order.tokenA == address(_tokenA)) {
                total += order.amountA;
            }
        }
    }

    /// @notice Sum of remaining ETH tokenA escrow across all orders (incl. inactive dust)
    function sumActiveEthOrderAmounts() external view returns (uint256 total) {
        uint256 nextId = _board.getNextOrderId();

        for (uint256 i = 0; i < nextId; ++i) {
            ISwapboard.Order memory order = _board.getOrder(i);
            if (order.tokenA == _ETH) {
                total += order.amountA;
            }
        }
    }
}
