// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {TestToken, TestStable} from "shared/TestToken.sol";
import {GMock} from "./GMock.sol";
import {Side} from "swap/Types.sol";
import {Quote} from "ondo/Types.sol";

contract RedeemWithAttestation is Test {
    address public constant ALICE = 0x6060606060606060606060606060606060606060;
    TestStable usdz;
    TestToken stockz;
    GMock mock;
    Quote quote;

    function setUp() public {
        mock = new GMock("Gmock", "GMT");
        // our deposit token
        usdz = new TestStable("USDz", "USDZ");
        // USDZ 4 manager
        usdz.mint(address(mock), 3e6);
        // the ondo fund
        stockz = new TestToken("Stockz", "STKZ");
        // stockz alice has already bought
        stockz.mint(ALICE, 2e18);
        // register Alice
        assert(mock.setRegistered(ALICE, true));
        // a quote for Alice
        quote = Quote(1, 42, keccak256("userId"), address(stockz), 1e18, 2e18, 123456789, Side.Sell, keccak256("idk"));
    }

    function testRedeemRevertReceiveZero() public {
        vm.expectRevert("receive token zero");
        mock.redeemWithAttestation(quote, bytes("wtf"), address(0), 1e6);
    }

    function testRedeemRevertSide() public {
        Quote memory buy =
            Quote(1, 42, keccak256("userId"), address(stockz), 1e18, 2e18, 123456789, Side.Buy, keccak256("idk"));
        vm.expectRevert("quote side not Sell");
        mock.redeemWithAttestation(buy, bytes("wtf"), address(usdz), 1e6);
    }

    function testRedeemRevertUser() public {
        vm.expectRevert("unregistered user");
        mock.redeemWithAttestation(quote, bytes("wtf"), address(usdz), 1e6);
    }

    function testRedeemRevertQuote() public {
        assert(mock.setQuoteWillVerify(false));
        vm.expectRevert("invalid quote");
        vm.prank(ALICE);
        mock.redeemWithAttestation(quote, bytes("wtf"), address(usdz), 1e6);
    }

    function testRedeemRevertQuoteAmt() public {
        // set the min redemption higher than the quote amounts
        assert(mock.setMinRedemption(4e18));
        vm.expectRevert("quote amounts less than minimum");
        vm.prank(ALICE);
        mock.redeemWithAttestation(quote, bytes("wtf"), address(usdz), 1e6);
    }

    function testRevertRedemptionAmt() public {
        // min redeem on ondo is 98*10**16 currently
        assert(mock.setMinRedemption(98e16));
        // for this test well just approve gmock directly from alice
        vm.prank(ALICE);
        assert(stockz.approve(address(mock), 2e18));

        vm.expectRevert("redemption amount less than minimum");
        vm.prank(ALICE);
        mock.redeemWithAttestation(quote, bytes("wtf"), address(usdz), 4e20);
    }

    function testRedeemWithAttestation() public {
        assert(mock.setMinRedemption(98e16));
        // for this test well just approve gmock directly from alice
        vm.prank(ALICE);
        assert(stockz.approve(address(mock), 2e18));
        vm.prank(ALICE);
        mock.redeemWithAttestation(quote, bytes("wtf"), address(usdz), 2e6);

        // should have taken alice's stockz
        assertEq(stockz.balanceOf(ALICE), 0);
        // she should have her stable
        assertEq(usdz.balanceOf(ALICE), 2e6);
    }
}
