// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {ISemver} from "./ISemver.sol";

/// @title ISwapboard
/// @author Zak Cole (numbergroup.xyz) for Ethereum Community Foundation
/// @notice Interface for the Swapboard OTC trading contract
/// @dev Implement this interface for composability with the Swapboard protocol.
///      All amounts are in base units (wei-equivalent for 18 decimal tokens).
///      Native ETH is represented by the sentinel returned from `getEth()`.
interface ISwapboard is ISemver {
    /// @notice Represents a single OTC order
    /// @dev `uint128` amounts are sufficient for practical order sizes (e.g. ~3.4e20 wei ≈
    ///      340B tokens at 18 decimals).
    ///      Fill progress is `(amountA - availableA) / amountA` (and likewise for B).
    /// @param maker Address that created the order and deposited tokenA
    /// @param active Whether the order can still be filled or cancelled
    /// @param partialFillAllowed Whether the order may be filled in multiple parts
    /// @param tokenA Address of the token being sold (held in escrow)
    /// @param tokenB Address of the token maker wants to receive
    /// @param amountA Original amount of tokenA deposited (unchanged by fills)
    /// @param amountB Original amount of tokenB required (unchanged by fills)
    /// @param availableA Remaining tokenA still in escrow / available to fill
    /// @param availableB Remaining tokenB still required to complete the order
    struct Order {
        address maker;
        bool active;
        bool partialFillAllowed;
        address tokenA;
        address tokenB;
        uint128 amountA;
        uint128 amountB;
        uint128 availableA;
        uint128 availableB;
    }

    /// @notice Arguments for creating a single OTC order
    /// @param tokenA Address of the asset to sell (`getEth()` for native ETH)
    /// @param amountA Amount of tokenA to deposit (in base units / wei)
    /// @param tokenB Address of the asset wanted in exchange (`getEth()` for native ETH)
    /// @param amountB Amount of tokenB required to fill the order
    /// @param partialFillAllowed Whether the order may be filled in multiple parts
    struct CreateOrderParams {
        address tokenA;
        uint128 amountA;
        address tokenB;
        uint128 amountB;
        bool partialFillAllowed;
    }

    /// @notice Arguments for filling a single OTC order
    /// @param orderId Unique identifier of the order to fill
    /// @param amountA Amount of tokenA to receive from the order
    /// @param minAmountB Minimum amount of tokenB the taker is willing to pay (quoted payment may be higher)
    struct FillOrderParams {
        uint256 orderId;
        uint128 amountA;
        uint128 minAmountB;
    }

    // solhint-disable gas-indexed-events

    /// @notice Emitted when a new order is created
    /// @param orderId Unique identifier for the order
    /// @param maker Address that created the order
    /// @param tokenA Address of the token being sold
    /// @param amountA Amount of tokenA deposited
    /// @param tokenB Address of the token wanted
    /// @param amountB Amount of tokenB required to fill
    /// @param partialFillAllowed Whether the order may be filled in multiple parts
    event OrderCreated(
        uint256 indexed orderId,
        address indexed maker,
        address tokenA,
        uint128 amountA,
        address tokenB,
        uint128 amountB,
        bool partialFillAllowed
    );

    /// @notice Emitted when an order is filled (fully or partially) by a taker
    /// @param orderId Unique identifier for the filled order
    /// @param taker Address that filled the order
    /// @param amountA Amount of tokenA transferred to the taker
    /// @param amountB Amount of tokenB paid by the taker
    event OrderFilled(uint256 indexed orderId, address indexed taker, uint128 amountA, uint128 amountB);

    // solhint-enable gas-indexed-events

    /// @notice Emitted when an order is cancelled by its maker
    /// @param orderId Unique identifier for the cancelled order
    event OrderCanceled(uint256 indexed orderId);

    /// @notice Thrown when a zero address is provided for a token
    error ZeroAddress();

    /// @notice Thrown when a zero amount is provided
    error ZeroAmount();

    /// @notice Thrown when tokenA and tokenB are the same address
    error SameToken();

    /// @notice Thrown when a provided address has no code (not a contract)
    /// @param token The address that is not a contract
    error NotAContract(address token);

    /// @notice Thrown when the received token amount differs from expected
    /// @dev Used to detect fee-on-transfer / mid-transfer rebase / phantom tokens
    /// @param expected The amount that was expected to be received
    /// @param received The amount that was actually received
    error BalanceMismatch(uint256 expected, uint256 received);

    /// @notice Thrown when attempting to interact with a non-existent order
    /// @param orderId The order ID that was not found
    error OrderNotFound(uint256 orderId);

    /// @notice Thrown when attempting to fill or cancel an inactive order
    /// @param orderId The order ID that is not active
    error OrderNotActive(uint256 orderId);

    /// @notice Thrown when someone other than the maker tries to cancel an order
    /// @param orderId The order ID
    /// @param caller The address that attempted to cancel
    /// @param maker The actual maker of the order
    error NotMaker(uint256 orderId, address caller, address maker);

    /// @notice Thrown when msg.value does not match the required ETH amount
    /// @param required The required ETH amount (0 when ETH is not used)
    /// @param sent The actual msg.value
    error ETHAmountMismatch(uint256 required, uint256 sent);

    /// @notice Thrown when a fill is attempted after the specified deadline
    error DeadlineExpired();

    /// @notice Thrown when a partial fill is attempted on an order that disallows it
    /// @param orderId The order ID
    error PartialFillNotAllowed(uint256 orderId);

