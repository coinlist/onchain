// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {IOperable} from "shared/operable/IOperable.sol";
import {State, Status} from "shared/operable/Types.sol";
import {OPT} from "./OPT.sol";

contract OPTest is Test {
    OPT public op;
    address public constant SOMEONE = 0x6060606060606060606060606060606060606060;

    function setUp() public {
        op = new OPT();
        // the fictional other status is active at "1"
        assert(op.setOtherStatus(1));
    }

    function testActiveStatus() public {
        Status memory stat = op.status();
        assertEq(uint8(stat.state), 0);
        assertEq(uint32(stat.flags), 0);
    }

    function testPauseRevertNotOwner() public {
        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(SOMEONE);
        op.pause(2);
    }

    function testPause() public {
        assertEq(op.paused(), 0);
        assert(op.pause(op.FOO_LEVEL()));
        assertEq(op.paused(), op.FOO_LEVEL());
    }

    function testStopRevertNotOwner() public {
        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(SOMEONE);
        op.stop();
    }

    function testStop() public {
        assertEq(op.stopped(), false);
        assert(op.stop());
        assert(op.stopped());
    }

    function testSetFoo() public {
        // when not stopped or paused foo can be set
        assertEq(op.foo(), 0);
        assert(op.setFoo(42));
        assertEq(op.foo(), 42);

        // pause at foo level
        assert(op.pause(op.FOO_LEVEL()));

        // status reports correctly
        Status memory stat = op.status();
        assertEq(uint8(stat.state), 1);
        assertEq(uint32(stat.flags), op.FOO_LEVEL());

        // does not allow when paused
        vm.expectRevert(abi.encodeWithSelector(IOperable.IsPaused.selector, op.FOO_LEVEL()));
        op.setFoo(99);
        assertEq(op.foo(), 42);

        // foo level pause does not pause bar level operation
        assertEq(op.bar(), 0);
        assert(op.setBar(67));
        assertEq(op.bar(), 67);

        // can be unpaused
        assert(op.pause(0));
        // status is correct
        stat = op.status();
        assertEq(uint8(stat.state), 0);
        assertEq(uint32(stat.flags), 0);

        // can now be set again
        assert(op.setFoo(99));
        assertEq(op.foo(), 99);

        // cannot be set when stopped
        assert(op.stop());
        vm.expectRevert(IOperable.IsStopped.selector);
        op.setFoo(13);
        assertEq(op.foo(), 99);

        // status updates
        stat = op.status();
        assertEq(uint8(stat.state), 2);
        assertEq(uint32(stat.flags), 1);
    }

    function testSetBar() public {
        // when not stopped or paused foo can be set
        assertEq(op.bar(), 0);
        assert(op.setBar(42));
        assertEq(op.bar(), 42);

        // pause at bar level
        assert(op.pause(op.BAR_LEVEL()));

        // does not allow when paused
        vm.expectRevert(abi.encodeWithSelector(IOperable.IsPaused.selector, op.BAR_LEVEL()));
        op.setBar(99);
        assertEq(op.bar(), 42);

        // bar level pause does not pause foo level operation
        assertEq(op.foo(), 0);
        assert(op.setFoo(67));
        assertEq(op.foo(), 67);

        // can be unpaused
        assert(op.pause(0));
        // can now be set again
        assert(op.setBar(99));
        assertEq(op.bar(), 99);

        // cannot be set when stopped
        assert(op.stop());
        vm.expectRevert(IOperable.IsStopped.selector);
        op.setBar(13);
        assertEq(op.bar(), 99);
    }

    function testPauseAllViaBitmask() public {
        uint32 both = op.FOO_LEVEL() + op.BAR_LEVEL();
        assert(op.pause(both));
        assertEq(op.paused(), both);

        // since you are calling setFoo it will throw with FOO_LEVEL
        vm.expectRevert(abi.encodeWithSelector(IOperable.IsPaused.selector, op.FOO_LEVEL()));
        op.setFoo(37);

        // now BAR_LEVEL will be thrown
        vm.expectRevert(abi.encodeWithSelector(IOperable.IsPaused.selector, op.BAR_LEVEL()));
        op.setBar(37);

        assertEq(op.foo(), 0);
        assertEq(op.bar(), 0);
    }

    function testStatusWithOther() public {
        // 0 mapped to paused
        assert(op.setOtherStatus(0));
        Status memory stat = op.status();
        assertEq(uint8(stat.state), 1);
        // no flags means its external
        assertEq(uint32(stat.flags), 0);

        // 3 and above would be stopped
        assert(op.setOtherStatus(4));
        stat = op.status();
        assertEq(uint8(stat.state), 2);
        assertEq(uint32(stat.flags), 0);

        // "internal" settings will override
        // NOTE: we'd likely "match" them but this is strictly informative
        // and who knows ...
        assert(op.pause(op.FOO_LEVEL()));
        stat = op.status();
        assertEq(uint8(stat.state), 1);
        assertEq(uint32(stat.flags), op.FOO_LEVEL());
    }
}
