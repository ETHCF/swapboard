// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

/// @title ISwapboard
/// @author Zak Cole (numbergroup.xyz) for Ethereum Community Foundation
/// @notice Interface for the Swapboard OTC trading contract
/// @dev Implement this interface for composability with the Swapboard protocol.
///      All amounts are in base units (wei-equivalent for 18 decimal tokens).
interface ISwapboard {
    /// @notice Represents a single OTC order
    /// @param maker Address that created the order and deposited tokenA
    /// @param active Whether the order can still be filled or cancelled
    /// @param partialFill Whether the order allows partial fills
    /// @param tokenA Address of the token being sold (held in escrow)
    /// @param amountA Amount of tokenA remaining in the order (in base units)
    /// @param tokenB Address of the token maker wants to receive
    /// @param amountB Amount of tokenB still required to fill the order (in base units)
    struct Order {
        address maker;
        bool active;
        bool partialFill;
        address tokenA;
        uint256 amountA;
        address tokenB;
        uint256 amountB;
    }

    /// @notice Emitted when a new order is created
    /// @param orderId Unique identifier for the order
    /// @param maker Address that created the order
    /// @param tokenA Address of the token being sold
    /// @param amountA Amount of tokenA deposited
    /// @param tokenB Address of the token wanted
    /// @param amountB Amount of tokenB required to fill
    /// @param partialFill Whether the order allows partial fills
    event OrderCreated(
        uint256 indexed orderId,
        address indexed maker,
        address tokenA,
        uint256 amountA,
        address tokenB,
        uint256 amountB,
        bool partialFill
    );

    /// @notice Emitted when an order is fully filled by a taker
    /// @dev May follow one or more OrderPartiallyFilled events for the same orderId
    /// @param orderId Unique identifier for the filled order
    /// @param taker Address that filled the order
    /// @param maker Address that created the order
    /// @param tokenA Address of the token transferred to the taker
    /// @param amountA Amount of tokenA transferred to the taker
    /// @param tokenB Address of the token transferred to the maker
    /// @param amountB Amount of tokenB transferred to the maker
    event OrderFilled(
        uint256 indexed orderId,
        address indexed taker,
        address indexed maker,
        address tokenA,
        uint256 amountA,
        address tokenB,
        uint256 amountB
    );

    /// @notice Emitted when an order is partially filled by a taker
    /// @param orderId Unique identifier for the partially filled order
    /// @param taker Address that partially filled the order
    /// @param maker Address that created the order
    /// @param tokenA Address of the token transferred to the taker
    /// @param amountAFilled Amount of tokenA transferred to the taker
    /// @param tokenB Address of the token transferred to the maker
    /// @param amountBFilled Amount of tokenB transferred to the maker
    /// @param amountARemaining Amount of tokenA still in escrow
    /// @param amountBRemaining Amount of tokenB still required
    event OrderPartiallyFilled(
        uint256 indexed orderId,
        address indexed taker,
        address indexed maker,
        address tokenA,
        uint256 amountAFilled,
        address tokenB,
        uint256 amountBFilled,
        uint256 amountARemaining,
        uint256 amountBRemaining
    );

    /// @notice Emitted when an order is cancelled by its maker
    /// @param orderId Unique identifier for the cancelled order
    /// @param maker Address that created and cancelled the order
    /// @param tokenA Address of the token returned to the maker
    /// @param amountA Amount of tokenA returned to the maker (remaining after prior fills)
    event OrderCanceled(
        uint256 indexed orderId, address indexed maker, address tokenA, uint256 amountA
    );

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

    /// @notice Thrown when msg.value exceeds the remaining order amount
    /// @param required The maximum acceptable ETH amount
    /// @param sent The actual msg.value
    error ETHAmountMismatch(uint256 required, uint256 sent);

    /// @notice Thrown when an ETH transfer fails
    /// @param recipient The intended recipient
    error ETHTransferFailed(address recipient);

    /// @notice Thrown when msg.value is zero for a payable function
    error ZeroETH();

