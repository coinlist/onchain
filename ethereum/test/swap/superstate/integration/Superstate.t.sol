// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {TestToken} from "shared/TestToken.sol";
import {Status, State} from "shared/operable/Types.sol";
import {Preview} from "swap/Types.sol";
import {Superstate as SS} from "superstate/Superstate.sol";
import {MarketState} from "superstate/Types.sol";
import {MockTheDip} from "../MockTheDip.sol";

contract SuperState is Test {
    TestToken public inT;
    MockTheDip public mock;
    SS public ss;

    address public constant ALICE = 0x6060606060606060606060606060606060606060;
    address public constant BOB = 0x7070707070707070707070707070707070707070;
    bytes32 public constant MKT_ID = keccak256("abc-123");
    bytes32 public constant SALE_ID = keccak256("bcd-234");

    function setUp() public {
        inT = new TestToken("InToken", "INTKN");
        mock = new MockTheDip("outToken", "OUTKN");
        ss = new SS(address(mock), MKT_ID, SALE_ID);
        ss.setInputToken(address(inT), true);
    }

    function testMarketId() public {
        assertEq(ss.marketId(), MKT_ID);
    }

    function testDecimals() public {
        assertEq(mock.decimals(), 6);
    }

    function testDipContract() public {
        // just returns itself
        assertEq(mock.dipContract(), address(mock));
    }

    function testMockAddr() public {
        assertEq(ss.outputToken(), address(mock));
    }

    function testCalculatedOutput() public {
        // is 1e6 by default
        assertEq(mock.calculatedOutput(), 1000000);
        // can be set
        assert(mock.setCalculatedOutput(2000000));
        assertEq(mock.calculatedOutput(), 2000000);
    }

    function testCalculatedInput() public {
        // is 0 by default
        assertEq(mock.calculatedInput(), 0);
        // can be set
        assert(mock.setCalculatedInput(100));
        assertEq(mock.calculatedInput(), 100);
    }

    function testPreview() public {
        // will return what is passed as spent by default, along with set calculatedAmount
        Preview memory pre = ss.preview(address(inT), 100);
        assertEq(pre.input, 100);
        assertEq(pre.output, 1000000);
        assertEq(pre.fee, 0);

        // with set input, will return that vs passed in amt
        assert(mock.setCalculatedInput(500));
        pre = ss.preview(address(inT), 1000);
        assertEq(pre.input, 500);
    }

    function testWhitelist() public {
        // alice is not by default
        assertEq(ss.authorized(ALICE), false);

        // allow
        assert(mock.whitelist(ALICE, true));
        assert(ss.authorized(ALICE));

        // disallow
        assert(mock.whitelist(ALICE, false));
        assertEq(ss.authorized(ALICE), false);
    }

    function testRevertState() public {
        // is false by default
        assertEq(mock.shouldRevert(), false);
        // can be set
        assert(mock.setShouldRevert(true));
        assert(mock.shouldRevert());
        // calculateAmount will now revert
        vm.expectRevert(abi.encodeWithSelector(bytes4(0x08c379a0), "womp womp"));
        ss.preview(address(inT), 100);
    }

    function testMarketState() public {
        // set the market into the mapping
        assert(mock.setMarket(ss.marketId(), MarketState.Initialized));
        // will be paused as ss hasn't started this market yet..
        Status memory stat = ss.status();
        assertEq(uint8(stat.state), 1);
        assertEq(uint32(stat.flags), 0);

        // once active ours will correct
        assert(mock.setMarket(ss.marketId(), MarketState.Active));
        stat = ss.status();
        assertEq(uint8(stat.state), 0);
    }

    function testRevertBuyTheDipUnauthorized() public {
        // alice would need balance of input token
        inT.mint(ALICE, 200000000);

        // alice must approve the ss contract
        vm.prank(ALICE);
        assert(inT.approve(address(ss), 100000000));

        // minus a whitelisting step for the ss contract here, it should revert
        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(ALICE);
        ss.swap(address(inT), 100000000, 100);
    }

    function testBuyTheDip() public {
        // alice needs balance of input token
        inT.mint(ALICE, 200000000);
        assertEq(inT.balanceOf(ALICE), 200000000);

        // alice must approve the ss contract
        vm.prank(ALICE);
        assert(inT.approve(address(ss), 100000000));
        assertEq(inT.allowance(ALICE, address(ss)), 100000000);

        // atm the mock output token has no input token balance
        assertEq(inT.balanceOf(address(mock)), 0);

        // ss contract must be whitelisted
        assert(mock.whitelist(address(ss), true));
        assert(ss.authorized(address(ss)));

        // alice must be whitelisted
        assert(mock.whitelist(ALICE, true));
        assert(ss.authorized(ALICE));

        vm.prank(ALICE);
        uint256 minted = ss.swap(address(inT), 100000000, 100);
        // will mint the default calculatedAmount
        assertEq(minted, 1000000);
    }

    // changing calc amount will result in that being the delta
    function testBuyTheDipCalculated() public {
        // alice needs balance of input token
        inT.mint(ALICE, 200000000);
        assertEq(inT.balanceOf(ALICE), 200000000);

        // alice must approve the ss contract
        vm.prank(ALICE);
        assert(inT.approve(address(ss), 100000000));
        assertEq(inT.allowance(ALICE, address(ss)), 100000000);

        // atm the mock output token has no input token balance
        assertEq(inT.balanceOf(address(mock)), 0);

        // ss contract must be whitelisted
        assert(mock.whitelist(address(ss), true));

        // and alice...
        assert(mock.whitelist(ALICE, true));

        // this should then be the reported mint amount
        assert(mock.setCalculatedOutput(6767));

        vm.prank(ALICE);
        uint256 minted = ss.swap(address(inT), 100000000, 100);
        // will mint the default calculatedAmount
        assertEq(minted, 6767);
    }
}
