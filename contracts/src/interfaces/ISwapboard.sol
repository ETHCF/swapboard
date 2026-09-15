// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.0;

import {ISemver} from "./ISemver.sol";

/// @title ISwapboard
/// @author Zak Cole (numbergroup.xyz) for Ethereum Community Foundation
/// @notice Interface for the Swapboard OTC trading contract
/// @dev Implement this interface for composability with the Swapboard protocol.
///      All amounts are in base units (wei-equivalent for 18 decimal tokens).
///      Native ETH is represented by the sentinel returned from `getEth()`.
///      Create, fill, and modify have EIP-2612 and Permit2 SignatureTransfer overloads; original
///      signatures are unchanged.
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

    /// @notice Arguments for modifying an existing order's remaining amounts
    /// @dev Token addresses, maker, and `partialFillAllowed` cannot be changed here (use
    ///      `setPartialFillAllowed` for the fill flag). Callers set the desired *remaining*
    ///      liquidity; order totals (`amountA` / `amountB`) are reset to those remainings.
    /// @param availableA Desired remaining tokenA in escrow
    /// @param availableB Desired remaining tokenB required to complete the order
    struct ModifyOrderParams {
        uint128 availableA;
        uint128 availableB;
    }

    /// @notice Expected on-chain amounts used for modify race protection
    /// @dev Compared against the live order; only these four fields are checked.
    /// @param amountA Expected `amountA`
    /// @param amountB Expected `amountB`
    /// @param availableA Expected `availableA`
    /// @param availableB Expected `availableB`
    struct OrderAmounts {
        uint128 amountA;
        uint128 amountB;
        uint128 availableA;
        uint128 availableB;
    }

    /// @notice Arguments for filling a single OTC order by exact tokenB paid
    /// @param orderId Unique identifier of the order to fill
    /// @param amountB Exact amount of tokenB to send
    /// @param minAmountA Minimum amount of tokenA the taker will accept
    struct FillOrderParams {
        uint256 orderId;
        uint128 amountB;
        uint128 minAmountA;
    }

    /// @notice Arguments for filling a single OTC order by exact tokenA received
    /// @param orderId Unique identifier of the order to fill
    /// @param amountA Exact amount of tokenA to receive
    /// @param maxAmountB Maximum amount of tokenB the taker is willing to send
    struct FillOrderPayingParams {
        uint256 orderId;
        uint128 amountA;
        uint128 maxAmountB;
    }

    /// @notice Arguments for one entry in a `modifyOrders` batch
    /// @param orderId Unique identifier of the order to modify
    /// @param previousAmounts Expected on-chain amounts from the caller's snapshot
    /// @param updatedOrder Desired remaining amounts
    struct ModifyOrdersParams {
        uint256 orderId;
        OrderAmounts previousAmounts;
        ModifyOrderParams updatedOrder;
    }

    /// @notice EIP-2612 permit for a single known token (create/fill/modify)
    /// @dev `v == 0` skips the permit (use when the caller already has allowance). Spender is
    ///      always this Swapboard. Native ETH with `v != 0` reverts `PermitOnNative`.
    /// @param value Allowance value signed by the owner
    /// @param deadline Unix timestamp after which the permit is invalid
    /// @param v Signature v (27/28); 0 means skip
    /// @param r Signature r
    /// @param s Signature s
    struct Permit {
        uint256 value;
        uint256 deadline;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    /// @notice EIP-2612 permit for one ERC20 in a batch (createOrders/fillOrders/modifyOrders)
    /// @dev Every entry is applied (`v == 0` reverts `InvalidPermit`). Duplicate `token` values
    ///      revert `DuplicatePermitToken`. Empty array means no permits.
    /// @param token ERC20 to permit (not the ETH sentinel)
    /// @param v Signature v (27/28)
    /// @param value Allowance value signed by the owner
    /// @param deadline Unix timestamp after which the permit is invalid
    /// @param r Signature r
    /// @param s Signature s
    struct TokenPermit {
        address token;
        uint8 v;
        uint256 value;
        uint256 deadline;
        bytes32 r;
        bytes32 s;
    }

    /// @notice Permit2 SignatureTransfer payload for a single known token (create/fill/modify)
    /// @dev Empty `signature` skips (classic `transferFrom` / existing Swapboard allowance). Spender is
    ///      always this Swapboard. Native ETH with a non-empty signature reverts `PermitOnNative`.
    /// @param amount Max amount signed in Permit2 `TokenPermissions`
    /// @param nonce Unordered Permit2 nonce
    /// @param deadline Unix timestamp after which the signature is invalid
    /// @param signature EIP-712 signature over Permit2 `PermitTransferFrom` (empty = skip)
    struct Permit2Permit {
        uint256 amount;
        uint256 nonce;
        uint256 deadline;
        bytes signature;
    }

    /// @notice Permit2 SignatureTransfer for one ERC20 in a batch
    /// @dev Every entry is applied (empty `signature` reverts `InvalidPermit2`). Duplicate `token`
    ///      values revert `DuplicatePermitToken`. An unused entry reverts `UnusedPermit2`. More than
    ///      256 entries revert `TooManyPermit2`. Empty array means no Permit2 pulls.
    /// @param token ERC20 to pull via Permit2 (not the ETH sentinel)
    /// @param amount Max amount signed in Permit2 `TokenPermissions`
    /// @param nonce Unordered Permit2 nonce
    /// @param deadline Unix timestamp after which the signature is invalid
    /// @param signature EIP-712 signature over Permit2 `PermitTransferFrom`
    struct TokenPermit2 {
        address token;
        uint256 amount;
        uint256 nonce;
        uint256 deadline;
        bytes signature;
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

    // solhint-disable gas-indexed-events
    /// @notice Emitted when an order's remaining amounts are modified by its maker
    /// @param orderId Unique identifier for the modified order
    /// @param availableA New remaining tokenA in escrow
    /// @param availableB New remaining tokenB required
    event OrderModified(uint256 indexed orderId, uint128 availableA, uint128 availableB);

    /// @notice Emitted when an order's partial-fill setting is changed by its maker
    /// @param orderId Unique identifier for the order
    /// @param partialFillAllowed Whether the order may be filled in multiple parts
    event OrderPartialFillUpdated(uint256 indexed orderId, bool partialFillAllowed);
    // solhint-enable gas-indexed-events

    /// @notice Thrown when a zero address is provided for a token
    error ZeroAddress();

    /// @notice Thrown when a zero amount is provided
    /// @dev On `modifyOrder` / `modifyOrders`, also thrown when either remaining (`availableA` /
    ///      `availableB`) is set to 0 — closing an order requires `cancelOrder` / `cancelOrders`
    ///      instead. Empty `modifyOrders` also reverts.
    error ZeroAmount();

    /// @notice Thrown when a modification would leave the order unchanged
    /// @dev `modifyOrder` / `modifyOrders` when both remainings match on-chain; `setPartialFillAllowed`
    ///      when the flag already equals the requested value.
    error NoChange();

    /// @notice Thrown when tokenA and tokenB are the same address
    error SameToken();

    /// @notice Thrown when a provided address has no code (not a contract)
    /// @param token The address that is not a contract
    error NotAContract(address token);

    /// @notice Thrown when the received token amount differs from expected
    /// @dev Used to detect fee-on-transfer / mid-transfer rebase / phantom tokens on inbound
    ///      pulls: tokenA deposits into escrow and ERC20 tokenB payments directly to the maker
    /// @param expected The amount that was expected to be received
    /// @param received The amount that was actually received
    error BalanceMismatch(uint256 expected, uint256 received);

    /// @notice Thrown when attempting to interact with a non-existent order
    /// @param orderId The order ID that was not found
    error OrderNotFound(uint256 orderId);

    /// @notice Thrown when attempting to operate on an inactive order that still exists
    /// @dev Full fills and cancels `delete` storage, so those paths revert with `OrderNotFound`
    ///      instead. `OrderNotActive` remains for any residual inactive-but-present shell.
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

    /// @notice Thrown when the requested fill amount exceeds the order's remaining liquidity
    /// @dev Used for both amountB-driven (`fillOrder`) and amountA-driven (`fillOrderPaying`) fills.
    /// @param orderId The order ID
    /// @param requested The requested fill amount
    /// @param remaining The available amount on the order for that side
    error FillAmountTooHigh(uint256 orderId, uint128 requested, uint128 remaining);

    /// @notice Thrown when the quoted tokenA receive is below the taker's minimum
    /// @param orderId The order ID
    /// @param quoted The quoted tokenA receive for this fill
    /// @param minimum The minimum tokenA receive declared by the taker
    error FillAmountMismatch(uint256 orderId, uint128 quoted, uint128 minimum);

    /// @notice Thrown when the quoted tokenB payment exceeds the taker's maximum
    /// @param orderId The order ID
    /// @param quoted The quoted tokenB payment for this fill
    /// @param maximum The maximum tokenB payment declared by the taker
    error FillPayTooHigh(uint256 orderId, uint128 quoted, uint128 maximum);

    /// @notice Thrown when the provided previous amounts do not match the current on-chain order
    /// @dev Only `amountA`, `amountB`, `availableA`, and `availableB` are compared; immutable fields
    ///      (maker, tokenA, tokenB) are not checked.
    /// @param orderId The order ID
    /// @param expectedAmountA Expected `amountA` from the caller's snapshot
    /// @param expectedAmountB Expected `amountB` from the caller's snapshot
    /// @param expectedAvailableA Expected `availableA` from the caller's snapshot
    /// @param expectedAvailableB Expected `availableB` from the caller's snapshot
    /// @param actualAmountA Actual `amountA` currently stored on-chain
    /// @param actualAmountB Actual `amountB` currently stored on-chain
    /// @param actualAvailableA Actual `availableA` currently stored on-chain
    /// @param actualAvailableB Actual `availableB` currently stored on-chain
    error OrderStateMismatch(
        uint256 orderId,
        uint128 expectedAmountA,
        uint128 expectedAmountB,
        uint128 expectedAvailableA,
        uint128 expectedAvailableB,
        uint128 actualAmountA,
        uint128 actualAmountB,
        uint128 actualAvailableA,
        uint128 actualAvailableB
    );

    /// @notice Thrown when the same order ID appears more than once in a cancel or modify batch
    /// @param orderId The duplicated order ID
    error DuplicateOrderId(uint256 orderId);

    /// @notice Thrown when an EIP-2612 permit is supplied for the native ETH sentinel
    error PermitOnNative();

    /// @notice Thrown when a batch permit entry is malformed (`v == 0`)
    error InvalidPermit();

    /// @notice Thrown when the same token appears more than once in a permit batch
    /// @param token The duplicated token
    error DuplicatePermitToken(address token);

    /// @notice Thrown when a batch Permit2 entry has an empty signature
    error InvalidPermit2();

    /// @notice Thrown when a batch Permit2 entry is not used by any pull
    error UnusedPermit2();

    /// @notice Thrown when a Permit2 batch has more than 256 entries
    error TooManyPermit2();

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

    /// @notice Creates a new OTC order after applying an EIP-2612 permit for tokenA
    /// @dev `permit.v == 0` skips the permit. Otherwise `token.permit(msg.sender, this, ...)`.
    ///      Native tokenA with `permit.v != 0` reverts `PermitOnNative`.
    /// @param order Order creation arguments
    /// @param permit EIP-2612 signature for tokenA (`v == 0` to skip)
    /// @return orderId The unique identifier for the created order
    function createOrder(
        CreateOrderParams calldata order,
        Permit calldata permit
    ) external payable returns (uint256);

    /// @notice Creates a new OTC order pulling tokenA via Permit2 SignatureTransfer
    /// @dev Empty `permit.signature` skips (classic pull). Native tokenA with a non-empty signature
    ///      reverts `PermitOnNative`. User must have approved the canonical Permit2 contract.
    /// @param order Order creation arguments
    /// @param permit Permit2 signature for tokenA (empty signature to skip)
    /// @return orderId The unique identifier for the created order
    function createOrder(
        CreateOrderParams calldata order,
        Permit2Permit calldata permit
    ) external payable returns (uint256);

    /// @notice Creates multiple OTC orders in one call
    /// @dev Repeated `tokenA` deposits are aggregated into a single ERC20 `transferFrom` per
    ///      unique token. ETH deposits are summed and checked against `msg.value`.
    /// @param orders Order creation arguments
    /// @return orderIds Identifiers assigned to each created order, in input order
    function createOrders(
        CreateOrderParams[] calldata orders
    ) external payable returns (uint256[] memory);

    /// @notice Creates multiple OTC orders after applying EIP-2612 permits
    /// @dev Permits are applied in order before aggregated pulls. One permit per distinct ERC20.
    /// @param orders Order creation arguments
    /// @param permits EIP-2612 signatures keyed by token (empty = none)
    /// @return orderIds Identifiers assigned to each created order, in input order
    function createOrders(
        CreateOrderParams[] calldata orders,
        TokenPermit[] calldata permits
    ) external payable returns (uint256[] memory);

    /// @notice Creates multiple OTC orders pulling ERC20 tokenA via Permit2 SignatureTransfer
    /// @dev One Permit2 entry per distinct ERC20. Signed `amount` must cover the aggregated pull for
    ///      that token. Tokens without an entry use classic `transferFrom`. Empty array = none.
    /// @param orders Order creation arguments
    /// @param permits Permit2 signatures keyed by tokenA (empty = none)
    /// @return orderIds Identifiers assigned to each created order, in input order
    function createOrders(
        CreateOrderParams[] calldata orders,
        TokenPermit2[] calldata permits
    ) external payable returns (uint256[] memory);

    /// @notice Fills an existing order by sending exact amountB
    /// @dev Taker sends `amountB` of tokenB and receives floored proportional tokenA
    ///      (`amountB * availableA / availableB`). Full remaining `amountB == availableB` pays out
    ///      all remaining `availableA`.
    ///      `minAmountA` is the minimum tokenA the taker accepts. Reverts with `FillAmountMismatch`
    ///      when the floored receive is lower.
    ///      ERC20 tokenB is `transferFrom` the taker straight to the maker with an exact-balance
    ///      check (`BalanceMismatch`). ETH tokenB requires `msg.value == amountB`.
    ///      If tokenA is ETH, pays the taker in ETH.
    ///      A fill that exhausts either remaining side `delete`s the order (subsequent reads look
    ///      like `OrderNotFound`); partial fills keep originals and update availables only.
    /// @param orderId The unique identifier of the order to fill
    /// @param amountB Exact amount of tokenB to send
    /// @param minAmountA Minimum amount of tokenA the taker will accept
    /// @param deadline Unix timestamp after which the fill reverts (0 = no deadline)
    function fillOrder(
        uint256 orderId,
        uint128 amountB,
        uint128 minAmountA,
        uint256 deadline
    ) external payable;

    /// @notice Fills an order by exact amountB after an EIP-2612 permit for tokenB
    /// @dev `permit.v == 0` skips the permit. Native tokenB with `permit.v != 0` reverts
    ///      `PermitOnNative`.
    /// @param orderId The unique identifier of the order to fill
    /// @param amountB Exact amount of tokenB to send
    /// @param minAmountA Minimum amount of tokenA the taker will accept
    /// @param deadline Unix timestamp after which the fill reverts (0 = no deadline)
    /// @param permit EIP-2612 signature for tokenB (`v == 0` to skip)
    function fillOrder(
        uint256 orderId,
        uint128 amountB,
        uint128 minAmountA,
        uint256 deadline,
        Permit calldata permit
    ) external payable;

    /// @notice Fills an order by exact amountB pulling tokenB via Permit2 SignatureTransfer
    /// @dev Empty `permit.signature` skips. Native tokenB with a non-empty signature reverts
    ///      `PermitOnNative`. ERC20 tokenB is pulled directly to the maker.
    /// @param orderId The unique identifier of the order to fill
    /// @param amountB Exact amount of tokenB to send
    /// @param minAmountA Minimum amount of tokenA the taker will accept
    /// @param deadline Unix timestamp after which the fill reverts (0 = no deadline)
    /// @param permit Permit2 signature for tokenB (empty signature to skip)
    function fillOrder(
        uint256 orderId,
        uint128 amountB,
        uint128 minAmountA,
        uint256 deadline,
        Permit2Permit calldata permit
    ) external payable;

    /// @notice Fills multiple orders in one call by exact tokenB sent
    /// @dev The same `orderId` may appear more than once when the order allows partial fills and
    ///      still has remaining liquidity; otherwise later legs revert (`FillAmountTooHigh` /
    ///      `OrderNotActive` / `PartialFillNotAllowed`). ERC20 tokenB payments are aggregated per
    ///      unique `(maker, token)` and pulled directly to each maker; ETH tokenB is summed into
    ///      one `msg.value` check. tokenA payouts to the taker are aggregated.
    /// @param fills Fill arguments in execution order
    /// @param deadline Unix timestamp after which the batch reverts (0 = no deadline)
    function fillOrders(
        FillOrderParams[] calldata fills,
        uint256 deadline
    ) external payable;

    /// @notice Fills multiple orders by exact tokenB after EIP-2612 permits
    /// @param fills Fill arguments in execution order
    /// @param deadline Unix timestamp after which the batch reverts (0 = no deadline)
    /// @param permits EIP-2612 signatures keyed by tokenB (empty = none)
    function fillOrders(
        FillOrderParams[] calldata fills,
        uint256 deadline,
        TokenPermit[] calldata permits
    ) external payable;

    /// @notice Fills multiple orders by exact tokenB via Permit2 SignatureTransfer
    /// @dev One Permit2 entry per distinct ERC20 tokenB. For each such token the signed amount must
    ///      cover the total paid across makers. Sole-maker pulls go to that maker; multi-maker
    ///      totals pull here then distribute. Every ERC20 tokenB hop exact-checks the recipient
    ///      (`BalanceMismatch`). Tokens without an entry use classic direct-to-maker pulls.
    ///      Empty array = none.
    /// @param fills Fill arguments in execution order
    /// @param deadline Unix timestamp after which the batch reverts (0 = no deadline)
    /// @param permits Permit2 signatures keyed by tokenB (empty = none)
    function fillOrders(
        FillOrderParams[] calldata fills,
        uint256 deadline,
        TokenPermit2[] calldata permits
    ) external payable;

    /// @notice Fills an existing order by receiving exact amountA
    /// @dev Taker receives `amountA` of tokenA and pays ceiled proportional tokenB
    ///      (`(amountA * availableB + availableA - 1) / availableA`). If that payment consumes all
    ///      remaining tokenB, remaining tokenA is paid out as well so escrow is not left stranded.
    ///      `maxAmountB` is the maximum tokenB the taker will send. Reverts with `FillPayTooHigh`
    ///      when the ceiled payment is higher.
    ///      ERC20 tokenB is `transferFrom` the taker straight to the maker with an exact-balance
    ///      check (`BalanceMismatch`). ETH tokenB requires `msg.value` equal to the quoted payment.
    ///      If tokenA is ETH, pays the taker in ETH.
    ///      A fill that exhausts either remaining side `delete`s the order (subsequent reads look
    ///      like `OrderNotFound`); partial fills keep originals and update availables only.
    /// @param orderId The unique identifier of the order to fill
    /// @param amountA Exact amount of tokenA to receive
    /// @param maxAmountB Maximum amount of tokenB the taker is willing to send
    /// @param deadline Unix timestamp after which the fill reverts (0 = no deadline)
    function fillOrderPaying(
        uint256 orderId,
        uint128 amountA,
        uint128 maxAmountB,
        uint256 deadline
    ) external payable;

    /// @notice Fills an order by exact amountA after an EIP-2612 permit for tokenB
    /// @dev `permit.v == 0` skips the permit. Native tokenB with `permit.v != 0` reverts
    ///      `PermitOnNative`.
    /// @param orderId The unique identifier of the order to fill
    /// @param amountA Exact amount of tokenA to receive
    /// @param maxAmountB Maximum amount of tokenB the taker is willing to send
    /// @param deadline Unix timestamp after which the fill reverts (0 = no deadline)
    /// @param permit EIP-2612 signature for tokenB (`v == 0` to skip)
    function fillOrderPaying(
        uint256 orderId,
        uint128 amountA,
        uint128 maxAmountB,
        uint256 deadline,
        Permit calldata permit
    ) external payable;

    /// @notice Fills an order by exact amountA pulling tokenB via Permit2 SignatureTransfer
    /// @dev Empty `permit.signature` skips. Native tokenB with a non-empty signature reverts
    ///      `PermitOnNative`. ERC20 tokenB is pulled directly to the maker.
    /// @param orderId The unique identifier of the order to fill
    /// @param amountA Exact amount of tokenA to receive
    /// @param maxAmountB Maximum amount of tokenB the taker is willing to send
    /// @param deadline Unix timestamp after which the fill reverts (0 = no deadline)
    /// @param permit Permit2 signature for tokenB (empty signature to skip)
    function fillOrderPaying(
        uint256 orderId,
        uint128 amountA,
        uint128 maxAmountB,
        uint256 deadline,
        Permit2Permit calldata permit
    ) external payable;

    /// @notice Fills multiple orders in one call by exact tokenA received
    /// @dev Same aggregation and multi-leg rules as `fillOrders`, but each leg specifies `amountA`
    ///      and `maxAmountB`.
    /// @param fills Fill arguments in execution order
    /// @param deadline Unix timestamp after which the batch reverts (0 = no deadline)
    function fillOrdersPaying(
        FillOrderPayingParams[] calldata fills,
        uint256 deadline
    ) external payable;

    /// @notice Fills multiple orders by exact tokenA after EIP-2612 permits
    /// @param fills Fill arguments in execution order
    /// @param deadline Unix timestamp after which the batch reverts (0 = no deadline)
    /// @param permits EIP-2612 signatures keyed by tokenB (empty = none)
    function fillOrdersPaying(
        FillOrderPayingParams[] calldata fills,
        uint256 deadline,
        TokenPermit[] calldata permits
    ) external payable;

    /// @notice Fills multiple orders by exact tokenA via Permit2 SignatureTransfer
    /// @dev Same Permit2 aggregation rules as `fillOrders` (one entry per distinct ERC20 tokenB).
    /// @param fills Fill arguments in execution order
    /// @param deadline Unix timestamp after which the batch reverts (0 = no deadline)
    /// @param permits Permit2 signatures keyed by tokenB (empty = none)
    function fillOrdersPaying(
        FillOrderPayingParams[] calldata fills,
        uint256 deadline,
        TokenPermit2[] calldata permits
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

    /// @notice Modifies an existing order's remaining liquidity
    /// @dev Only callable by the order's maker.
    ///      Reverts if `previousAmounts` does not match on-chain amounts (race protection).
    ///      Callers set desired remaining `availableA` / `availableB`; totals are reset to those
    ///      remainings (filled history is not preserved in `amountA` / `amountB`).
    ///      Does not change `partialFillAllowed` — use `setPartialFillAllowed` for that.
    ///      `ZeroAmount` blocks setting either remaining to 0 — use `cancelOrder` / `cancelOrders`
    ///      to close and reclaim escrow instead.
    ///      `NoChange` when both remainings already match on-chain.
    ///      Token addresses and maker are immutable. Escrow is refunded or topped-up for tokenA.
    /// @param orderId The order ID
    /// @param previousAmounts Expected on-chain amounts from the caller's snapshot
    /// @param updatedOrder Desired remaining amounts
    function modifyOrder(
        uint256 orderId,
        OrderAmounts calldata previousAmounts,
        ModifyOrderParams calldata updatedOrder
    ) external payable;

    /// @notice Modifies remaining liquidity after an EIP-2612 permit for tokenA
    /// @dev Used when topping up escrowed tokenA. `permit.v == 0` skips. Native tokenA with
    ///      `permit.v != 0` reverts `PermitOnNative`.
    /// @param orderId The order ID
    /// @param previousAmounts Expected on-chain amounts from the caller's snapshot
    /// @param updatedOrder Desired remaining amounts
    /// @param permit EIP-2612 signature for tokenA (`v == 0` to skip)
    function modifyOrder(
        uint256 orderId,
        OrderAmounts calldata previousAmounts,
        ModifyOrderParams calldata updatedOrder,
        Permit calldata permit
    ) external payable;

    /// @notice Modifies remaining liquidity pulling tokenA top-up via Permit2 SignatureTransfer
    /// @dev Empty `permit.signature` skips. Native tokenA with a non-empty signature reverts
    ///      `PermitOnNative`. Used when topping up escrowed tokenA.
    /// @param orderId The order ID
    /// @param previousAmounts Expected on-chain amounts from the caller's snapshot
    /// @param updatedOrder Desired remaining amounts
    /// @param permit Permit2 signature for tokenA (empty signature to skip)
    function modifyOrder(
        uint256 orderId,
        OrderAmounts calldata previousAmounts,
        ModifyOrderParams calldata updatedOrder,
        Permit2Permit calldata permit
    ) external payable;

    /// @notice Modifies multiple orders' remaining liquidity in one call
    /// @dev Only the maker may modify each order. Duplicate `orderId`s revert.
    ///      Per unique tokenA (and ETH), top-ups are netted against refunds so only the net delta
    ///      is pulled or sent. `msg.value` must equal the net ETH top-up (0 when flat or net refund).
    /// @param mods Modify arguments in execution order
    function modifyOrders(
        ModifyOrdersParams[] calldata mods
    ) external payable;

    /// @notice Modifies multiple orders after applying EIP-2612 permits
    /// @dev Permits are applied before netted tokenA top-ups. One permit per distinct ERC20.
    /// @param mods Modify arguments in execution order
    /// @param permits EIP-2612 signatures keyed by tokenA (empty = none)
    function modifyOrders(
        ModifyOrdersParams[] calldata mods,
        TokenPermit[] calldata permits
    ) external payable;

    /// @notice Modifies multiple orders pulling net tokenA top-ups via Permit2 SignatureTransfer
    /// @dev One Permit2 entry per distinct ERC20 tokenA. Signed `amount` must cover the net top-up
    ///      for that token after refund netting. Empty array = none.
    /// @param mods Modify arguments in execution order
    /// @param permits Permit2 signatures keyed by tokenA (empty = none)
    function modifyOrders(
        ModifyOrdersParams[] calldata mods,
        TokenPermit2[] calldata permits
    ) external payable;

    /// @notice Sets whether an active order may be filled in multiple parts
    /// @dev Only callable by the order's maker. Does not change amounts or escrow.
    ///      Reverts with `NoChange` when the flag already equals `partialFillAllowed`.
    /// @param orderId The order ID
    /// @param partialFillAllowed Whether the order may be filled in multiple parts
    function setPartialFillAllowed(
        uint256 orderId,
        bool partialFillAllowed
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
