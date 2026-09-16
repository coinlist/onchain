// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {State, Status} from "shared/operable/Types.sol";
import {RPT} from "./RPT.sol";

contract RPTest is Test {
    RPT public rpt;
    address public constant SOMEONE = 0x6060606060606060606060606060606060606060;

    function setUp() public {
        rpt = new RPT();
        // the fictional other status is active at "1"
        assert(rpt.setOtherStatus(1));
    }

    function testActiveStatus() public {
        Status memory stat = rpt.status();
        assertEq(uint8(stat.state), 0);
        assertEq(uint32(stat.flags), 0);
    }

    function testPauseRevertNotOwner() public {
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vm.prank(SOMEONE);
        rpt.pause(2);
    }

    function testPause() public {
        assertEq(rpt.paused(), 0);
        assert(rpt.pause(rpt.FOO_LEVEL()));
        assertEq(rpt.paused(), rpt.FOO_LEVEL());
    }

    function testStopRevertNotOwner() public {
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vm.prank(SOMEONE);
        rpt.stop();
    }

    function testStop() public {
        assertEq(rpt.stopped(), false);
        assert(rpt.stop());
        assert(rpt.stopped());
    }

    function testSetFoo() public {
        // when not stopped or paused foo can be set
        assertEq(rpt.foo(), 0);
        assert(rpt.setFoo(42));
        assertEq(rpt.foo(), 42);

        // pause at foo level
        assert(rpt.pause(rpt.FOO_LEVEL()));

        // status reports correctly
        Status memory stat = rpt.status();
        assertEq(uint8(stat.state), 1);
        assertEq(uint32(stat.flags), rpt.FOO_LEVEL());

        // does not allow when paused
        vm.expectRevert(abi.encodeWithSignature("IsPaused(uint32)", rpt.FOO_LEVEL()));
        rpt.setFoo(99);
        assertEq(rpt.foo(), 42);

        // foo level pause does not pause bar level operation
        assertEq(rpt.bar(), 0);
        assert(rpt.setBar(67));
        assertEq(rpt.bar(), 67);

        // can be unpaused
        assert(rpt.pause(0));
        // status is correct
        stat = rpt.status();
        assertEq(uint8(stat.state), 0);
        assertEq(uint32(stat.flags), 0);

        // can now be set again
        assert(rpt.setFoo(99));
        assertEq(rpt.foo(), 99);

        // cannot be set when stopped
        assert(rpt.stop());
        vm.expectRevert(abi.encodeWithSignature("IsStopped()"));
        rpt.setFoo(13);
        assertEq(rpt.foo(), 99);

        // status updates
        stat = rpt.status();
        assertEq(uint8(stat.state), 2);
        assertEq(uint32(stat.flags), 1);
    }

    function testSetBar() public {
        // when not stopped or paused foo can be set
        assertEq(rpt.bar(), 0);
        assert(rpt.setBar(42));
        assertEq(rpt.bar(), 42);

        // pause at bar level
        assert(rpt.pause(rpt.BAR_LEVEL()));

        // does not allow when paused
        vm.expectRevert(abi.encodeWithSignature("IsPaused(uint32)", rpt.BAR_LEVEL()));
        rpt.setBar(99);
        assertEq(rpt.bar(), 42);

        // bar level pause does not pause foo level operation
        assertEq(rpt.foo(), 0);
        assert(rpt.setFoo(67));
        assertEq(rpt.foo(), 67);

        // can be unpaused
        assert(rpt.pause(0));
        // can now be set again
        assert(rpt.setBar(99));
        assertEq(rpt.bar(), 99);

        // cannot be set when stopped
        assert(rpt.stop());
        vm.expectRevert(abi.encodeWithSignature("IsStopped()"));
        rpt.setBar(13);
        assertEq(rpt.bar(), 99);
    }

    function testPauseAllViaBitmask() public {
        uint32 both = rpt.FOO_LEVEL() + rpt.BAR_LEVEL();
        assert(rpt.pause(both));
        assertEq(rpt.paused(), both);

        // since you are calling setFoo it will throw with FOO_LEVEL
        vm.expectRevert(abi.encodeWithSignature("IsPaused(uint32)", rpt.FOO_LEVEL()));
        rpt.setFoo(37);

        // now BAR_LEVEL will be thrown
        vm.expectRevert(abi.encodeWithSignature("IsPaused(uint32)", rpt.BAR_LEVEL()));
        rpt.setBar(37);

        assertEq(rpt.foo(), 0);
        assertEq(rpt.bar(), 0);
    }

    function testStatusWithOther() public {
        // 0 mapped to paused
        assert(rpt.setOtherStatus(0));
        Status memory stat = rpt.status();
        assertEq(uint8(stat.state), 1);
        // no flags means its external
        assertEq(uint32(stat.flags), 0);

        // 3 and above would be stopped
        assert(rpt.setOtherStatus(4));
        stat = rpt.status();
        assertEq(uint8(stat.state), 2);
        assertEq(uint32(stat.flags), 0);

        // "internal" settings will override
        // NOTE: we'd likely "match" them but this is strictly informative
        // and who knows ...
        assert(rpt.pause(rpt.FOO_LEVEL()));
        stat = rpt.status();
        assertEq(uint8(stat.state), 1);
        assertEq(uint32(stat.flags), rpt.FOO_LEVEL());
    }
}
