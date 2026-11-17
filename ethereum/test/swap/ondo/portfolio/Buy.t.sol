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

contract OndoPortfolioBuy is Test {
    address public constant ALICE = 0x7070707070707070707070707070707070707070;

    bytes4 public constant MINT_WITH_SELECTOR = bytes4(
        keccak256("mintWithAttestation((uint256,uint256,bytes32,address,uint256,uint256,uint256,uint8,bytes32),bytes)")
    );
    bytes4 public constant STABLECOIN_SELECTOR = bytes4(keccak256("stablecoin()"));
    bytes4 public constant BALANCE_OF_SELECTOR = bytes4(keccak256("balanceOf(address)"));
    bytes4 public constant TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"));

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

        // alice has funds and has approved the integration
        inT.mint(ALICE, 3e8);
        vm.prank(ALICE);
        inT.approve(address(ondo), 3e8);
    }

    function _sig(Quote memory q, uint64 nonce, uint256 amt) internal view returns (bytes memory) {
        bytes32 hash =
            a.structHash(ondo.VERIFY_REQUEST(), Side.Buy, address(inT), q.asset, ALICE, ATTRIBUTION, nonce, amt);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(a.privateKey()), a.digest(ondo.domainSeparator(), hash));
        return a.encodeSig(v, r, s);
    }

    function _mockMinted(Quote memory q, uint256 minted) internal {
        bytes[] memory mocks = new bytes[](2);
        mocks[0] = abi.encode(0);
        mocks[1] = abi.encode(minted);
        vm.mockCalls(q.asset, abi.encodeWithSelector(BALANCE_OF_SELECTOR), mocks);
        vm.mockCall(q.asset, abi.encodeWithSelector(TRANSFER_SELECTOR), abi.encode(true));
        vm.mockCall(ondo.manager(), abi.encodeWithSelector(MINT_WITH_SELECTOR), abi.encode(minted));
    }

    function testRevertUnderpay() public {
        // default quote costs 200e6, alice sends 199e6
        Quote memory q = a.quote(block.chainid, Side.Buy);
        bytes memory sig = _sig(q, 0, 199e6);
        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        vm.prank(ALICE);
        ondo.swap(q, bytes("idc"), address(inT), 199e6, ATTRIBUTION, sig);
    }

    function testRevertOverspend() public {
        Quote memory q = a.quote(block.chainid, Side.Buy);
        bytes memory sig = _sig(q, 0, 201e6);
        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        vm.prank(ALICE);
        ondo.swap(q, bytes("idc"), address(inT), 201e6, ATTRIBUTION, sig);
    }

    function testRevertUnderMint() public {
        Quote memory q = a.quote(block.chainid, Side.Buy);
        bytes memory sig = _sig(q, 0, 200e6);
        // manager "mints" less than the quote quantity
        _mockMinted(q, 50e18);
        vm.expectRevert(abi.encodeWithSignature("InsufficientAmount()"));
        vm.prank(ALICE);
        ondo.swap(q, bytes("idc"), address(inT), 200e6, ATTRIBUTION, sig);
    }

    function testBuy() public {
        Quote memory q = a.quote(block.chainid, Side.Buy);
        bytes memory sig = _sig(q, 0, 200e6);
        _mockMinted(q, q.quantity);

        vm.expectEmit(true, true, true, true, address(ondo));
        emit ISoms.Swapped(ALICE, q.asset, address(inT), ATTRIBUTION, q.attestationId, Side.Buy, q.quantity, 0, 200e6);

        // the manager is approved exactly the cost, then reset
        vm.expectCall(address(inT), abi.encodeCall(inT.approve, (ondo.manager(), 200e6)), 1);
        vm.expectCall(address(inT), abi.encodeCall(inT.approve, (ondo.manager(), 0)), 1);
        // the 2 argument mint
        vm.expectCall(ondo.manager(), abi.encodeWithSelector(MINT_WITH_SELECTOR), 1);

        vm.prank(ALICE);
        uint256 minted = ondo.swap(q, bytes("idc"), address(inT), 200e6, ATTRIBUTION, sig);
        assertEq(minted, q.quantity);

        Total memory t = ondo.totals(ALICE, address(inT), q.asset);
        assertEq(t.count, 1);
        assertEq(t.inputSum, 200e6);
        assertEq(t.outputSum, minted);
        assertEq(t.feeSum, 0);
    }

    function testBuyWithFee() public {
        assert(ondo.setBps(Side.Buy, 100));
        (uint256 fee, uint256 input) = ondo.fee(Side.Buy, 100e6);
        assertEq(input, 99009900);

        // fee aware quote: 100 at 0.990099 each
        assert(a.setQuantity(100e18));
        assert(a.setPrice(990099e12));
        Quote memory q = a.quote(block.chainid, Side.Buy);
        bytes memory sig = _sig(q, 0, 100e6);
        _mockMinted(q, q.quantity);

        // cost is 99009900, the fee never reaches the manager
        vm.expectCall(address(inT), abi.encodeCall(inT.approve, (ondo.manager(), 99009900)), 1);

        vm.prank(ALICE);
        ondo.swap(q, bytes("idc"), address(inT), 100e6, ATTRIBUTION, sig);

        Total memory t = ondo.totals(ALICE, address(inT), q.asset);
        assertEq(t.feeSum, fee);
        assertEq(t.inputSum, input);
        assertEq(inT.balanceOf(address(ondo)), 100e6);
    }
}