    /// @notice Thrown when the requested fill amountA exceeds the order's available amountA
    /// @param orderId The order ID
    /// @param requested The requested amountA
    /// @param remaining The available amountA on the order
    error FillAmountTooHigh(uint256 orderId, uint128 requested, uint128 remaining);

    /// @notice Thrown when the quoted fill payment is below the taker's minimum
    /// @param orderId The order ID
    /// @param quoted The quoted payment amount for this fill
    /// @param minimum The minimum payment amount declared by the taker
    error FillAmountMismatch(uint256 orderId, uint128 quoted, uint128 minimum);

    /// @notice Thrown when the same order ID appears more than once in a cancel batch
    /// @param orderId The duplicated order ID
    error DuplicateOrderId(uint256 orderId);

    /// @notice Creates a new OTC order by depositing tokenA (ERC20 or native ETH)
    /// @dev For ERC20 tokenA, transfers from caller and rejects fee-on-transfer / mid-transfer
    ///      rebase tokens.
    ///      For ETH tokenA (`getEth()`), requires `msg.value == amountA`.
    ///      Amounts use `uint128`, which is sufficient for practical order sizes.
    /// @param order Order creation arguments
    /// @return orderId The unique identifier for the created order
    function createOrder(
        CreateOrderParams calldata order
    ) external payable returns (uint256);

    /// @notice Creates multiple OTC orders in one call
    /// @dev Repeated `tokenA` deposits are aggregated into a single ERC20 `transferFrom` per
    ///      unique token. ETH deposits are summed and checked against `msg.value`.
    /// @param orders Order creation arguments
    /// @return orderIds Identifiers assigned to each created order, in input order
    function createOrders(
        CreateOrderParams[] calldata orders
    ) external payable returns (uint256[] memory);

    /// @notice Fills an existing order for the given amountA
    /// @dev Taker receives `amountA` of tokenA and pays proportional tokenB.
    ///      tokenB in is ceiled (`(amountA * availableB + availableA - 1) / availableA`) so the
    ///      taker never underpays. Residual tokenA dust is not refunded (not worth the gas); it
    ///      can be picked up by any user that rounds favorably on another order where the dust
    ///      token is tokenB.
    ///      `minAmountB` is the minimum tokenB payment the taker accepts; the quoted ceiled payment may
    ///      exceed it (e.g. rounding). Reverts with `FillAmountMismatch` when the quote is lower.
    ///      If tokenB is ETH, requires `msg.value` equal to the ceiled tokenB amount.
    ///      If tokenA is ETH, pays the taker in ETH.
    /// @param orderId The unique identifier of the order to fill
    /// @param amountA Amount of tokenA to receive from the order
    /// @param minAmountB Minimum amount of tokenB the taker is willing to pay
    /// @param deadline Unix timestamp after which the fill reverts (0 = no deadline)
    function fillOrder(
        uint256 orderId,
        uint128 amountA,
        uint128 minAmountB,
        uint256 deadline
    ) external payable;

    /// @notice Fills multiple orders in one call
    /// @dev The same `orderId` may appear more than once when the order allows partial fills and
    ///      still has remaining liquidity; otherwise later legs revert (`FillAmountTooHigh` /
    ///      `OrderNotActive` / `PartialFillNotAllowed`). Repeated tokenB payments are aggregated
    ///      into a single ERC20 pull per unique token (and one `msg.value` check for ETH). tokenA
    ///      payouts to the taker and tokenB payouts to makers are similarly aggregated.
    /// @param fills Fill arguments in execution order
    /// @param deadline Unix timestamp after which the batch reverts (0 = no deadline)
    function fillOrders(
        FillOrderParams[] calldata fills,
        uint256 deadline
    ) external payable;

    /// @notice Cancels an existing order and returns available tokenA to maker
    /// @dev Only callable by the order's maker. Returns ETH if tokenA is ETH.
    ///      Clears the order from storage after refunding.
    /// @param orderId The unique identifier of the order to cancel
    function cancelOrder(
        uint256 orderId
    ) external;

    /// @notice Cancels multiple orders in one call
    /// @dev Only the maker may cancel each order. Repeated `tokenA` refunds are aggregated into
    ///      a single ERC20 transfer per unique token. ETH refunds are summed into one send.
    /// @param orderIds Identifiers of the orders to cancel
    function cancelOrders(
        uint256[] calldata orderIds
    ) external;

    /// @notice Canonical placeholder address representing native ETH
    /// @return The ETH sentinel address (`0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`)
    function getEth() external pure returns (address);

    /// @notice Next order ID that will be assigned on create
    /// @return The next order ID
    function getNextOrderId() external view returns (uint256);

    /// @notice Retrieves the details of a single order
    /// @param orderId The unique identifier of the order
    /// @return The Order struct containing all order details
    function getOrder(
        uint256 orderId
    ) external view returns (Order memory);

    /// @notice Retrieves the details of multiple orders in a single call
    /// @dev Returns default Order struct for non-existent orderIds
    /// @param orderIds Array of order identifiers to retrieve
    /// @return Array of Order structs in the same order as input
    function getOrders(
        uint256[] calldata orderIds
    ) external view returns (Order[] memory);

    /// @notice Checks whether an order can be filled
    /// @dev Returns false for non-existent orders (they have active=false by default)
    /// @param orderId The unique identifier of the order to check
    /// @return Whether the order exists and is active
    function canFill(
        uint256 orderId
    ) external view returns (bool);
}
