// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {TestToken} from "shared/TestToken.sol";
import {TokenSaleFund} from "sale/TokenSaleFund.sol";
import {ITokenSaleFund} from "sale/ITokenSaleFund.sol";
import {SaleTotal as Total} from "sale/Types.sol";

contract FundingIntegration is Test {
    TestToken public token;
    TokenSaleFund public fund;
    address public constant ALICE = 0xfCe15dD3A9867daf6aA6e5b547eE27554E2E8893;
    address public constant BOB = 0x6060606060606060606060606060606060606060;
    address public constant ADMIN = 0x7070707070707070707070707070707070707070;
    address public constant SOMEBODY = 0x8080808080808080808080808080808080808080;
    bytes32 public constant SALE_ID = keccak256("abc-123");
    // a hashed uuid as an example
    bytes32 public constant OPT = 0xfb175f72f2dd9e5dae06ce01ca5fb9abce099d7ecb0405332c9a4ea5a74f5718;
    address[] public users = [ALICE, BOB];

    function setUp() public {
        token = new TestToken("TestToken", "TEST");
        fund = new TokenSaleFund(10, SALE_ID);

        fund.grantRoles(ADMIN, fund.COMMIT_LEVEL() + fund.REMIT_LEVEL());
        // alice's balance at the funding token
        token.mint(ALICE, 100);
    }

    function testDefaultState() public view {
        address tokenAddr = address(token);

        assertEq(token.name(), "TestToken");
        assertEq(token.symbol(), "TEST");
        assertEq(token.decimals(), 18);

        assertEq(token.balanceOf(ALICE), 100);
        assertEq(token.balanceOf(BOB), 0);
        // the allowance for fund via alice should be 0
        assertEq(token.allowance(ALICE, address(fund)), 0);
        // alice, bob have no committment
        Total memory t = fund.totals(ALICE, OPT, tokenAddr);
        assertEq(t.commitSum, 0);
        t = fund.totals(BOB, OPT, tokenAddr);
        assertEq(t.commitSum, 0);
    }

    // various paths for alice commits / remits / reverts
    function testAlice() public {
        address fundAddr = address(fund);
        address tokenAddr = address(token);
        // make the caller alice
        vm.startPrank(ALICE);
        assertEq(token.approve(fundAddr, 50), true);
        assertEq(token.allowance(ALICE, fundAddr), 50);
        vm.stopPrank();

        vm.startPrank(ADMIN);
        // call to commit
        assertEq(fund.commit(ALICE, OPT, tokenAddr, 25), true);
        Total memory t = fund.totals(ALICE, OPT, tokenAddr);
        assertEq(t.commitSum, 25);
        assertEq(fund.commitBalance(ALICE, OPT, tokenAddr), 25);
        // fund now has tokens
        assertEq(token.balanceOf(ALICE), 75);
        assertEq(token.balanceOf(fundAddr), 25);

        // alice allowance will now be 25

        // commits 10 more
        assertEq(fund.commit(ALICE, OPT, tokenAddr, 10), true);
        t = fund.totals(ALICE, OPT, tokenAddr);
        assertEq(t.commitCount, 2);
        assertEq(t.commitSum, 35);
        assertEq(fund.commitBalance(ALICE, OPT, tokenAddr), 35);
        assertEq(token.balanceOf(ALICE), 65);
        assertEq(token.balanceOf(fundAddr), 35);

        // alice allowance will now be 15

        // tries to commit 25 (allowance will fail)
        vm.expectRevert(abi.encodeWithSelector(ITokenSaleFund.CommitFailed.selector, ALICE, OPT, tokenAddr));
        fund.commit(ALICE, OPT, tokenAddr, 25);
        vm.stopPrank();

        // alice raises her allowance greater than her balance, this is not something we control
        vm.startPrank(ALICE);
        // NOTE `approve` is overwriting. if available we could choose to use [in|de]creaseAllowance (not std interface however)
        assertEq(token.approve(fundAddr, 500), true);
        assertEq(token.allowance(ALICE, fundAddr), 500);
        vm.stopPrank();

        // tries to commit 400 (balance will fail)
        vm.startPrank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(ITokenSaleFund.CommitFailed.selector, ALICE, OPT, tokenAddr));
        fund.commit(ALICE, OPT, tokenAddr, 400);

        // alice's bookkeeping is unchanged since last successful commit
        t = fund.totals(ALICE, OPT, tokenAddr);
        assertEq(t.commitCount, 2);
        assertEq(t.commitSum, 35);
        assertEq(fund.commitBalance(ALICE, OPT, tokenAddr), 35);

        // tries to remit more than her balance
        vm.expectRevert(abi.encodeWithSelector(ITokenSaleFund.InsufficientCommitment.selector, ALICE, OPT, tokenAddr));
        fund.remit(ALICE, OPT, tokenAddr, 100);

        // admin remits alice 15
        assertEq(token.balanceOf(ALICE), 65); // alice pre remit token balance
        assertEq(token.balanceOf(fundAddr), 35); // fund pre remit token bal
        assertEq(fund.remit(ALICE, OPT, tokenAddr, 15), true);

        t = fund.totals(ALICE, OPT, tokenAddr);
        assertEq(t.commitCount, 2);
        assertEq(t.commitSum, 35);
        assertEq(t.remitCount, 1);
        assertEq(t.remitSum, 15);
        // properly reflected in commit bal
        assertEq(fund.commitBalance(ALICE, OPT, tokenAddr), 20);
        assertEq(token.balanceOf(ALICE), 80); // post remit...
        assertEq(token.balanceOf(fundAddr), 20); // post remit..
        vm.stopPrank();

        // owner can approve SOMEBODY for whatevs
        assertEq(fund.approve(SOMEBODY, address(token), 100), true);
        assertEq(token.allowance(address(fund), SOMEBODY), 100);
    }
}
