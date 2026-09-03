// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec

import {Test} from "forge-std/Test.sol";
import {Swapboard} from "../../src/Swapboard.sol";
import {ISwapboard} from "../../src/interfaces/ISwapboard.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {FillTestLib} from "../helpers/FillTestLib.sol";

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
    mapping(uint256 orderId => uint128 amountA) private _ghostOriginalAmountA;
    mapping(uint256 orderId => uint128 amountB) private _ghostOriginalAmountB;

    // Actors
    address[] internal _actors;
    address internal _currentActor;

    // Counters for call tracking
    uint256 private _callsCreateOrder;
    uint256 private _callsCreateOrderSellEth;
    uint256 private _callsCreateOrderWantEth;
    uint256 private _callsCreateOrderAllowPartial;
    uint256 private _callsCreateOrders;
    uint256 private _callsFillOrder;
    uint256 private _callsFillOrders;
    uint256 private _callsCancelOrder;
    uint256 private _callsCancelOrders;
    uint256 private _callsModifyOrder;
    uint256 private _callsSetPartialFillAllowed;

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

    function getCallsCreateOrders() external view returns (uint256) {
        return _callsCreateOrders;
    }

    function getCallsFillOrder() external view returns (uint256) {
        return _callsFillOrder;
    }

    function getCallsFillOrders() external view returns (uint256) {
        return _callsFillOrders;
    }

    function getCallsCancelOrder() external view returns (uint256) {
        return _callsCancelOrder;
    }

    function getCallsCancelOrders() external view returns (uint256) {
        return _callsCancelOrders;
    }

    function getCallsModifyOrder() external view returns (uint256) {
        return _callsModifyOrder;
    }

    function getCallsSetPartialFillAllowed() external view returns (uint256) {
        return _callsSetPartialFillAllowed;
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
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: amountA128,
                tokenB: address(_tokenB),
                amountB: amountB128,
                partialFillAllowed: false
            })
        );

        _ghostTotalTokenADeposited += amountA;
        _trackCreatedOrder(orderId, amountA128, amountB128);
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
        uint256 orderId = _board.createOrder{value: amountA}(
            ISwapboard.CreateOrderParams({
                tokenA: _ETH,
                amountA: amountA128,
                tokenB: address(_tokenB),
                amountB: amountB128,
                partialFillAllowed: false
            })
        );

        _ghostTotalEthDeposited += amountA;
        _trackCreatedOrder(orderId, amountA128, amountB128);
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
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: amountA128,
                tokenB: _ETH,
                amountB: amountB128,
                partialFillAllowed: false
            })
        );

        _ghostTotalTokenADeposited += amountA;
        _trackCreatedOrder(orderId, amountA128, amountB128);
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
        uint256 orderId = _board.createOrder(
            ISwapboard.CreateOrderParams({
                tokenA: address(_tokenA),
                amountA: amountA128,
                tokenB: address(_tokenB),
                amountB: amountB128,
                partialFillAllowed: true
            })
        );

        _ghostTotalTokenADeposited += amountA;
        _trackCreatedOrder(orderId, amountA128, amountB128);
    }

    /// @notice Creates two same-tokenA orders in one aggregated pull
    function createOrders(
        uint256 actorSeed,
        uint256 amountA,
        uint256 amountB
    ) external useActor(actorSeed) {
        amountA = bound(amountA, 2, 1000 ether);
        amountB = bound(amountB, 2, 1000 ether);

        if (_tokenA.balanceOf(_currentActor) < amountA) {
            return;
        }

        uint256 amountA1 = amountA / 2;
        uint256 amountA2 = amountA - amountA1;
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountA1128 = uint128(amountA1);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountA2128 = uint128(amountA2);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 amountB128 = uint128(amountB);

        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = ISwapboard.CreateOrderParams({
            tokenA: address(_tokenA),
            amountA: amountA1128,
            tokenB: address(_tokenB),
            amountB: amountB128,
            partialFillAllowed: false
        });
        orders[1] = ISwapboard.CreateOrderParams({
            tokenA: address(_tokenA),
            amountA: amountA2128,
            tokenB: address(_tokenB),
            amountB: amountB128,
            partialFillAllowed: true
        });

        ++_callsCreateOrders;
        uint256[] memory ids = _board.createOrders(orders);

        _ghostTotalTokenADeposited += amountA;
        _trackCreatedOrder(ids[0], amountA1128, amountB128);
        _trackCreatedOrder(ids[1], amountA2128, amountB128);
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

        uint128 fillA128;
        if (order.partialFillAllowed) {
            // casting to 'uint128' is safe because fill amount is bounded by order.availableA
            // forge-lint: disable-next-line(unsafe-typecast)
            fillA128 = uint128(bound(fillAmountSeed, 1, order.availableA));
        } else {
            fillA128 = order.availableA;
        }

        uint128 amountBIn = FillTestLib.quoteAmountB(order, fillA128);
        if (amountBIn == 0 || !_actorCanPayTokenB(order.tokenB, amountBIn)) {
            return;
        }

        ++_callsFillOrder;

        if (order.tokenB == _ETH) {
            _board.fillOrder{value: amountBIn}(orderId, fillA128, amountBIn, 0);
        } else {
            _board.fillOrder(orderId, fillA128, amountBIn, 0);
        }

        _recordFillGhosts(order, orderId, fillA128);
    }

    /// @notice Fills two same-tokenB ERC20 orders in one aggregated pull
    function fillOrders(
        uint256 actorSeed,
        uint256 orderIdSeed1,
        uint256 orderIdSeed2
    ) external useActor(actorSeed) {
        uint256 nextId = _board.getNextOrderId();
        if (nextId < 2) {
            return;
        }

        uint256 id1 = bound(orderIdSeed1, 0, nextId - 1);
        uint256 id2 = bound(orderIdSeed2, 0, nextId - 1);
        if (id1 == id2) {
            return;
        }

        ISwapboard.Order memory order1 = _board.getOrder(id1);
        ISwapboard.Order memory order2 = _board.getOrder(id2);
        if (!order1.active || !order2.active) {
            return;
        }
        if (order1.tokenB != order2.tokenB || order1.tokenB == _ETH) {
            return;
        }

        uint256 amountBIn1 = order1.availableB;
        uint256 amountBIn2 = order2.availableB;
        uint256 totalBIn = amountBIn1 + amountBIn2;
        if (!_actorCanPayTokenB(order1.tokenB, totalBIn)) {
            return;
        }

        ++_callsFillOrders;
        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = FillTestLib.fillParams(_board.getOrder(id1), id1, order1.availableA);
        fills[1] = FillTestLib.fillParams(_board.getOrder(id2), id2, order2.availableA);
        _board.fillOrders(fills, 0);

        _recordFillGhosts(order1, id1, order1.availableA);
        _recordFillGhosts(order2, id2, order2.availableA);
    }

    /// @notice Fills one partial-fill order with two sequential legs in one batch
    function fillOrdersPartialSameOrder(
        uint256 actorSeed,
        uint256 orderIdSeed
    ) external useActor(actorSeed) {
        uint256 nextId = _board.getNextOrderId();
        if (nextId == 0) {
            return;
        }

        uint256 orderId = bound(orderIdSeed, 0, nextId - 1);
        ISwapboard.Order memory order = _board.getOrder(orderId);
        if (!order.active || !order.partialFillAllowed || order.availableA < 2) {
            return;
        }
        if (order.tokenB == _ETH) {
            return;
        }

        uint128 fillA1 = uint128(order.availableA / 2);
        uint128 fillA2 = uint128(order.availableA - fillA1);
        uint256 amountBIn1 =
            (uint256(fillA1) * uint256(order.availableB) + uint256(order.availableA) - 1) / uint256(order.availableA);
        uint256 remA = order.availableA - fillA1;
        uint256 remB = order.availableB - amountBIn1;
        uint256 amountBIn2 = remA == 0 ? remB : (uint256(fillA2) * remB + remA - 1) / remA;
        if (amountBIn1 == 0 || amountBIn2 == 0 || !_actorCanPayTokenB(order.tokenB, amountBIn1 + amountBIn2)) {
            return;
        }

        ++_callsFillOrders;
        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = FillTestLib.fillParams(_board.getOrder(orderId), orderId, fillA1);
        fills[1] = FillTestLib.fillParams(_board.getOrder(orderId), orderId, fillA2);
        _board.fillOrders(fills, 0);

        _recordFillGhosts(order, orderId, uint256(fillA1) + uint256(fillA2));
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
            _ghostOrderAmounts[orderId] = order.availableA - fillA;
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
            _ghostTotalEthWithdrawn += order.availableA;
        } else if (order.tokenA == address(_tokenA)) {
            _ghostTotalTokenAWithdrawn += order.availableA;
        }

        ++_ghostOrdersCancelled;
        --_ghostActiveOrders;
        _ghostOrderActive[orderId] = false;
    }

    /// @notice Cancels two same-tokenA orders owned by the actor in one batch
    function cancelOrders(
        uint256 actorSeed,
        uint256 orderIdSeed1,
        uint256 orderIdSeed2
    ) external useActor(actorSeed) {
        uint256 nextId = _board.getNextOrderId();
        if (nextId < 2) {
            return;
        }

        uint256 id1 = bound(orderIdSeed1, 0, nextId - 1);
        uint256 id2 = bound(orderIdSeed2, 0, nextId - 1);
        if (id1 == id2) {
            return;
        }

        ISwapboard.Order memory order1 = _board.getOrder(id1);
        ISwapboard.Order memory order2 = _board.getOrder(id2);
        if (!order1.active || !order2.active) {
            return;
        }
        if (order1.maker != _currentActor || order2.maker != _currentActor) {
            return;
        }
        if (order1.tokenA != order2.tokenA || order1.tokenA == _ETH) {
            return;
        }

        ++_callsCancelOrders;
        uint256[] memory ids = new uint256[](2);
        ids[0] = id1;
        ids[1] = id2;
        _board.cancelOrders(ids);

        _ghostTotalTokenAWithdrawn += order1.availableA + order2.availableA;
        _ghostOrdersCancelled += 2;
        _ghostActiveOrders -= 2;
        _ghostOrderActive[id1] = false;
        _ghostOrderActive[id2] = false;
    }

    /// @notice Modifies remaining liquidity on an active order owned by the actor
    function modifyOrder(
        uint256 actorSeed,
        uint256 orderIdSeed,
        uint256 newASeed,
        uint256 newBSeed
    ) external useActor(actorSeed) {
        uint256 nextId = _board.getNextOrderId();
        if (nextId == 0) {
            return;
        }

        uint256 orderId = bound(orderIdSeed, 0, nextId - 1);
        ISwapboard.Order memory order = _board.getOrder(orderId);
        if (!order.active || order.maker != _currentActor) {
            return;
        }

        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 newA = uint128(bound(newASeed, 1, 200 ether));
        // forge-lint: disable-next-line(unsafe-typecast)
        uint128 newB = uint128(bound(newBSeed, 1, 200 ether));
        if (newA == order.availableA && newB == order.availableB) {
            return;
        }

        uint256 value = 0;
        if (newA > order.availableA) {
            uint256 delta = uint256(newA) - uint256(order.availableA);
            if (order.tokenA == _ETH) {
                value = delta;
                if (_currentActor.balance < value) {
                    return;
                }
            } else if (_tokenA.balanceOf(_currentActor) < delta) {
                return;
            }
        }

        ++_callsModifyOrder;

        ISwapboard.OrderAmounts memory previous = ISwapboard.OrderAmounts({
            amountA: order.amountA, amountB: order.amountB, availableA: order.availableA, availableB: order.availableB
        });
        ISwapboard.ModifyOrderParams memory updated =
            ISwapboard.ModifyOrderParams({availableA: newA, availableB: newB});

        _board.modifyOrder{value: value}(orderId, previous, updated);

        if (order.tokenA == _ETH) {
            if (newA > order.availableA) {
                _ghostTotalEthDeposited += uint256(newA) - uint256(order.availableA);
            } else if (newA < order.availableA) {
                _ghostTotalEthWithdrawn += uint256(order.availableA) - uint256(newA);
            }
        } else if (order.tokenA == address(_tokenA)) {
            if (newA > order.availableA) {
                _ghostTotalTokenADeposited += uint256(newA) - uint256(order.availableA);
            } else if (newA < order.availableA) {
                _ghostTotalTokenAWithdrawn += uint256(order.availableA) - uint256(newA);
            }
        }

        _ghostOrderAmounts[orderId] = newA;
        _ghostOriginalAmountA[orderId] = newA;
        _ghostOriginalAmountB[orderId] = newB;
    }

    /// @notice Flips partialFillAllowed on an active order owned by the actor
    function setPartialFillAllowed(
        uint256 actorSeed,
        uint256 orderIdSeed,
        bool partialFillAllowed
    ) external useActor(actorSeed) {
        uint256 nextId = _board.getNextOrderId();
        if (nextId == 0) {
            return;
        }

        uint256 orderId = bound(orderIdSeed, 0, nextId - 1);
        ISwapboard.Order memory order = _board.getOrder(orderId);
        if (!order.active || order.maker != _currentActor) {
            return;
        }
        if (order.partialFillAllowed == partialFillAllowed) {
            return;
        }

        ++_callsSetPartialFillAllowed;
        _board.setPartialFillAllowed(orderId, partialFillAllowed);
    }

    /// @notice Records ghost state for a newly created order
    function _trackCreatedOrder(
        uint256 orderId,
        uint128 amountA,
        uint128 amountB
    ) private {
        ++_ghostOrdersCreated;
        ++_ghostActiveOrders;
        _ghostOrderAmounts[orderId] = amountA;
        _ghostOrderActive[orderId] = true;
        _ghostOriginalAmountA[orderId] = amountA;
        _ghostOriginalAmountB[orderId] = amountB;
    }

    /// @notice Asserts amount/available invariants across all created orders
    /// @dev Originals never change; available never exceeds originals; active iff both available > 0
    function assertAmountInvariants() external view {
        uint256 nextId = _board.getNextOrderId();

        for (uint256 i = 0; i < nextId; ++i) {
            ISwapboard.Order memory order = _board.getOrder(i);
            if (order.maker == address(0)) {
                continue;
            }

            assertEq(order.amountA, _ghostOriginalAmountA[i]);
            assertEq(order.amountB, _ghostOriginalAmountB[i]);
            assertTrue(order.amountA > 0 && order.amountB > 0);

            assertTrue(!(order.availableA > order.amountA));
            assertTrue(!(order.availableB > order.amountB));

            if (order.active) {
                assertTrue(order.availableA > 0 && order.availableB > 0);
            } else {
                assertTrue(order.availableA == 0 || order.availableB == 0);
            }
        }
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
                total += order.availableA;
            }
        }
    }

    /// @notice Sum of remaining ETH tokenA escrow across all orders (incl. inactive dust)
    function sumActiveEthOrderAmounts() external view returns (uint256 total) {
        uint256 nextId = _board.getNextOrderId();

        for (uint256 i = 0; i < nextId; ++i) {
            ISwapboard.Order memory order = _board.getOrder(i);
            if (order.tokenA == _ETH) {
                total += order.availableA;
            }
        }
    }
}