    /// @notice Thrown when a fill is attempted after the specified deadline
    error DeadlineExpired();

    /// @notice Thrown when a partial fill is attempted on a non-partial order
    /// @param orderId The order ID that does not allow partial fills
    error PartialFillNotAllowed(uint256 orderId);

    /// @notice Thrown when the computed fillAmountA rounds to zero
    /// @dev Means the fill is too small to transfer any tokenA
    error ZeroFillAmount();

    /// @notice Thrown when array arguments have mismatched lengths
    error LengthMismatch();

    /// @notice Parameters for creating an order in a batch
    /// @param tokenA Address of the ERC20 token to sell
    /// @param amountA Amount of tokenA to deposit (in base units)
    /// @param tokenB Address of the ERC20 token wanted in exchange
    /// @param amountB Amount of tokenB required to fill the order (in base units)
    /// @param partialFill Whether the order allows partial fills
    struct CreateOrderParams {
        address tokenA;
        uint256 amountA;
        address tokenB;
        uint256 amountB;
        bool partialFill;
    }

    /// @notice Creates a new OTC order by depositing tokenA
    /// @dev Transfers tokenA from caller to contract. Reverts if token is fee-on-transfer.
    /// @param tokenA Address of the ERC20 token to sell
    /// @param amountA Amount of tokenA to deposit (in base units)
    /// @param tokenB Address of the ERC20 token wanted in exchange
    /// @param amountB Amount of tokenB required to fill the order (in base units)
    /// @param partialFill Whether the order allows partial fills
    /// @return orderId The unique identifier for the created order
    function createOrder(
        address tokenA,
        uint256 amountA,
        address tokenB,
        uint256 amountB,
        bool partialFill
    ) external returns (uint256 orderId);

    /// @notice Creates multiple orders in a single transaction
    /// @dev Atomic: if any order creation reverts, the entire batch reverts.
    ///      Gas scales linearly with array length.
    /// @param params Array of CreateOrderParams structs
    /// @return orderIds Array of unique identifiers for the created orders
    function createOrders(
        CreateOrderParams[] calldata params
    ) external returns (uint256[] memory orderIds);

    /// @notice Fills an existing order, fully or partially
    /// @dev When fillAmountB is 0 or >= remaining amountB, fills the entire order.
    ///      When fillAmountB < remaining amountB, performs a partial fill (requires
    ///      partialFill flag). Partial fillAmountA = fillAmountB * amountA / amountB,
    ///      rounded down (favoring maker).
    ///      Fee-on-transfer tokenB: maker receives less than the nominal amount.
    ///      This is the maker's risk — verify token behavior before creating orders.
    /// @param orderId The unique identifier of the order to fill
    /// @param deadline Unix timestamp after which the fill reverts (0 = no deadline)
    /// @param fillAmountB Amount of tokenB to pay (0 = fill entire order)
    function fillOrder(
        uint256 orderId,
        uint256 deadline,
        uint256 fillAmountB
    ) external;

    /// @notice Fills multiple orders in a single transaction
    /// @dev Non-payable — use WETH for ETH-denominated fills. Atomic: if any fill
    ///      reverts, the entire batch reverts. Gas scales linearly with array length.
    ///      Fee-on-transfer tokenB: maker receives less than the nominal amount.
    ///      This is the maker's risk — verify token behavior before creating orders.
    /// @param orderIds Array of order identifiers to fill
    /// @param deadline Unix timestamp after which the fill reverts (0 = no deadline)
    /// @param fillAmountsB Array of tokenB amounts to pay (0 = fill entire order)
    function fillOrders(
        uint256[] calldata orderIds,
        uint256 deadline,
        uint256[] calldata fillAmountsB
    ) external;

