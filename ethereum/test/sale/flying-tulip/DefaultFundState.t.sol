// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {FlyingTulipFund} from "flying-tulip/FlyingTulipFund.sol";

contract FlyingTulipFundDefault is Test {
    FlyingTulipFund public fund;
    bytes32 public constant SALE_ID = keccak256("abc-123");
    address public constant PUT_MANAGER = 0x5050505050505050505050505050505050505050;
    bytes32 public constant THIS = keccak256("abc-456");
    bytes32 public constant THAT = keccak256("abc-789");
    bytes32[] public pwl = [THIS, THAT];

    function setUp() public {
        fund = new FlyingTulipFund(100, SALE_ID, PUT_MANAGER);
    }

    function testIsOwned() public view {
        // all forge test contracts are deployed from 0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496
        assertEq(fund.owner(), 0x7FA9385bE102ac3EAc297483Dd6233D62b3e1496);
    }

    function testIsNotStopped() public view {
        assertEq(fund.stopped(), 0);
    }

    function testIsNotOverridden() public view {
        assertEq(fund.commitBalanceOverride(), false);
    }

    function testSaleId() public view {
        assertEq(fund.id(), SALE_ID);
    }

    function testSaleMinCommit() public view {
        assertEq(fund.minCommit(), 100);
    }

    function testPutManagerAddr() public view {
        assertEq(fund.putManagerAddress(), PUT_MANAGER);
    }

    function testProofWlisNotSet() public view {
        assertEq(fund.isProofWlSet(), false);
    }

    function testRevertWhenNotOwner() public {
        vm.prank(PUT_MANAGER);
        vm.expectRevert(Ownable.Unauthorized.selector);

        fund.setProofWl(pwl);
    }

    function testCanSetProofWl() public {
        fund.setProofWl(pwl);
        assertEq(fund.isProofWlSet(), true);
    }

    function testCanOverrideCommitBalance() public {
        fund.toggleCommitBalanceOverride();
        assertEq(fund.commitBalanceOverride(), true);
        fund.toggleCommitBalanceOverride();
        assertEq(fund.commitBalanceOverride(), false);
    }
}
