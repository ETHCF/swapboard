// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec

import {ISwapboard} from "../src/interfaces/ISwapboard.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockPermit2} from "./mocks/MockPermit2.sol";
import {OutboundFotToken} from "./mocks/OutboundFotToken.sol";
import {OrderTestLib} from "./helpers/OrderTestLib.sol";
import {SwapboardTwoPartyTest} from "./helpers/SwapboardTwoPartyTest.sol";

/// @notice Permit2 SignatureTransfer overloads for create / fill / modify
contract SwapboardPermit2Test is SwapboardTwoPartyTest {
    address private constant _PERMIT2_ADDR = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    MockPermit2 internal _permit2;
    uint256 private _makerNonce;
    uint256 private _takerNonce;

    /// @notice Deploys board, etches MockPermit2 at the canonical address, funds actors
    function setUp() public {
        _setUpActors();

        MockPermit2 impl = new MockPermit2();
        vm.etch(_PERMIT2_ADDR, address(impl).code);
        _permit2 = MockPermit2(_PERMIT2_ADDR);

        _tokenA = new MockERC20("Token A", "TKA", 18);
        _tokenB = new MockERC20("Token B", "TKB", 6);
        _tokenC = new MockERC20("Token C", "TKC", 18);

        _mintStandardBalances();

        vm.prank(_maker);
        _tokenA.approve(_PERMIT2_ADDR, type(uint256).max);
        vm.prank(_maker);
        _tokenC.approve(_PERMIT2_ADDR, type(uint256).max);
        vm.prank(_taker);
        _tokenB.approve(_PERMIT2_ADDR, type(uint256).max);
        vm.prank(_taker);
        _tokenC.approve(_PERMIT2_ADDR, type(uint256).max);
    }

    /// @notice createOrder pulls tokenA via Permit2 without approving Swapboard
    function test_createOrder_permit2_noApprove() public {
        ISwapboard.Permit2Permit memory permit = _signPermit2(_tokenA, _maker, _MAKER_PK, _AMOUNT_A);

        vm.prank(_maker);
        uint256 orderId = _board.createOrder(_plainOrder(), permit);

        assertTrue(_board.getOrder(orderId).active);
        assertEq(_tokenA.balanceOf(address(_board)), _AMOUNT_A);
        assertEq(_tokenA.allowance(_maker, address(_board)), 0);
    }

    /// @notice Empty signature skips Permit2 and uses classic Swapboard allowance
    function test_createOrder_permit2_emptySig_skips() public {
        vm.prank(_maker);
        _tokenA.approve(address(_board), _AMOUNT_A);

        vm.prank(_maker);
        uint256 orderId = _board.createOrder(_plainOrder(), _skipPermit2());

        assertTrue(_board.getOrder(orderId).active);
        assertEq(_tokenA.balanceOf(address(_board)), _AMOUNT_A);
    }

    /// @notice Empty signature with no Swapboard allowance reverts on the pull
    function test_createOrder_permit2_emptySig_needsAllowance() public {
        vm.prank(_maker);
        vm.expectRevert();
        _board.createOrder(_plainOrder(), _skipPermit2());
    }

    /// @notice Native tokenA with a non-empty Permit2 signature reverts
    function test_createOrder_permit2_native_revert() public {
        ISwapboard.Permit2Permit memory permit = _signPermit2(_tokenA, _maker, _MAKER_PK, _AMOUNT_A);

        vm.prank(_maker);
        vm.expectRevert(ISwapboard.PermitOnNative.selector);
        _board.createOrder{value: _AMOUNT_A}(_ethOffered(), permit);
    }

    /// @notice Empty signature allows native tokenA create
    function test_createOrder_permit2_emptySig_native() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: _AMOUNT_A}(_ethOffered(), _skipPermit2());

        assertTrue(_board.getOrder(orderId).active);
        assertEq(address(_board).balance, _AMOUNT_A);
    }

    /// @notice createOrders pulls aggregated tokenA with one Permit2 signature
    function test_createOrders_permit2_noApprove() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _plainOrder();
        orders[1] = _plainOrder();
        ISwapboard.TokenPermit2[] memory permits =
            _single(_tokenPermit2(_tokenA, _maker, _MAKER_PK, uint256(_AMOUNT_A) * 2));

        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders(orders, permits);

        assertEq(ids.length, 2);
        assertEq(_tokenA.balanceOf(address(_board)), uint256(_AMOUNT_A) * 2);
    }

    /// @notice createOrders with two distinct tokenA uses one Permit2 per token
    function test_createOrders_permit2_twoTokens() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _plainOrder();
        orders[1] = OrderTestLib.order(address(_tokenC), _AMOUNT_A, address(_tokenB), _AMOUNT_B);

        ISwapboard.TokenPermit2[] memory permits = new ISwapboard.TokenPermit2[](2);
        permits[0] = _tokenPermit2(_tokenA, _maker, _MAKER_PK, _AMOUNT_A);
        permits[1] = _tokenPermit2(_tokenC, _maker, _MAKER_PK, _AMOUNT_A);

        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders(orders, permits);

        assertEq(ids.length, 2);
        assertEq(_tokenA.balanceOf(address(_board)), _AMOUNT_A);
        assertEq(_tokenC.balanceOf(address(_board)), _AMOUNT_A);
    }

    /// @notice Empty Permit2 array uses classic allowance
    function test_createOrders_permit2_emptyArray_usesAllowance() public {
        vm.prank(_maker);
        _tokenA.approve(address(_board), _AMOUNT_A);

        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders(_single(_plainOrder()), _noPermit2());

        assertEq(ids.length, 1);
        assertEq(_tokenA.balanceOf(address(_board)), _AMOUNT_A);
    }

    /// @notice Duplicate token in a Permit2 batch reverts
    function test_createOrders_permit2_revert_duplicateToken() public {
        ISwapboard.TokenPermit2[] memory permits = new ISwapboard.TokenPermit2[](2);
        permits[0] = _tokenPermit2(_tokenA, _maker, _MAKER_PK, _AMOUNT_A);
        permits[1] = permits[0];

        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.DuplicatePermitToken.selector, address(_tokenA)));
        _board.createOrders(_single(_plainOrder()), permits);
    }

    /// @notice Empty signature in a Permit2 batch reverts InvalidPermit2
    function test_createOrders_permit2_revert_invalidPermit2() public {
        ISwapboard.TokenPermit2 memory invalid = _dummyTokenPermit2(address(_tokenA));
        invalid.signature = "";

        vm.prank(_maker);
        vm.expectRevert(ISwapboard.InvalidPermit2.selector);
        _board.createOrders(_single(_plainOrder()), _single(invalid));
    }

    /// @notice Zero token in a Permit2 batch reverts
    function test_createOrders_permit2_revert_zeroAddress() public {
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.ZeroAddress.selector);
        _board.createOrders(_single(_plainOrder()), _single(_dummyTokenPermit2(address(0))));
    }

    /// @notice Native token in a Permit2 batch reverts
    function test_createOrders_permit2_revert_native() public {
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.PermitOnNative.selector);
        _board.createOrders{value: _AMOUNT_A}(_single(_ethOffered()), _single(_dummyTokenPermit2(_eth)));
    }

    /// @notice Unused Permit2 entry (token not deposited) reverts UnusedPermit2
    function test_createOrders_permit2_revert_unusedPermit() public {
        ISwapboard.TokenPermit2[] memory permits = new ISwapboard.TokenPermit2[](1);
        permits[0] = _tokenPermit2(_tokenC, _maker, _MAKER_PK, _AMOUNT_A);

        vm.prank(_maker);
        vm.expectRevert(ISwapboard.UnusedPermit2.selector);
        _board.createOrders(_single(_plainOrder()), permits);
    }

    /// @notice A used create Permit2 plus an unused extra entry reverts UnusedPermit2
    function test_createOrders_permit2_revert_unusedPermit_mixed() public {
        ISwapboard.TokenPermit2[] memory permits = _pair(
            _tokenPermit2(_tokenA, _maker, _MAKER_PK, _AMOUNT_A), _tokenPermit2(_tokenC, _maker, _MAKER_PK, _AMOUNT_A)
        );

        vm.prank(_maker);
        vm.expectRevert(ISwapboard.UnusedPermit2.selector);
        _board.createOrders(_single(_plainOrder()), permits);
    }

    /// @notice More than 256 Permit2 batch entries reverts TooManyPermit2
    function test_createOrders_permit2_revert_tooManyPermit2() public {
        ISwapboard.TokenPermit2[] memory permits = new ISwapboard.TokenPermit2[](257);

        vm.prank(_maker);
        vm.expectRevert(ISwapboard.TooManyPermit2.selector);
        _board.createOrders(_single(_plainOrder()), permits);
    }

    /// @notice fillOrder pulls tokenB to the maker via Permit2
    function test_fillOrder_permit2_noApprove() public {
        uint256 orderId = _createWithAllowance();
        ISwapboard.Permit2Permit memory permit = _signPermit2(_tokenB, _taker, _TAKER_PK, _AMOUNT_B);

        vm.prank(_taker);
        _board.fillOrder(orderId, _AMOUNT_B, _AMOUNT_A, 0, permit);

        _assertFilled();
    }

    /// @notice fillOrder native tokenB with non-empty Permit2 reverts
    function test_fillOrder_permit2_native_revert() public {
        uint256 orderId = _createWantEth();
        ISwapboard.Permit2Permit memory permit = _signPermit2(_tokenB, _taker, _TAKER_PK, _AMOUNT_A);

        vm.prank(_taker);
        vm.expectRevert(ISwapboard.PermitOnNative.selector);
        _board.fillOrder{value: _AMOUNT_A}(orderId, _AMOUNT_A, _AMOUNT_A, 0, permit);
    }

    /// @notice fillOrder empty signature with native tokenB succeeds
    function test_fillOrder_permit2_emptySig_native() public {
        uint256 orderId = _createWantEth();

        vm.prank(_taker);
        _board.fillOrder{value: _AMOUNT_A}(orderId, _AMOUNT_A, _AMOUNT_A, 0, _skipPermit2());

        assertEq(_tokenA.balanceOf(_taker), _AMOUNT_A);
    }

    /// @notice fillOrderPaying pulls tokenB via Permit2
    function test_fillOrderPaying_permit2_noApprove() public {
        uint256 orderId = _createWithAllowance();
        ISwapboard.Permit2Permit memory permit = _signPermit2(_tokenB, _taker, _TAKER_PK, _AMOUNT_B);

        vm.prank(_taker);
        _board.fillOrderPaying(orderId, _AMOUNT_A, _AMOUNT_B, 0, permit);

        _assertFilled();
    }

    /// @notice fillOrders pulls aggregated tokenB via Permit2 to the board then makers
    function test_fillOrders_permit2_noApprove() public {
        uint256 orderId = _createWithAllowance();
        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](1);
        fills[0] = ISwapboard.FillOrderParams({orderId: orderId, amountB: _AMOUNT_B, minAmountA: _AMOUNT_A});
        ISwapboard.TokenPermit2[] memory permits = _single(_tokenPermit2(_tokenB, _taker, _TAKER_PK, _AMOUNT_B));

        vm.prank(_taker);
        _board.fillOrders(fills, 0, permits);

        _assertFilled();
    }

    /// @notice fillOrders empty array uses classic allowance
    function test_fillOrders_permit2_emptyArray_usesAllowance() public {
        uint256 orderId = _createWithAllowance();
        vm.prank(_taker);
        _tokenB.approve(address(_board), _AMOUNT_B);

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](1);
        fills[0] = ISwapboard.FillOrderParams({orderId: orderId, amountB: _AMOUNT_B, minAmountA: _AMOUNT_A});

        vm.prank(_taker);
        _board.fillOrders(fills, 0, _noPermit2());

        _assertFilled();
    }

    /// @notice fillOrders with two tokenB values uses one Permit2 each
    function test_fillOrders_permit2_twoTokens() public {
        uint256 id0 = _createWithAllowance();
        uint256 id1 = _createWantTokenC();

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = ISwapboard.FillOrderParams({orderId: id0, amountB: _AMOUNT_B, minAmountA: _AMOUNT_A});
        fills[1] = ISwapboard.FillOrderParams({orderId: id1, amountB: _AMOUNT_B, minAmountA: _AMOUNT_A});

        ISwapboard.TokenPermit2[] memory permits = new ISwapboard.TokenPermit2[](2);
        permits[0] = _tokenPermit2(_tokenB, _taker, _TAKER_PK, _AMOUNT_B);
        permits[1] = _tokenPermit2(_tokenC, _taker, _TAKER_PK, _AMOUNT_B);

        vm.prank(_taker);
        _board.fillOrders(fills, 0, permits);

        assertEq(_tokenA.balanceOf(_taker), uint256(_AMOUNT_A) * 2);
        assertEq(_tokenB.balanceOf(_maker), _AMOUNT_B);
        assertEq(_tokenC.balanceOf(_maker) - (_AMOUNT_A * 10), _AMOUNT_B);
    }

    /// @notice fillOrdersPaying pulls tokenB via Permit2
    function test_fillOrdersPaying_permit2_noApprove() public {
        uint256 orderId = _createWithAllowance();
        ISwapboard.FillOrderPayingParams[] memory fills = new ISwapboard.FillOrderPayingParams[](1);
        fills[0] = ISwapboard.FillOrderPayingParams({orderId: orderId, amountA: _AMOUNT_A, maxAmountB: _AMOUNT_B});
        ISwapboard.TokenPermit2[] memory permits = _single(_tokenPermit2(_tokenB, _taker, _TAKER_PK, _AMOUNT_B));

        vm.prank(_taker);
        _board.fillOrdersPaying(fills, 0, permits);

        _assertFilled();
    }

    /// @notice modifyOrder tops up tokenA via Permit2
    function test_modifyOrder_permit2_topUp() public {
        uint256 orderId = _createWithAllowance();
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        ISwapboard.Permit2Permit memory permit = _signPermit2(_tokenA, _maker, _MAKER_PK, _AMOUNT_A);

        vm.prank(_maker);
        _board.modifyOrder(
            orderId,
            _amounts(snapshot),
            ISwapboard.ModifyOrderParams({availableA: _AMOUNT_A * 2, availableB: _AMOUNT_B * 2}),
            permit
        );

        assertEq(_board.getOrder(orderId).availableA, _AMOUNT_A * 2);
        assertEq(_tokenA.balanceOf(address(_board)), uint256(_AMOUNT_A) * 2);
    }

    /// @notice modifyOrder native top-up with non-empty Permit2 reverts
    function test_modifyOrder_permit2_native_revert() public {
        vm.deal(_maker, 200 ether);
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: _AMOUNT_A}(_ethOffered(), _skipPermit2());
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        ISwapboard.Permit2Permit memory permit = _signPermit2(_tokenA, _maker, _MAKER_PK, _AMOUNT_A);

        vm.prank(_maker);
        vm.expectRevert(ISwapboard.PermitOnNative.selector);
        _board.modifyOrder{value: _AMOUNT_A}(
            orderId,
            _amounts(snapshot),
            ISwapboard.ModifyOrderParams({availableA: _AMOUNT_A * 2, availableB: _AMOUNT_B * 2}),
            permit
        );
    }

    /// @notice modifyOrders tops up via Permit2
    function test_modifyOrders_permit2_topUp() public {
        uint256 orderId = _createWithAllowance();
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](1);
        mods[0] = ISwapboard.ModifyOrdersParams({
            orderId: orderId,
            previousAmounts: _amounts(snapshot),
            updatedOrder: ISwapboard.ModifyOrderParams({availableA: _AMOUNT_A * 2, availableB: _AMOUNT_B * 2})
        });
        ISwapboard.TokenPermit2[] memory permits = _single(_tokenPermit2(_tokenA, _maker, _MAKER_PK, _AMOUNT_A));

        vm.prank(_maker);
        _board.modifyOrders(mods, permits);

        assertEq(_board.getOrder(orderId).availableA, _AMOUNT_A * 2);
        assertEq(_tokenA.balanceOf(address(_board)), uint256(_AMOUNT_A) * 2);
    }

    /// @notice Replay of a Permit2 nonce reverts
    function test_createOrder_permit2_revert_replay() public {
        ISwapboard.Permit2Permit memory permit = _signPermit2(_tokenA, _maker, _MAKER_PK, _AMOUNT_A);

        vm.prank(_maker);
        _board.createOrder(_plainOrder(), permit);

        vm.prank(_maker);
        vm.expectRevert(MockPermit2.InvalidNonce.selector);
        _board.createOrder(_plainOrder(), permit);
    }

    /// @notice Expired Permit2 signature reverts
    function test_createOrder_permit2_revert_expired() public {
        ISwapboard.Permit2Permit memory permit =
            _signPermit2(_tokenA, _maker, _MAKER_PK, _AMOUNT_A, _nextMakerNonce(), block.timestamp - 1);

        vm.prank(_maker);
        vm.expectRevert(MockPermit2.SignatureExpired.selector);
        _board.createOrder(_plainOrder(), permit);
    }

    /// @notice Wrong Permit2 signer reverts
    function test_createOrder_permit2_revert_invalidSigner() public {
        uint256 otherPk = uint256(keccak256("other"));
        ISwapboard.Permit2Permit memory permit = _signPermit2(_tokenA, _maker, otherPk, _AMOUNT_A);

        vm.prank(_maker);
        vm.expectRevert(MockPermit2.InvalidSigner.selector);
        _board.createOrder(_plainOrder(), permit);
    }

    /// @notice Signed Permit2 amount below the pull reverts
    function test_createOrder_permit2_revert_amountTooLow() public {
        ISwapboard.Permit2Permit memory permit = _signPermit2(_tokenA, _maker, _MAKER_PK, _AMOUNT_A - 1);

        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(MockPermit2.InvalidAmount.selector, _AMOUNT_A - 1));
        _board.createOrder(_plainOrder(), permit);
    }

    /// @notice fillOrder empty signature uses classic Swapboard allowance
    function test_fillOrder_permit2_emptySig_skips() public {
        uint256 orderId = _createWithAllowance();
        vm.prank(_taker);
        _tokenB.approve(address(_board), _AMOUNT_B);

        vm.prank(_taker);
        _board.fillOrder(orderId, _AMOUNT_B, _AMOUNT_A, 0, _skipPermit2());

        _assertFilled();
    }

    /// @notice fillOrderPaying native tokenB with non-empty Permit2 reverts
    function test_fillOrderPaying_permit2_native_revert() public {
        uint256 orderId = _createWantEth();
        ISwapboard.Permit2Permit memory permit = _signPermit2(_tokenB, _taker, _TAKER_PK, _AMOUNT_A);

        vm.prank(_taker);
        vm.expectRevert(ISwapboard.PermitOnNative.selector);
        _board.fillOrderPaying{value: _AMOUNT_A}(orderId, _AMOUNT_A, _AMOUNT_A, 0, permit);
    }

    /// @notice fillOrderPaying empty signature with native tokenB succeeds
    function test_fillOrderPaying_permit2_emptySig_native() public {
        uint256 orderId = _createWantEth();

        vm.prank(_taker);
        _board.fillOrderPaying{value: _AMOUNT_A}(orderId, _AMOUNT_A, _AMOUNT_A, 0, _skipPermit2());

        assertEq(_tokenA.balanceOf(_taker), _AMOUNT_A);
    }

    /// @notice fillOrderPaying empty signature uses classic allowance
    function test_fillOrderPaying_permit2_emptySig_skips() public {
        uint256 orderId = _createWithAllowance();
        vm.prank(_taker);
        _tokenB.approve(address(_board), _AMOUNT_B);

        vm.prank(_taker);
        _board.fillOrderPaying(orderId, _AMOUNT_A, _AMOUNT_B, 0, _skipPermit2());

        _assertFilled();
    }

    /// @notice Maker cannot self-fill via Permit2
    function test_fillOrder_permit2_selfFill_revert() public {
        uint256 orderId = _createWithAllowance();
        _tokenB.mint(_maker, _AMOUNT_B);
        vm.prank(_maker);
        _tokenB.approve(_PERMIT2_ADDR, type(uint256).max);

        ISwapboard.Permit2Permit memory permit = _signPermit2(_tokenB, _maker, _MAKER_PK, _AMOUNT_B);

        vm.prank(_maker);
        vm.expectRevert(ISwapboard.SelfFill.selector);
        _board.fillOrder(orderId, _AMOUNT_B, _AMOUNT_A, 0, permit);

        assertTrue(_board.canFill(orderId));
        assertEq(_tokenA.balanceOf(address(_board)), _AMOUNT_A);
    }

    /// @notice Maker self-fill via Permit2 with outbound-only FOT tokenB reverts SelfFill before pull
    function test_fillOrder_permit2_selfFill_outboundFot_revert_selfFill() public {
        OutboundFotToken fotB = new OutboundFotToken();
        vm.prank(_maker);
        _tokenA.approve(address(_board), _AMOUNT_A);
        vm.prank(_maker);
        uint256 orderId = _board.createOrder(OrderTestLib.order(address(_tokenA), _AMOUNT_A, address(fotB), _AMOUNT_B));

        fotB.mint(_maker, _AMOUNT_B);
        vm.prank(_maker);
        fotB.approve(_PERMIT2_ADDR, type(uint256).max);

        ISwapboard.Permit2Permit memory permit = _signPermit2(fotB, _maker, _MAKER_PK, _AMOUNT_B);

        vm.prank(_maker);
        vm.expectRevert(ISwapboard.SelfFill.selector);
        _board.fillOrder(orderId, _AMOUNT_B, _AMOUNT_A, 0, permit);

        assertTrue(_board.canFill(orderId));
        assertEq(fotB.balanceOf(_maker), _AMOUNT_B);
        assertEq(fotB.balanceOf(address(_board)), 0);
    }

    /// @notice fillOrders same tokenB to two makers pulls once to the board then distributes
    function test_fillOrders_permit2_twoMakers_sameTokenB() public {
        address maker2 = vm.addr(0xC0FFEE);
        _tokenA.mint(maker2, _AMOUNT_A);
        vm.prank(maker2);
        _tokenA.approve(address(_board), _AMOUNT_A);
        vm.prank(maker2);
        uint256 id1 = _board.createOrder(_plainOrder());

        uint256 id0 = _createWithAllowance();

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = ISwapboard.FillOrderParams({orderId: id0, amountB: _AMOUNT_B, minAmountA: _AMOUNT_A});
        fills[1] = ISwapboard.FillOrderParams({orderId: id1, amountB: _AMOUNT_B, minAmountA: _AMOUNT_A});

        uint256 maker0Before = _tokenB.balanceOf(_maker);
        uint256 maker2Before = _tokenB.balanceOf(maker2);
        ISwapboard.TokenPermit2[] memory permits =
            _single(_tokenPermit2(_tokenB, _taker, _TAKER_PK, uint256(_AMOUNT_B) * 2));

        vm.prank(_taker);
        _board.fillOrders(fills, 0, permits);

        assertEq(_tokenA.balanceOf(_taker), uint256(_AMOUNT_A) * 2);
        assertEq(_tokenB.balanceOf(_maker), maker0Before + _AMOUNT_B);
        assertEq(_tokenB.balanceOf(maker2), maker2Before + _AMOUNT_B);
        assertEq(_tokenB.balanceOf(address(_board)), 0);
    }

    /// @notice Multi-maker Permit2 tokenB with outbound-only FOT reverts BalanceMismatch on distribute
    function test_fillOrders_permit2_twoMakers_outboundFot_revert_balanceMismatch() public {
        OutboundFotToken fotB = new OutboundFotToken();
        address maker2 = vm.addr(0xC0FFEE);
        _tokenA.mint(maker2, _AMOUNT_A);
        fotB.mint(_taker, uint256(_AMOUNT_B) * 2);

        vm.prank(_maker);
        _tokenA.approve(address(_board), _AMOUNT_A);
        vm.prank(_maker);
        uint256 id0 = _board.createOrder(OrderTestLib.order(address(_tokenA), _AMOUNT_A, address(fotB), _AMOUNT_B));

        vm.prank(maker2);
        _tokenA.approve(address(_board), _AMOUNT_A);
        vm.prank(maker2);
        uint256 id1 = _board.createOrder(OrderTestLib.order(address(_tokenA), _AMOUNT_A, address(fotB), _AMOUNT_B));

        vm.prank(_taker);
        fotB.approve(_PERMIT2_ADDR, type(uint256).max);

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = ISwapboard.FillOrderParams({orderId: id0, amountB: _AMOUNT_B, minAmountA: _AMOUNT_A});
        fills[1] = ISwapboard.FillOrderParams({orderId: id1, amountB: _AMOUNT_B, minAmountA: _AMOUNT_A});
        ISwapboard.TokenPermit2[] memory permits =
            _single(_tokenPermit2(fotB, _taker, _TAKER_PK, uint256(_AMOUNT_B) * 2));

        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.BalanceMismatch.selector, _AMOUNT_B, _fotNet(_AMOUNT_B)));
        _board.fillOrders(fills, 0, permits);

        assertTrue(_board.canFill(id0));
        assertTrue(_board.canFill(id1));
        assertEq(fotB.balanceOf(address(_board)), 0);
    }

    /// @notice fillOrders mixes Permit2 for one tokenB with classic allowance for another
    function test_fillOrders_permit2_mixedClassic() public {
        uint256 id0 = _createWithAllowance();
        uint256 id1 = _createWantTokenC();

        vm.prank(_taker);
        _tokenC.approve(address(_board), _AMOUNT_B);

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = ISwapboard.FillOrderParams({orderId: id0, amountB: _AMOUNT_B, minAmountA: _AMOUNT_A});
        fills[1] = ISwapboard.FillOrderParams({orderId: id1, amountB: _AMOUNT_B, minAmountA: _AMOUNT_A});
        ISwapboard.TokenPermit2[] memory permits = _single(_tokenPermit2(_tokenB, _taker, _TAKER_PK, _AMOUNT_B));

        vm.prank(_taker);
        _board.fillOrders(fills, 0, permits);

        assertEq(_tokenA.balanceOf(_taker), uint256(_AMOUNT_A) * 2);
        assertEq(_tokenB.balanceOf(_maker), _AMOUNT_B);
        assertEq(_tokenC.balanceOf(_maker) - (_AMOUNT_A * 10), _AMOUNT_B);
    }

    /// @notice Unused Permit2 entry on fillOrders reverts UnusedPermit2
    function test_fillOrders_permit2_revert_unusedPermit() public {
        uint256 orderId = _createWithAllowance();
        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](1);
        fills[0] = ISwapboard.FillOrderParams({orderId: orderId, amountB: _AMOUNT_B, minAmountA: _AMOUNT_A});

        // Classic pull for tokenB succeeds; unused tokenC Permit2 must still revert.
        vm.prank(_taker);
        _tokenB.approve(address(_board), _AMOUNT_B);
        ISwapboard.TokenPermit2[] memory permits = _single(_tokenPermit2(_tokenC, _taker, _TAKER_PK, _AMOUNT_B));

        vm.prank(_taker);
        vm.expectRevert(ISwapboard.UnusedPermit2.selector);
        _board.fillOrders(fills, 0, permits);
    }

    /// @notice A used fill Permit2 plus an unused extra entry reverts UnusedPermit2
    function test_fillOrders_permit2_revert_unusedPermit_mixed() public {
        uint256 orderId = _createWithAllowance();
        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](1);
        fills[0] = ISwapboard.FillOrderParams({orderId: orderId, amountB: _AMOUNT_B, minAmountA: _AMOUNT_A});

        ISwapboard.TokenPermit2[] memory permits = _pair(
            _tokenPermit2(_tokenB, _taker, _TAKER_PK, _AMOUNT_B), _tokenPermit2(_tokenC, _taker, _TAKER_PK, _AMOUNT_B)
        );

        vm.prank(_taker);
        vm.expectRevert(ISwapboard.UnusedPermit2.selector);
        _board.fillOrders(fills, 0, permits);
    }

    /// @notice Duplicate token in a fillOrders Permit2 batch reverts
    function test_fillOrders_permit2_revert_duplicateToken() public {
        uint256 orderId = _createWithAllowance();
        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](1);
        fills[0] = ISwapboard.FillOrderParams({orderId: orderId, amountB: _AMOUNT_B, minAmountA: _AMOUNT_A});

        ISwapboard.TokenPermit2[] memory permits = new ISwapboard.TokenPermit2[](2);
        permits[0] = _dummyTokenPermit2(address(_tokenB));
        permits[1] = permits[0];

        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.DuplicatePermitToken.selector, address(_tokenB)));
        _board.fillOrders(fills, 0, permits);
    }

    /// @notice Empty signature in a fillOrders Permit2 batch reverts
    function test_fillOrders_permit2_revert_invalidPermit2() public {
        uint256 orderId = _createWithAllowance();
        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](1);
        fills[0] = ISwapboard.FillOrderParams({orderId: orderId, amountB: _AMOUNT_B, minAmountA: _AMOUNT_A});

        ISwapboard.TokenPermit2 memory invalid = _dummyTokenPermit2(address(_tokenB));
        invalid.signature = "";

        vm.prank(_taker);
        vm.expectRevert(ISwapboard.InvalidPermit2.selector);
        _board.fillOrders(fills, 0, _single(invalid));
    }

    /// @notice Zero token in a fillOrders Permit2 batch reverts
    function test_fillOrders_permit2_revert_zeroAddress() public {
        uint256 orderId = _createWithAllowance();
        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](1);
        fills[0] = ISwapboard.FillOrderParams({orderId: orderId, amountB: _AMOUNT_B, minAmountA: _AMOUNT_A});

        vm.prank(_taker);
        vm.expectRevert(ISwapboard.ZeroAddress.selector);
        _board.fillOrders(fills, 0, _single(_dummyTokenPermit2(address(0))));
    }

    /// @notice Native token in a fillOrders Permit2 batch reverts
    function test_fillOrders_permit2_revert_native() public {
        uint256 orderId = _createWithAllowance();
        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](1);
        fills[0] = ISwapboard.FillOrderParams({orderId: orderId, amountB: _AMOUNT_B, minAmountA: _AMOUNT_A});

        vm.prank(_taker);
        vm.expectRevert(ISwapboard.PermitOnNative.selector);
        _board.fillOrders(fills, 0, _single(_dummyTokenPermit2(_eth)));
    }

    /// @notice fillOrdersPaying empty array uses classic allowance
    function test_fillOrdersPaying_permit2_emptyArray_usesAllowance() public {
        uint256 orderId = _createWithAllowance();
        vm.prank(_taker);
        _tokenB.approve(address(_board), _AMOUNT_B);

        ISwapboard.FillOrderPayingParams[] memory fills = new ISwapboard.FillOrderPayingParams[](1);
        fills[0] = ISwapboard.FillOrderPayingParams({orderId: orderId, amountA: _AMOUNT_A, maxAmountB: _AMOUNT_B});

        vm.prank(_taker);
        _board.fillOrdersPaying(fills, 0, _noPermit2());

        _assertFilled();
    }

    /// @notice fillOrdersPaying with two tokenB values uses one Permit2 each
    function test_fillOrdersPaying_permit2_twoTokens() public {
        uint256 id0 = _createWithAllowance();
        uint256 id1 = _createWantTokenC();

        ISwapboard.FillOrderPayingParams[] memory fills = new ISwapboard.FillOrderPayingParams[](2);
        fills[0] = ISwapboard.FillOrderPayingParams({orderId: id0, amountA: _AMOUNT_A, maxAmountB: _AMOUNT_B});
        fills[1] = ISwapboard.FillOrderPayingParams({orderId: id1, amountA: _AMOUNT_A, maxAmountB: _AMOUNT_B});

        ISwapboard.TokenPermit2[] memory permits = new ISwapboard.TokenPermit2[](2);
        permits[0] = _tokenPermit2(_tokenB, _taker, _TAKER_PK, _AMOUNT_B);
        permits[1] = _tokenPermit2(_tokenC, _taker, _TAKER_PK, _AMOUNT_B);

        vm.prank(_taker);
        _board.fillOrdersPaying(fills, 0, permits);

        assertEq(_tokenA.balanceOf(_taker), uint256(_AMOUNT_A) * 2);
        assertEq(_tokenB.balanceOf(_maker), _AMOUNT_B);
        assertEq(_tokenC.balanceOf(_maker) - (_AMOUNT_A * 10), _AMOUNT_B);
    }

    /// @notice Unused Permit2 entry on fillOrdersPaying reverts
    function test_fillOrdersPaying_permit2_revert_unusedPermit() public {
        uint256 orderId = _createWithAllowance();
        ISwapboard.FillOrderPayingParams[] memory fills = new ISwapboard.FillOrderPayingParams[](1);
        fills[0] = ISwapboard.FillOrderPayingParams({orderId: orderId, amountA: _AMOUNT_A, maxAmountB: _AMOUNT_B});

        vm.prank(_taker);
        _tokenB.approve(address(_board), _AMOUNT_B);
        ISwapboard.TokenPermit2[] memory permits = _single(_tokenPermit2(_tokenC, _taker, _TAKER_PK, _AMOUNT_B));

        vm.prank(_taker);
        vm.expectRevert(ISwapboard.UnusedPermit2.selector);
        _board.fillOrdersPaying(fills, 0, permits);
    }

    /// @notice A used fillPaying Permit2 plus an unused extra entry reverts UnusedPermit2
    function test_fillOrdersPaying_permit2_revert_unusedPermit_mixed() public {
        uint256 orderId = _createWithAllowance();
        ISwapboard.FillOrderPayingParams[] memory fills = new ISwapboard.FillOrderPayingParams[](1);
        fills[0] = ISwapboard.FillOrderPayingParams({orderId: orderId, amountA: _AMOUNT_A, maxAmountB: _AMOUNT_B});

        ISwapboard.TokenPermit2[] memory permits = _pair(
            _tokenPermit2(_tokenB, _taker, _TAKER_PK, _AMOUNT_B), _tokenPermit2(_tokenC, _taker, _TAKER_PK, _AMOUNT_B)
        );

        vm.prank(_taker);
        vm.expectRevert(ISwapboard.UnusedPermit2.selector);
        _board.fillOrdersPaying(fills, 0, permits);
    }

    /// @notice modifyOrder empty signature tops up via classic allowance
    function test_modifyOrder_permit2_emptySig_topUp() public {
        uint256 orderId = _createWithAllowance();
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        vm.prank(_maker);
        _tokenA.approve(address(_board), _AMOUNT_A);

        vm.prank(_maker);
        _board.modifyOrder(
            orderId,
            _amounts(snapshot),
            ISwapboard.ModifyOrderParams({availableA: _AMOUNT_A * 2, availableB: _AMOUNT_B * 2}),
            _skipPermit2()
        );

        assertEq(_board.getOrder(orderId).availableA, _AMOUNT_A * 2);
        assertEq(_tokenA.balanceOf(address(_board)), uint256(_AMOUNT_A) * 2);
    }

    /// @notice modifyOrder empty signature allows native tokenA top-up
    function test_modifyOrder_permit2_emptySig_native() public {
        vm.deal(_maker, 200 ether);
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: _AMOUNT_A}(_ethOffered(), _skipPermit2());
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        vm.prank(_maker);
        _board.modifyOrder{value: _AMOUNT_A}(
            orderId,
            _amounts(snapshot),
            ISwapboard.ModifyOrderParams({availableA: _AMOUNT_A * 2, availableB: _AMOUNT_B * 2}),
            _skipPermit2()
        );

        assertEq(_board.getOrder(orderId).availableA, _AMOUNT_A * 2);
        assertEq(address(_board).balance, uint256(_AMOUNT_A) * 2);
    }

    /// @notice modifyOrder refund-only with empty Permit2 returns tokenA
    function test_modifyOrder_permit2_refundOnly() public {
        uint256 orderId = _createWithAllowance();
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        uint256 makerBefore = _tokenA.balanceOf(_maker);

        vm.prank(_maker);
        _board.modifyOrder(
            orderId,
            _amounts(snapshot),
            ISwapboard.ModifyOrderParams({availableA: _AMOUNT_A / 2, availableB: _AMOUNT_B / 2}),
            _skipPermit2()
        );

        assertEq(_board.getOrder(orderId).availableA, _AMOUNT_A / 2);
        assertEq(_tokenA.balanceOf(_maker), makerBefore + _AMOUNT_A / 2);
        assertEq(_tokenA.balanceOf(address(_board)), _AMOUNT_A / 2);
    }

    /// @notice modifyOrder refund-only with a non-empty Permit2 signature reverts UnusedPermit2
    function test_modifyOrder_permit2_refundOnly_revert_unusedPermit() public {
        uint256 orderId = _createWithAllowance();
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        ISwapboard.Permit2Permit memory permit = _signPermit2(_tokenA, _maker, _MAKER_PK, _AMOUNT_A);

        vm.prank(_maker);
        vm.expectRevert(ISwapboard.UnusedPermit2.selector);
        _board.modifyOrder(
            orderId,
            _amounts(snapshot),
            ISwapboard.ModifyOrderParams({availableA: _AMOUNT_A / 2, availableB: _AMOUNT_B / 2}),
            permit
        );
    }

    /// @notice modifyOrder native refund-only with empty Permit2 returns ETH
    function test_modifyOrder_permit2_refundOnly_native() public {
        vm.deal(_maker, 200 ether);
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: _AMOUNT_A}(_ethOffered(), _skipPermit2());
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        uint256 makerBefore = _maker.balance;

        vm.prank(_maker);
        _board.modifyOrder(
            orderId,
            _amounts(snapshot),
            ISwapboard.ModifyOrderParams({availableA: _AMOUNT_A / 2, availableB: _AMOUNT_B / 2}),
            _skipPermit2()
        );

        assertEq(_board.getOrder(orderId).availableA, _AMOUNT_A / 2);
        assertEq(_maker.balance, makerBefore + _AMOUNT_A / 2);
        assertEq(address(_board).balance, _AMOUNT_A / 2);
    }

    /// @notice Empty Permit2 array still modifies when allowance is already set
    function test_modifyOrders_permit2_emptyArray_usesAllowance() public {
        vm.prank(_maker);
        _tokenA.approve(address(_board), _AMOUNT_A * 2);
        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders(_single(_plainOrder()), _noPermit2());
        ISwapboard.Order memory snapshot = _board.getOrder(ids[0]);

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](1);
        mods[0] = ISwapboard.ModifyOrdersParams({
            orderId: ids[0],
            previousAmounts: _amounts(snapshot),
            updatedOrder: ISwapboard.ModifyOrderParams({availableA: _AMOUNT_A * 2, availableB: _AMOUNT_B * 2})
        });

        vm.prank(_maker);
        _board.modifyOrders(mods, _noPermit2());

        assertEq(_board.getOrder(ids[0]).availableA, _AMOUNT_A * 2);
        assertEq(_tokenA.balanceOf(address(_board)), uint256(_AMOUNT_A) * 2);
    }

    /// @notice modifyOrders tops up two distinct tokenA via Permit2
    function test_modifyOrders_permit2_twoTokens() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _plainOrder();
        orders[1] = OrderTestLib.order(address(_tokenC), _AMOUNT_A, address(_tokenB), _AMOUNT_B);
        ISwapboard.TokenPermit2[] memory createPermits = new ISwapboard.TokenPermit2[](2);
        createPermits[0] = _tokenPermit2(_tokenA, _maker, _MAKER_PK, _AMOUNT_A);
        createPermits[1] = _tokenPermit2(_tokenC, _maker, _MAKER_PK, _AMOUNT_A);
        // Sign modify permits before any board call so `_makerNonce` is not written after an external call.
        ISwapboard.TokenPermit2[] memory permits = new ISwapboard.TokenPermit2[](2);
        permits[0] = _tokenPermit2(_tokenA, _maker, _MAKER_PK, _AMOUNT_A);
        permits[1] = _tokenPermit2(_tokenC, _maker, _MAKER_PK, _AMOUNT_A);

        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders(orders, createPermits);

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = ISwapboard.ModifyOrdersParams({
            orderId: ids[0],
            previousAmounts: _amounts(_board.getOrder(ids[0])),
            updatedOrder: ISwapboard.ModifyOrderParams({availableA: _AMOUNT_A * 2, availableB: _AMOUNT_B * 2})
        });
        mods[1] = ISwapboard.ModifyOrdersParams({
            orderId: ids[1],
            previousAmounts: _amounts(_board.getOrder(ids[1])),
            updatedOrder: ISwapboard.ModifyOrderParams({availableA: _AMOUNT_A * 2, availableB: _AMOUNT_B * 2})
        });

        vm.prank(_maker);
        _board.modifyOrders(mods, permits);

        assertEq(_board.getOrder(ids[0]).availableA, _AMOUNT_A * 2);
        assertEq(_board.getOrder(ids[1]).availableA, _AMOUNT_A * 2);
        assertEq(_tokenA.balanceOf(address(_board)), uint256(_AMOUNT_A) * 2);
        assertEq(_tokenC.balanceOf(address(_board)), uint256(_AMOUNT_A) * 2);
    }

    /// @notice Unused Permit2 entry on modifyOrders reverts
    function test_modifyOrders_permit2_revert_unusedPermit() public {
        uint256 orderId = _createWithAllowance();
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](1);
        mods[0] = ISwapboard.ModifyOrdersParams({
            orderId: orderId,
            previousAmounts: _amounts(snapshot),
            updatedOrder: ISwapboard.ModifyOrderParams({availableA: _AMOUNT_A * 2, availableB: _AMOUNT_B * 2})
        });

        vm.prank(_maker);
        _tokenA.approve(address(_board), _AMOUNT_A);
        ISwapboard.TokenPermit2[] memory permits = _single(_tokenPermit2(_tokenC, _maker, _MAKER_PK, _AMOUNT_A));

        vm.prank(_maker);
        vm.expectRevert(ISwapboard.UnusedPermit2.selector);
        _board.modifyOrders(mods, permits);
    }

    /// @notice Duplicate token in a modifyOrders Permit2 batch reverts
    function test_modifyOrders_permit2_revert_duplicateToken() public {
        uint256 orderId = _createWithAllowance();
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](1);
        mods[0] = ISwapboard.ModifyOrdersParams({
            orderId: orderId,
            previousAmounts: _amounts(snapshot),
            updatedOrder: ISwapboard.ModifyOrderParams({availableA: _AMOUNT_A * 2, availableB: _AMOUNT_B * 2})
        });

        ISwapboard.TokenPermit2[] memory permits = new ISwapboard.TokenPermit2[](2);
        permits[0] = _dummyTokenPermit2(address(_tokenA));
        permits[1] = permits[0];

        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.DuplicatePermitToken.selector, address(_tokenA)));
        _board.modifyOrders(mods, permits);
    }

    /// @notice Empty signature in a modifyOrders Permit2 batch reverts
    function test_modifyOrders_permit2_revert_invalidPermit2() public {
        uint256 orderId = _createWithAllowance();
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](1);
        mods[0] = ISwapboard.ModifyOrdersParams({
            orderId: orderId,
            previousAmounts: _amounts(snapshot),
            updatedOrder: ISwapboard.ModifyOrderParams({availableA: _AMOUNT_A * 2, availableB: _AMOUNT_B * 2})
        });

        ISwapboard.TokenPermit2 memory invalid = _dummyTokenPermit2(address(_tokenA));
        invalid.signature = "";

        vm.prank(_maker);
        vm.expectRevert(ISwapboard.InvalidPermit2.selector);
        _board.modifyOrders(mods, _single(invalid));
    }

    /// @notice Zero token in a modifyOrders Permit2 batch reverts
    function test_modifyOrders_permit2_revert_zeroAddress() public {
        uint256 orderId = _createWithAllowance();
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](1);
        mods[0] = ISwapboard.ModifyOrdersParams({
            orderId: orderId,
            previousAmounts: _amounts(snapshot),
            updatedOrder: ISwapboard.ModifyOrderParams({availableA: _AMOUNT_A * 2, availableB: _AMOUNT_B * 2})
        });

        vm.prank(_maker);
        vm.expectRevert(ISwapboard.ZeroAddress.selector);
        _board.modifyOrders(mods, _single(_dummyTokenPermit2(address(0))));
    }

    /// @notice Native token in a modifyOrders Permit2 batch reverts
    function test_modifyOrders_permit2_revert_native() public {
        uint256 orderId = _createWithAllowance();
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](1);
        mods[0] = ISwapboard.ModifyOrdersParams({
            orderId: orderId,
            previousAmounts: _amounts(snapshot),
            updatedOrder: ISwapboard.ModifyOrderParams({availableA: _AMOUNT_A * 2, availableB: _AMOUNT_B * 2})
        });

        vm.prank(_maker);
        vm.expectRevert(ISwapboard.PermitOnNative.selector);
        _board.modifyOrders(mods, _single(_dummyTokenPermit2(_eth)));
    }

    /// @notice Empty Permit2 array still refunds without a top-up signature
    function test_modifyOrders_permit2_refundOnly_noPermitNeeded() public {
        uint256 orderId = _createWithAllowance();
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        uint256 makerBefore = _tokenA.balanceOf(_maker);

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](1);
        mods[0] = ISwapboard.ModifyOrdersParams({
            orderId: orderId,
            previousAmounts: _amounts(snapshot),
            updatedOrder: ISwapboard.ModifyOrderParams({availableA: _AMOUNT_A / 2, availableB: _AMOUNT_B / 2})
        });

        // Empty array: no Permit2 needed for a refund-only modify
        vm.prank(_maker);
        _board.modifyOrders(mods, _noPermit2());

        assertEq(_board.getOrder(orderId).availableA, _AMOUNT_A / 2);
        assertEq(_tokenA.balanceOf(_maker), makerBefore + _AMOUNT_A / 2);
    }

    /// @notice Refund-only modifyOrders with a Permit2 signature for that tokenA reverts UnusedPermit2
    function test_modifyOrders_permit2_refundOnly_revert_unusedPermit() public {
        uint256 orderId = _createWithAllowance();
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](1);
        mods[0] = ISwapboard.ModifyOrdersParams({
            orderId: orderId,
            previousAmounts: _amounts(snapshot),
            updatedOrder: ISwapboard.ModifyOrderParams({availableA: _AMOUNT_A / 2, availableB: _AMOUNT_B / 2})
        });

        ISwapboard.TokenPermit2[] memory permits = _single(_tokenPermit2(_tokenA, _maker, _MAKER_PK, _AMOUNT_A));
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.UnusedPermit2.selector);
        _board.modifyOrders(mods, permits);
    }

    /// @notice createOrder Permit2 with stray ETH reverts
    function test_createOrder_permit2_revert_strayEth() public {
        ISwapboard.Permit2Permit memory permit = _signPermit2(_tokenA, _maker, _MAKER_PK, _AMOUNT_A);

        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, 0, 1));
        _board.createOrder{value: 1}(_plainOrder(), permit);
    }

    /// @notice createOrders with Permit2 entries but empty orders reverts ZeroAmount
    function test_createOrders_permit2_revert_emptyOrders() public {
        ISwapboard.TokenPermit2[] memory permits = _single(_dummyTokenPermit2(address(_tokenA)));

        vm.prank(_maker);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.createOrders(new ISwapboard.CreateOrderParams[](0), permits);
    }

    /// @notice createOrders mixes Permit2 for one tokenA with classic allowance for another
    function test_createOrders_permit2_mixedClassic() public {
        vm.prank(_maker);
        _tokenC.approve(address(_board), _AMOUNT_A);

        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _plainOrder();
        orders[1] = OrderTestLib.order(address(_tokenC), _AMOUNT_A, address(_tokenB), _AMOUNT_B);
        ISwapboard.TokenPermit2[] memory permits = _single(_tokenPermit2(_tokenA, _maker, _MAKER_PK, _AMOUNT_A));

        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders(orders, permits);

        assertEq(ids.length, 2);
        assertEq(_tokenA.balanceOf(address(_board)), _AMOUNT_A);
        assertEq(_tokenC.balanceOf(address(_board)), _AMOUNT_A);
    }

    /// @notice fillOrder native empty Permit2 with wrong msg.value reverts
    function test_fillOrder_permit2_emptySig_native_revert_ethMismatch() public {
        uint256 orderId = _createWantEth();

        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, _AMOUNT_A, 1));
        _board.fillOrder{value: 1}(orderId, _AMOUNT_A, _AMOUNT_A, 0, _skipPermit2());
    }

    /// @notice fillOrder Permit2 with stray ETH on ERC20 tokenB reverts
    function test_fillOrder_permit2_revert_strayEth() public {
        uint256 orderId = _createWithAllowance();
        ISwapboard.Permit2Permit memory permit = _signPermit2(_tokenB, _taker, _TAKER_PK, _AMOUNT_B);

        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, 0, 1));
        _board.fillOrder{value: 1}(orderId, _AMOUNT_B, _AMOUNT_A, 0, permit);
    }

    /// @notice modifyOrder native empty Permit2 with wrong msg.value reverts
    function test_modifyOrder_permit2_emptySig_native_revert_ethMismatch() public {
        vm.deal(_maker, 200 ether);
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: _AMOUNT_A}(_ethOffered(), _skipPermit2());
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, _AMOUNT_A, 1));
        _board.modifyOrder{value: 1}(
            orderId,
            _amounts(snapshot),
            ISwapboard.ModifyOrderParams({availableA: _AMOUNT_A * 2, availableB: _AMOUNT_B * 2}),
            _skipPermit2()
        );
    }

    /// @notice modifyOrder Permit2 top-up with stray ETH reverts
    function test_modifyOrder_permit2_revert_strayEth() public {
        uint256 orderId = _createWithAllowance();
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        ISwapboard.Permit2Permit memory permit = _signPermit2(_tokenA, _maker, _MAKER_PK, _AMOUNT_A);

        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.ETHAmountMismatch.selector, 0, 1));
        _board.modifyOrder{value: 1}(
            orderId,
            _amounts(snapshot),
            ISwapboard.ModifyOrderParams({availableA: _AMOUNT_A * 2, availableB: _AMOUNT_B * 2}),
            permit
        );
    }

    /// @notice modifyOrders with Permit2 entries but empty mods reverts ZeroAmount
    function test_modifyOrders_permit2_revert_emptyMods() public {
        ISwapboard.TokenPermit2[] memory permits = _single(_dummyTokenPermit2(address(_tokenA)));

        vm.prank(_maker);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.modifyOrders(new ISwapboard.ModifyOrdersParams[](0), permits);
    }

    /// @notice modifyOrders Permit2 nets a same-token refund while topping up another token
    function test_modifyOrders_permit2_netRefundWithTopUp() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _plainOrder();
        orders[1] = OrderTestLib.order(address(_tokenC), _AMOUNT_A, address(_tokenB), _AMOUNT_B);
        ISwapboard.TokenPermit2[] memory createPermits = new ISwapboard.TokenPermit2[](2);
        createPermits[0] = _tokenPermit2(_tokenA, _maker, _MAKER_PK, _AMOUNT_A);
        createPermits[1] = _tokenPermit2(_tokenC, _maker, _MAKER_PK, _AMOUNT_A);

        ISwapboard.TokenPermit2[] memory permits = _single(_tokenPermit2(_tokenA, _maker, _MAKER_PK, _AMOUNT_A));

        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders(orders, createPermits);

        // Top up tokenA via Permit2; refund half of tokenC (no Permit2 needed for refund).
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = ISwapboard.ModifyOrdersParams({
            orderId: ids[0],
            previousAmounts: _amounts(_board.getOrder(ids[0])),
            updatedOrder: ISwapboard.ModifyOrderParams({availableA: _AMOUNT_A * 2, availableB: _AMOUNT_B * 2})
        });
        mods[1] = ISwapboard.ModifyOrdersParams({
            orderId: ids[1],
            previousAmounts: _amounts(_board.getOrder(ids[1])),
            updatedOrder: ISwapboard.ModifyOrderParams({availableA: _AMOUNT_A / 2, availableB: _AMOUNT_B / 2})
        });

        uint256 makerCBefore = _tokenC.balanceOf(_maker);

        vm.prank(_maker);
        _board.modifyOrders(mods, permits);

        assertEq(_board.getOrder(ids[0]).availableA, _AMOUNT_A * 2);
        assertEq(_board.getOrder(ids[1]).availableA, _AMOUNT_A / 2);
        assertEq(_tokenA.balanceOf(address(_board)), uint256(_AMOUNT_A) * 2);
        assertEq(_tokenC.balanceOf(address(_board)), _AMOUNT_A / 2);
        assertEq(_tokenC.balanceOf(_maker), makerCBefore + _AMOUNT_A / 2);
    }

    /// @notice Same-token top-up and refund that net to zero make a tokenA Permit2 unused
    function test_modifyOrders_permit2_netZero_revert_unusedPermit() public {
        uint256[] memory ids = _createTwoPlainOrdersWithAllowance();
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = ISwapboard.ModifyOrdersParams({
            orderId: ids[0],
            previousAmounts: _amounts(_board.getOrder(ids[0])),
            updatedOrder: ISwapboard.ModifyOrderParams({
                availableA: _AMOUNT_A + (_AMOUNT_A / 2), availableB: _AMOUNT_B
            })
        });
        mods[1] = ISwapboard.ModifyOrdersParams({
            orderId: ids[1],
            previousAmounts: _amounts(_board.getOrder(ids[1])),
            updatedOrder: ISwapboard.ModifyOrderParams({availableA: _AMOUNT_A / 2, availableB: _AMOUNT_B})
        });

        ISwapboard.TokenPermit2[] memory permits = _single(_tokenPermit2(_tokenA, _maker, _MAKER_PK, _AMOUNT_A));
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.UnusedPermit2.selector);
        _board.modifyOrders(mods, permits);

        assertEq(_board.getOrder(ids[0]).availableA, _AMOUNT_A);
        assertEq(_board.getOrder(ids[1]).availableA, _AMOUNT_A);
    }

    /// @notice Same-token net refund (refund dominates) makes a tokenA Permit2 unused
    function test_modifyOrders_permit2_netRefund_revert_unusedPermit() public {
        uint256[] memory ids = _createTwoPlainOrdersWithAllowance();
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = ISwapboard.ModifyOrdersParams({
            orderId: ids[0],
            previousAmounts: _amounts(_board.getOrder(ids[0])),
            updatedOrder: ISwapboard.ModifyOrderParams({
                availableA: _AMOUNT_A + (_AMOUNT_A / 4), availableB: _AMOUNT_B
            })
        });
        mods[1] = ISwapboard.ModifyOrdersParams({
            orderId: ids[1],
            previousAmounts: _amounts(_board.getOrder(ids[1])),
            updatedOrder: ISwapboard.ModifyOrderParams({availableA: _AMOUNT_A / 2, availableB: _AMOUNT_B})
        });

        ISwapboard.TokenPermit2[] memory permits = _single(_tokenPermit2(_tokenA, _maker, _MAKER_PK, _AMOUNT_A));
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.UnusedPermit2.selector);
        _board.modifyOrders(mods, permits);

        assertEq(_board.getOrder(ids[0]).availableA, _AMOUNT_A);
        assertEq(_board.getOrder(ids[1]).availableA, _AMOUNT_A);
    }

    function _createWithAllowance() private returns (uint256 orderId) {
        return _createApproved(_plainOrder());
    }

    function _createWantEth() private returns (uint256 orderId) {
        return _createApproved(_ethWanted());
    }

    function _createWantTokenC() private returns (uint256 orderId) {
        return _createApproved(_tokenCWanted());
    }

    function _plainOrder() private view returns (ISwapboard.CreateOrderParams memory) {
        return OrderTestLib.order(address(_tokenA), _AMOUNT_A, address(_tokenB), _AMOUNT_B);
    }

    /// @notice Net amount after OutboundFotToken's 5% `transfer` fee
    function _fotNet(
        uint256 gross
    ) private pure returns (uint256) {
        return gross - (gross * 5) / 100;
    }

    function _ethOffered() private view returns (ISwapboard.CreateOrderParams memory) {
        return OrderTestLib.order(_eth, _AMOUNT_A, address(_tokenB), _AMOUNT_B);
    }

    function _single(
        ISwapboard.TokenPermit2 memory permit
    ) private pure returns (ISwapboard.TokenPermit2[] memory permits) {
        permits = new ISwapboard.TokenPermit2[](1);
        permits[0] = permit;
    }

    function _pair(
        ISwapboard.TokenPermit2 memory first,
        ISwapboard.TokenPermit2 memory second
    ) private pure returns (ISwapboard.TokenPermit2[] memory permits) {
        permits = new ISwapboard.TokenPermit2[](2);
        permits[0] = first;
        permits[1] = second;
    }

    /// @notice Creates two plain orders via classic allowance (avoids `_makerNonce` around board calls)
    function _createTwoPlainOrdersWithAllowance() private returns (uint256[] memory) {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _plainOrder();
        orders[1] = _plainOrder();
        vm.prank(_maker);
        _tokenA.approve(address(_board), uint256(_AMOUNT_A) * 2);
        vm.prank(_maker);
        return _board.createOrders(orders, _noPermit2());
    }

    function _noPermit2() private pure returns (ISwapboard.TokenPermit2[] memory) {
        return new ISwapboard.TokenPermit2[](0);
    }

    function _skipPermit2() private pure returns (ISwapboard.Permit2Permit memory) {
        return ISwapboard.Permit2Permit({amount: 0, nonce: 0, deadline: 0, signature: ""});
    }

    function _dummyTokenPermit2(
        address token
    ) private view returns (ISwapboard.TokenPermit2 memory) {
        return ISwapboard.TokenPermit2({
            token: token, amount: 1, nonce: 0, deadline: block.timestamp + 1, signature: hex"01"
        });
    }

    function _nextMakerNonce() private returns (uint256 nonce) {
        nonce = _makerNonce;
        ++_makerNonce;
    }

    function _nextTakerNonce() private returns (uint256 nonce) {
        nonce = _takerNonce;
        ++_takerNonce;
    }

    function _signPermit2(
        MockERC20 token,
        address owner,
        uint256 pk,
        uint256 amount
    ) private returns (ISwapboard.Permit2Permit memory) {
        uint256 nonce = owner == _maker ? _nextMakerNonce() : _nextTakerNonce();
        return _signPermit2(token, owner, pk, amount, nonce, block.timestamp + 1 days);
    }

    function _signPermit2(
        MockERC20 token,
        address,
        uint256 pk,
        uint256 amount,
        uint256 nonce,
        uint256 deadline
    ) private view returns (ISwapboard.Permit2Permit memory permit) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                _permit2.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        _permit2.PERMIT_TRANSFER_FROM_TYPEHASH(),
                        keccak256(abi.encode(_permit2.TOKEN_PERMISSIONS_TYPEHASH(), address(token), amount)),
                        address(_board),
                        nonce,
                        deadline
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        permit = ISwapboard.Permit2Permit({
            amount: amount, nonce: nonce, deadline: deadline, signature: abi.encodePacked(r, s, v)
        });
    }

    function _tokenPermit2(
        MockERC20 token,
        address owner,
        uint256 pk,
        uint256 amount
    ) private returns (ISwapboard.TokenPermit2 memory) {
        ISwapboard.Permit2Permit memory p = _signPermit2(token, owner, pk, amount);
        return ISwapboard.TokenPermit2({
            token: address(token), amount: p.amount, nonce: p.nonce, deadline: p.deadline, signature: p.signature
        });
    }
}

