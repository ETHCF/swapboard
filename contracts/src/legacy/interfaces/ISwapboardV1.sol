// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

/// @title ISwapboardV1
/// @author Zak Cole (numbergroup.xyz) for Ethereum Community Foundation
/// @notice Legacy v1 interface for the Swapboard OTC trading contract
/// @dev Matches `ISwapboard` as shipped on `main` (pre-v2). Kept for integrators
///      targeting deployed v1 contracts. All amounts are in base units
///      (wei-equivalent for 18 decimal tokens).
interface ISwapboardV1 {
    /// @notice Represents a single OTC order
    /// @param maker Address that created the order and deposited tokenA
    /// @param tokenA Address of the token being sold (held in escrow)
    /// @param amountA Amount of tokenA deposited by maker (in base units)
    /// @param tokenB Address of the token maker wants to receive
    /// @param amountB Amount of tokenB required to fill the order (in base units)
    /// @param active Whether the order can still be filled or cancelled
    struct Order {
        address maker;
        bool active;
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
    event OrderCreated(
        uint256 indexed orderId,
        address indexed maker,
        address tokenA,
        uint256 amountA,
        address tokenB,
        uint256 amountB
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

    /// @notice Thrown when a function requiring WETH is called on a non-WETH token
    /// @param expected The WETH address
    /// @param actual The actual token address
    error NotWETH(address expected, address actual);

    /// @notice Thrown when msg.value does not match the required ETH amount
    /// @param required The required ETH amount
    /// @param sent The actual msg.value
    error ETHAmountMismatch(uint256 required, uint256 sent);

    /// @notice Thrown when an ETH transfer fails
    /// @param recipient The intended recipient
    error ETHTransferFailed(address recipient);

    /// @notice Thrown when msg.value is zero for a payable function
    error ZeroETH();

    /// @notice Thrown when a fill is attempted after the specified deadline
    error DeadlineExpired();

    /// @notice Creates a new OTC order by depositing tokenA
    /// @dev Transfers tokenA from caller to contract. Reverts if token is fee-on-transfer.
    /// @param tokenA Address of the ERC20 token to sell
    /// @param amountA Amount of tokenA to deposit (in base units)
    /// @param tokenB Address of the ERC20 token wanted in exchange
    /// @param amountB Amount of tokenB required to fill the order (in base units)
    /// @return orderId The unique identifier for the created order
    function createOrder(
        address tokenA,
        uint256 amountA,
        address tokenB,
        uint256 amountB
    ) external returns (uint256 orderId);

    /// @notice Fills an existing order by transferring tokenB to maker
    /// @dev Transfers tokenB from caller to maker, transfers tokenA from contract to caller
    /// @param orderId The unique identifier of the order to fill
    /// @param deadline Unix timestamp after which the fill reverts (0 = no deadline)
    function fillOrder(
        uint256 orderId,
        uint256 deadline
    ) external;

    /// @notice Cancels an existing order and returns tokenA to maker
    /// @dev Only callable by the order's maker
    /// @param orderId The unique identifier of the order to cancel
    function cancelOrder(
        uint256 orderId
    ) external;

    /// @notice Retrieves the details of a single order
    /// @param orderId The unique identifier of the order
    /// @return order The Order struct containing all order details
    function getOrder(
        uint256 orderId
    ) external view returns (Order memory order);

    /// @notice Retrieves the details of multiple orders in a single call
    /// @dev Returns default Order struct for non-existent orderIds
    /// @param orderIds Array of order identifiers to retrieve
    /// @return result Array of Order structs in the same order as input
    function getOrders(
        uint256[] calldata orderIds
    ) external view returns (Order[] memory result);

    /// @notice Checks whether an order can be filled
    /// @dev Returns false for non-existent orders (they have active=false by default)
    /// @param orderId The unique identifier of the order to check
    /// @return Whether the order exists and is active
    function canFill(
        uint256 orderId
    ) external view returns (bool);

    /// @notice Returns the WETH address used by this contract
    /// @return The WETH token address
    function weth() external view returns (address);

    /// @notice Creates an order selling ETH (auto-wrapped to WETH)
    /// @dev Wraps msg.value to WETH and stores order with tokenA = WETH
    /// @param tokenB Address of the ERC20 token wanted in exchange
    /// @param amountB Amount of tokenB required to fill the order (in base units)
    /// @return orderId The unique identifier for the created order
    function createOrderWithEth(
        address tokenB,
        uint256 amountB
    ) external payable returns (uint256 orderId);

    /// @notice Fills an order by sending ETH (auto-wrapped to WETH)
    /// @dev Requires order.tokenB == WETH and msg.value == order.amountB
    /// @param orderId The unique identifier of the order to fill
    /// @param deadline Unix timestamp after which the fill reverts (0 = no deadline)
    function fillOrderWithEth(
        uint256 orderId,
        uint256 deadline
    ) external payable;

    /// @notice Cancels an order where tokenA is WETH, returning ETH to maker
    /// @dev Only callable by the order's maker. Unwraps WETH to ETH.
    /// @param orderId The unique identifier of the order to cancel
    function cancelOrderUnwrap(
        uint256 orderId
    ) external;

    /// @notice Fills an order where tokenA is WETH, receiving ETH instead
    /// @dev Pays tokenB normally, receives ETH after WETH unwrap
    /// @param orderId The unique identifier of the order to fill
    /// @param deadline Unix timestamp after which the fill reverts (0 = no deadline)
    function fillOrderUnwrap(
        uint256 orderId,
        uint256 deadline
    ) external;
}
