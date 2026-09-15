// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";
import {TestStable} from "shared/TestToken.sol";
import {Side, OptimizedSwapTotal as Total} from "swap/Types.sol";
import {Ondo} from "ondo/Ondo.sol";
import {Quote, VerifyRequest} from "ondo/Types.sol";
import {Assembler} from "./Assembler.sol";

// manager must be a deployed contract
contract Manager {}

contract OndoSell is Test {
    address public constant ALICE = 0x7070707070707070707070707070707070707070;

    bytes4 public constant REDEEM_WITH_SELECTOR = bytes4(
        keccak256(
            "redeemWithAttestation((uint256,uint256,bytes32,address,uint256,uint256,uint256,uint8,bytes32),bytes,address,uint256)"
        )
    );
    bytes4 public constant TRANSFER_FROM_SELECTOR = bytes4(keccak256("transferFrom(address,address,uint256)"));
    bytes4 public constant APPROVE_SELECTOR = bytes4(keccak256("approve(address,uint256)"));
    bytes4 public constant BALANCE_OF_SELECTOR = bytes4(keccak256("balanceOf(address)"));

    TestStable inT;
    Manager man;
    Ondo ondo;
    Assembler a;

    function setUp() public {
        inT = new TestStable("usdz", "USDZ");
        man = new Manager();
        a = new Assembler();
        // use USDZ as an approved input
        ondo = new Ondo(keccak256("yolo"), a.addr(), address(man), address(inT));
    }

    function testRevertSlippage() public {
        // get a quote
        Quote memory q = a.quote(block.chainid, Side.Sell);

        // the amount "redeemed" for the quote as a 6 decimal stabelcoin number
        uint256 redeemed = ((q.quantity * q.price) / 1e18) / 1e12;

        // assemble a signature "externally"
        bytes32 ds = ondo.domainSeparator();
        bytes32 hash = a.structHash(ondo.VERIFY_REQUEST(), Side.Sell, q.asset, address(inT), ALICE, uint64(0), redeemed);
        bytes32 digest = a.digest(ds, hash);
        // sign and encode the sig into single bytes
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(a.privateKey()), digest);
        bytes memory sig = a.encodeSig(v, r, s);

        // mock the transferFrom rwa <-> us
        vm.mockCall(q.asset, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));
        // mock the approve rwa us <-> manager
        vm.mockCall(q.asset, abi.encodeWithSelector(APPROVE_SELECTOR), abi.encode(true));

        // mock the 2 calls to balanceOf for the receive token (inT)
        bytes[] memory mocks = new bytes[](2);
        // first call we have 0 balance
        mocks[0] = abi.encode(0);
        // this should revert as we expect at least redeemed amount to be the delta
        mocks[1] = abi.encode(redeemed - 1);
        vm.mockCalls(address(inT), abi.encodeWithSelector(BALANCE_OF_SELECTOR), mocks);

        // mock the call to imanager target, the return value is of no consequence
        vm.mockCall(ondo.manager(), abi.encodeWithSelector(REDEEM_WITH_SELECTOR), abi.encode(123));

        vm.expectRevert(abi.encodeWithSignature("InsufficientAmount()"));
        vm.prank(ALICE);
        ondo.swap(q, bytes("idc"), address(inT), redeemed, sig);
    }

    // happy path, no fee
    function testSell() public {
        Quote memory q = a.quote(block.chainid, Side.Sell);

        // the amount "redeemed" for the quote as a 6 decimal stabelcoin number
        uint256 redeemed = ((q.quantity * q.price) / 1e18) / 1e12;

        // we can facilitate the final txfer in sell by minting ourself the redeemed amt
        inT.mint(address(ondo), redeemed);

        bytes32 ds = ondo.domainSeparator();
        bytes32 hash = a.structHash(ondo.VERIFY_REQUEST(), Side.Sell, q.asset, address(inT), ALICE, uint64(0), redeemed);
        bytes32 digest = a.digest(ds, hash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(a.privateKey()), digest);
        bytes memory sig = a.encodeSig(v, r, s);

        vm.mockCall(q.asset, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));
        vm.mockCall(q.asset, abi.encodeWithSelector(APPROVE_SELECTOR), abi.encode(true));

        // mock the 2 calls to balanceOf for the receive token (inT)
        bytes[] memory mocks = new bytes[](2);
        // first call we have 0 balance
        mocks[0] = abi.encode(0);
        // second call we should have redeemed amount
        mocks[1] = abi.encode(redeemed);
        vm.mockCalls(address(inT), abi.encodeWithSelector(BALANCE_OF_SELECTOR), mocks);

        vm.mockCall(ondo.manager(), abi.encodeWithSelector(REDEEM_WITH_SELECTOR), abi.encode(123));

        // there should be 2 calls made to asset approve (q.quantity * q.price, reset)
        vm.expectCall(q.asset, abi.encodeWithSelector(APPROVE_SELECTOR, ondo.manager(), 1e20), 1);
        vm.expectCall(q.asset, abi.encodeWithSelector(APPROVE_SELECTOR, ondo.manager(), 0), 1);
        // vm.expectCall(q.asset, abi.encodeWithSelector(APPROVE_SELECTOR), 2);

        // return is the redeemed amt
        vm.prank(ALICE);
        uint256 res = ondo.swap(q, bytes("idc"), address(inT), redeemed, sig);
        assertEq(res, redeemed);

        // correct amount txfer (it's the mocks[1] amt)
        vm.clearMockedCalls();
        uint256 bal = inT.balanceOf(ALICE);
        assertEq(bal, redeemed);

        // the totals should reflect no fee
        Total memory total = ondo.totals(ALICE, q.asset, address(inT));
        assertEq(total.count, 1);
        assertEq(total.outputSum, res);
        assertEq(total.feeSum, 0);
    }

    function testSellWithFee() public {
        assert(ondo.setBps(Side.Sell, 100));

        Quote memory q = a.quote(block.chainid, Side.Sell);

        uint256 redeemed = ((q.quantity * q.price) / 1e18) / 1e12;

        // its fine to mint this amount, tho the transferred will be - fee
        inT.mint(address(ondo), redeemed);

        bytes32 ds = ondo.domainSeparator();
        bytes32 hash = a.structHash(ondo.VERIFY_REQUEST(), Side.Sell, q.asset, address(inT), ALICE, uint64(0), redeemed);
        bytes32 digest = a.digest(ds, hash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(a.privateKey()), digest);
        bytes memory sig = a.encodeSig(v, r, s);

        vm.mockCall(q.asset, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));
        vm.mockCall(q.asset, abi.encodeWithSelector(APPROVE_SELECTOR), abi.encode(true));

        // mock the 2 calls to balanceOf for the receive token (inT)
        bytes[] memory mocks = new bytes[](2);
        // first call we have 0 balance
        mocks[0] = abi.encode(0);
        // second call we should have redeemed amount
        mocks[1] = abi.encode(redeemed);
        vm.mockCalls(address(inT), abi.encodeWithSelector(BALANCE_OF_SELECTOR), mocks);

        vm.mockCall(ondo.manager(), abi.encodeWithSelector(REDEEM_WITH_SELECTOR), abi.encode(123));

        // return is the redeemed amt
        vm.prank(ALICE);
        uint256 res = ondo.swap(q, bytes("idc"), address(inT), redeemed, sig);

        // NOTE: inT.balanceOf(ALICE) would reflect the mocks[1] value, but the trace shows correct txfer

        // we can check the bps calc
        uint256 fee = ondo.bpp(Side.Sell, redeemed);
        assertEq(res, (redeemed - fee));
    }
}
