// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

import {ReentrancyGuardTransient} from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ISwapboard} from "./interfaces/ISwapboard.sol";
import {Semver} from "./Semver.sol";

/// @title Swapboard
/// @author Zak Cole (numbergroup.xyz) for Ethereum Community Foundation
/// @notice Trustless OTC bulletin board for ERC20 and native ETH swaps on Ethereum
/// @dev This contract implements a simple orderbook for peer-to-peer token swaps.
///
///      Key properties:
///      - No admin functions, fees, or upgrades
///      - Orders are filled atomically (all-or-nothing); `partialFillAllowed` is stored but not enforced yet
///      - Fee-on-transfer tokens are rejected for tokenA (selling token)
///      - Native ETH uses the `0xEeee...eE` sentinel (`getEth()`)
///      - Reentrancy protected via OpenZeppelin ReentrancyGuardTransient (EIP-1153)
///
///      Security considerations:
///      - Front-running is possible on fillOrder (inherent to on-chain orderbooks)
///      - Rebasing tokens may cause unexpected behavior
///      - Malicious tokens can cause fund loss - users must verify token contracts
///      - ETH is sent with `Address.sendValue` (forwards all gas) so contract recipients
///        can run `receive`/`fallback`; always after state updates (CEI)
///
/// @custom:security-contact zak@numbergroup.xyz
contract Swapboard is ISwapboard, Semver, ReentrancyGuardTransient {
    using SafeERC20 for IERC20;
    using Address for address payable;

    /// @notice Canonical placeholder address representing native ETH
    address private constant _ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice Counter for generating unique order IDs
    /// @dev Starts at 0, increments by 1 for each new order
    uint256 private _nextOrderId;

    /// @notice Mapping from order ID to Order struct
    /// @dev Non-existent orders return default struct with maker=address(0) and active=false
    mapping(uint256 orderId => Order order) private _orders;

    /// @notice Initializes Swapboard
    constructor() Semver(2, 0, 0) {}

    /// @inheritdoc ISwapboard
    /// @dev Token addresses are identity-based. Aliased or rebranded tokens at different
    ///      addresses are treated as distinct tokens. Users must verify token addresses.
    function createOrder(
        address tokenA,
        uint256 amountA,
        address tokenB,
        uint256 amountB,
        bool partialFillAllowed
    ) external payable nonReentrant returns (uint256 orderId) {
        _validateCreateOrder(tokenA, amountA, tokenB, amountB);

        if (tokenA != _ETH) {
            _pullExactToken(tokenA, amountA);
        }

        unchecked {
            orderId = _nextOrderId;

            ++_nextOrderId;
        }

        _orders[orderId] = Order({
            maker: msg.sender,
            active: true,
            partialFillAllowed: partialFillAllowed,
            tokenA: tokenA,
            amountA: amountA,
            tokenB: tokenB,
            amountB: amountB
        });

        emit OrderCreated({
            orderId: orderId,
            maker: msg.sender,
            tokenA: tokenA,
            amountA: amountA,
            tokenB: tokenB,
            amountB: amountB,
            partialFillAllowed: partialFillAllowed
        });
    }

    /// @inheritdoc ISwapboard
    /// @dev Fee-on-transfer tokenB: maker receives less than amountB. This is maker's risk.
    function fillOrder(
        uint256 orderId,
        uint256 deadline
    ) external payable nonReentrant {
        if (deadline != 0 && block.timestamp > deadline) {
            revert DeadlineExpired();
        }

        Order storage order = _orders[orderId];

        (address maker, bool active, address tokenA, uint256 amountA, address tokenB, uint256 amountB) =
            (order.maker, order.active, order.tokenA, order.amountA, order.tokenB, order.amountB);
        if (maker == address(0)) {
            revert OrderNotFound(orderId);
        }
        if (!active) {
            revert OrderNotActive(orderId);
        }

        uint256 requiredEth = tokenB == _ETH ? amountB : 0;
        if (msg.value != requiredEth) {
            revert ETHAmountMismatch(requiredEth, msg.value);
        }

        order.active = false;

        // Transfer tokenB from taker to maker
        if (tokenB == _ETH) {
            // Forward all gas so maker contracts can execute receive/fallback.
            payable(maker).sendValue(amountB);
        } else {
            // Note: If tokenB is fee-on-transfer, maker receives less than amountB
            IERC20(tokenB).safeTransferFrom(msg.sender, maker, amountB);
        }

        // Transfer tokenA from contract to taker
        if (tokenA == _ETH) {
            // Forward all gas so taker contracts can execute receive/fallback.
            payable(msg.sender).sendValue(amountA);
        } else {
            IERC20(tokenA).safeTransfer(msg.sender, amountA);
        }

        emit OrderFilled({orderId: orderId, taker: msg.sender});
    }

    /// @inheritdoc ISwapboard
    function cancelOrder(
        uint256 orderId
    ) external nonReentrant {
        Order storage order = _orders[orderId];

        (address maker, bool active, address tokenA, uint256 amountA) =
            (order.maker, order.active, order.tokenA, order.amountA);
        if (maker == address(0)) {
            revert OrderNotFound(orderId);
        }
        if (!active) {
            revert OrderNotActive(orderId);
        }
        if (msg.sender != maker) {
            revert NotMaker(orderId, msg.sender, maker);
        }

        order.active = false;

        if (tokenA == _ETH) {
            // Forward all gas so maker contracts can execute receive/fallback.
            payable(maker).sendValue(amountA);
        } else {
            IERC20(tokenA).safeTransfer(maker, amountA);
        }

        emit OrderCanceled({orderId: orderId});
    }

    /// @inheritdoc ISwapboard
    function getEth() external pure returns (address) {
        return _ETH;
    }

    /// @inheritdoc ISwapboard
    function getNextOrderId() external view returns (uint256) {
        return _nextOrderId;
    }

    /// @inheritdoc ISwapboard
    function getOrder(
        uint256 orderId
    ) external view returns (Order memory) {
        return _orders[orderId];
    }

    /// @inheritdoc ISwapboard
    /// @dev Gas scales linearly with array length. Callers should limit to ~100 IDs per call.
    function getOrders(
        uint256[] calldata orderIds
    ) external view returns (Order[] memory) {
        Order[] memory result = new Order[](orderIds.length);

        for (uint256 i; i < orderIds.length;) {
            result[i] = _orders[orderIds[i]];
            unchecked {
                ++i;
            }
        }

        return result;
    }

    /// @inheritdoc ISwapboard
    function canFill(
        uint256 orderId
    ) external view returns (bool) {
        return _orders[orderId].active;
    }

    /// @notice Validates createOrder arguments and exact ETH payment
    /// @param tokenA Address of the asset to sell
    /// @param amountA Amount of tokenA to deposit
    /// @param tokenB Address of the asset wanted
    /// @param amountB Amount of tokenB required to fill
    function _validateCreateOrder(
        address tokenA,
        uint256 amountA,
        address tokenB,
        uint256 amountB
    ) private view {
        if (tokenA == address(0) || tokenB == address(0)) {
            revert ZeroAddress();
        }
        if (amountA == 0 || amountB == 0) {
            revert ZeroAmount();
        }
        if (tokenA == tokenB) {
            revert SameToken();
        }

        bool tokenAIsEth = tokenA == _ETH;
        bool tokenBIsEth = tokenB == _ETH;

        if (!tokenAIsEth && tokenA.code.length == 0) {
            revert NotAContract(tokenA);
        }
        if (!tokenBIsEth && tokenB.code.length == 0) {
            revert NotAContract(tokenB);
        }

        uint256 requiredEth = tokenAIsEth ? amountA : 0;
        if (msg.value != requiredEth) {
            revert ETHAmountMismatch(requiredEth, msg.value);
        }
    }

    /// @notice Pulls an exact ERC20 amount into escrow, rejecting fee-on-transfer
    /// @param token ERC20 token to pull from the caller
    /// @param amount Expected amount received
    function _pullExactToken(
        address token,
        uint256 amount
    ) private {
        uint256 balanceBefore = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        uint256 balanceAfter = IERC20(token).balanceOf(address(this));

        // Detect fee-on-transfer tokens by comparing received amount to expected
        // Using unchecked is safe: balanceAfter >= balanceBefore after successful transfer
        unchecked {
            uint256 received = balanceAfter - balanceBefore;
            if (received != amount) {
                revert BalanceMismatch(amount, received);
            }
        }
    }
}
