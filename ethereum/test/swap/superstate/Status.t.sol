// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {TestToken} from "shared/TestToken.sol";
import {State, Status} from "shared/operable/Types.sol";
import {Superstate} from "superstate/Superstate.sol";
import {Market, MarketState} from "superstate/Types.sol";

contract StatusTest is Test {
    TestToken public inT;
    // we'll just stub the ss specific calls in this test
    TestToken public outT;
    Superstate public ss;

    bytes32 public constant MKT_ID = keccak256("abc-123");
    bytes32 public constant SALE_ID = keccak256("bcd-234");

    address private constant DIP_CONTRACT = 0x7070707070707070707070707070707070707070;
    bytes4 public constant DIP_CONTRACT_SELECTOR = bytes4(keccak256("dipContract()"));
    bytes4 public constant MARKETS_SELECTOR = bytes4(keccak256("markets(bytes32)"));

    function setUp() public {
        inT = new TestToken("InToken", "INTKN");
        outT = new TestToken("outToken", "OUTKN");
        ss = new Superstate(address(outT), MKT_ID, SALE_ID);
    }

    function testStatus() public {
        vm.mockCall(address(outT), abi.encodeWithSelector(DIP_CONTRACT_SELECTOR), abi.encode(DIP_CONTRACT));
        // initialized by default
        Market memory mkt;
        vm.mockCall(DIP_CONTRACT, abi.encodeWithSelector(MARKETS_SELECTOR, MKT_ID), abi.encode(mkt));

        // initialized
        Status memory stat = ss.status();
        assertEq(uint8(stat.state), uint8(State.Paused));

        // paused
        mkt.state = MarketState.Paused;
        vm.mockCall(DIP_CONTRACT, abi.encodeWithSelector(MARKETS_SELECTOR, MKT_ID), abi.encode(mkt));
        stat = ss.status();
        assertEq(uint8(stat.state), uint8(State.Paused));

        // active
        mkt.state = MarketState.Active;
        vm.mockCall(DIP_CONTRACT, abi.encodeWithSelector(MARKETS_SELECTOR, MKT_ID), abi.encode(mkt));
        stat = ss.status();
        assertEq(uint8(stat.state), uint8(State.Active));

        // closed
        mkt.state = MarketState.Closed;
        vm.mockCall(DIP_CONTRACT, abi.encodeWithSelector(MARKETS_SELECTOR, MKT_ID), abi.encode(mkt));
        stat = ss.status();
        assertEq(uint8(stat.state), uint8(State.Stopped));

        // cancelled
        mkt.state = MarketState.Cancelled;
        vm.mockCall(DIP_CONTRACT, abi.encodeWithSelector(MARKETS_SELECTOR, MKT_ID), abi.encode(mkt));
        stat = ss.status();
        assertEq(uint8(stat.state), uint8(State.Stopped));

        // setting any non active state on our own contract would take precedence
        assert(ss.pause(ss.SWAP_LEVEL()));
        stat = ss.status();
        assertEq(uint8(stat.state), uint8(State.Paused));
    }
}
