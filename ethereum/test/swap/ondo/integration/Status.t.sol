// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {TestToken, TestStable} from "shared/TestToken.sol";
import {State, SidedStatus as Status} from "shared/operable/Types.sol";
import {Side} from "swap/Types.sol";
import {Ondo} from "ondo/Ondo.sol";
import {GMock} from "../GMock.sol";

contract OndoStatus is Test {
    GMock public mock;
    Ondo public ondo;

    address public constant CL = 0x6060606060606060606060606060606060606060;
    address public constant STOCKZ = 0x7070707070707070707070707070707070707070;
    bytes32 public constant SALE_ID = keccak256("bcd-234");

    function setUp() public {
        mock = new GMock("USDMock", "USDM");
        ondo = new Ondo(SALE_ID, CL, address(mock), address(0));
    }

    function testMintingPaused() public {
        // unpaused
        Status memory s = ondo.status(STOCKZ);
        assertEq(uint8(s.buyState), uint8(State.Active));
        assertEq(uint8(s.sellState), uint8(State.Active));

        // paused at asset level
        assert(mock.setGmTokenMintingPaused(STOCKZ, true));
        s = ondo.status(STOCKZ);
        assertEq(uint8(s.buyState), uint8(State.Paused));
        // does not effect other side
        assertEq(uint8(s.sellState), uint8(State.Active));

        // unpaused
        assert(mock.setGmTokenMintingPaused(STOCKZ, false));
        s = ondo.status(STOCKZ);
        assertEq(uint8(s.buyState), uint8(State.Active));

        // paused at global level
        assert(mock.setGlobalMintingPaused(true));
        s = ondo.status(STOCKZ);
        assertEq(uint8(s.buyState), uint8(State.Paused));
        // other side
        assertEq(uint8(s.sellState), uint8(State.Active));
    }

    function testRedeemingPaused() public {
        // unpaused
        Status memory s = ondo.status(STOCKZ);
        assertEq(uint8(s.sellState), uint8(State.Active));

        // paused at asset level
        assert(mock.setGmTokenRedemptionsPaused(STOCKZ, true));
        s = ondo.status(STOCKZ);
        assertEq(uint8(s.sellState), uint8(State.Paused));
        // does not effect other side
        assertEq(uint8(s.buyState), uint8(State.Active));

        // unpaused
        assert(mock.setGmTokenRedemptionsPaused(STOCKZ, false));
        s = ondo.status(STOCKZ);
        assertEq(uint8(s.sellState), uint8(State.Active));

        // paused at global level
        assert(mock.setGlobalRedeemingPaused(true));
        s = ondo.status(STOCKZ);
        assertEq(uint8(s.sellState), uint8(State.Paused));
        // other side
        assertEq(uint8(s.buyState), uint8(State.Active));
    }

    function testInternallyPaused() public {
        // unpaused
        Status memory s = ondo.status(STOCKZ);
        assertEq(uint8(s.buyState), uint8(State.Active));
        assertEq(uint8(s.sellState), uint8(State.Active));

        // if we pause it at the Operable level..
        assert(ondo.pause(ondo.SWAP_LEVEL()));

        // either would be paused, regardless of side or asset
        s = ondo.status(STOCKZ);
        assertEq(uint8(s.buyState), uint8(State.Paused));
        assertEq(uint8(s.sellState), uint8(State.Paused));
        assert(s.flags > 0);
    }

    function testInternallyStopped() public {
        // not stopped
        Status memory s = ondo.status(STOCKZ);
        assertEq(uint8(s.buyState), uint8(State.Active));
        assertEq(uint8(s.sellState), uint8(State.Active));

        // if we stop it at the Operable level..
        assert(ondo.stop());

        // either would be stopped, regardless of side or asset
        s = ondo.status(STOCKZ);
        assertEq(uint8(s.buyState), uint8(State.Stopped));
        assertEq(uint8(s.sellState), uint8(State.Stopped));
        assert(s.flags > 0);
    }
}
