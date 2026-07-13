// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IStopable} from "shared/stopable/IStopable.sol";
import {TokenSaleFund} from "sale/TokenSaleFund.sol";
import {ITokenSaleFund} from "sale/ITokenSaleFund.sol";
import {SaleTotal as Total} from "sale/Types.sol";

contract TokenSaleRemit is Test {
    TokenSaleFund public fund;
    address public constant F_TOKEN_1 = 0x4040404040404040404040404040404040404040;
    address public constant F_TOKEN_2 = 0x5050505050505050505050505050505050505050;
    address public constant ALICE = 0x6060606060606060606060606060606060606060;
    address public constant BOB = 0x7070707070707070707070707070707070707070;
    address public constant REMITTER = 0x8080808080808080808080808080808080808080;
    address public constant COMMITTER = 0x9090909090909090909090909090909090909090;
    address public constant ADMIN = 0x1010101010101010101010101010101010101010;
    bytes32 public constant SALE_ID = keccak256("abc-123");
    bytes32 public constant OPT_ONE = keccak256("opt-12345");
    bytes32 public constant OPT_TWO = keccak256("opt-67890");

    bytes4 public constant TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"));
    bytes4 public constant TRANSFER_FROM_SELECTOR = bytes4(keccak256("transferFrom(address,address,uint256)"));

    address[] public users = [BOB, ALICE];
    address[] public zeroAndAlice = [address(0), ALICE];
    address[] public contractAndAlice = new address[](2);
    uint256[] public amounts = [5, 10];
    uint256[] public wrongAmounts = [5, 0];

    function setUp() public {
        fund = new TokenSaleFund(5, SALE_ID);
        // can only commit
        fund.grantRoles(COMMITTER, fund.COMMIT_LEVEL());
        // can only remit
        fund.grantRoles(REMITTER, fund.REMIT_LEVEL());
        // can both remit and commit
        fund.grantRoles(ADMIN, fund.COMMIT_LEVEL() + fund.REMIT_LEVEL());

        contractAndAlice[0] = address(fund);
        contractAndAlice[1] = ALICE;
    }

    // *********** refund call and bookkeeping ********************************

    function testRevertWhenStopped() public {
        fund.stop(fund.REMIT_LEVEL());
        vm.expectRevert(IStopable.IsStopped.selector);

        fund.remit(ALICE, OPT_ONE, F_TOKEN_2, 10);

        assertEq(zero(ALICE, OPT_ONE, F_TOKEN_2), true);
        assertEq(zero(address(fund), SALE_ID, F_TOKEN_2), true);
    }

    function testRevertBatchWhenStopped() public {
        // may also use the sum of each level, stopping both
        fund.stop(fund.COMMIT_LEVEL() + fund.REMIT_LEVEL());
        vm.expectRevert(IStopable.IsStopped.selector);

        fund.remit(users, OPT_ONE, F_TOKEN_2, amounts);

        assertEq(zero(ALICE, OPT_ONE, F_TOKEN_2), true);
        assertEq(zero(BOB, OPT_ONE, F_TOKEN_2), true);
        assertEq(zero(address(fund), SALE_ID, F_TOKEN_2), true);
    }

    function testRevertWhenNotRemitter() public {
        // does not have remit level perms
        vm.prank(COMMITTER);
        vm.expectRevert(Ownable.Unauthorized.selector);
        fund.remit(ALICE, OPT_ONE, F_TOKEN_1, 10);

        // no remits recorded
        assertEq(zero(ALICE, OPT_ONE, F_TOKEN_1), true);
        assertEq(zero(BOB, OPT_ONE, F_TOKEN_1), true);
        assertEq(zero(address(fund), SALE_ID, F_TOKEN_1), true);
    }

    function testRevertZeroAddress() public {
        vm.prank(REMITTER);
        vm.expectRevert(ITokenSaleFund.InvalidUser.selector);
        fund.remit(address(0), OPT_TWO, F_TOKEN_2, 10);
    }

    function testRevertContractAddress() public {
        vm.prank(REMITTER);
        vm.expectRevert(ITokenSaleFund.InvalidUser.selector);
        fund.remit(address(fund), OPT_TWO, F_TOKEN_2, 10);
    }

    function testReverMinRemit() public {
        vm.prank(REMITTER);
        vm.expectRevert(abi.encodeWithSelector(ITokenSaleFund.InsufficientAmount.selector, 0, 1));
        fund.remit(ALICE, OPT_TWO, F_TOKEN_2, 0);

        assertEq(zero(ALICE, OPT_TWO, F_TOKEN_2), true);
        assertEq(zero(address(fund), SALE_ID, F_TOKEN_2), true);
    }

    function testRevertNoCommitment() public {
        vm.prank(REMITTER);
        vm.expectRevert(
            abi.encodeWithSelector(ITokenSaleFund.InsufficientCommitment.selector, ALICE, OPT_TWO, F_TOKEN_2)
        );
        fund.remit(ALICE, OPT_TWO, F_TOKEN_2, 10);

        assertEq(zero(ALICE, OPT_TWO, F_TOKEN_2), true);
        assertEq(zero(address(fund), SALE_ID, F_TOKEN_2), true);
    }

    function testRevertPostCommitTransfer() public {
        vm.startPrank(ADMIN);
        // setup alice's commit
        vm.mockCall(F_TOKEN_2, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));
        assertEq(fund.commit(ALICE, OPT_TWO, F_TOKEN_2, 10), true);

        // reverts here for some reason..
        vm.mockCall(F_TOKEN_2, abi.encodeWithSelector(TRANSFER_SELECTOR), abi.encode(false));
        vm.expectRevert(SafeTransferLib.TransferFailed.selector);
        fund.remit(ALICE, OPT_TWO, F_TOKEN_2, 10);

        // alice's bookkeeping still in place
        Total memory t = fund.totals(ALICE, OPT_TWO, F_TOKEN_2);

        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 10);
        // no remits recorded
        assertEq(t.remitCount, 0);
        assertEq(t.remitSum, 0);

        vm.stopPrank();

        // contract commit balance would reflect alice's commit
        assertEq(fund.commitBalance(address(fund), SALE_ID, F_TOKEN_2), 10);
    }

    function testRemit() public {
        vm.startPrank(ADMIN);
        // setup bob's commit
        vm.mockCall(F_TOKEN_2, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));
        assertEq(fund.commit(BOB, OPT_ONE, F_TOKEN_2, 10), true);

        // bookkeeping present
        Total memory t = fund.totals(BOB, OPT_ONE, F_TOKEN_2);
        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 10);
        assertEq(fund.commitBalance(BOB, OPT_ONE, F_TOKEN_2), 10);
        // no remits recorded yet
        assertEq(t.remitCount, 0);
        assertEq(t.remitSum, 0);

        vm.stopPrank();

        // remit will function if stop level is commit only
        assertEq(fund.stop(fund.COMMIT_LEVEL()), true);

        vm.startPrank(ADMIN);
        // return partial funds
        assertEq(fund.remit(BOB, OPT_ONE, F_TOKEN_2, 5), true);

        // does not alter commit total
        t = fund.totals(BOB, OPT_ONE, F_TOKEN_2);
        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 10);
        // remits present
        assertEq(t.remitCount, 1);
        assertEq(t.remitSum, 5);
        // properly reflected in commit balance
        assertEq(fund.commitBalance(BOB, OPT_ONE, F_TOKEN_2), 5);
        vm.stopPrank();

        // contract globals
        t = fund.totals(address(fund), SALE_ID, F_TOKEN_2);
        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 10);
        assertEq(t.remitCount, 1);
        assertEq(t.remitSum, 5);
    }

    function testBatchRevertPostCommitZeroAddress() public {
        vm.startPrank(ADMIN);
        // setup bob's commit
        vm.mockCall(F_TOKEN_1, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));
        assertEq(fund.commit(ALICE, OPT_TWO, F_TOKEN_1, 5), true);

        // bookkeeping present
        Total memory t = fund.totals(ALICE, OPT_TWO, F_TOKEN_1);
        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 5);
        // no remits recorded
        assertEq(t.remitCount, 0);
        assertEq(t.remitSum, 0);

        // reverts on zero address
        vm.expectRevert(ITokenSaleFund.InvalidUser.selector);
        fund.remit(zeroAndAlice, OPT_TWO, F_TOKEN_1, amounts);

        t = fund.totals(ALICE, OPT_TWO, F_TOKEN_1);
        // remits not recorded
        assertEq(t.remitCount, 0);
        assertEq(t.remitSum, 0);
        // commits unchanged
        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 5);
        assertEq(fund.commitBalance(ALICE, OPT_TWO, F_TOKEN_1), 5);
        vm.stopPrank();

        // contract globals
        assertEq(fund.commitBalance(address(fund), SALE_ID, F_TOKEN_1), 5);
    }

    function testBatchRevertPostCommitContractAddress() public {
        vm.startPrank(ADMIN);
        // setup bob's commit
        vm.mockCall(F_TOKEN_1, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));
        assertEq(fund.commit(ALICE, OPT_TWO, F_TOKEN_1, 5), true);

        // bookkeeping present
        Total memory t = fund.totals(ALICE, OPT_TWO, F_TOKEN_1);
        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 5);
        // no remits recorded
        assertEq(t.remitCount, 0);
        assertEq(t.remitSum, 0);

        // reverts on zero address
        vm.expectRevert(ITokenSaleFund.InvalidUser.selector);
        fund.remit(contractAndAlice, OPT_TWO, F_TOKEN_1, amounts);

        t = fund.totals(ALICE, OPT_TWO, F_TOKEN_1);
        // remits not recorded for alice
        assertEq(t.remitCount, 0);
        assertEq(t.remitSum, 0);
        // commits unchanged
        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 5);
        assertEq(fund.commitBalance(ALICE, OPT_TWO, F_TOKEN_1), 5);
        vm.stopPrank();

        // contract globals
        t = fund.totals(address(fund), SALE_ID, F_TOKEN_1);
        assertEq(t.commitSum, 5);
        assertEq(t.remitCount, 0);
        assertEq(fund.commitBalance(address(fund), SALE_ID, F_TOKEN_1), 5);
    }

    function testBatchRevertPostCommitMinRemit() public {
        vm.startPrank(ADMIN);
        // setup bob's commit
        vm.mockCall(F_TOKEN_1, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));
        assertEq(fund.commit(BOB, OPT_TWO, F_TOKEN_1, 5), true);

        // bookkeeping present
        Total memory t = fund.totals(BOB, OPT_TWO, F_TOKEN_1);
        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 5);
        // no remits recorded yet
        assertEq(t.remitCount, 0);
        assertEq(t.remitSum, 0);

        // reverts for min amount
        vm.expectRevert(abi.encodeWithSelector(ITokenSaleFund.InsufficientAmount.selector, 0, 1));
        fund.remit(users, OPT_TWO, F_TOKEN_1, wrongAmounts);

        t = fund.totals(BOB, OPT_TWO, F_TOKEN_1);
        // remits not recorded
        assertEq(t.remitCount, 0);
        assertEq(t.remitSum, 0);
        // commits unchanged
        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 5);
        assertEq(fund.commitBalance(BOB, OPT_TWO, F_TOKEN_1), 5);
        vm.stopPrank();

        // contract globals
        assertEq(fund.commitBalance(address(fund), SALE_ID, F_TOKEN_1), 5);
    }

    function testBatchRevertPostCommitTransfer() public {
        vm.startPrank(ADMIN);
        // setup bob's commit
        vm.mockCall(F_TOKEN_1, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));
        assertEq(fund.commit(BOB, OPT_TWO, F_TOKEN_1, 5), true);

        // bookkeeping present
        Total memory t = fund.totals(BOB, OPT_TWO, F_TOKEN_1);
        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 5);
        // no remits recorded yet
        assertEq(t.remitCount, 0);
        assertEq(t.remitSum, 0);

        // reverts for some reason at the token transfer
        vm.mockCall(F_TOKEN_1, abi.encodeWithSelector(TRANSFER_SELECTOR), abi.encode(false));
        vm.expectRevert(SafeTransferLib.TransferFailed.selector);
        fund.remit(users, OPT_TWO, F_TOKEN_1, amounts);

        t = fund.totals(BOB, OPT_TWO, F_TOKEN_1);
        // remits not recorded
        assertEq(t.remitCount, 0);
        assertEq(t.remitSum, 0);
        // commits unchanged
        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 5);
        assertEq(fund.commitBalance(BOB, OPT_TWO, F_TOKEN_1), 5);
        vm.stopPrank();

        // contract globals
        assertEq(fund.commitBalance(address(fund), SALE_ID, F_TOKEN_1), 5);
    }

    // NOTE: remit batches must be equivalent option and funding tokens
    function testRemitBatch() public {
        vm.startPrank(ADMIN);
        // setup bob's commit
        vm.mockCall(F_TOKEN_2, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));
        assertEq(fund.commit(BOB, OPT_TWO, F_TOKEN_2, 5), true);

        // bookkeeping present
        Total memory t = fund.totals(BOB, OPT_TWO, F_TOKEN_2);
        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 5);
        // no remits recorded yet
        assertEq(t.remitCount, 0);
        assertEq(t.remitSum, 0);
        assertEq(fund.commitBalance(BOB, OPT_TWO, F_TOKEN_2), 5);

        // setup alice's commit
        vm.mockCall(F_TOKEN_2, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));
        assertEq(fund.commit(ALICE, OPT_TWO, F_TOKEN_2, 10), true);

        t = fund.totals(ALICE, OPT_TWO, F_TOKEN_2);
        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 10);
        assertEq(t.remitCount, 0);
        assertEq(t.remitSum, 0);
        assertEq(fund.commitBalance(ALICE, OPT_TWO, F_TOKEN_2), 10);

        // return all funding to both users
        assertEq(fund.remit(users, OPT_TWO, F_TOKEN_2, amounts), true);

        // alice
        t = fund.totals(ALICE, OPT_TWO, F_TOKEN_2);
        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 10);
        assertEq(t.remitCount, 1);
        assertEq(t.remitSum, 10);
        // commit balance is zeroed
        assertEq(fund.commitBalance(ALICE, OPT_TWO, F_TOKEN_2), 0);

        // bob
        t = fund.totals(BOB, OPT_TWO, F_TOKEN_2);
        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 5);
        assertEq(t.remitCount, 1);
        assertEq(t.remitSum, 5);
        assertEq(fund.commitBalance(BOB, OPT_TWO, F_TOKEN_2), 0);
        vm.stopPrank();

        // contract globals
        t = fund.totals(address(fund), SALE_ID, F_TOKEN_2);
        assertEq(t.commitCount, 2);
        assertEq(t.commitSum, 15);
        assertEq(t.remitCount, 2);
        assertEq(t.remitSum, 15);
        assertEq(fund.commitBalance(address(fund), SALE_ID, F_TOKEN_2), 0);
    }

    // ************************* Utility **************************

    function zero(address user, bytes32 option, address token) internal view returns (bool) {
        Total memory t = fund.totals(user, option, token);

        return t.remitCount == 0 && t.remitSum == 0;
    }
}
