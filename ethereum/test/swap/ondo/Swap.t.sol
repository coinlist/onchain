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

contract OndoSwap is Test {
    address public constant ALICE = 0x7070707070707070707070707070707070707070;

    TestStable inT;
    Manager man;
    Ondo swap;
    Assembler a;

    function setUp() public {
        inT = new TestStable("usdz", "USDZ");
        man = new Manager();
        a = new Assembler();
        // use USDZ as an approved input
        swap = new Ondo(keccak256("yolo"), ALICE, address(man), address(inT));
    }

    function testRevertVerify() public {
        uint256 amt = 2e8; // 200 USDZ
        // generate a valid signed VerifyRequest, but will not ecrecover ALICE (set above), thus revert
        Quote memory q = a.quote(block.chainid, Side.Buy);
        // assemble a signature "externally"
        bytes32 ds = swap.domainSeparator();
        bytes32 hash = a.structHash(swap.VERIFY_REQUEST(), Side.Buy, address(inT), q.asset, ALICE, uint64(0), amt);
        bytes32 digest = a.digest(ds, hash);
        // sign and encode the sig into single bytes
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(a.privateKey()), digest);
        bytes memory sig = a.encodeSig(v, r, s);

        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vm.prank(ALICE);
        uint256 minted = swap.swap(q, bytes("idc"), address(inT), amt, sig);
    }
}