    /// @notice Batch fill that skips inactive/nonexistent orders without reverting
    /// @dev NOT a general best-effort fill. The only failure mode handled here is an
    ///      inactive or nonexistent order — those are skipped and marked false in the
    ///      returned array. Every other revert path (insufficient tokenB allowance,
    ///      tokenB transfer failure, partial-fill-not-allowed, zero-fill rounding,
    ///      expired deadline, length mismatch) aborts the entire batch. Integrators
    ///      must pre-validate allowances and partial-fill flags off-chain.
    ///      Fee-on-transfer tokenB: maker receives less than the nominal amount.
    ///      This is the maker's risk — verify token behavior before creating orders.
    /// @param orderIds Array of order identifiers to fill
    /// @param deadline Unix timestamp after which the fill reverts (0 = no deadline)
    /// @param fillAmountsB Array of tokenB amounts to pay (0 = fill entire order)
    /// @return filled Array of booleans indicating which orders were filled
    function tryFillOrders(
        uint256[] calldata orderIds,
        uint256 deadline,
        uint256[] calldata fillAmountsB
    ) external returns (bool[] memory filled);

    /// @notice Cancels an existing order and returns remaining tokenA to maker
    /// @dev Only callable by the order's maker. For partially filled orders,
    ///      returns only the remaining amountA still held in escrow.
    /// @param orderId The unique identifier of the order to cancel
    function cancelOrder(
        uint256 orderId
    ) external;

    /// @notice Cancels multiple orders in a single transaction
    /// @dev Only callable by the orders' maker. Atomic: if any cancellation reverts,
    ///      the entire batch reverts. Gas scales linearly with array length.
    /// @param orderIds Array of order identifiers to cancel
    function cancelOrders(
        uint256[] calldata orderIds
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
    function weth() external view returns (address);

    /// @notice Creates an order selling ETH (auto-wrapped to WETH)
    /// @dev Wraps msg.value to WETH and stores order with tokenA = WETH
    /// @param tokenB Address of the ERC20 token wanted in exchange
    /// @param amountB Amount of tokenB required to fill the order (in base units)
    /// @param partialFill Whether the order allows partial fills
    /// @return orderId The unique identifier for the created order
    function createOrderWithEth(
        address tokenB,
        uint256 amountB,
        bool partialFill
    ) external payable returns (uint256 orderId);

    /// @notice Fills an order where tokenB is WETH by sending ETH
    /// @dev msg.value is the fill amount. For full fills, msg.value must equal
    ///      remaining amountB. For partial fills (msg.value < amountB), the order
    ///      must have partialFill enabled. Reverts if msg.value > amountB.
    /// @param orderId The unique identifier of the order to fill
    /// @param deadline Unix timestamp after which the fill reverts (0 = no deadline)
    function fillOrderWithEth(
        uint256 orderId,
        uint256 deadline
    ) external payable;

    /// @notice Cancels an order where tokenA is WETH, returning remaining ETH to maker
    /// @dev Only callable by the order's maker. Unwraps remaining WETH to ETH.
    /// @param orderId The unique identifier of the order to cancel
    function cancelOrderUnwrap(
        uint256 orderId
    ) external;

    /// @notice Cancels multiple orders where tokenA is WETH, returning remaining ETH to maker
    /// @dev Only callable by the orders' maker. Atomic: if any cancellation reverts,
    ///      the entire batch reverts. Gas scales linearly with array length.
    /// @param orderIds Array of order identifiers to cancel
    function cancelOrdersUnwrap(
        uint256[] calldata orderIds
    ) external;

    /// @notice Fills an order where tokenA is WETH, receiving ETH instead of WETH
    /// @dev When fillAmountB is 0 or >= remaining amountB, fills the entire order.
    ///      When fillAmountB < remaining amountB, performs a partial fill (requires
    ///      partialFill flag). Taker receives ETH after WETH unwrap.
    /// @param orderId The unique identifier of the order to fill
    /// @param deadline Unix timestamp after which the fill reverts (0 = no deadline)
    /// @param fillAmountB Amount of tokenB to pay (0 = fill entire order)
    function fillOrderUnwrap(
        uint256 orderId,
        uint256 deadline,
        uint256 fillAmountB
    ) external;
}
