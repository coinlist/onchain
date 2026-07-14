// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IStopable} from "shared/stopable/IStopable.sol";
import {TestToken} from "shared/TestToken.sol";
import {TokenSaleDist} from "sale/TokenSaleDist.sol";
import {ITokenSaleDist} from "sale/ITokenSaleDist.sol";
import {DistTotal as Total} from "sale/Types.sol";

contract TokenSaleRemit is Test {
    TestToken public token;
    TokenSaleDist public dist;
    address public constant D_TOKEN = 0x4040404040404040404040404040404040404040;
    address public constant ALICE = 0x6060606060606060606060606060606060606060;
    address public constant BOB = 0x7070707070707070707070707070707070707070;
    address public constant DISTRIBUTOR = 0x8080808080808080808080808080808080808080;
    bytes32 public constant SALE_ID = keccak256("abc-123");

    bytes4 public constant TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"));

    address[] public users = [BOB, ALICE];
    address[] public wrongUsers = [BOB, ALICE, DISTRIBUTOR];
    uint256[] public amounts = [5, 10];
    uint256[] public wrongAmounts = [5, 0];

    function setUp() public {
        token = new TestToken("TestToken", "TEST");
        dist = new TokenSaleDist(address(token), SALE_ID);
        // can distribute
        dist.grantRoles(DISTRIBUTOR, dist.DISTRIBUTE_LEVEL());
    }

    // *********** distribute call and bookkeeping ********************************

    function testRevertWhenStopped() public {
        dist.stop(dist.DISTRIBUTE_LEVEL());
        vm.expectRevert(IStopable.IsStopped.selector);

        dist.distribute(ALICE, 10);

        assertEq(zero(ALICE), true);
        assertEq(zero(address(dist)), true);
    }

    function testRevertBatchWhenStopped() public {
        dist.stop(dist.DISTRIBUTE_LEVEL());
        vm.expectRevert(IStopable.IsStopped.selector);

        dist.distribute(users, amounts);

        assertEq(zero(ALICE), true);
        assertEq(zero(BOB), true);
        assertEq(zero(address(dist)), true);
    }

    function testRevertBatchListLength() public {
        vm.prank(DISTRIBUTOR);
        vm.expectRevert(ITokenSaleDist.NonEquivalentListLength.selector);
        dist.distribute(wrongUsers, amounts);
    }

    function testRevertWhenNotDistributor() public {
        // does not have distribute level perms
        vm.prank(ALICE);
        vm.expectRevert(Ownable.Unauthorized.selector);
        dist.distribute(ALICE, 10);

        // no dist recorded
        assertEq(zero(ALICE), true);
        assertEq(zero(BOB), true);
        assertEq(zero(address(dist)), true);
    }

    function testRevertZeroAddress() public {
        vm.prank(DISTRIBUTOR);
        vm.expectRevert(ITokenSaleDist.InvalidAddress.selector);
        dist.distribute(address(0), 10);
    }

    function testRevertContractAddress() public {
        vm.prank(DISTRIBUTOR);
        vm.expectRevert(ITokenSaleDist.InvalidAddress.selector);
        dist.distribute(address(dist), 10);
    }

    function testReverMinDist() public {
        vm.prank(DISTRIBUTOR);
        vm.expectRevert(ITokenSaleDist.InsufficientAmount.selector);
        dist.distribute(ALICE, 0);

        assertEq(zero(ALICE), true);
        assertEq(zero(address(dist)), true);
    }

    // we hove no balance of the dist token..
    function testRevertNoBalance() public {
        vm.prank(DISTRIBUTOR);
        vm.expectRevert(SafeTransferLib.TransferFailed.selector);
        dist.distribute(ALICE, 10);

        assertEq(zero(ALICE), true);
        assertEq(zero(address(dist)), true);
    }

    function testRevertBatchMinDist() public {
        // get balance of the dist token
        token.mint(address(dist), 20);
        vm.prank(DISTRIBUTOR);
        vm.expectRevert(ITokenSaleDist.InsufficientAmount.selector);
        // BOB will succeed, ALICE will fail with min
        dist.distribute(users, wrongAmounts);

        // no bookkeeping as no partial pass is accepted
        assertEq(zero(ALICE), true);
        assertEq(zero(BOB), true);
        assertEq(zero(address(dist)), true);
    }

    function testDistribute() public {
        token.mint(address(dist), 20);
        // public getter now reports correctly
        assertEq(dist.distributionTokenBalance(), 20);

        vm.startPrank(DISTRIBUTOR);
        dist.distribute(ALICE, 10);

        // alice has bookkeeping present
        Total memory t = dist.totals(ALICE);
        assertEq(t.distCount, 1);
        assertEq(t.distSum, 10);

        // bob has bookkeeping present
        dist.distribute(BOB, 5);
        t = dist.totals(BOB);
        assertEq(t.distCount, 1);
        assertEq(t.distSum, 5);

        // contract has global bookkeeping
        t = dist.totals(address(dist));
        assertEq(t.distCount, 2);
        assertEq(t.distSum, 15);

        // global balance updated
        assertEq(dist.distributionTokenBalance(), 5);
        vm.stopPrank();
    }

    function testBatchDistribute() public {
        token.mint(address(dist), 20);

        vm.prank(DISTRIBUTOR);
        dist.distribute(users, amounts);

        // alice
        Total memory t = dist.totals(ALICE);
        assertEq(t.distCount, 1);
        assertEq(t.distSum, 10);

        // bob
        t = dist.totals(BOB);
        assertEq(t.distCount, 1);
        assertEq(t.distSum, 5);

        // contract
        t = dist.totals(address(dist));
        assertEq(t.distCount, 2);
        assertEq(t.distSum, 15);

        // global balance updated
        assertEq(dist.distributionTokenBalance(), 5);
    }

    // ************************* Utility **************************

    function zero(address user) internal view returns (bool) {
        Total memory t = dist.totals(user);

        return t.distCount == 0 && t.distSum == 0;
    }
}
