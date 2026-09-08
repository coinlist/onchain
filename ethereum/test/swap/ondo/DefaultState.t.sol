// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {Ondo} from "ondo/Ondo.sol";
import {State, Status} from "shared/operable/Types.sol";

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

    function testNotPaused() public {
        assertEq(swap.paused(), 0);
        Status memory s = swap.status();
        assertEq(uint8(s.state), uint8(State.Active));
        assertEq(s.flags, uint32(0));
    }

    function testRevertPause() public {
        vm.expectRevert(4);
        // should only accept 0 (unpause) and honored SWAP_LEVEL values
        swap.pause(1);
        // NOTE a decimal value of 3 would pass and behave as expected
        swap.pause(4);
        swap.pause(5);
        swap.pause(8);
    }

    function testPause() public {
        assertEq(swap.paused(), 0);
        assert(swap.pause(swap.SWAP_LEVEL()));
        assertEq(swap.paused(), swap.SWAP_LEVEL());
        Status memory s = swap.status();
        assertEq(uint8(s.state), uint8(State.Paused));
        // we use flags as an indication that WE have caused the status
        assertEq(s.flags, swap.SWAP_LEVEL());

        // can be unpaused
        assert(swap.pause(0));
        s = swap.status();
        assertEq(uint8(s.state), uint8(State.Active));
        assertEq(s.flags, uint32(0));
    }
}
