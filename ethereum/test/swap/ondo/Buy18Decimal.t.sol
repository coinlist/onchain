// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";
import {TestToken} from "shared/TestToken.sol";
import {Side, OptimizedSwapTotal as Total} from "swap/Types.sol";
import {Ondo} from "ondo/Ondo.sol";
import {Quote, VerifyRequest} from "ondo/Types.sol";
import {Assembler} from "./Assembler.sol";

// manager must be a deployed contract
contract Manager {}

contract OndoBuy18 is Test {
    address public constant ALICE = 0x7070707070707070707070707070707070707070;

    bytes4 public constant MINT_WITH_SELECTOR = bytes4(
        keccak256(
            "mintWithAttestation((uint256,uint256,bytes32,address,uint256,uint256,uint256,uint8,bytes32),bytes,address,uint256)"
        )
    );
    bytes4 public constant BALANCE_OF_SELECTOR = bytes4(keccak256("balanceOf(address)"));
    bytes4 public constant TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"));

    TestToken inT;
    Manager man;
    Ondo ondo;
    Assembler a;

    function setUp() public {
        inT = new TestToken("USDon", "USDN");
        man = new Manager();
        a = new Assembler();
        ondo = new Ondo(keccak256("justincase"), a.addr(), address(man));
        // use USDZ as an approved input
        ondo.setInputToken(address(inT), true);
    }

    function testRevertOverspend() public {
        assert(a.setQuantity(50e18));
        assert(a.setPrice(2e18));
        // Alice overpays the expected 100e18
        uint256 amt = 101e18;
        Quote memory q = a.quote(block.chainid, Side.Buy);
        // assemble a signature "externally"
        bytes32 ds = ondo.domainSeparator();
        bytes32 hash = a.structHash(ondo.VERIFY_REQUEST(), Side.Buy, address(inT), q.asset, ALICE, uint64(0), amt);
        bytes32 digest = a.digest(ds, hash);
        // sign and encode the sig into single bytes
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(a.privateKey()), digest);
        bytes memory sig = a.encodeSig(v, r, s);

        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        vm.prank(ALICE);
        uint256 minted = ondo.swap(q, bytes("idc"), address(inT), amt, sig);
    }

    function testRevertUnderMint() public {
        uint256 amt = 2e20; // 200 USDon the default quote

        // alice will need amount of USDZ
        inT.mint(ALICE, amt);
        assertEq(inT.balanceOf(ALICE), amt);

        // integration will need to be approved for it
        vm.prank(ALICE);
        inT.approve(address(ondo), amt);
        assertEq(inT.allowance(ALICE, address(ondo)), amt);

        Quote memory q = a.quote(block.chainid, Side.Buy);
        // assemble a signature "externally"
        bytes32 ds = ondo.domainSeparator();
        bytes32 hash = a.structHash(ondo.VERIFY_REQUEST(), Side.Buy, address(inT), q.asset, ALICE, uint64(0), amt);
        bytes32 digest = a.digest(ds, hash);
        // sign and encode the sig into single bytes
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(a.privateKey()), digest);
        bytes memory sig = a.encodeSig(v, r, s);

        // mock the 2 calls to balanceOf such that we get minted less than expected
        bytes[] memory mocks = new bytes[](2);
        // first call we have 0 balance
        mocks[0] = abi.encode(0);
        // second call will report UNDER the quote.quantity of 100e18
        mocks[1] = abi.encode(50e18);
        vm.mockCalls(q.asset, abi.encodeWithSelector(BALANCE_OF_SELECTOR), mocks);

        // mock the call to imanager target
        vm.mockCall(ondo.manager(), abi.encodeWithSelector(MINT_WITH_SELECTOR), abi.encode(q.quantity));

        vm.expectRevert(abi.encodeWithSignature("InsufficientAmount()"));
        vm.prank(ALICE);
        ondo.swap(q, bytes("idc"), address(inT), amt, sig);
    }

    // happy path, no fee
    function testBuy() public {
        uint256 amt = 2e20;

        inT.mint(ALICE, amt);
        assertEq(inT.balanceOf(ALICE), amt);

        // integration will need to be approved for it
        vm.prank(ALICE);
        inT.approve(address(ondo), amt);
        assertEq(inT.allowance(ALICE, address(ondo)), amt);

        Quote memory q = a.quote(block.chainid, Side.Buy);
        // assemble a signature "externally"
        bytes32 ds = ondo.domainSeparator();
        bytes32 hash = a.structHash(ondo.VERIFY_REQUEST(), Side.Buy, address(inT), q.asset, ALICE, uint64(0), amt);
        bytes32 digest = a.digest(ds, hash);
        // sign and encode the sig into single bytes
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(a.privateKey()), digest);
        bytes memory sig = a.encodeSig(v, r, s);

        // mock the 2 calls to balanceOf for quote.asset
        bytes[] memory mocks = new bytes[](2);
        // first call we have 0 balance
        mocks[0] = abi.encode(0);
        // second call we should have quote.quantity
        mocks[1] = abi.encode(q.quantity);
        vm.mockCalls(q.asset, abi.encodeWithSelector(BALANCE_OF_SELECTOR), mocks);

        // mock the call to imanager target
        vm.mockCall(ondo.manager(), abi.encodeWithSelector(MINT_WITH_SELECTOR), abi.encode(q.quantity));

        // returns delta of the two balance of calls, will be quote.quantity in this case
        vm.prank(ALICE);
        uint256 minted = ondo.swap(q, bytes("idc"), address(inT), amt, sig);
        assertEq(minted, q.quantity);
        Total memory total = ondo.totals(ALICE, address(inT), q.asset);
        assertEq(total.count, 1);
        assertEq(total.outputSum, minted);
        assertEq(total.feeSum, 0);
    }

    // happy path, fee of 1%
    function testBuyWithFee() public {
        assert(ondo.setBps(Side.Buy, 100));

        uint256 amt = 1e20; // 100 USDon
        // alice will need amount of USDZ
        inT.mint(ALICE, amt);
        assertEq(inT.balanceOf(ALICE), amt);

        // integration will need to be approved for it
        vm.prank(ALICE);
        inT.approve(address(ondo), amt);
        assertEq(inT.allowance(ALICE, address(ondo)), amt);

        // set the quote to match a "fee aware" example
        // fee would come back as 990100...
        (, uint256 input) = ondo.fee(Side.Buy, amt);
        assertEq(input, 99009900990099009900); // amount that will be compared for overage

        // so if we wanted 100 whatevers we'd have
        // (price * quantity) / 1e18 = input
        // i.e -> (990099e12 * 100e18) / 1e18 == 99099...;

        // alice gets 100
        assert(a.setQuantity(amt));
        // priced at..
        assert(a.setPrice(990099e12));
        Quote memory q = a.quote(block.chainid, Side.Buy);

        // bytes32 ds = ondo.domainSeparator();
        bytes32 hash = a.structHash(ondo.VERIFY_REQUEST(), Side.Buy, address(inT), q.asset, ALICE, uint64(0), amt);
        bytes32 digest = a.digest(ondo.domainSeparator(), hash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(a.privateKey()), digest);
        bytes memory sig = a.encodeSig(v, r, s);

        bytes[] memory mocks = new bytes[](2);
        mocks[0] = abi.encode(0);
        mocks[1] = abi.encode(q.quantity);
        vm.mockCalls(q.asset, abi.encodeWithSelector(BALANCE_OF_SELECTOR), mocks);

        vm.mockCall(ondo.manager(), abi.encodeWithSelector(MINT_WITH_SELECTOR), abi.encode(q.quantity));

        vm.prank(ALICE);
        uint256 minted = ondo.swap(q, bytes("idc"), address(inT), amt, sig);
        assertEq(minted, q.quantity);

        // totals will reflect fee
        Total memory total = ondo.totals(ALICE, address(inT), q.asset);
        assertEq(total.count, 1);
        assertEq(total.inputSum, input);
        assertEq(total.outputSum, minted);
        assertEq(total.feeSum, 990099009900990100);
    }
}
