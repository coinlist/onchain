// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {TestToken, TestStable} from "shared/TestToken.sol";
import {State, SidedStatus as Status} from "shared/operable/Types.sol";
import {OndoPortfolio} from "ondo/OndoPortfolio.sol";
import {PMock} from "../PMock.sol";

contract OndoPortfolioStatus is Test {
    TestToken public stockz;
    TestStable public usdz;
    PMock public mock;
    OndoPortfolio public ondo;

    address public constant CL = 0x6060606060606060606060606060606060606060;
    bytes32 public constant SALE_ID = keccak256("bcd-234");

    function setUp() public {
        stockz = new TestToken("Stockz", "STKZ");
        usdz = new TestStable("Usdz", "USDZ");
        mock = new PMock(address(usdz));
        ondo = new OndoPortfolio(SALE_ID, CL, address(mock));
    }

    function testStatus() public {
        address asset = address(stockz);
        Status memory s = ondo.status(asset);
        assertEq(uint8(s.buyState), uint8(State.Active));
        assertEq(uint8(s.sellState), uint8(State.Active));

        mock.setPortfolioTokenMintingPaused(asset, true);
        s = ondo.status(asset);
        assertEq(uint8(s.buyState), uint8(State.Paused));
        assertEq(uint8(s.sellState), uint8(State.Active));

        mock.setPortfolioTokenRedemptionsPaused(asset, true);
        s = ondo.status(asset);
        assertEq(uint8(s.sellState), uint8(State.Paused));

        mock.setPortfolioTokenMintingPaused(asset, false);
        mock.setPortfolioTokenRedemptionsPaused(asset, false);
        mock.setGlobalMintingPaused(true);
        s = ondo.status();
        assertEq(uint8(s.buyState), uint8(State.Paused));
        assertEq(uint8(s.sellState), uint8(State.Active));

        mock.setGlobalMintingPaused(false);
        mock.setGlobalRedeemingPaused(true);
        s = ondo.status(asset);
        assertEq(uint8(s.sellState), uint8(State.Paused));
        assertEq(uint8(s.buyState), uint8(State.Active));
    }

    /// @dev our own pause or stop flags short-circuit status(asset), the manager is not consulted
    function testStatusShortCircuit() public {
        address asset = address(stockz);
        uint32 level = ondo.SWAP_LEVEL();

        assert(ondo.pause(level));
        Status memory s = ondo.status(asset);
        assertEq(uint8(s.buyState), uint8(State.Paused));
        assertEq(uint8(s.sellState), uint8(State.Paused));
        assertEq(s.flags, level);

        // the manager is not asked, so the per-asset pauses do not change the result
        mock.setPortfolioTokenMintingPaused(asset, true);
        s = ondo.status(asset);
        assertEq(s.flags, level);
        assertEq(uint8(s.sellState), uint8(State.Paused));

        // unpausing returns control to the manager
        assert(ondo.pause(0));
        s = ondo.status(asset);
        assertEq(s.flags, uint32(0));
        assertEq(uint8(s.buyState), uint8(State.Paused));
        assertEq(uint8(s.sellState), uint8(State.Active));

        // stopping short-circuits as well
        assert(ondo.stop());
        s = ondo.status(asset);
        assertGt(s.flags, uint32(0));
        assertEq(uint8(s.buyState), uint8(State.Stopped));
        assertEq(uint8(s.sellState), uint8(State.Stopped));
    }
}
