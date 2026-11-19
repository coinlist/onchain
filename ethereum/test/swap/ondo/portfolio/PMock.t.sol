// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {TestToken, TestStable} from "shared/TestToken.sol";
import {PMock} from "../PMock.sol";
import {Side} from "swap/Types.sol";
import {Quote} from "ondo/Types.sol";

/// @dev the mock manager's own invariants, so integration failures can be trusted to be ours
contract PMockTest is Test {
    address public constant ALICE = 0x6060606060606060606060606060606060606060;
    TestStable usdz;
    TestToken stockz;
    PMock mock;
    Quote quote;

    function setUp() public {
        usdz = new TestStable("USDz", "USDZ");
        stockz = new TestToken("Stockz", "STKZ");
        mock = new PMock(address(usdz));
        assert(usdz.mint(ALICE, 3e6));
        mock.setRegistered(ALICE, true);
        quote = Quote(1, 42, keccak256("userId"), address(stockz), 1e18, 2e18, 123456789, Side.Buy, keccak256("idk"));
    }

    function testRevertSide() public {
        vm.expectRevert("quote side not Buy");
        vm.prank(ALICE);
        mock.mintWithAttestation(_side(Side.Sell), bytes("x"));

        vm.expectRevert("quote side not Sell");
        vm.prank(ALICE);
        mock.redeemWithAttestation(_side(Side.Buy), bytes("x"));
    }

    function testRevertUnregistered() public {
        vm.expectRevert("unregistered user");
        mock.mintWithAttestation(quote, bytes("x"));
        vm.expectRevert("unregistered user");
        mock.redeemWithAttestation(_side(Side.Sell), bytes("x"));
    }

    function testRevertQuote() public {
        mock.setQuoteWillVerify(false);
        vm.expectRevert("invalid quote");
        vm.prank(ALICE);
        mock.mintWithAttestation(quote, bytes("x"));
        vm.expectRevert("invalid quote");
        vm.prank(ALICE);
        mock.redeemWithAttestation(_side(Side.Sell), bytes("x"));
    }

    function testRevertMinimum() public {
        mock.setMinDeposit(10e18);
        mock.setMinRedemption(10e18);
        vm.expectRevert("quote amounts less than minimum");
        vm.prank(ALICE);
        mock.mintWithAttestation(quote, bytes("x"));
        vm.expectRevert("quote amounts less than minimum");
        vm.prank(ALICE);
        mock.redeemWithAttestation(_side(Side.Sell), bytes("x"));
    }

    function _side(Side side) internal view returns (Quote memory q) {
        q = quote;
        q.side = side;
    }
}
