// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {TestToken, TestStable} from "shared/TestToken.sol";
import {GMock} from "./GMock.sol";
import {Side} from "swap/Types.sol";
import {Quote} from "ondo/Types.sol";

contract MintWithAttestation is Test {
    address public constant ALICE = 0x6060606060606060606060606060606060606060;
    TestStable usdz;
    TestToken stockz;
    GMock mock;
    Quote quote;

    function setUp() public {
        // our deposit token
        usdz = new TestStable("USDz", "USDZ");
        // USDZ 4 Alice
        usdz.mint(ALICE, 3e6);
        // the ondo fund
        stockz = new TestToken("Stockz", "STKZ");
        mock = new GMock("Gmock", "GMT");
        // register Alice
        assert(mock.setRegistered(ALICE, true));
        // a quote for Alice
        quote = Quote(1, 42, keccak256("userId"), address(stockz), 1e18, 2e18, 123456789, Side.Buy, keccak256("idk"));
    }

    function testMintRevertDepositZero() public {
        vm.expectRevert("deposit token zero");
        mock.mintWithAttestation(quote, bytes("wtf"), address(0), 1e6);
    }

    function testMintRevertSide() public {
        Quote memory sell =
            Quote(1, 42, keccak256("userId"), address(stockz), 1e18, 2e18, 123456789, Side.Sell, keccak256("idk"));
        vm.expectRevert("quote side not Buy");
        mock.mintWithAttestation(sell, bytes("wtf"), address(usdz), 1e6);
    }

    function testMintRevertUser() public {
        vm.expectRevert("unregistered user");
        mock.mintWithAttestation(quote, bytes("wtf"), address(usdz), 1e6);
    }

    function testMintRevertQuote() public {
        assert(mock.setQuoteWillVerify(false));
        vm.expectRevert("invalid quote");
        vm.prank(ALICE);
        mock.mintWithAttestation(quote, bytes("wtf"), address(usdz), 1e6);
    }

    function testMintRevertQuoteAmt() public {
        // set the min Deposit higher than the quote amounts
        assert(mock.setMinDeposit(4e18));
        vm.expectRevert("quote amounts less than minimum");
        vm.prank(ALICE);
        mock.mintWithAttestation(quote, bytes("wtf"), address(usdz), 1e6);
    }

    function testRevertDepositAmt() public {
        // min deposit on ondo looks to be 98*10**16 atm
        assert(mock.setMinDeposit(98e16));
        // for this test well just approve gmock directly from alice
        vm.prank(ALICE);
        assert(usdz.approve(address(mock), 2e6));

        vm.expectRevert("deposit amount less than minimum");
        vm.prank(ALICE);
        mock.mintWithAttestation(quote, bytes("wtf"), address(usdz), 100);
    }

    function testMintWithAttestation() public {
        assert(mock.setMinDeposit(1e18));
        // for this test well just approve gmock directly from alice
        vm.prank(ALICE);
        assert(usdz.approve(address(mock), 2e6));

        vm.prank(ALICE);
        // the deposit amount should be denoted in that token's decimals
        mock.mintWithAttestation(quote, bytes("wtf"), address(usdz), 2e6);

        // should have taken alice's usdz
        assertEq(usdz.balanceOf(ALICE), 1e6);
        // should result in 2e18 stockz minted to alice, with no "refund"
        assertEq(stockz.balanceOf(ALICE), 2e18);
        // should not be any gmock minted to caller
        assertEq(mock.balanceOf(ALICE), 0);
    }

    function testMintWithAttestationOverpay() public {
        assert(mock.setMinDeposit(1e18));
        // for this test well just approve gmock directly from alice
        vm.prank(ALICE);
        assert(usdz.approve(address(mock), 3e6));

        vm.prank(ALICE);
        // the deposit amount should be denoted in that token's decimals
        mock.mintWithAttestation(quote, bytes("wtf"), address(usdz), 3e6);

        // should have taken all of alice's usdz
        assertEq(usdz.balanceOf(ALICE), 0);
        // should result in 2e18 stockz minted to alice
        assertEq(stockz.balanceOf(ALICE), 2e18);
        // and an overpayment of 1e18 minted to caller
        assertEq(mock.balanceOf(ALICE), 1e18);
    }
}
