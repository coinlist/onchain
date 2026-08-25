// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {Ondo} from "ondo/Ondo.sol";

contract Manager {}

contract OndoDefaultState is Test {
    bytes32 public constant REQ_TYPE_HASH = 0x0cc904b971527963aceb93b8a37a552af0ad75836275b27556fef1c4763c07ac;
    address public constant ALICE = 0x6060606060606060606060606060606060606060;
    Manager man;
    Ondo swap;

    function setUp() public {
        man = new Manager();
        swap = new Ondo(keccak256("yolo"), ALICE, address(man));
    }

    function testRequestTypeHash() public {
        assertEq(swap.VERIFY_REQUEST(), REQ_TYPE_HASH);
    }
}
