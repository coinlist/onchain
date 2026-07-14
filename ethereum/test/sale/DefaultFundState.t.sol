// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {TokenSaleFund} from "sale/TokenSaleFund.sol";

contract TokenSaleFundDefault is Test {
    TokenSaleFund public fund;
    address public constant ALICE = 0x5050505050505050505050505050505050505050;
    bytes32 public constant SALE_ID = keccak256("abc-123");

    function setUp() public {
        fund = new TokenSaleFund(100, SALE_ID);
    }

    // ********* properties ***************************************************

    function testIsOwned() public view {
        // all forge test contracts are deployed from 0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496
        assertEq(fund.owner(), 0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496);
    }

    function testIsNotStopped() public view {
        assertEq(fund.stopped(), 0);
    }

    function testSaleId() public view {
        assertEq(fund.id(), SALE_ID);
    }

    function testSaleMinCommit() public view {
        assertEq(fund.minCommit(), 100);
    }

    // ******** default state changes *****************************************

    function testAssignRole() public {
        fund.grantRoles(ALICE, 1);

        assertEq(fund.rolesOf(ALICE), 1);

        // numbers above the granted role are false
        assertEq(fund.hasAnyRole(ALICE, 2), false);

        fund.grantRoles(ALICE, 3);

        // roles of will return the highest
        assertEq(fund.rolesOf(ALICE), 3);

        // any role <= the highest is now true
        assertEq(fund.hasAnyRole(ALICE, 1), true);
        assertEq(fund.hasAnyRole(ALICE, 2), true);
        assertEq(fund.hasAnyRole(ALICE, 3), true);
        assertEq(fund.hasAnyRole(ALICE, 4), false);
    }

    function testOwnerIsNotRole() public view {
        assertEq(fund.hasAnyRole(0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496, 4), false);
    }

    function testRevertStopWhenNotOwner() public {
        vm.prank(ALICE);
        vm.expectRevert(Ownable.Unauthorized.selector);

        fund.stop(2);
    }

    function testStop() public {
        assertEq(fund.stopped(), 0);
        fund.stop(2);
        assertEq(fund.stopped(), 2);
        fund.stop(4);
        assertEq(fund.stopped(), 4);
    }
}
