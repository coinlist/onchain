// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {TestStable} from "shared/TestToken.sol";
import {Side, OptimizedSwapTotal as Total} from "swap/Types.sol";
import {OndoPortfolio} from "ondo/OndoPortfolio.sol";
import {ISoms} from "swap/ISoms.sol";
import {Quote} from "ondo/Types.sol";
import {Assembler, ATTRIBUTION} from "../Assembler.sol";

// manager must be a deployed contract
contract Manager {}

contract OndoPortfolioSell is Test {
    address public constant ALICE = 0x7070707070707070707070707070707070707070;

    bytes4 public constant REDEEM_WITH_SELECTOR = bytes4(
        keccak256(
            "redeemWithAttestation((uint256,uint256,bytes32,address,uint256,uint256,uint256,uint8,bytes32),bytes)"
        )
    );
    bytes4 public constant STABLECOIN_SELECTOR = bytes4(keccak256("stablecoin()"));
    bytes4 public constant TRANSFER_FROM_SELECTOR = bytes4(keccak256("transferFrom(address,address,uint256)"));
    bytes4 public constant APPROVE_SELECTOR = bytes4(keccak256("approve(address,uint256)"));
    bytes4 public constant BALANCE_OF_SELECTOR = bytes4(keccak256("balanceOf(address)"));

    TestStable inT;
    Manager man;
    OndoPortfolio ondo;
    Assembler a;

    function setUp() public {
        inT = new TestStable("usdz", "USDZ");
        man = new Manager();
        a = new Assembler();
        vm.mockCall(address(man), abi.encodeWithSelector(STABLECOIN_SELECTOR), abi.encode(address(inT)));
        ondo = new OndoPortfolio(keccak256("yolo"), a.addr(), address(man));
    }

    function _sig(Quote memory q, uint64 nonce, uint256 amt) internal view returns (bytes memory) {
        bytes32 hash =
            a.structHash(ondo.VERIFY_REQUEST(), Side.Sell, q.asset, address(inT), ALICE, ATTRIBUTION, nonce, amt);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(a.privateKey()), a.digest(ondo.domainSeparator(), hash));
        return a.encodeSig(v, r, s);
    }

    /// @dev asset moves are mocked, the manager "pays" `paid` stable by the balance reads
    function _mockRedeem(Quote memory q, uint256 paid) internal {
        vm.mockCall(q.asset, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));
        vm.mockCall(q.asset, abi.encodeWithSelector(APPROVE_SELECTOR), abi.encode(true));
        // the redeemed amount is what the contract then forwards, so it has to really hold it
        inT.mint(address(ondo), paid);
        bytes[] memory mocks = new bytes[](2);
        mocks[0] = abi.encode(0);
        mocks[1] = abi.encode(paid);
        vm.mockCalls(address(inT), abi.encodeWithSelector(BALANCE_OF_SELECTOR), mocks);
        vm.mockCall(ondo.manager(), abi.encodeWithSelector(REDEEM_WITH_SELECTOR), abi.encode(paid));
    }

    function testRevertSlippage() public {
        Quote memory q = a.quote(block.chainid, Side.Sell);
        // floor of 201e6 is above the 200e6 paid
        bytes memory sig = _sig(q, 0, 201e6);
        _mockRedeem(q, 200e6);
        vm.expectRevert(abi.encodeWithSignature("InsufficientAmount()"));
        vm.prank(ALICE);
        ondo.swap(q, bytes("idc"), address(inT), 201e6, ATTRIBUTION, sig);
    }

    function testSell() public {
        Quote memory q = a.quote(block.chainid, Side.Sell);
        bytes memory sig = _sig(q, 0, 190e6);
        _mockRedeem(q, 200e6);

        vm.expectEmit(true, true, true, true, address(ondo));
        emit ISoms.Swapped(ALICE, q.asset, address(inT), ATTRIBUTION, q.attestationId, Side.Sell, q.quantity, 0, 200e6);

        vm.expectCall(ondo.manager(), abi.encodeWithSelector(REDEEM_WITH_SELECTOR), 1);
        // the asset is approved to the manager for the quantity, then reset
        vm.expectCall(q.asset, abi.encodeWithSelector(APPROVE_SELECTOR, ondo.manager(), q.quantity), 1);
        vm.expectCall(q.asset, abi.encodeWithSelector(APPROVE_SELECTOR, ondo.manager(), 0), 1);

        vm.prank(ALICE);
        uint256 res = ondo.swap(q, bytes("idc"), address(inT), 190e6, ATTRIBUTION, sig);
        assertEq(res, 200e6);

        Total memory t = ondo.totals(ALICE, q.asset, address(inT));
        assertEq(t.count, 1);
        assertEq(t.inputSum, q.quantity);
        assertEq(t.outputSum, 200e6);
        assertEq(t.feeSum, 0);
    }

    function testSellWithFee() public {
        assert(ondo.setBps(Side.Sell, 100));
        Quote memory q = a.quote(block.chainid, Side.Sell);
        bytes memory sig = _sig(q, 0, 190e6);
        _mockRedeem(q, 200e6);

        vm.prank(ALICE);
        uint256 res = ondo.swap(q, bytes("idc"), address(inT), 190e6, ATTRIBUTION, sig);

        uint256 fee = ondo.bpp(Side.Sell, 200e6);
        assertEq(res, 200e6 - fee);
        assertEq(ondo.totals(ALICE, q.asset, address(inT)).feeSum, fee);
    }
}
