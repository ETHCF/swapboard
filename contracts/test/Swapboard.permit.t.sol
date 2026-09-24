// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.36;

// solhint-disable use-natspec

import {ISwapboard} from "../src/interfaces/ISwapboard.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockERC20Permit} from "./mocks/MockERC20Permit.sol";
import {OrderTestLib} from "./helpers/OrderTestLib.sol";
import {SwapboardTwoPartyTest} from "./helpers/SwapboardTwoPartyTest.sol";

/// @notice EIP-2612 permit overloads for create / fill / modify
contract SwapboardPermitTest is SwapboardTwoPartyTest {
    MockERC20Permit internal _permitA;
    MockERC20Permit internal _permitB;
    MockERC20Permit internal _permitC;
    MockERC20 internal _plainB;

    /// @notice Deploys permit tokens and funds maker/taker
    function setUp() public {
        _setUpActors();

        _permitA = new MockERC20Permit("Permit A", "PA", 18);
        _permitB = new MockERC20Permit("Permit B", "PB", 6);
        _permitC = new MockERC20Permit("Permit C", "PC", 18);
        _plainB = new MockERC20("Token B", "TKB", 6);
        _tokenA = _permitA;
        _tokenB = _permitB;
        _tokenC = _permitC;

        _mintStandardBalances();
        _plainB.mint(_maker, _AMOUNT_A * 10);
        _plainB.mint(_taker, _AMOUNT_B * 10);
    }

    /// @notice createOrder with permit deposits tokenA without a prior approve
    function test_createOrder_permit_noApprove() public {
        ISwapboard.Permit memory permit = _signPermit(_permitA, _maker, _MAKER_PK, _AMOUNT_A);

        vm.prank(_maker);
        uint256 orderId = _board.createOrder(_plainOrder(), permit);

        assertNotEq(_board.getOrder(orderId).maker, address(0));
        assertEq(_tokenA.balanceOf(address(_board)), _AMOUNT_A);
        assertEq(_tokenA.allowance(_maker, address(_board)), 0);
    }

    /// @notice createOrder with v == 0 skips permit and uses existing allowance
    function test_createOrder_permit_v0_skips() public {
        vm.prank(_maker);
        _tokenA.approve(address(_board), _AMOUNT_A);

        vm.prank(_maker);
        uint256 orderId = _board.createOrder(_plainOrder(), _skipPermit());

        assertNotEq(_board.getOrder(orderId).maker, address(0));
        assertEq(_tokenA.balanceOf(address(_board)), _AMOUNT_A);
    }

    /// @notice createOrder with v == 0 and no allowance reverts on the pull
    function test_createOrder_permit_v0_needsAllowance() public {
        vm.prank(_maker);
        vm.expectRevert();
        _board.createOrder(_plainOrder(), _skipPermit());
    }

    /// @notice createOrder permit on ETH tokenA reverts
    function test_createOrder_permit_native_revert() public {
        ISwapboard.Permit memory permit = _signPermit(_permitA, _maker, _MAKER_PK, _AMOUNT_A);

        vm.prank(_maker);
        vm.expectRevert(ISwapboard.PermitOnNative.selector);
        _board.createOrder{value: _AMOUNT_A}(_ethOffered(), permit);
    }

    /// @notice createOrder with v == 0 allows native tokenA (no permit call)
    function test_createOrder_permit_v0_native() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: _AMOUNT_A}(_ethOffered(), _skipPermit());

        assertNotEq(_board.getOrder(orderId).maker, address(0));
        assertEq(address(_board).balance, _AMOUNT_A);
    }

    /// @notice createOrders applies one permit per unique tokenA
    function test_createOrders_permit_noApprove() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _plainOrder();
        orders[1] = _plainOrder();
        ISwapboard.TokenPermit[] memory permits =
            _single(_tokenPermit(_permitA, _maker, _MAKER_PK, uint256(_AMOUNT_A) * 2));

        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders(orders, permits);

        assertEq(ids.length, 2);
        assertEq(_tokenA.balanceOf(address(_board)), uint256(_AMOUNT_A) * 2);
    }

    /// @notice Duplicate token in a permit batch reverts
    function test_createOrders_permit_revert_duplicateToken() public {
        ISwapboard.TokenPermit[] memory permits = new ISwapboard.TokenPermit[](2);
        permits[0] = _tokenPermit(_permitA, _maker, _MAKER_PK, _AMOUNT_A);
        permits[1] = permits[0];

        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.DuplicatePermitToken.selector, address(_tokenA)));
        _board.createOrders(_single(_plainOrder()), permits);
    }

    /// @notice Batch permit with v == 0 reverts InvalidPermit
    function test_createOrders_permit_revert_invalidPermit() public {
        ISwapboard.TokenPermit memory invalid = _dummyTokenPermit(address(_tokenA));
        invalid.v = 0;

        vm.prank(_maker);
        vm.expectRevert(ISwapboard.InvalidPermit.selector);
        _board.createOrders(_single(_plainOrder()), _single(invalid));
    }

    /// @notice Batch permit with token == 0 reverts ZeroAddress
    function test_createOrders_permit_revert_zeroAddress() public {
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.ZeroAddress.selector);
        _board.createOrders(_single(_plainOrder()), _single(_dummyTokenPermit(address(0))));
    }

    /// @notice Batch permit for the ETH sentinel reverts PermitOnNative
    function test_createOrders_permit_revert_native() public {
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.PermitOnNative.selector);
        _board.createOrders{value: _AMOUNT_A}(_single(_ethOffered()), _single(_dummyTokenPermit(_eth)));
    }

    /// @notice Empty permit array still creates when allowance is already set
    function test_createOrders_permit_emptyArray_usesAllowance() public {
        vm.prank(_maker);
        _tokenA.approve(address(_board), _AMOUNT_A);

        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders(_single(_plainOrder()), _noPermits());

        assertEq(ids.length, 1);
        assertEq(_tokenA.balanceOf(address(_board)), _AMOUNT_A);
    }

    /// @notice createOrders applies one permit per distinct tokenA
    function test_createOrders_permit_twoTokens() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _plainOrder();
        orders[1] = OrderTestLib.order(address(_tokenC), _AMOUNT_A, address(_plainB), _AMOUNT_B);

        ISwapboard.TokenPermit[] memory permits = new ISwapboard.TokenPermit[](2);
        permits[0] = _tokenPermit(_permitA, _maker, _MAKER_PK, _AMOUNT_A);
        permits[1] = _tokenPermit(_permitC, _maker, _MAKER_PK, _AMOUNT_A);

        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders(orders, permits);

        assertEq(ids.length, 2);
        assertEq(_tokenA.balanceOf(address(_board)), _AMOUNT_A);
        assertEq(_tokenC.balanceOf(address(_board)), _AMOUNT_A);
        assertEq(_permitA.nonces(_maker), 1);
        assertEq(_permitC.nonces(_maker), 1);
    }

    /// @notice Unused batch permit (token not deposited) reverts UnusedPermit without consuming nonce
    function test_createOrders_permit_revert_unusedPermit() public {
        ISwapboard.TokenPermit[] memory permits = _single(_tokenPermit(_permitC, _maker, _MAKER_PK, _AMOUNT_A));

        vm.prank(_maker);
        vm.expectRevert(ISwapboard.UnusedPermit.selector);
        _board.createOrders(_single(_plainOrder()), permits);

        assertEq(_permitC.nonces(_maker), 0);
    }

    /// @notice A used create permit plus an unused extra entry reverts before either nonce is consumed
    function test_createOrders_permit_revert_unusedPermit_mixed() public {
        ISwapboard.TokenPermit[] memory permits = _pair(
            _tokenPermit(_permitA, _maker, _MAKER_PK, _AMOUNT_A), _tokenPermit(_permitC, _maker, _MAKER_PK, _AMOUNT_A)
        );

        vm.prank(_maker);
        vm.expectRevert(ISwapboard.UnusedPermit.selector);
        _board.createOrders(_single(_plainOrder()), permits);

        assertEq(_permitA.nonces(_maker), 0);
        assertEq(_permitC.nonces(_maker), 0);
    }

    /// @notice Empty createOrders with a valid unused permit batch reverts ZeroAmount (after validation)
    function test_createOrders_permit_revert_emptyOrders() public {
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.createOrders(new ISwapboard.CreateOrderParams[](0), _single(_dummyTokenPermit(address(_tokenA))));
    }

    /// @notice Invalid create args revert before permit, so the token nonce is unchanged
    function test_createOrder_permit_revert_zeroAddress_doesNotConsumeNonce() public {
        ISwapboard.Permit memory permit = _signPermit(_permitA, _maker, _MAKER_PK, _AMOUNT_A);

        vm.prank(_maker);
        vm.expectRevert(ISwapboard.ZeroAddress.selector);
        _board.createOrder(OrderTestLib.order(address(0), _AMOUNT_A, address(_plainB), _AMOUNT_B), permit);

        assertEq(_permitA.nonces(_maker), 0);
    }

    /// @notice Same-token create reverts before permit, so the token nonce is unchanged
    function test_createOrder_permit_revert_sameToken_doesNotConsumeNonce() public {
        ISwapboard.Permit memory permit = _signPermit(_permitA, _maker, _MAKER_PK, _AMOUNT_A);

        vm.prank(_maker);
        vm.expectRevert(ISwapboard.SameToken.selector);
        _board.createOrder(OrderTestLib.order(address(_tokenA), _AMOUNT_A, address(_tokenA), _AMOUNT_B), permit);

        assertEq(_permitA.nonces(_maker), 0);
    }

    /// @notice A permit value below the pull amount reverts the whole create (nonce unchanged)
    function test_createOrder_permit_revert_valueTooLow() public {
        ISwapboard.Permit memory permit = _signPermit(_permitA, _maker, _MAKER_PK, _AMOUNT_A - 1);

        vm.prank(_maker);
        vm.expectRevert();
        _board.createOrder(_plainOrder(), permit);

        assertEq(_permitA.nonces(_maker), 0);
        assertEq(_tokenA.balanceOf(address(_board)), 0);
    }

    /// @notice Permit on a token without EIP-2612 bubbles the token revert
    function test_createOrder_permit_revert_nonPermitToken() public {
        vm.prank(_maker);
        vm.expectRevert();
        _board.createOrder(
            OrderTestLib.order(address(_plainB), _AMOUNT_A, address(_tokenA), _AMOUNT_B), _nonzeroDummyPermit()
        );
    }

    /// @notice fillOrder with permit pulls tokenB without a prior approve
    function test_fillOrder_permit_noApprove() public {
        uint256 orderId = _createPairOrder();
        ISwapboard.Permit memory permit = _signPermit(_permitB, _taker, _TAKER_PK, _AMOUNT_B);

        vm.prank(_taker);
        _board.fillOrder(orderId, _AMOUNT_B, _AMOUNT_A, 0, permit, address(0));

        _assertFilled();
        assertEq(_tokenB.allowance(_taker, address(_board)), 0);
    }

    /// @notice fillOrder with permit pays tokenA to a non-zero `taker`
    function test_fillOrder_permit_taker_receivesTokenA() public {
        uint256 orderId = _createPairOrder();
        ISwapboard.Permit memory permit = _signPermit(_permitB, _taker, _TAKER_PK, _AMOUNT_B);
        address payout = makeAddr("payout");

        vm.prank(_taker);
        _board.fillOrder(orderId, _AMOUNT_B, _AMOUNT_A, 0, permit, payout);

        assertEq(_tokenA.balanceOf(payout), _AMOUNT_A);
        assertEq(_tokenA.balanceOf(_taker), 0);
        assertEq(_tokenB.balanceOf(_maker), _AMOUNT_B);
        assertEq(_tokenB.allowance(_taker, address(_board)), 0);
    }

    /// @notice Maker cannot self-fill via fillOrder with EIP-2612 permit (beginFill before permit)
    function test_fillOrder_permit_selfFill_revert_nonceUnchanged() public {
        uint256 orderId = _createPairOrder();
        _permitB.mint(_maker, _AMOUNT_B);
        ISwapboard.Permit memory permit = _signPermit(_permitB, _maker, _MAKER_PK, _AMOUNT_B);

        vm.prank(_maker);
        vm.expectRevert(ISwapboard.SelfFill.selector);
        _board.fillOrder(orderId, _AMOUNT_B, _AMOUNT_A, 0, permit, address(0));

        assertTrue(_board.canFill(orderId));
        assertEq(_permitB.nonces(_maker), 0);
        assertEq(_tokenA.balanceOf(address(_board)), _AMOUNT_A);
    }

    /// @notice Batch EIP-2612 SelfFill reverts after permits would apply; full tx rolls nonce back
    function test_fillOrders_permit_selfFill_revert_nonceUnchanged() public {
        uint256 orderId = _createPairOrder();
        _permitB.mint(_maker, _AMOUNT_B);
        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](1);
        fills[0] = ISwapboard.FillOrderParams({orderId: orderId, amountB: _AMOUNT_B, minAmountA: _AMOUNT_A});
        ISwapboard.TokenPermit[] memory permits = _single(_tokenPermit(_permitB, _maker, _MAKER_PK, _AMOUNT_B));

        vm.prank(_maker);
        vm.expectRevert(ISwapboard.SelfFill.selector);
        _board.fillOrders(fills, 0, permits, address(0));

        assertTrue(_board.canFill(orderId));
        assertEq(_permitB.nonces(_maker), 0);
        assertEq(_tokenA.balanceOf(address(_board)), _AMOUNT_A);
    }

    /// @notice Mid-batch EIP-2612 SelfFill rolls back earlier legs and permit nonce
    function test_fillOrders_permit_selfFill_midBatch_revert() public {
        address maker2 = vm.addr(0xC0FFEE);
        _tokenA.mint(maker2, _AMOUNT_A);
        vm.prank(maker2);
        _tokenA.approve(address(_board), _AMOUNT_A);
        vm.prank(maker2);
        uint256 otherId = _board.createOrder(_pairOrder());

        uint256 ownId = _createPairOrder();
        _permitB.mint(_maker, uint256(_AMOUNT_B) * 2);

        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = ISwapboard.FillOrderParams({orderId: otherId, amountB: _AMOUNT_B, minAmountA: _AMOUNT_A});
        fills[1] = ISwapboard.FillOrderParams({orderId: ownId, amountB: _AMOUNT_B, minAmountA: _AMOUNT_A});
        ISwapboard.TokenPermit[] memory permits =
            _single(_tokenPermit(_permitB, _maker, _MAKER_PK, uint256(_AMOUNT_B) * 2));

        vm.prank(_maker);
        vm.expectRevert(ISwapboard.SelfFill.selector);
        _board.fillOrders(fills, 0, permits, address(0));

        assertTrue(_board.canFill(otherId));
        assertTrue(_board.canFill(ownId));
        assertEq(_permitB.nonces(_maker), 0);
        assertEq(_tokenA.balanceOf(address(_board)), uint256(_AMOUNT_A) * 2);
        assertEq(_tokenB.balanceOf(maker2), 0);
    }

    /// @notice fillOrder permit on ETH tokenB reverts
    function test_fillOrder_permit_native_revert() public {
        uint256 orderId = _createEthWantedOrder();

        vm.prank(_taker);
        vm.expectRevert(ISwapboard.PermitOnNative.selector);
        _board.fillOrder{value: _AMOUNT_A}(orderId, _AMOUNT_A, _AMOUNT_A, 0, _nonzeroDummyPermit(), address(0));
    }

    /// @notice fillOrder with v == 0 allows native tokenB (no permit call)
    function test_fillOrder_permit_v0_native() public {
        uint256 orderId = _createEthWantedOrder();

        vm.prank(_taker);
        _board.fillOrder{value: _AMOUNT_A}(orderId, _AMOUNT_A, _AMOUNT_A, 0, _skipPermit(), address(0));

        assertEq(_tokenA.balanceOf(_taker), _AMOUNT_A);
        assertEq(_maker.balance, 100 ether + _AMOUNT_A);
    }

    /// @notice fillOrders with a tokenB permit
    function test_fillOrders_permit_noApprove() public {
        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](1);
        fills[0] = ISwapboard.FillOrderParams({orderId: _createPairOrder(), amountB: _AMOUNT_B, minAmountA: _AMOUNT_A});
        ISwapboard.TokenPermit[] memory permits = _single(_tokenPermit(_permitB, _taker, _TAKER_PK, _AMOUNT_B));

        vm.prank(_taker);
        _board.fillOrders(fills, 0, permits, address(0));

        _assertFilled();
    }

    /// @notice Empty permit array still fills when allowance is already set
    function test_fillOrders_permit_emptyArray_usesAllowance() public {
        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](1);
        fills[0] = ISwapboard.FillOrderParams({orderId: _createPairOrder(), amountB: _AMOUNT_B, minAmountA: _AMOUNT_A});

        vm.prank(_taker);
        _tokenB.approve(address(_board), _AMOUNT_B);
        vm.prank(_taker);
        _board.fillOrders(fills, 0, _noPermits(), address(0));

        _assertFilled();
    }

    /// @notice fillOrders applies one permit per distinct tokenB
    function test_fillOrders_permit_twoTokens() public {
        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = ISwapboard.FillOrderParams({orderId: _createPairOrder(), amountB: _AMOUNT_B, minAmountA: _AMOUNT_A});
        fills[1] = ISwapboard.FillOrderParams({
            orderId: _createApproved(_tokenCWanted()), amountB: _AMOUNT_B, minAmountA: _AMOUNT_A
        });

        ISwapboard.TokenPermit[] memory permits = new ISwapboard.TokenPermit[](2);
        permits[0] = _tokenPermit(_permitB, _taker, _TAKER_PK, _AMOUNT_B);
        permits[1] = _tokenPermit(_permitC, _taker, _TAKER_PK, _AMOUNT_B);

        uint256 makerCBefore = _tokenC.balanceOf(_maker);
        vm.prank(_taker);
        _board.fillOrders(fills, 0, permits, address(0));

        assertEq(_tokenA.balanceOf(_taker), uint256(_AMOUNT_A) * 2);
        assertEq(_tokenB.balanceOf(_maker), _AMOUNT_B);
        assertEq(_tokenC.balanceOf(_maker), makerCBefore + _AMOUNT_B);
    }

    /// @notice fillOrders with two same-tokenB orders uses one permit (duplicate skip in unique set)
    function test_fillOrders_permit_sameTokenB_twoOrders() public {
        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = ISwapboard.FillOrderParams({orderId: _createPairOrder(), amountB: _AMOUNT_B, minAmountA: _AMOUNT_A});
        fills[1] = ISwapboard.FillOrderParams({orderId: _createPairOrder(), amountB: _AMOUNT_B, minAmountA: _AMOUNT_A});
        ISwapboard.TokenPermit[] memory permits =
            _single(_tokenPermit(_permitB, _taker, _TAKER_PK, uint256(_AMOUNT_B) * 2));

        vm.prank(_taker);
        _board.fillOrders(fills, 0, permits, address(0));

        assertEq(_tokenA.balanceOf(_taker), uint256(_AMOUNT_A) * 2);
        assertEq(_tokenB.balanceOf(_maker), uint256(_AMOUNT_B) * 2);
        assertEq(_permitB.nonces(_taker), 1);
    }

    /// @notice fillOrders permit batch skips native tokenB when building the used-token set
    function test_fillOrders_permit_mixedNativeTokenB() public {
        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](2);
        fills[0] = ISwapboard.FillOrderParams({orderId: _createPairOrder(), amountB: _AMOUNT_B, minAmountA: _AMOUNT_A});
        fills[1] =
            ISwapboard.FillOrderParams({orderId: _createEthWantedOrder(), amountB: _AMOUNT_A, minAmountA: _AMOUNT_A});
        ISwapboard.TokenPermit[] memory permits = _single(_tokenPermit(_permitB, _taker, _TAKER_PK, _AMOUNT_B));

        uint256 makerEthBefore = _maker.balance;
        vm.prank(_taker);
        _board.fillOrders{value: _AMOUNT_A}(fills, 0, permits, address(0));

        assertEq(_tokenA.balanceOf(_taker), uint256(_AMOUNT_A) * 2);
        assertEq(_tokenB.balanceOf(_maker), _AMOUNT_B);
        assertEq(_maker.balance, makerEthBefore + _AMOUNT_A);
        assertEq(_permitB.nonces(_taker), 1);
    }

    /// @notice Unused fillOrders permit (tokenB not pulled) reverts UnusedPermit without consuming nonce
    function test_fillOrders_permit_revert_unusedPermit() public {
        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](1);
        fills[0] = ISwapboard.FillOrderParams({orderId: _createPairOrder(), amountB: _AMOUNT_B, minAmountA: _AMOUNT_A});
        ISwapboard.TokenPermit[] memory permits = _single(_tokenPermit(_permitC, _taker, _TAKER_PK, _AMOUNT_B));

        vm.prank(_taker);
        vm.expectRevert(ISwapboard.UnusedPermit.selector);
        _board.fillOrders(fills, 0, permits, address(0));

        assertEq(_permitC.nonces(_taker), 0);
    }

    /// @notice A used fill permit plus an unused extra entry reverts before either nonce is consumed
    function test_fillOrders_permit_revert_unusedPermit_mixed() public {
        ISwapboard.FillOrderParams[] memory fills = new ISwapboard.FillOrderParams[](1);
        fills[0] = ISwapboard.FillOrderParams({orderId: _createPairOrder(), amountB: _AMOUNT_B, minAmountA: _AMOUNT_A});
        ISwapboard.TokenPermit[] memory permits = _pair(
            _tokenPermit(_permitB, _taker, _TAKER_PK, _AMOUNT_B), _tokenPermit(_permitC, _taker, _TAKER_PK, _AMOUNT_B)
        );

        vm.prank(_taker);
        vm.expectRevert(ISwapboard.UnusedPermit.selector);
        _board.fillOrders(fills, 0, permits, address(0));

        assertEq(_permitB.nonces(_taker), 0);
        assertEq(_permitC.nonces(_taker), 0);
    }

    /// @notice Duplicate token in a fillOrders permit batch reverts
    function test_fillOrders_permit_revert_duplicateToken() public {
        ISwapboard.TokenPermit[] memory permits = new ISwapboard.TokenPermit[](2);
        permits[0] = _dummyTokenPermit(address(_tokenB));
        permits[1] = permits[0];

        vm.prank(_taker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.DuplicatePermitToken.selector, address(_tokenB)));
        _board.fillOrders(new ISwapboard.FillOrderParams[](0), 0, permits, address(0));
    }

    /// @notice fillOrders batch permit with v == 0 reverts InvalidPermit
    function test_fillOrders_permit_revert_invalidPermit() public {
        ISwapboard.TokenPermit memory invalid = _dummyTokenPermit(address(_tokenB));
        invalid.v = 0;

        vm.prank(_taker);
        vm.expectRevert(ISwapboard.InvalidPermit.selector);
        _board.fillOrders(new ISwapboard.FillOrderParams[](0), 0, _single(invalid), address(0));
    }

    /// @notice fillOrders batch permit with token == 0 reverts ZeroAddress
    function test_fillOrders_permit_revert_zeroAddress() public {
        vm.prank(_taker);
        vm.expectRevert(ISwapboard.ZeroAddress.selector);
        _board.fillOrders(new ISwapboard.FillOrderParams[](0), 0, _single(_dummyTokenPermit(address(0))), address(0));
    }

    /// @notice fillOrders batch permit for the ETH sentinel reverts PermitOnNative
    function test_fillOrders_permit_revert_native() public {
        vm.prank(_taker);
        vm.expectRevert(ISwapboard.PermitOnNative.selector);
        _board.fillOrders(new ISwapboard.FillOrderParams[](0), 0, _single(_dummyTokenPermit(_eth)), address(0));
    }

    /// @notice modifyOrder top-up with permit (exact initial allowance, then permit for extra)
    function test_modifyOrder_permit_topUp() public {
        ISwapboard.Permit memory createPermit = _signPermit(_permitA, _maker, _MAKER_PK, _AMOUNT_A);
        vm.prank(_maker);
        uint256 orderId = _board.createOrder(_plainOrder(), createPermit);
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        ISwapboard.Permit memory topUpPermit = _signPermit(_permitA, _maker, _MAKER_PK, _AMOUNT_A);
        vm.prank(_maker);
        _board.modifyOrder(
            orderId,
            _amounts(snapshot),
            ISwapboard.ModifyOrderParams({availableA: _AMOUNT_A * 2, availableB: _AMOUNT_B, maker: address(0)}),
            topUpPermit,
            address(0)
        );

        assertEq(_board.getOrder(orderId).availableA, _AMOUNT_A * 2);
        assertEq(_tokenA.balanceOf(address(_board)), uint256(_AMOUNT_A) * 2);
    }

    /// @notice modifyOrder permit on ETH tokenA top-up reverts
    function test_modifyOrder_permit_native_revert() public {
        vm.deal(_maker, 200 ether);
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: _AMOUNT_A}(_ethOffered(), _skipPermit());
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        vm.prank(_maker);
        vm.expectRevert(ISwapboard.PermitOnNative.selector);
        _board.modifyOrder{value: 1 ether}(
            orderId,
            _amounts(snapshot),
            ISwapboard.ModifyOrderParams({availableA: _AMOUNT_A + 1 ether, availableB: _AMOUNT_B, maker: address(0)}),
            _nonzeroDummyPermit(),
            address(0)
        );
    }

    /// @notice modifyOrder with v == 0 allows native tokenA top-up (no permit call)
    function test_modifyOrder_permit_v0_native() public {
        vm.deal(_maker, 200 ether);
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: _AMOUNT_A}(_ethOffered(), _skipPermit());
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        vm.prank(_maker);
        _board.modifyOrder{value: 1 ether}(
            orderId,
            _amounts(snapshot),
            ISwapboard.ModifyOrderParams({availableA: _AMOUNT_A + 1 ether, availableB: _AMOUNT_B, maker: address(0)}),
            _skipPermit(),
            address(0)
        );

        assertEq(_board.getOrder(orderId).availableA, _AMOUNT_A + 1 ether);
        assertEq(address(_board).balance, uint256(_AMOUNT_A) + 1 ether);
    }

    /// @notice modifyOrders netted top-up with permit
    function test_modifyOrders_permit_topUp() public {
        ISwapboard.TokenPermit[] memory createPermits = _single(_tokenPermit(_permitA, _maker, _MAKER_PK, _AMOUNT_A));
        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders(_single(_plainOrder()), createPermits);
        ISwapboard.Order memory snapshot = _board.getOrder(ids[0]);

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](1);
        mods[0] = ISwapboard.ModifyOrdersParams({
            orderId: ids[0],
            previousAmounts: _amounts(snapshot),
            updatedOrder: ISwapboard.ModifyOrderParams({
                availableA: _AMOUNT_A * 2, availableB: _AMOUNT_B, maker: address(0)
            })
        });

        ISwapboard.TokenPermit[] memory permits = _single(_tokenPermit(_permitA, _maker, _MAKER_PK, _AMOUNT_A));
        vm.prank(_maker);
        _board.modifyOrders(mods, permits, address(0));

        assertEq(_board.getOrder(ids[0]).availableA, _AMOUNT_A * 2);
        assertEq(_tokenA.balanceOf(address(_board)), uint256(_AMOUNT_A) * 2);
    }

    /// @notice Unused modifyOrders permit (tokenA not topped up) reverts UnusedPermit without consuming nonce
    function test_modifyOrders_permit_revert_unusedPermit() public {
        ISwapboard.TokenPermit[] memory createPermits = _single(_tokenPermit(_permitA, _maker, _MAKER_PK, _AMOUNT_A));
        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders(_single(_plainOrder()), createPermits);
        ISwapboard.Order memory snapshot = _board.getOrder(ids[0]);

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](1);
        mods[0] = ISwapboard.ModifyOrdersParams({
            orderId: ids[0],
            previousAmounts: _amounts(snapshot),
            updatedOrder: ISwapboard.ModifyOrderParams({
                availableA: _AMOUNT_A * 2, availableB: _AMOUNT_B, maker: address(0)
            })
        });

        ISwapboard.TokenPermit[] memory permits = _single(_tokenPermit(_permitC, _maker, _MAKER_PK, _AMOUNT_A));
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.UnusedPermit.selector);
        _board.modifyOrders(mods, permits, address(0));

        assertEq(_permitC.nonces(_maker), 0);
    }

    /// @notice Refund-only modifyOrders with an EIP-2612 permit reverts UnusedPermit
    function test_modifyOrders_permit_refundOnly_revert_unusedPermit() public {
        ISwapboard.TokenPermit[] memory createPermits = _single(_tokenPermit(_permitA, _maker, _MAKER_PK, _AMOUNT_A));
        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders(_single(_plainOrder()), createPermits);
        ISwapboard.Order memory snapshot = _board.getOrder(ids[0]);

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](1);
        mods[0] = ISwapboard.ModifyOrdersParams({
            orderId: ids[0],
            previousAmounts: _amounts(snapshot),
            updatedOrder: ISwapboard.ModifyOrderParams({
                availableA: _AMOUNT_A / 2, availableB: _AMOUNT_B / 2, maker: address(0)
            })
        });

        ISwapboard.TokenPermit[] memory permits = _single(_tokenPermit(_permitA, _maker, _MAKER_PK, _AMOUNT_A));
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.UnusedPermit.selector);
        _board.modifyOrders(mods, permits, address(0));

        assertEq(_permitA.nonces(_maker), 1);
    }

    /// @notice Refund-only modifyOrder with a non-skip EIP-2612 permit reverts UnusedPermit
    function test_modifyOrder_permit_refundOnly_revert_unusedPermit() public {
        ISwapboard.Permit memory createPermit = _signPermit(_permitA, _maker, _MAKER_PK, _AMOUNT_A);
        vm.prank(_maker);
        uint256 orderId = _board.createOrder(_plainOrder(), createPermit);
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        ISwapboard.Permit memory refundPermit = _signPermit(_permitA, _maker, _MAKER_PK, _AMOUNT_A);
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.UnusedPermit.selector);
        _board.modifyOrder(
            orderId,
            _amounts(snapshot),
            ISwapboard.ModifyOrderParams({availableA: _AMOUNT_A / 2, availableB: _AMOUNT_B / 2, maker: address(0)}),
            refundPermit,
            address(0)
        );

        assertEq(_permitA.nonces(_maker), 1);
    }

    /// @notice Same-token top-up and refund that net to zero make a tokenA permit unused
    function test_modifyOrders_permit_netZero_revert_unusedPermit() public {
        uint256[] memory ids = _createTwoPlainOrdersWithPermit();
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = ISwapboard.ModifyOrdersParams({
            orderId: ids[0],
            previousAmounts: _amounts(_board.getOrder(ids[0])),
            updatedOrder: ISwapboard.ModifyOrderParams({
                availableA: _AMOUNT_A + (_AMOUNT_A / 2), availableB: _AMOUNT_B, maker: address(0)
            })
        });
        mods[1] = ISwapboard.ModifyOrdersParams({
            orderId: ids[1],
            previousAmounts: _amounts(_board.getOrder(ids[1])),
            updatedOrder: ISwapboard.ModifyOrderParams({
                availableA: _AMOUNT_A / 2, availableB: _AMOUNT_B, maker: address(0)
            })
        });

        ISwapboard.TokenPermit[] memory permits = _single(_tokenPermit(_permitA, _maker, _MAKER_PK, _AMOUNT_A));
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.UnusedPermit.selector);
        _board.modifyOrders(mods, permits, address(0));

        assertEq(_permitA.nonces(_maker), 1);
        assertEq(_board.getOrder(ids[0]).availableA, _AMOUNT_A);
        assertEq(_board.getOrder(ids[1]).availableA, _AMOUNT_A);
    }

    /// @notice Same-token net refund (refund dominates) makes a tokenA permit unused
    function test_modifyOrders_permit_netRefund_revert_unusedPermit() public {
        uint256[] memory ids = _createTwoPlainOrdersWithPermit();
        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = ISwapboard.ModifyOrdersParams({
            orderId: ids[0],
            previousAmounts: _amounts(_board.getOrder(ids[0])),
            updatedOrder: ISwapboard.ModifyOrderParams({
                availableA: _AMOUNT_A + (_AMOUNT_A / 4), availableB: _AMOUNT_B, maker: address(0)
            })
        });
        mods[1] = ISwapboard.ModifyOrdersParams({
            orderId: ids[1],
            previousAmounts: _amounts(_board.getOrder(ids[1])),
            updatedOrder: ISwapboard.ModifyOrderParams({
                availableA: _AMOUNT_A / 2, availableB: _AMOUNT_B, maker: address(0)
            })
        });

        ISwapboard.TokenPermit[] memory permits = _single(_tokenPermit(_permitA, _maker, _MAKER_PK, _AMOUNT_A));
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.UnusedPermit.selector);
        _board.modifyOrders(mods, permits, address(0));

        assertEq(_permitA.nonces(_maker), 1);
        assertEq(_board.getOrder(ids[0]).availableA, _AMOUNT_A);
        assertEq(_board.getOrder(ids[1]).availableA, _AMOUNT_A);
    }

    /// @notice Mixed-token modify: permit only the net ERC20 top-up; refund the other token without a permit
    function test_modifyOrders_permit_netRefundWithTopUp() public {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _plainOrder();
        orders[1] = OrderTestLib.order(address(_tokenC), _AMOUNT_A, address(_plainB), _AMOUNT_B);
        ISwapboard.TokenPermit[] memory createPermits = _pair(
            _tokenPermit(_permitA, _maker, _MAKER_PK, _AMOUNT_A), _tokenPermit(_permitC, _maker, _MAKER_PK, _AMOUNT_A)
        );
        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders(orders, createPermits);

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = ISwapboard.ModifyOrdersParams({
            orderId: ids[0],
            previousAmounts: _amounts(_board.getOrder(ids[0])),
            updatedOrder: ISwapboard.ModifyOrderParams({
                availableA: _AMOUNT_A * 2, availableB: _AMOUNT_B, maker: address(0)
            })
        });
        mods[1] = ISwapboard.ModifyOrdersParams({
            orderId: ids[1],
            previousAmounts: _amounts(_board.getOrder(ids[1])),
            updatedOrder: ISwapboard.ModifyOrderParams({
                availableA: _AMOUNT_A / 2, availableB: _AMOUNT_B / 2, maker: address(0)
            })
        });

        uint256 makerCBefore = _tokenC.balanceOf(_maker);
        ISwapboard.TokenPermit[] memory permits = _single(_tokenPermit(_permitA, _maker, _MAKER_PK, _AMOUNT_A));
        vm.prank(_maker);
        _board.modifyOrders(mods, permits, address(0));

        assertEq(_board.getOrder(ids[0]).availableA, _AMOUNT_A * 2);
        assertEq(_board.getOrder(ids[1]).availableA, _AMOUNT_A / 2);
        assertEq(_tokenA.balanceOf(address(_board)), uint256(_AMOUNT_A) * 2);
        assertEq(_tokenC.balanceOf(address(_board)), _AMOUNT_A / 2);
        assertEq(_tokenC.balanceOf(_maker), makerCBefore + _AMOUNT_A / 2);
        assertEq(_permitA.nonces(_maker), 2);
        assertEq(_permitC.nonces(_maker), 1);
    }

    /// @notice modifyOrders with permits skips native tokenA when previewing net ERC20 top-ups
    function test_modifyOrders_permit_mixedNativeTokenA() public {
        vm.deal(_maker, 200 ether);

        ISwapboard.TokenPermit[] memory createPermits = _single(_tokenPermit(_permitA, _maker, _MAKER_PK, _AMOUNT_A));
        vm.prank(_maker);
        uint256 erc20Id = _board.createOrders(_single(_plainOrder()), createPermits)[0];

        vm.prank(_maker);
        uint256 ethId = _board.createOrder{value: _AMOUNT_A}(_ethOffered(), _skipPermit());

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](2);
        mods[0] = ISwapboard.ModifyOrdersParams({
            orderId: erc20Id,
            previousAmounts: _amounts(_board.getOrder(erc20Id)),
            updatedOrder: ISwapboard.ModifyOrderParams({
                availableA: _AMOUNT_A * 2, availableB: _AMOUNT_B, maker: address(0)
            })
        });
        mods[1] = ISwapboard.ModifyOrdersParams({
            orderId: ethId,
            previousAmounts: _amounts(_board.getOrder(ethId)),
            updatedOrder: ISwapboard.ModifyOrderParams({
                availableA: _AMOUNT_A + 1 ether, availableB: _AMOUNT_B, maker: address(0)
            })
        });

        ISwapboard.TokenPermit[] memory permits = _single(_tokenPermit(_permitA, _maker, _MAKER_PK, _AMOUNT_A));
        vm.prank(_maker);
        _board.modifyOrders{value: 1 ether}(mods, permits, address(0));

        assertEq(_board.getOrder(erc20Id).availableA, _AMOUNT_A * 2);
        assertEq(_board.getOrder(ethId).availableA, _AMOUNT_A + 1 ether);
        assertEq(_tokenA.balanceOf(address(_board)), uint256(_AMOUNT_A) * 2);
        assertEq(address(_board).balance, uint256(_AMOUNT_A) + 1 ether);
        assertEq(_permitA.nonces(_maker), 2);
    }

    /// @notice Refund-only modifyOrder with v == 0 skips permit and returns tokenA
    function test_modifyOrder_permit_refundOnly_v0_skips() public {
        ISwapboard.Permit memory createPermit = _signPermit(_permitA, _maker, _MAKER_PK, _AMOUNT_A);
        vm.prank(_maker);
        uint256 orderId = _board.createOrder(_plainOrder(), createPermit);
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        uint256 makerBefore = _tokenA.balanceOf(_maker);

        vm.prank(_maker);
        _board.modifyOrder(
            orderId,
            _amounts(snapshot),
            ISwapboard.ModifyOrderParams({availableA: _AMOUNT_A / 2, availableB: _AMOUNT_B / 2, maker: address(0)}),
            _skipPermit(),
            address(0)
        );

        assertEq(_board.getOrder(orderId).availableA, _AMOUNT_A / 2);
        assertEq(_tokenA.balanceOf(_maker), makerBefore + _AMOUNT_A / 2);
        assertEq(_permitA.nonces(_maker), 1);
    }

    /// @notice Refund-only modifyOrder with permit pays tokenA refund to `maker`
    function test_modifyOrder_permit_refundOnly_maker() public {
        ISwapboard.Permit memory createPermit = _signPermit(_permitA, _maker, _MAKER_PK, _AMOUNT_A);
        vm.prank(_maker);
        uint256 orderId = _board.createOrder(_plainOrder(), createPermit);
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        address payout = makeAddr("payout");
        uint256 makerBefore = _tokenA.balanceOf(_maker);

        vm.prank(_maker);
        _board.modifyOrder(
            orderId,
            _amounts(snapshot),
            ISwapboard.ModifyOrderParams({availableA: _AMOUNT_A / 2, availableB: _AMOUNT_B / 2, maker: address(0)}),
            _skipPermit(),
            payout
        );

        assertEq(_board.getOrder(orderId).availableA, _AMOUNT_A / 2);
        assertEq(_tokenA.balanceOf(payout), _AMOUNT_A / 2);
        assertEq(_tokenA.balanceOf(_maker), makerBefore);
        assertEq(_permitA.nonces(_maker), 1);
    }

    /// @notice modifyOrder with empty permit can reassign the order maker
    function test_modifyOrder_permit_changesMaker() public {
        ISwapboard.Permit memory createPermit = _signPermit(_permitA, _maker, _MAKER_PK, _AMOUNT_A);
        vm.prank(_maker);
        uint256 orderId = _board.createOrder(_plainOrder(), createPermit);
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);
        address newMaker = makeAddr("newMaker");

        vm.prank(_maker);
        _board.modifyOrder(
            orderId,
            _amounts(snapshot),
            ISwapboard.ModifyOrderParams({availableA: _AMOUNT_A, availableB: _AMOUNT_B, maker: newMaker}),
            _skipPermit(),
            address(0)
        );

        assertEq(_board.getOrder(orderId).maker, newMaker);

        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.NotMaker.selector, orderId, _maker, newMaker));
        _board.cancelOrder(orderId, address(0));

        vm.prank(newMaker);
        _board.cancelOrder(orderId, address(0));
        assertEq(_tokenA.balanceOf(newMaker), _AMOUNT_A);
    }

    /// @notice Empty permit array still refunds without a top-up permit
    function test_modifyOrders_permit_refundOnly_emptyArray() public {
        ISwapboard.TokenPermit[] memory createPermits = _single(_tokenPermit(_permitA, _maker, _MAKER_PK, _AMOUNT_A));
        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders(_single(_plainOrder()), createPermits);
        ISwapboard.Order memory snapshot = _board.getOrder(ids[0]);
        uint256 makerBefore = _tokenA.balanceOf(_maker);

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](1);
        mods[0] = ISwapboard.ModifyOrdersParams({
            orderId: ids[0],
            previousAmounts: _amounts(snapshot),
            updatedOrder: ISwapboard.ModifyOrderParams({
                availableA: _AMOUNT_A / 2, availableB: _AMOUNT_B / 2, maker: address(0)
            })
        });

        vm.prank(_maker);
        _board.modifyOrders(mods, _noPermits(), address(0));

        assertEq(_board.getOrder(ids[0]).availableA, _AMOUNT_A / 2);
        assertEq(_tokenA.balanceOf(_maker), makerBefore + _AMOUNT_A / 2);
        assertEq(_permitA.nonces(_maker), 1);
    }

    /// @notice Native refund-only modifyOrder with v != 0 reverts PermitOnNative
    function test_modifyOrder_permit_refundOnly_native_revert() public {
        vm.prank(_maker);
        uint256 orderId = _board.createOrder{value: _AMOUNT_A}(_ethOffered(), _skipPermit());
        ISwapboard.Order memory snapshot = _board.getOrder(orderId);

        vm.prank(_maker);
        vm.expectRevert(ISwapboard.PermitOnNative.selector);
        _board.modifyOrder(
            orderId,
            _amounts(snapshot),
            ISwapboard.ModifyOrderParams({availableA: _AMOUNT_A / 2, availableB: _AMOUNT_B / 2, maker: address(0)}),
            _nonzeroDummyPermit(),
            address(0)
        );
    }

    /// @notice Empty permit array still modifies when allowance is already set
    function test_modifyOrders_permit_emptyArray_usesAllowance() public {
        vm.prank(_maker);
        _tokenA.approve(address(_board), _AMOUNT_A * 2);
        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders(_single(_plainOrder()), _noPermits());
        ISwapboard.Order memory snapshot = _board.getOrder(ids[0]);

        ISwapboard.ModifyOrdersParams[] memory mods = new ISwapboard.ModifyOrdersParams[](1);
        mods[0] = ISwapboard.ModifyOrdersParams({
            orderId: ids[0],
            previousAmounts: _amounts(snapshot),
            updatedOrder: ISwapboard.ModifyOrderParams({
                availableA: _AMOUNT_A * 2, availableB: _AMOUNT_B, maker: address(0)
            })
        });

        vm.prank(_maker);
        _board.modifyOrders(mods, _noPermits(), address(0));

        assertEq(_board.getOrder(ids[0]).availableA, _AMOUNT_A * 2);
        assertEq(_tokenA.balanceOf(address(_board)), uint256(_AMOUNT_A) * 2);
    }

    /// @notice Duplicate token in a modifyOrders permit batch reverts
    function test_modifyOrders_permit_revert_duplicateToken() public {
        ISwapboard.TokenPermit[] memory permits = new ISwapboard.TokenPermit[](2);
        permits[0] = _dummyTokenPermit(address(_tokenA));
        permits[1] = permits[0];

        vm.prank(_maker);
        vm.expectRevert(abi.encodeWithSelector(ISwapboard.DuplicatePermitToken.selector, address(_tokenA)));
        _board.modifyOrders(new ISwapboard.ModifyOrdersParams[](0), permits, address(0));
    }

    /// @notice modifyOrders batch permit with v == 0 reverts InvalidPermit
    function test_modifyOrders_permit_revert_invalidPermit() public {
        ISwapboard.TokenPermit memory invalid = _dummyTokenPermit(address(_tokenA));
        invalid.v = 0;

        vm.prank(_maker);
        vm.expectRevert(ISwapboard.InvalidPermit.selector);
        _board.modifyOrders(new ISwapboard.ModifyOrdersParams[](0), _single(invalid), address(0));
    }

    /// @notice modifyOrders batch permit with token == 0 reverts ZeroAddress
    function test_modifyOrders_permit_revert_zeroAddress() public {
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.ZeroAddress.selector);
        _board.modifyOrders(new ISwapboard.ModifyOrdersParams[](0), _single(_dummyTokenPermit(address(0))), address(0));
    }

    /// @notice modifyOrders batch permit for the ETH sentinel reverts PermitOnNative
    function test_modifyOrders_permit_revert_native() public {
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.PermitOnNative.selector);
        _board.modifyOrders(new ISwapboard.ModifyOrdersParams[](0), _single(_dummyTokenPermit(_eth)), address(0));
    }

    /// @notice Empty modifyOrders with a valid unused permit batch reverts ZeroAmount (after validation)
    function test_modifyOrders_permit_revert_emptyMods() public {
        vm.prank(_maker);
        vm.expectRevert(ISwapboard.ZeroAmount.selector);
        _board.modifyOrders(
            new ISwapboard.ModifyOrdersParams[](0), _single(_dummyTokenPermit(address(_tokenA))), address(0)
        );
    }

    /// @notice Expired permit reverts from the token
    function test_createOrder_permit_revert_expired() public {
        ISwapboard.Permit memory permit = _signPermit(_permitA, _maker, _MAKER_PK, _AMOUNT_A, block.timestamp);
        vm.warp(block.timestamp + 1);

        vm.prank(_maker);
        vm.expectRevert(MockERC20Permit.PermitExpired.selector);
        _board.createOrder(_plainOrder(), permit);
    }

    /// @notice Wrong signer reverts from the token
    function test_createOrder_permit_revert_invalidSigner() public {
        uint256 otherPk = uint256(keccak256("other"));
        ISwapboard.Permit memory permit = _signPermit(_permitA, _maker, otherPk, _AMOUNT_A);

        vm.prank(_maker);
        vm.expectRevert(MockERC20Permit.InvalidSigner.selector);
        _board.createOrder(_plainOrder(), permit);
    }

    /// @notice createOrder still works when the permit nonce was spent by a front-runner
    function test_createOrder_permit_frontRunNonce_stillCreates() public {
        ISwapboard.Permit memory permit = _signPermit(_permitA, _maker, _MAKER_PK, _AMOUNT_A);
        _frontRunPermit(_permitA, permit);

        vm.prank(_maker);
        uint256 orderId = _board.createOrder(_plainOrder(), permit);

        assertNotEq(_board.getOrder(orderId).maker, address(0));
        assertEq(_tokenA.balanceOf(address(_board)), _AMOUNT_A);
        assertEq(_permitA.nonces(_maker), 1);
    }

    /// @notice createOrders still works when a batch permit nonce was spent by a front-runner
    function test_createOrders_permit_frontRunNonce_stillCreates() public {
        ISwapboard.TokenPermit memory tokenPermit = _tokenPermit(_permitA, _maker, _MAKER_PK, _AMOUNT_A);
        _frontRunPermit(
            _permitA,
            ISwapboard.Permit({
                value: tokenPermit.value,
                deadline: tokenPermit.deadline,
                v: tokenPermit.v,
                r: tokenPermit.r,
                s: tokenPermit.s
            })
        );

        vm.prank(_maker);
        uint256[] memory ids = _board.createOrders(_single(_plainOrder()), _single(tokenPermit));

        assertEq(ids.length, 1);
        assertEq(_tokenA.balanceOf(address(_board)), _AMOUNT_A);
        assertEq(_permitA.nonces(_maker), 1);
    }

    /// @notice A permit already covered by the current allowance is not sent to the token
    function test_createOrder_permit_existingAllowance_skipsPermit() public {
        ISwapboard.Permit memory permit = _signPermit(_permitA, _maker, _MAKER_PK, _AMOUNT_A);

        vm.prank(_maker);
        _tokenA.approve(address(_board), _AMOUNT_A);

        vm.prank(_maker);
        uint256 orderId = _board.createOrder(_plainOrder(), permit);

        assertNotEq(_board.getOrder(orderId).maker, address(0));
        assertEq(_tokenA.balanceOf(address(_board)), _AMOUNT_A);
        assertEq(_permitA.nonces(_maker), 0);
    }

    /// @notice Submits the maker's permit signature from another account, spending the nonce
    function _frontRunPermit(
        MockERC20Permit token,
        ISwapboard.Permit memory permit
    ) private {
        vm.prank(vm.addr(0xF00D));
        token.permit(_maker, address(_board), permit.value, permit.deadline, permit.v, permit.r, permit.s);

        assertEq(token.nonces(_maker), 1);
        assertEq(token.allowance(_maker, address(_board)), permit.value);
    }

    function _createPairOrder() private returns (uint256) {
        return _createApproved(_pairOrder());
    }

    function _createEthWantedOrder() private returns (uint256) {
        return _createApproved(_ethWanted());
    }

    function _plainOrder() private view returns (ISwapboard.CreateOrderParams memory) {
        return OrderTestLib.order(address(_tokenA), _AMOUNT_A, address(_plainB), _AMOUNT_B);
    }

    function _pairOrder() private view returns (ISwapboard.CreateOrderParams memory) {
        return OrderTestLib.order(address(_tokenA), _AMOUNT_A, address(_tokenB), _AMOUNT_B);
    }

    function _ethOffered() private view returns (ISwapboard.CreateOrderParams memory) {
        return OrderTestLib.order(_eth, _AMOUNT_A, address(_plainB), _AMOUNT_B);
    }

    function _single(
        ISwapboard.TokenPermit memory permit
    ) private pure returns (ISwapboard.TokenPermit[] memory permits) {
        permits = new ISwapboard.TokenPermit[](1);
        permits[0] = permit;
    }

    function _pair(
        ISwapboard.TokenPermit memory first,
        ISwapboard.TokenPermit memory second
    ) private pure returns (ISwapboard.TokenPermit[] memory permits) {
        permits = new ISwapboard.TokenPermit[](2);
        permits[0] = first;
        permits[1] = second;
    }

    function _createTwoPlainOrdersWithPermit() private returns (uint256[] memory) {
        ISwapboard.CreateOrderParams[] memory orders = new ISwapboard.CreateOrderParams[](2);
        orders[0] = _plainOrder();
        orders[1] = _plainOrder();
        ISwapboard.TokenPermit[] memory permits =
            _single(_tokenPermit(_permitA, _maker, _MAKER_PK, uint256(_AMOUNT_A) * 2));
        vm.prank(_maker);
        return _board.createOrders(orders, permits);
    }

    function _noPermits() private pure returns (ISwapboard.TokenPermit[] memory) {
        return new ISwapboard.TokenPermit[](0);
    }

    function _dummyTokenPermit(
        address token
    ) private view returns (ISwapboard.TokenPermit memory) {
        ISwapboard.Permit memory p = _nonzeroDummyPermit();
        return ISwapboard.TokenPermit({token: token, value: p.value, deadline: p.deadline, v: p.v, r: p.r, s: p.s});
    }

    function _skipPermit() private pure returns (ISwapboard.Permit memory) {
        return ISwapboard.Permit({value: 0, deadline: 0, v: 0, r: bytes32(0), s: bytes32(0)});
    }

    function _nonzeroDummyPermit() private view returns (ISwapboard.Permit memory) {
        return ISwapboard.Permit({
            value: 1, deadline: block.timestamp + 1, v: 27, r: bytes32(uint256(1)), s: bytes32(uint256(1))
        });
    }

    function _signPermit(
        MockERC20Permit token,
        address owner,
        uint256 pk,
        uint256 value
    ) private view returns (ISwapboard.Permit memory) {
        return _signPermit(token, owner, pk, value, block.timestamp + 1 days);
    }

    function _signPermit(
        MockERC20Permit token,
        address owner,
        uint256 pk,
        uint256 value,
        uint256 deadline
    ) private view returns (ISwapboard.Permit memory permit) {
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(token.PERMIT_TYPEHASH(), owner, address(_board), value, token.nonces(owner), deadline)
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        permit = ISwapboard.Permit({value: value, deadline: deadline, v: v, r: r, s: s});
    }

    function _tokenPermit(
        MockERC20Permit token,
        address owner,
        uint256 pk,
        uint256 value
    ) private view returns (ISwapboard.TokenPermit memory) {
        ISwapboard.Permit memory p = _signPermit(token, owner, pk, value);
        return
            ISwapboard.TokenPermit({
                token: address(token), value: p.value, deadline: p.deadline, v: p.v, r: p.r, s: p.s
            });
    }
}

