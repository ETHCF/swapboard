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
    /// @param maker Address that created the order and deposited tokenA
    /// @param active Whether the order can still be filled or cancelled
    /// @param partialFillAllowed Whether the order may be filled in multiple parts
    /// @param tokenA Address of the token being sold (held in escrow)
    /// @param amountA Amount of tokenA deposited by maker (in base units)
    /// @param tokenB Address of the token maker wants to receive
    /// @param amountB Amount of tokenB required to fill the order (in base units)
    struct Order {
        address maker;
        bool active;
        bool partialFillAllowed;
        address tokenA;
        uint256 amountA;
        address tokenB;
        uint256 amountB;
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
        uint256 amountA,
        address tokenB,
        uint256 amountB,
        bool partialFillAllowed
    );
    // solhint-enable gas-indexed-events

    /// @notice Emitted when an order is filled by a taker
    /// @param orderId Unique identifier for the filled order
    /// @param taker Address that filled the order
    event OrderFilled(uint256 indexed orderId, address indexed taker);

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
    /// @dev Used to detect fee-on-transfer tokens
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

    /// @notice Creates a new OTC order by depositing tokenA (ERC20 or native ETH)
    /// @dev For ERC20 tokenA, transfers from caller and rejects fee-on-transfer tokens.
    ///      For ETH tokenA (`getEth()`), requires `msg.value == amountA`.
    /// @param tokenA Address of the asset to sell (`getEth()` for native ETH)
    /// @param amountA Amount of tokenA to deposit (in base units / wei)
    /// @param tokenB Address of the asset wanted in exchange (`getEth()` for native ETH)
    /// @param amountB Amount of tokenB required to fill the order
    /// @param partialFillAllowed Whether the order may be filled in multiple parts
    /// @return orderId The unique identifier for the created order
    function createOrder(
        address tokenA,
        uint256 amountA,
        address tokenB,
        uint256 amountB,
        bool partialFillAllowed
    ) external payable returns (uint256 orderId);

    /// @notice Fills an existing order
    /// @dev If tokenB is ETH, requires `msg.value == amountB`.
    ///      If tokenA is ETH, pays the taker in ETH.
    /// @param orderId The unique identifier of the order to fill
    /// @param deadline Unix timestamp after which the fill reverts (0 = no deadline)
    function fillOrder(
        uint256 orderId,
        uint256 deadline
    ) external payable;

    /// @notice Cancels an existing order and returns tokenA to maker
    /// @dev Only callable by the order's maker. Returns ETH if tokenA is ETH.
    /// @param orderId The unique identifier of the order to cancel
    function cancelOrder(
        uint256 orderId
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
