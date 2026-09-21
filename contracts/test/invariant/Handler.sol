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

    // Counters for call tracking (packed to satisfy solhint max-states-count)
    struct CallCounts {
        uint256 createOrder;
        uint256 createOrderSellEth;
        uint256 createOrderWantEth;
        uint256 createOrderAllowPartial;
        uint256 createOrders;
        uint256 fillOrder;
        uint256 fillOrders;
        uint256 cancelOrder;
        uint256 cancelOrders;
        uint256 modifyOrder;
        uint256 modifyOrders;
        uint256 setPartialFillAllowed;
    }

    CallCounts private _calls;

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
        return _calls.createOrder;
    }

    function getCallsCreateOrderSellEth() external view returns (uint256) {
        return _calls.createOrderSellEth;
    }

    function getCallsCreateOrderWantEth() external view returns (uint256) {
        return _calls.createOrderWantEth;
    }

    function getCallsCreateOrderAllowPartial() external view returns (uint256) {
        return _calls.createOrderAllowPartial;
    }

    function getCallsCreateOrders() external view returns (uint256) {
        return _calls.createOrders;
    }

    function getCallsFillOrder() external view returns (uint256) {
        return _calls.fillOrder;
    }

    function getCallsFillOrders() external view returns (uint256) {
        return _calls.fillOrders;
    }

    function getCallsCancelOrder() external view returns (uint256) {
        return _calls.cancelOrder;
    }

    function getCallsCancelOrders() external view returns (uint256) {
        return _calls.cancelOrders;
    }

    function getCallsModifyOrder() external view returns (uint256) {
        return _calls.modifyOrder;
    }

    function getCallsModifyOrders() external view returns (uint256) {
        return _calls.modifyOrders;
    }

    function getCallsSetPartialFillAllowed() external view returns (uint256) {
        return _calls.setPartialFillAllowed;
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

        ++_calls.createOrder;

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

        ++_calls.createOrderSellEth;

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

        ++_calls.createOrderWantEth;

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

        ++_calls.createOrderAllowPartial;

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

        ++_calls.createOrders;
        uint256[] memory ids = _board.createOrders(orders);

        _ghostTotalTokenADeposited += amountA;
        _trackCreatedOrder(ids[0], amountA1128, amountB128);
        _trackCreatedOrder(ids[1], amountA2128, amountB128);
    }

    struct LoadedOrder {
        bool ok;
        uint256 orderId;
        ISwapboard.Order order;
    }

    struct LoadedOrderPair {
        bool ok;
        uint256 id1;
        ISwapboard.Order order1;
        uint256 id2;
        ISwapboard.Order order2;
    }

    struct ModifyTopUp {
        bool funded;
        uint256 value;
    }

    /// @notice Loads a bounded order id when any orders exist; returns false if none
    function _tryLoadOrder(
        uint256 orderIdSeed
    ) private view returns (LoadedOrder memory result) {
        uint256 nextId = _board.getNextOrderId();
        if (nextId == 0) {
            return result;
        }

        result.orderId = bound(orderIdSeed, 0, nextId - 1);
        result.order = _board.getOrder(result.orderId);
        result.ok = true;

        return result;
    }

    /// @notice Loads a bounded active order; returns false when missing or inactive
    function _tryLoadActiveOrder(
        uint256 orderIdSeed
    ) private view returns (LoadedOrder memory result) {
        result = _tryLoadOrder(orderIdSeed);
        if (!result.ok || !result.order.active) {
            result.ok = false;
        }

        return result;
    }

    /// @notice Loads two distinct active same-ERC20-tokenB orders for batch fills
    function _tryLoadTwoDistinctActiveSameErc20B(
        uint256 orderIdSeed1,
        uint256 orderIdSeed2
    ) private view returns (LoadedOrderPair memory result) {
        uint256 nextId = _board.getNextOrderId();
        if (nextId < 2) {
            return result;
        }

        result.id1 = bound(orderIdSeed1, 0, nextId - 1);
        result.id2 = bound(orderIdSeed2, 0, nextId - 1);
        if (result.id1 == result.id2) {
            return result;
        }

        result.order1 = _board.getOrder(result.id1);
        result.order2 = _board.getOrder(result.id2);
        if (!result.order1.active || !result.order2.active) {
            return result;
        }
        if (result.order1.tokenB != result.order2.tokenB || result.order1.tokenB == _ETH) {
            return result;
        }
        result.ok = true;

        return result;
    }

    /// @notice Fills an existing order (full or partial when allowed)
    function fillOrder(
        uint256 actorSeed,
        uint256 orderIdSeed,
        uint256 fillAmountSeed
    ) external useActor(actorSeed) {
        LoadedOrder memory loaded = _tryLoadActiveOrder(orderIdSeed);
        if (!loaded.ok) {
            return;
        }
        ISwapboard.Order memory order = loaded.order;

        uint128 fillB128;
        if (order.partialFillAllowed) {
            // casting to 'uint128' is safe because fill amount is bounded by order.availableB
            // forge-lint: disable-next-line(unsafe-typecast)
            fillB128 = uint128(bound(fillAmountSeed, 1, order.availableB));
        } else {
            fillB128 = order.availableB;
        }

        uint128 amountAOut = FillTestLib.quoteAmountA(order, fillB128);
        if (amountAOut == 0 || !_actorCanPayTokenB(order.tokenB, fillB128)) {
            return;
        }

        ++_calls.fillOrder;

        if (order.tokenB == _ETH) {
            _board.fillOrder{value: fillB128}(loaded.orderId, fillB128, amountAOut, 0);
        } else {
            _board.fillOrder(loaded.orderId, fillB128, amountAOut, 0);
        }

        _recordFillGhosts(order, loaded.orderId, amountAOut);
    }

    /// @notice Fills two same-tokenB ERC20 orders in one aggregated pull
    function fillOrders(
        uint256 actorSeed,
        uint256 orderIdSeed1,
        uint256 orderIdSeed2
    ) external useActor(actorSeed) {
        LoadedOrderPair memory loaded = _tryLoadTwoDistinctActiveSameErc20B(orderIdSeed1, orderIdSeed2);
        if (!loaded.ok) {
            return;
        }
        ISwapboard.Order memory order1 = loaded.order1;
        ISwapboard.Order memory order2 = loaded.order2;

        uint256 totalBIn = uint256(order1.availableB) + uint256(order2.availableB);
        if (!_actorCanPayTokenB(order1.tokenB, totalBIn)) {
            return;
        }

        ++_calls.fillOrders;
        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = FillTestLib.fillParams(order1, loaded.id1, order1.availableA);
        fills[1] = FillTestLib.fillParams(order2, loaded.id2, order2.availableA);
        _board.fillOrders(fills, 0);

        _recordFillGhosts(order1, loaded.id1, order1.availableA);
        _recordFillGhosts(order2, loaded.id2, order2.availableA);
    }

    /// @notice Fills one partial-fill order with two sequential legs in one batch
    function fillOrdersPartialSameOrder(
        uint256 actorSeed,
        uint256 orderIdSeed
    ) external useActor(actorSeed) {
        LoadedOrder memory loaded = _tryLoadActiveOrder(orderIdSeed);
        ISwapboard.Order memory order = loaded.order;
        if (!loaded.ok || !order.partialFillAllowed || order.availableB < 2) {
            return;
        }
        if (order.tokenB == _ETH) {
            return;
        }

        uint128 fillB1 = uint128(order.availableB / 2);
        uint128 amountAOut1 = FillTestLib.quoteAmountA(order, fillB1);
        if (amountAOut1 == 0 || fillB1 == 0 || fillB1 > order.availableB - 1) {
            return;
        }
        uint128 fillB2 = uint128(order.availableB - fillB1);
        ISwapboard.Order memory afterFirst = order;
        unchecked {
            afterFirst.availableA = uint128(uint256(order.availableA) - uint256(amountAOut1));
            afterFirst.availableB = uint128(uint256(order.availableB) - uint256(fillB1));
        }
        uint128 amountAOut2 = FillTestLib.quoteAmountA(afterFirst, fillB2);
        if (
            fillB2 == 0 || fillB2 > afterFirst.availableB || amountAOut2 == 0
                || !_actorCanPayTokenB(order.tokenB, uint256(fillB1) + uint256(fillB2))
        ) {
            return;
        }

        ++_calls.fillOrders;
        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = ISwapboard.FillOrderParams({orderId: loaded.orderId, amountB: fillB1, minAmountA: amountAOut1});
        fills[1] = ISwapboard.FillOrderParams({orderId: loaded.orderId, amountB: fillB2, minAmountA: amountAOut2});
        _board.fillOrders(fills, 0);

        _recordFillGhosts(order, loaded.orderId, uint256(amountAOut1) + uint256(amountAOut2));
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

        ++_calls.cancelOrder;

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

        ++_calls.cancelOrders;
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

        ModifyTopUp memory topUp = _modifyOrderTopUp(order, newA);
        if (!topUp.funded) {
            return;
        }

        ++_calls.modifyOrder;

        ISwapboard.OrderAmounts memory previous = ISwapboard.OrderAmounts({
            amountA: order.amountA, amountB: order.amountB, availableA: order.availableA, availableB: order.availableB
        });
        ISwapboard.ModifyOrderParams memory updated =
            ISwapboard.ModifyOrderParams({availableA: newA, availableB: newB});

        _board.modifyOrder{value: topUp.value}(orderId, previous, updated);
        _trackModifyOrderGhosts(order, orderId, newA, newB);
    }

    struct BoundModifyAmounts {
        bool ok;
        uint128 newA1;
        uint128 newB1;
        uint128 newA2;
        uint128 newB2;
    }

    /// @notice Modifies two same-tokenA ERC20 orders owned by the actor in one batch
    function modifyOrders(
        uint256 actorSeed,
        uint256 orderIdSeed1,
        uint256 orderIdSeed2,
        uint256 newASeed1,
        uint256 newBSeed1,
        uint256 newASeed2,
        uint256 newBSeed2
    ) external useActor(actorSeed) {
        LoadedOrderPair memory loaded = _pickTwoOwnedOrders(orderIdSeed1, orderIdSeed2);
        ISwapboard.Order memory order1 = loaded.order1;
        ISwapboard.Order memory order2 = loaded.order2;
        if (!loaded.ok || order1.tokenA != order2.tokenA || order1.tokenA == _ETH) {
            return;
        }

        BoundModifyAmounts memory amounts =
            _boundModifyAmounts(order1, order2, newASeed1, newBSeed1, newASeed2, newBSeed2, 200 ether, 200 ether);
        if (!amounts.ok) {
            return;
        }

        ModifyTopUp memory topUp1 = _modifyOrderTopUp(order1, amounts.newA1);
        ModifyTopUp memory topUp2 = _modifyOrderTopUp(order2, amounts.newA2);
        if (!topUp1.funded || !topUp2.funded) {
            return;
        }

        uint256 netPull = _netModifyPull(order1.availableA, amounts.newA1, order2.availableA, amounts.newA2);
        if (order1.tokenA == address(_tokenA) && _tokenA.balanceOf(_currentActor) < netPull) {
            return;
        }

        _commitTwoModifies(loaded.id1, order1, loaded.id2, order2, amounts, 0);
    }

    /// @notice Modifies two ETH-sell orders owned by the actor, using netted msg.value
    function modifyOrdersEth(
        uint256 actorSeed,
        uint256 orderIdSeed1,
        uint256 orderIdSeed2,
        uint256 newASeed1,
        uint256 newBSeed1,
        uint256 newASeed2,
        uint256 newBSeed2
    ) external useActor(actorSeed) {
        LoadedOrderPair memory loaded = _pickTwoOwnedOrders(orderIdSeed1, orderIdSeed2);
        ISwapboard.Order memory order1 = loaded.order1;
        ISwapboard.Order memory order2 = loaded.order2;
        if (!loaded.ok || order1.tokenA != _ETH || order2.tokenA != _ETH) {
            return;
        }

        BoundModifyAmounts memory amounts =
            _boundModifyAmounts(order1, order2, newASeed1, newBSeed1, newASeed2, newBSeed2, 50 ether, 200 ether);
        if (!amounts.ok) {
            return;
        }

        uint256 netPull = _netModifyPull(order1.availableA, amounts.newA1, order2.availableA, amounts.newA2);
        if (_currentActor.balance < netPull) {
            return;
        }

        _commitTwoModifies(loaded.id1, order1, loaded.id2, order2, amounts, netPull);
    }

    /// @notice Calls `modifyOrders` and updates ghosts for a validated pair
    function _commitTwoModifies(
        uint256 id1,
        ISwapboard.Order memory order1,
        uint256 id2,
        ISwapboard.Order memory order2,
        BoundModifyAmounts memory amounts,
        uint256 ethValue
    ) private {
        ++_calls.modifyOrders;

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = ISwapboard.ModifyOrdersParams({
            orderId: id1,
            previousAmounts: ISwapboard.OrderAmounts({
                amountA: order1.amountA,
                amountB: order1.amountB,
                availableA: order1.availableA,
                availableB: order1.availableB
            }),
            updatedOrder: ISwapboard.ModifyOrderParams({availableA: amounts.newA1, availableB: amounts.newB1})
        });
        mods[1] = ISwapboard.ModifyOrdersParams({
            orderId: id2,
            previousAmounts: ISwapboard.OrderAmounts({
                amountA: order2.amountA,
                amountB: order2.amountB,
                availableA: order2.availableA,
                availableB: order2.availableB
            }),
            updatedOrder: ISwapboard.ModifyOrderParams({availableA: amounts.newA2, availableB: amounts.newB2})
        });

        _board.modifyOrders{value: ethValue}(mods);
        _trackModifyOrderGhosts(order1, id1, amounts.newA1, amounts.newB1);
        _trackModifyOrderGhosts(order2, id2, amounts.newA2, amounts.newB2);
    }

    /// @notice Picks two distinct active orders owned by the current actor
    function _pickTwoOwnedOrders(
        uint256 orderIdSeed1,
        uint256 orderIdSeed2
    ) private view returns (LoadedOrderPair memory result) {
        uint256 nextId = _board.getNextOrderId();
        if (nextId < 2) {
            return result;
        }

        result.id1 = bound(orderIdSeed1, 0, nextId - 1);
        result.id2 = bound(orderIdSeed2, 0, nextId - 1);
        if (result.id1 == result.id2) {
            return result;
        }

        result.order1 = _board.getOrder(result.id1);
        result.order2 = _board.getOrder(result.id2);
        if (!result.order1.active || !result.order2.active) {
            return result;
        }
        if (result.order1.maker != _currentActor || result.order2.maker != _currentActor) {
            return result;
        }

        result.ok = true;
        return result;
    }

    /// @notice Bounds new remainings for a two-order modify; rejects no-change legs
    function _boundModifyAmounts(
        ISwapboard.Order memory order1,
        ISwapboard.Order memory order2,
        uint256 newASeed1,
        uint256 newBSeed1,
        uint256 newASeed2,
        uint256 newBSeed2,
        uint256 maxA,
        uint256 maxB
    ) private pure returns (BoundModifyAmounts memory amounts) {
        // forge-lint: disable-next-line(unsafe-typecast)
        amounts.newA1 = uint128(bound(newASeed1, 1, maxA));
        // forge-lint: disable-next-line(unsafe-typecast)
        amounts.newB1 = uint128(bound(newBSeed1, 1, maxB));
        // forge-lint: disable-next-line(unsafe-typecast)
        amounts.newA2 = uint128(bound(newASeed2, 1, maxA));
        // forge-lint: disable-next-line(unsafe-typecast)
        amounts.newB2 = uint128(bound(newBSeed2, 1, maxB));
        if (
            (amounts.newA1 == order1.availableA && amounts.newB1 == order1.availableB)
                || (amounts.newA2 == order2.availableA && amounts.newB2 == order2.availableB)
        ) {
            return amounts;
        }

        amounts.ok = true;
    }

    /// @notice Nets two availableA deltas into the ERC20/ETH top-up the batch must fund
    function _netModifyPull(
        uint128 availableA1,
        uint128 newA1,
        uint128 availableA2,
        uint128 newA2
    ) private pure returns (uint256 netPull) {
        uint256 totalTopUp = 0;
        uint256 totalRefund = 0;
        if (newA1 > availableA1) {
            totalTopUp += uint256(newA1) - uint256(availableA1);
        } else if (newA1 < availableA1) {
            totalRefund += uint256(availableA1) - uint256(newA1);
        }
        if (newA2 > availableA2) {
            totalTopUp += uint256(newA2) - uint256(availableA2);
        } else if (newA2 < availableA2) {
            totalRefund += uint256(availableA2) - uint256(newA2);
        }

        return totalTopUp > totalRefund ? totalTopUp - totalRefund : 0;
    }

    /// @notice Computes ETH top-up value for a modify, or reports insufficient funds
    function _modifyOrderTopUp(
        ISwapboard.Order memory order,
        uint128 newA
    ) private view returns (ModifyTopUp memory result) {
        if (newA > order.availableA) {
            uint256 delta = uint256(newA) - uint256(order.availableA);
            if (order.tokenA == _ETH) {
                if (_currentActor.balance < delta) {
                    return result;
                }
                result.funded = true;
                result.value = delta;
                return result;
            }
            if (_tokenA.balanceOf(_currentActor) < delta) {
                return result;
            }
        }
        result.funded = true;
        return result;
    }

    /// @notice Updates ghost accounting after a successful modifyOrder
    function _trackModifyOrderGhosts(
        ISwapboard.Order memory order,
        uint256 orderId,
        uint128 newA,
        uint128 newB
    ) private {
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

        ++_calls.setPartialFillAllowed;
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
            assertTrue(order.active);
            assertTrue(order.availableA > 0 && order.availableB > 0);
            // Fully filled / cancelled orders are deleted (maker == 0) and skipped above.
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
