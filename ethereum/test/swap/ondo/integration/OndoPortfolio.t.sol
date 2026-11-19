// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {TestToken, TestStable} from "shared/TestToken.sol";
import {Side, OptimizedSwapTotal as Total} from "swap/Types.sol";
import {OndoPortfolio} from "ondo/OndoPortfolio.sol";
import {Quote} from "ondo/Types.sol";
import {ISoms} from "swap/ISoms.sol";
import {PMock} from "../PMock.sol";
import {Assembler, ATTRIBUTION} from "../Assembler.sol";

contract OndoPortfolioIntegration is Test {
    TestToken public stockz;
    TestStable public usdz;
    PMock public mock;
    OndoPortfolio public ondo;
    Assembler a;

    address public constant ALICE = 0x6060606060606060606060606060606060606060;
    bytes32 public constant SALE_ID = keccak256("bcd-234");
    uint256 public constant MINZ = 98 * 1e16;

    function setUp() public {
        stockz = new TestToken("Stockz", "STKZ");
        usdz = new TestStable("Usdz", "USDZ");
        assert(usdz.mint(ALICE, 100e6));

        mock = new PMock(address(usdz));
        mock.setMinDeposit(MINZ);
        mock.setMinRedemption(MINZ);

        a = new Assembler();
        assert(a.setRwa(address(stockz)));

        ondo = new OndoPortfolio(SALE_ID, a.addr(), address(mock));
        mock.setRegistered(address(ondo), true);

        vm.prank(ALICE);
        assert(usdz.approve(address(ondo), 50e6));
    }

    // ******************** construction ***********************************************************************

    function testConstruction() public view {
        assertEq(ondo.stablecoin(), address(usdz));
        assertEq(ondo.manager(), address(mock));
        assertEq(ondo.KIND(), 3);
        assertEq(ondo.VERSION(), 2);
        // the stablecoin is whitelisted from the start
        assert(ondo.inputTokens(address(usdz)));
    }

    function testRevertEoaManager() public {
        address cl = a.addr(); // read before expectRevert, an external call would consume it
        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        new OndoPortfolio(SALE_ID, cl, ALICE);
    }

    function testRevertZeroManager() public {
        address cl = a.addr(); // read before expectRevert, an external call would consume it
        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        new OndoPortfolio(SALE_ID, cl, address(0));
    }

    function testRevertZeroCoinList() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        new OndoPortfolio(SALE_ID, address(0), address(mock));
    }

    function testRevertDisabledToken() public {
        assert(ondo.setInputToken(address(usdz), false));
        Quote memory q = a.quote(block.chainid, Side.Buy);
        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        vm.prank(ALICE);
        ondo.swap(q, bytes("x"), address(usdz), 50e6, ATTRIBUTION, bytes(""));
    }

    // ******************** swaps ******************************************************************************

    function _sign(Quote memory q, address in_, address out, uint64 nonce, uint256 amt)
        internal
        view
        returns (bytes memory)
    {
        bytes32 hash = a.structHash(ondo.VERIFY_REQUEST(), q.side, in_, out, ALICE, ATTRIBUTION, nonce, amt);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(uint256(a.privateKey()), a.digest(ondo.domainSeparator(), hash));
        return a.encodeSig(v, r, s);
    }

    function testBuyAndSell() public {
        // 10 stockz at 5 each, alice spends 50 usdz
        a.setQuantity(10e18);
        a.setPrice(5e18);
        Quote memory q = a.quote(block.chainid, Side.Buy);
        bytes memory sig = _sign(q, address(usdz), q.asset, 0, 50e6);

        vm.prank(ALICE);
        uint256 res = ondo.swap(q, bytes("doit"), address(usdz), 50e6, ATTRIBUTION, sig);

        assertEq(res, q.quantity);
        assertEq(stockz.balanceOf(ALICE), res);
        assertEq(usdz.balanceOf(ALICE), 50e6);
        assertEq(usdz.balanceOf(address(ondo)), 0);
        assertEq(usdz.balanceOf(address(mock)), 50e6);
        // no residual allowance to the manager
        assertEq(usdz.allowance(address(ondo), address(mock)), 0);

        Total memory t = ondo.totals(ALICE, address(usdz), address(stockz));
        assertEq(t.count, 1);
        assertEq(t.feeSum, 0);
        assertEq(t.inputSum, 50e6);
        assertEq(t.outputSum, res);

        // sell at 6 each
        a.setPrice(6e18);
        q = a.quote(block.chainid, Side.Sell);
        assert(usdz.mint(address(mock), 10e6));
        sig = _sign(q, q.asset, address(usdz), 0, 59e6);

        vm.prank(ALICE);
        assert(stockz.approve(address(ondo), q.quantity));

        vm.prank(ALICE);
        res = ondo.swap(q, bytes("doitagain"), address(usdz), 59e6, ATTRIBUTION, sig);

        assertEq(res, 60e6);
        assertEq(usdz.balanceOf(ALICE), 110e6);
        assertEq(stockz.balanceOf(ALICE), 0);
        assertEq(stockz.allowance(address(ondo), address(mock)), 0);
    }

    function testBuyWithFee() public {
        assert(ondo.setBps(Side.Buy, 85));
        a.setPrice(2e18);
        (uint256 fee, uint256 input) = ondo.fee(Side.Buy, 20e6);
        // quantity * 2 == input expanded to 18 decimals
        a.setQuantity((input * 1e12) / 2);
        Quote memory q = a.quote(block.chainid, Side.Buy);
        bytes memory sig = _sign(q, address(usdz), q.asset, 0, 20e6);

        vm.prank(ALICE);
        uint256 res = ondo.swap(q, bytes("fee"), address(usdz), 20e6, ATTRIBUTION, sig);
        assertEq(res, q.quantity);

        Total memory t = ondo.totals(ALICE, address(usdz), address(stockz));
        assertEq(t.feeSum, fee);
        assertEq(t.inputSum, input);
        // the fee stays on the contract, the manager pulled only the cost
        assertEq(usdz.balanceOf(address(ondo)), fee);
        assertEq(usdz.balanceOf(address(mock)), input);
    }

    function testSellWithFee() public {
        assert(ondo.setBps(Side.Sell, 50));
        a.setQuantity(5e18);
        a.setPrice(5e18);
        Quote memory q = a.quote(block.chainid, Side.Sell);
        assert(usdz.mint(address(mock), 25e6));
        assert(stockz.mint(ALICE, 5e18));
        vm.prank(ALICE);
        assert(stockz.approve(address(ondo), q.quantity));
        bytes memory sig = _sign(q, q.asset, address(usdz), 0, 24e6);

        vm.prank(ALICE);
        uint256 res = ondo.swap(q, bytes("sell"), address(usdz), 24e6, ATTRIBUTION, sig);

        uint256 fee = ondo.bpp(Side.Sell, 25e6);
        assertEq(res, 25e6 - fee);
        assertEq(usdz.balanceOf(address(ondo)), fee);
    }

    function testRevertUnderpay() public {
        // cost is 100 usdz, alice sends 90
        a.setQuantity(50e18);
        a.setPrice(2e18);
        Quote memory q = a.quote(block.chainid, Side.Buy);
        bytes memory sig = _sign(q, address(usdz), q.asset, 0, 90e6);
        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        vm.prank(ALICE);
        ondo.swap(q, bytes("x"), address(usdz), 90e6, ATTRIBUTION, sig);
    }

    function testRevertOverspend() public {
        a.setQuantity(50e18);
        a.setPrice(2e18);
        assert(usdz.mint(ALICE, 100e6));
        vm.prank(ALICE);
        assert(usdz.approve(address(ondo), 101e6));
        Quote memory q = a.quote(block.chainid, Side.Buy);
        bytes memory sig = _sign(q, address(usdz), q.asset, 0, 101e6);
        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        vm.prank(ALICE);
        ondo.swap(q, bytes("x"), address(usdz), 101e6, ATTRIBUTION, sig);
    }

    function testRevertSellSlippage() public {
        a.setQuantity(10e18);
        a.setPrice(6e18);
        Quote memory q = a.quote(block.chainid, Side.Sell);
        assert(usdz.mint(address(mock), 60e6));
        assert(stockz.mint(ALICE, 10e18));
        vm.prank(ALICE);
        assert(stockz.approve(address(ondo), q.quantity));
        // floor above what the manager will pay
        bytes memory sig = _sign(q, q.asset, address(usdz), 0, 61e6);
        vm.expectRevert();
        vm.prank(ALICE);
        ondo.swap(q, bytes("x"), address(usdz), 61e6, ATTRIBUTION, sig);
    }

    function testRevertUnauthorizedSig() public {
        a.setQuantity(10e18);
        a.setPrice(5e18);
        Quote memory q = a.quote(block.chainid, Side.Buy);
        // signed for a different amount
        bytes memory sig = _sign(q, address(usdz), q.asset, 0, 49e6);
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vm.prank(ALICE);
        ondo.swap(q, bytes("x"), address(usdz), 50e6, ATTRIBUTION, sig);
    }

    function testRevertBadStablecoin() public {
        // an EOA stablecoin
        PMock bad = new PMock(ALICE);
        address cl = a.addr();
        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        new OndoPortfolio(SALE_ID, cl, address(bad));

        // zero stablecoin
        bad = new PMock(address(0));
        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        new OndoPortfolio(SALE_ID, cl, address(bad));
    }

    function testRevertSwapWhenPausedOrStopped() public {
        a.setQuantity(5e18);
        a.setPrice(2e18);
        Quote memory q = a.quote(block.chainid, Side.Buy);
        bytes memory sig = _sign(q, address(usdz), q.asset, 0, 10e6);
        uint32 level = ondo.SWAP_LEVEL();

        assert(ondo.pause(level));
        vm.expectRevert();
        vm.prank(ALICE);
        ondo.swap(q, bytes("x"), address(usdz), 10e6, ATTRIBUTION, sig);

        assert(ondo.pause(0));
        assert(ondo.stop());
        vm.expectRevert();
        vm.prank(ALICE);
        ondo.swap(q, bytes("x"), address(usdz), 10e6, ATTRIBUTION, sig);
    }

    function testRevertQuoteRejectedByManager() public {
        mock.setQuoteWillVerify(false);
        a.setQuantity(5e18);
        a.setPrice(2e18);
        Quote memory q = a.quote(block.chainid, Side.Buy);
        bytes memory sig = _sign(q, address(usdz), q.asset, 0, 10e6);
        vm.expectRevert();
        vm.prank(ALICE);
        ondo.swap(q, bytes("x"), address(usdz), 10e6, ATTRIBUTION, sig);
    }

    function testRevertReplay() public {
        a.setQuantity(5e18);
        a.setPrice(2e18);
        Quote memory q = a.quote(block.chainid, Side.Buy);
        bytes memory sig = _sign(q, address(usdz), q.asset, 0, 10e6);

        vm.prank(ALICE);
        ondo.swap(q, bytes("x"), address(usdz), 10e6, ATTRIBUTION, sig);

        // the same signature again, the nonce (count) has moved on
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vm.prank(ALICE);
        ondo.swap(q, bytes("x"), address(usdz), 10e6, ATTRIBUTION, sig);
    }

    function testSwappedEvent() public {
        a.setQuantity(10e18);
        a.setPrice(5e18);
        Quote memory q = a.quote(block.chainid, Side.Buy);
        bytes memory sig = _sign(q, address(usdz), q.asset, 0, 50e6);

        vm.expectEmit(true, true, true, true, address(ondo));
        emit ISoms.Swapped(ALICE, q.asset, address(usdz), ATTRIBUTION, q.attestationId, Side.Buy, q.quantity, 0, 50e6);
        vm.prank(ALICE);
        ondo.swap(q, bytes("x"), address(usdz), 50e6, ATTRIBUTION, sig);
    }

    /// @dev quantity * price is not a whole number of stablecoin units, the cost rounds up
    function testBuyRoundsCostUp() public {
        a.setQuantity(100e18 + 1);
        a.setPrice(1e18);
        Quote memory q = a.quote(block.chainid, Side.Buy);

        // 100e6 is a unit short
        bytes memory sig = _sign(q, address(usdz), q.asset, 0, 100e6);
        vm.prank(ALICE);
        assert(usdz.approve(address(ondo), 101e6));
        assert(usdz.mint(ALICE, 100e6));
        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        vm.prank(ALICE);
        ondo.swap(q, bytes("x"), address(usdz), 100e6, ATTRIBUTION, sig);

        sig = _sign(q, address(usdz), q.asset, 0, 100e6 + 1);
        vm.prank(ALICE);
        uint256 res = ondo.swap(q, bytes("x"), address(usdz), 100e6 + 1, ATTRIBUTION, sig);
        assertEq(res, q.quantity);
        assertEq(usdz.balanceOf(address(mock)), 100e6 + 1);
        assertEq(usdz.balanceOf(address(ondo)), 0);
    }

    /// @dev an overpayment inside the tolerance stays on the contract, outside of it reverts
    function testOverpaymentTolerance() public {
        a.setQuantity(10e18);
        a.setPrice(5e18);
        Quote memory q = a.quote(block.chainid, Side.Buy);

        // cost is 50e6, 0.005 USD over is accepted
        bytes memory sig = _sign(q, address(usdz), q.asset, 0, 50e6 + 5000);
        vm.prank(ALICE);
        assert(usdz.approve(address(ondo), 50e6 + 5000));
        vm.prank(ALICE);
        ondo.swap(q, bytes("x"), address(usdz), 50e6 + 5000, ATTRIBUTION, sig);
        assertEq(usdz.balanceOf(address(mock)), 50e6);
        assertEq(usdz.balanceOf(address(ondo)), 5000);
        assertEq(usdz.allowance(address(ondo), address(mock)), 0);

        // exactly 0.01 USD over is not
        sig = _sign(q, address(usdz), q.asset, 1, 50e6 + 10000);
        vm.prank(ALICE);
        assert(usdz.approve(address(ondo), 50e6 + 10000));
        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        vm.prank(ALICE);
        ondo.swap(q, bytes("x"), address(usdz), 50e6 + 10000, ATTRIBUTION, sig);
    }

    /// @dev a stablecoin with 18 decimals, no scaling
    function testBuyAndSell18Decimal() public {
        TestToken d18 = new TestToken("D18", "D18");
        mock = new PMock(address(d18));
        mock.setMinDeposit(MINZ);
        mock.setMinRedemption(MINZ);
        ondo = new OndoPortfolio(SALE_ID, a.addr(), address(mock));
        mock.setRegistered(address(ondo), true);
        assert(d18.mint(ALICE, 100e18));
        vm.prank(ALICE);
        assert(d18.approve(address(ondo), 100e18));

        a.setQuantity(10e18);
        a.setPrice(5e18);
        Quote memory q = a.quote(block.chainid, Side.Buy);
        bytes memory sig = _sign(q, address(d18), q.asset, 0, 50e18);
        vm.prank(ALICE);
        uint256 res = ondo.swap(q, bytes("x"), address(d18), 50e18, ATTRIBUTION, sig);
        assertEq(res, 10e18);
        assertEq(d18.balanceOf(address(mock)), 50e18);

        a.setPrice(6e18);
        q = a.quote(block.chainid, Side.Sell);
        assert(d18.mint(address(mock), 10e18));
        sig = _sign(q, q.asset, address(d18), 0, 59e18);
        vm.prank(ALICE);
        assert(stockz.approve(address(ondo), q.quantity));
        vm.prank(ALICE);
        res = ondo.swap(q, bytes("x"), address(d18), 59e18, ATTRIBUTION, sig);
        assertEq(res, 60e18);
        assertEq(d18.balanceOf(ALICE), 110e18);
    }
}
