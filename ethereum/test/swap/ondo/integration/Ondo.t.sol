// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {TestToken, TestStable} from "shared/TestToken.sol";
import {Side, OptimizedSwapTotal as Total} from "swap/Types.sol";
import {Ondo} from "ondo/Ondo.sol";
import {Quote, VerifyRequest} from "ondo/Types.sol";
import {GMock} from "../GMock.sol";
import {Assembler} from "../Assembler.sol";

/// @notice buy and sell sides with and without fee
contract OndoIntegration is Test {
    TestToken public stockz;
    TestStable public usdz;
    GMock public mock;
    Ondo public ondo;
    Assembler a;

    address public constant ALICE = 0x6060606060606060606060606060606060606060;
    bytes32 public constant SALE_ID = keccak256("bcd-234");
    uint256 public constant MINZ = 98 * 1e16; // from current ondo GMTokenManager mainnet deploy

    function setUp() public {
        stockz = new TestToken("Stockz", "STKZ");
        usdz = new TestStable("Usdz", "USDZ");

        // Alice and Bob both get usdz
        assert(usdz.mint(ALICE, 100e6));

        mock = new GMock("USDMock", "USDM");
        assert(mock.setMinDeposit(MINZ));
        assert(mock.setMinRedemption(MINZ));

        a = new Assembler();
        // any quote is for stockz as an asset
        assert(a.setRwa(address(stockz)));

        ondo = new Ondo(SALE_ID, a.addr(), address(mock), address(usdz));

        // Alice approves ondo to pull funds
        vm.prank(ALICE);
        // half..
        assert(usdz.approve(address(ondo), 50e6));

        // set ondo as registered with the mock
        assert(mock.setRegistered(address(ondo), true));
    }

    function testRegistered() public {
        assert(mock.registered(address(ondo)));
    }

    function testBuyAndSell() public {
        // ******************** BUY NO FEE ***********************************************************************************

        // alice gets 10 stockz
        a.setQuantity(10e18);
        // priced at 5 ea
        a.setPrice(5e18);
        // NOTE all quotes are in 18 decimal format
        Quote memory q = a.quote(block.chainid, Side.Buy);

        // mimic the backend signature, alice nonce will be 0 here, payment amount is in 6 decimal USD* format
        bytes32 hash = a.structHash(ondo.VERIFY_REQUEST(), Side.Buy, address(usdz), q.asset, ALICE, uint64(0), 50e6);
        bytes32 digest = a.digest(ondo.domainSeparator(), hash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(a.privateKey()), digest);
        bytes memory sig = a.encodeSig(v, r, s);

        vm.prank(ALICE);
        // alice spending 50usdz to get 10stockz
        uint256 res = ondo.swap(q, bytes("doit"), address(usdz), 50e6, sig);
        // note that minted amount is in 18 decimal format, and should be quantity in this case
        assertEq(res, q.quantity);
        // that amount should be her balance at the rwa token
        assertEq(stockz.balanceOf(ALICE), res);
        // we should have pulled her sent amount, and it should have been pulled by ondo
        assertEq(usdz.balanceOf(ALICE), 50e6);
        assertEq(usdz.balanceOf(address(ondo)), 0);
        assertEq(usdz.balanceOf(address(mock)), 50e6);
        // check her contract Total storage
        Total memory t = ondo.totals(ALICE, address(usdz), address(stockz));
        assertEq(t.count, 1);
        assertEq(t.feeSum, 0);
        // note that input sums are in the format of the token itself (i.e the amount passed to swap)
        assertEq(t.inputSum, 50e6);
        assertEq(t.outputSum, res);

        // ******************** SELL NO FEE **********************************************************************************

        // alice sells her 10 stockz, no need to set quantity again
        // priced at 6 ea
        a.setPrice(6e18);
        q = a.quote(block.chainid, Side.Sell);

        // the mock's stable liquidity pool will have had to increase to cover her profit
        assert(usdz.mint(address(mock), 10e6));

        // alice nonce (count) will be 0 here, amount sell side represents a slippage floor
        hash = a.structHash(ondo.VERIFY_REQUEST(), Side.Sell, q.asset, address(usdz), ALICE, uint64(0), 59e6);
        digest = a.digest(ondo.domainSeparator(), hash);
        (v, r, s) = vm.sign(uint256(a.privateKey()), digest);
        sig = a.encodeSig(v, r, s);

        // alice needs to approve ondo contract to pull her stockz
        vm.prank(ALICE);
        assert(stockz.approve(address(ondo), q.quantity));

        vm.prank(ALICE);
        // alice spending 10stockz to get 60usdz
        res = ondo.swap(q, bytes("doitagain"), address(usdz), 59e6, sig);
        // note that result here is in the decimal format of the token
        assertEq(res, (((q.quantity * q.price) / 1e18) / 1e12)); // 18 decimal val to 6
        // alice will now be up 10 usdz from her initial balance
        assertEq(usdz.balanceOf(ALICE), 110e6);
        // stockz are gone
        assertEq(stockz.balanceOf(ALICE), 0);

        t = ondo.totals(ALICE, address(stockz), address(usdz));
        assertEq(t.count, 1);
        assertEq(t.feeSum, 0);
        // note that input sums are in the format of the token itself (i.e the amount passed to swap)
        assertEq(t.inputSum, 10e18);
        assertEq(t.outputSum, 60e6);

        // ******************** BUY WITH FEE *******************************************************************************

        // .85% fee on buy side
        assert(ondo.setBps(Side.Buy, 85));
        // say price had dipped to 2, quantity still 10, alice will spend 20e6
        a.setPrice(2e18);
        // to calculate the "fee aware" quote as the backend does, we first get the fee
        (uint256 fee, uint256 input) = ondo.fee(Side.Buy, 20e6);
        assertEq(input, (20e6 - fee)); // 19831432e12 expanded input in contract
        // quantity then is -> price * <x> = input
        a.setQuantity(9915716e12);

        q = a.quote(block.chainid, Side.Buy);

        // mimic the backend signature, alice nonce will be 1 now
        hash = a.structHash(ondo.VERIFY_REQUEST(), Side.Buy, address(usdz), q.asset, ALICE, uint64(1), 20e6);
        digest = a.digest(ondo.domainSeparator(), hash);
        (v, r, s) = vm.sign(uint256(a.privateKey()), digest);
        sig = a.encodeSig(v, r, s);

        // alice needs to approve our contract
        vm.prank(ALICE);
        assert(usdz.approve(address(ondo), 20e6));

        vm.prank(ALICE);
        res = ondo.swap(q, bytes("onemoartime"), address(usdz), 20e6, sig);
        // again, should be quantity-ish
        assertEq(res, q.quantity);

        t = ondo.totals(ALICE, address(usdz), address(stockz));
        // now bumped to 2
        assertEq(t.count, 2);
        // total fee sum will just be fee at this point
        assertEq(t.feeSum, fee);

        // ******************* SELL WITH FEE *******************************************************************************

        // .50% fee on sell side
        assert(ondo.setBps(Side.Sell, 50));
        // lets say she sells 5 stockz, all priced at 5 ea
        a.setQuantity(5e18);
        a.setPrice(5e18);
        q = a.quote(block.chainid, Side.Sell);

        // the mock's stable liquidity pool from her purchase would be a bit under..
        assert(usdz.mint(address(mock), 6e6));

        // alice nonce (count) will be 1 here, amount sell side represents a slippage floor
        // note that the floor is calculated by us and does not have to be fee aware
        hash = a.structHash(ondo.VERIFY_REQUEST(), Side.Sell, q.asset, address(usdz), ALICE, uint64(1), 24e6);
        digest = a.digest(ondo.domainSeparator(), hash);
        (v, r, s) = vm.sign(uint256(a.privateKey()), digest);
        sig = a.encodeSig(v, r, s);

        // alice needs to approve ondo contract to pull her stockz
        vm.prank(ALICE);
        assert(stockz.approve(address(ondo), q.quantity));

        vm.prank(ALICE);
        // alice spending 10stockz to get 60usdz
        res = ondo.swap(q, bytes("thistimewithfeeling"), address(usdz), 24e6, sig); // 24875000

        t = ondo.totals(ALICE, address(stockz), address(usdz));
        assertEq(t.count, 2);
        // the bpp value in sell is calculated against the amount redeemed by the mock (in this test)
        // the mock contracts 25e18 (quantity*price) down to 6 digits 25e6 which the .5% fee will be 125000
        assertEq(t.feeSum, (ondo.bpp(Side.Sell, 25e6)));

        // ******************** GLOBAL TOTALS ******************************************************************************

        // for the buy sides
        t = ondo.totals(address(usdz), address(stockz));
        assertEq(t.count, 2);
        assertEq(t.inputSum, 69831432);
        assertEq(t.feeSum, 168568);
        assertEq(t.outputSum, 19915716000000000000);

        // for the sell sides
        t = ondo.totals(address(stockz), address(usdz));
        assertEq(t.count, 2);
        assertEq(t.inputSum, 15000000000000000000);
        assertEq(t.feeSum, 125000);
        assertEq(t.outputSum, 84875000);

        // both sides can be reset
        assert(ondo.resetTotals(address(usdz), address(stockz)));
        t = ondo.totals(address(usdz), address(stockz));
        assertEq(t.count, 0);
        assertEq(t.inputSum, 0);
        assertEq(t.feeSum, 0);
        assertEq(t.outputSum, 0);

        assert(ondo.resetTotals(address(stockz), address(usdz)));
        t = ondo.totals(address(stockz), address(usdz));
        assertEq(t.count, 0);
        assertEq(t.inputSum, 0);
        assertEq(t.feeSum, 0);
        assertEq(t.outputSum, 0);
    }
}
