// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {IStopable} from "shared/stopable/IStopable.sol";
import {TokenSaleFund} from "sale/TokenSaleFund.sol";
import {ITokenSaleFund} from "sale/ITokenSaleFund.sol";
import {SaleTotal as Total} from "sale/Types.sol";

contract TokenSaleCommit is Test {
    TokenSaleFund public fund;
    address public constant F_TOKEN_1 = 0x4040404040404040404040404040404040404040;
    address public constant F_TOKEN_2 = 0x5050505050505050505050505050505050505050;
    address public constant ALICE = 0x6060606060606060606060606060606060606060;
    address public constant BOB = 0x7070707070707070707070707070707070707070;
    address public constant ADMIN = 0x8080808080808080808080808080808080808080;
    bytes32 public constant SALE_ID = keccak256("abc-123");
    bytes32 public constant OPT_ONE = keccak256("opt-12345");
    bytes32 public constant OPT_TWO = keccak256("opt-67890");

    bytes4 public constant TRANSFER_FROM_SELECTOR = bytes4(keccak256("transferFrom(address,address,uint256)"));

    address[] public tooManyUsers = [BOB, ALICE, F_TOKEN_1];
    address[] public users = [BOB, ALICE];
    address[] public zeroAndAlice = [address(0), ALICE];
    address[] public contractAndAlice = new address[](2);
    bytes32[] public options = [OPT_ONE, OPT_TWO];
    address[] public tokens = [F_TOKEN_1, F_TOKEN_2];
    uint256[] public amounts = [5, 10];
    uint256[] public wrongAmounts = [4, 10];

    function setUp() public {
        fund = new TokenSaleFund(5, SALE_ID);
        fund.grantRoles(ADMIN, fund.COMMIT_LEVEL());

        contractAndAlice[0] = address(fund);
        contractAndAlice[1] = ALICE;
    }

    // *********** commit call and bookkeeping ********************************

    function testRevertWhenStopped() public {
        fund.stop(fund.COMMIT_LEVEL());
        vm.expectRevert(IStopable.IsStopped.selector);

        fund.commit(ALICE, OPT_ONE, F_TOKEN_2, 10);

        assertEq(zero(ALICE, OPT_ONE, F_TOKEN_2), true);
        assertEq(zero(address(fund), SALE_ID, F_TOKEN_2), true);
    }

    function testBatchRevertWhenStopped() public {
        // can also use the LEVEL_SUM to indicate both commit/remit
        fund.stop(fund.COMMIT_LEVEL() + fund.REMIT_LEVEL());
        vm.expectRevert(IStopable.IsStopped.selector);

        fund.commit(users, options, tokens, amounts);

        assertEq(zero(BOB, OPT_ONE, F_TOKEN_1), true);
        assertEq(zero(ALICE, OPT_TWO, F_TOKEN_2), true);
        assertEq(zero(address(fund), SALE_ID, F_TOKEN_1), true);
        assertEq(zero(address(fund), SALE_ID, F_TOKEN_2), true);
    }

    function testRevertWhenNotCommitter() public {
        vm.prank(BOB);

        vm.expectRevert(Ownable.Unauthorized.selector);
        fund.commit(ALICE, OPT_ONE, F_TOKEN_1, 10);

        assertEq(zero(ALICE, OPT_ONE, F_TOKEN_1), true);
        assertEq(zero(BOB, OPT_ONE, F_TOKEN_1), true);
        assertEq(zero(address(fund), SALE_ID, F_TOKEN_1), true);
        assertEq(zero(address(fund), SALE_ID, F_TOKEN_2), true);
    }

    function testBatchRevertWhenNotCommitter() public {
        vm.prank(BOB);

        vm.expectRevert(Ownable.Unauthorized.selector);
        fund.commit(users, options, tokens, amounts);

        assertEq(zero(BOB, OPT_ONE, F_TOKEN_1), true);
        assertEq(zero(ALICE, OPT_TWO, F_TOKEN_2), true);
        assertEq(zero(address(fund), SALE_ID, F_TOKEN_1), true);
        assertEq(zero(address(fund), SALE_ID, F_TOKEN_2), true);
    }

    function testRevertZeroAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert(ITokenSaleFund.InvalidUser.selector);
        fund.commit(address(0), OPT_TWO, F_TOKEN_1, 2);
    }

    function testRevertContractAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert(ITokenSaleFund.InvalidUser.selector);
        fund.commit(address(fund), OPT_TWO, F_TOKEN_1, 2);
    }

    function testRevertMinCommit() public {
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(ITokenSaleFund.InsufficientAmount.selector, 2, 5));
        fund.commit(ALICE, OPT_TWO, F_TOKEN_1, 2);

        assertEq(zero(ALICE, OPT_TWO, F_TOKEN_1), true);
        assertEq(zero(address(fund), SALE_ID, F_TOKEN_1), true);
    }

    function testLogFailZeroAddress() public {
        vm.prank(ADMIN);
        vm.mockCall(F_TOKEN_1, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));
        vm.mockCall(F_TOKEN_2, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));

        // we'll see zero fail and bob's succeed..
        assertEq(fund.commit(zeroAndAlice, options, tokens, amounts), true);
        assertEq(zero(address(0), OPT_ONE, F_TOKEN_1), true);

        Total memory t = fund.totals(ALICE, OPT_TWO, F_TOKEN_2);
        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 10);

        // contract totals updated
        t = fund.totals(address(fund), SALE_ID, F_TOKEN_2);
        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 10);
    }

    function testLogFailContractAddress() public {
        vm.prank(ADMIN);
        vm.mockCall(F_TOKEN_1, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));
        vm.mockCall(F_TOKEN_2, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));

        // we'll see zero fail and bob's succeed..
        assertEq(fund.commit(contractAndAlice, options, tokens, amounts), true);
        assertEq(zero(address(fund), OPT_ONE, F_TOKEN_1), true);

        Total memory t = fund.totals(ALICE, OPT_TWO, F_TOKEN_2);
        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 10);

        // contract totals updated
        t = fund.totals(address(fund), SALE_ID, F_TOKEN_2);
        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 10);
    }

    function testLogFailMinCommit() public {
        vm.prank(ADMIN);
        vm.mockCall(F_TOKEN_1, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));
        vm.mockCall(F_TOKEN_2, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));

        // we'll see bob's fail and alice's succeed..
        assertEq(fund.commit(users, options, tokens, wrongAmounts), true);
        assertEq(zero(BOB, OPT_ONE, F_TOKEN_1), true);

        Total memory t = fund.totals(ALICE, OPT_TWO, F_TOKEN_2);
        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 10);

        // contract totals updated
        t = fund.totals(address(fund), SALE_ID, F_TOKEN_2);
        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 10);
    }

    function testRevertTransferFrom() public {
        vm.prank(ADMIN);
        vm.mockCall(F_TOKEN_1, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(false));

        vm.expectRevert(abi.encodeWithSelector(ITokenSaleFund.CommitFailed.selector, ALICE, OPT_TWO, F_TOKEN_1));
        fund.commit(ALICE, OPT_TWO, F_TOKEN_1, 10);

        assertEq(zero(ALICE, OPT_TWO, F_TOKEN_1), true);
        assertEq(zero(address(fund), SALE_ID, F_TOKEN_1), true);
    }

    function testLogFailTransferFrom() public {
        vm.prank(ADMIN);
        // specifically using revert to assure trySafeTransferFrom catches it properly
        vm.mockCallRevert(F_TOKEN_1, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(false));
        vm.mockCall(F_TOKEN_2, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));

        // we'll see bob's fail and alice's succeed
        assertEq(fund.commit(users, options, tokens, amounts), true);
        assertEq(zero(BOB, OPT_ONE, F_TOKEN_1), true);

        Total memory t = fund.totals(ALICE, OPT_TWO, F_TOKEN_2);
        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 10);

        // contract totals updated
        t = fund.totals(address(fund), SALE_ID, F_TOKEN_2);
        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 10);
    }

    function testCommitOnceAlice() public {
        // the contract could have remit stopped, but commit still on
        assertEq(fund.stop(fund.REMIT_LEVEL()), true);

        vm.prank(ADMIN);
        // will pass the invariants
        vm.mockCall(F_TOKEN_1, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));

        assertEq(fund.commit(ALICE, OPT_TWO, F_TOKEN_1, 10), true);

        Total memory t = fund.totals(ALICE, OPT_TWO, F_TOKEN_1);

        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 10);

        // the public getter for commit balance is also available
        assertEq(fund.commitBalance(ALICE, OPT_TWO, F_TOKEN_1), 10);
        // this works for the contract globally as well (per token)
        assertEq(fund.commitBalance(address(fund), SALE_ID, F_TOKEN_1), 10);

        // incorrect paths to the commitBalance are still zero
        assertEq(fund.commitBalance(ALICE, OPT_ONE, F_TOKEN_1), 0);
        assertEq(fund.commitBalance(ALICE, OPT_ONE, F_TOKEN_2), 0);
        assertEq(fund.commitBalance(ALICE, OPT_TWO, F_TOKEN_2), 0);
    }

    function testCommitOnceAliceAndBob() public {
        vm.startPrank(ADMIN);
        vm.mockCall(F_TOKEN_1, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));

        assertEq(fund.commit(BOB, OPT_ONE, F_TOKEN_1, 5), true);
        Total memory t = fund.totals(BOB, OPT_ONE, F_TOKEN_1);

        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 5);
        assertEq(fund.commitBalance(BOB, OPT_ONE, F_TOKEN_1), 5);

        vm.mockCall(F_TOKEN_2, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));

        assertEq(fund.commit(ALICE, OPT_ONE, F_TOKEN_2, 10), true);
        t = fund.totals(ALICE, OPT_ONE, F_TOKEN_2);

        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 10);
        assertEq(fund.commitBalance(ALICE, OPT_ONE, F_TOKEN_2), 10);
        vm.stopPrank();

        // global totals
        t = fund.totals(address(fund), SALE_ID, F_TOKEN_1);
        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 5);
        t = fund.totals(address(fund), SALE_ID, F_TOKEN_2);
        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 10);
    }

    function testBatchRevertArrayLength() public {
        vm.prank(ADMIN);
        vm.expectRevert(ITokenSaleFund.NonEquivalentListLength.selector);

        fund.commit(tooManyUsers, options, tokens, amounts);
    }

    function testBatchCommitAliceAndBob() public {
        vm.prank(ADMIN);
        vm.mockCall(F_TOKEN_1, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));
        vm.mockCall(F_TOKEN_2, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));

        assertEq(fund.commit(users, options, tokens, amounts), true);
        Total memory t = fund.totals(BOB, OPT_ONE, F_TOKEN_1);
        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 5);

        t = fund.totals(ALICE, OPT_TWO, F_TOKEN_2);
        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 10);

        // global totals
        t = fund.totals(address(fund), SALE_ID, F_TOKEN_1);
        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 5);
        t = fund.totals(address(fund), SALE_ID, F_TOKEN_2);
        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 10);
    }

    // same token
    function testCommittedTwiceAlice() public {
        vm.startPrank(ADMIN);
        // first commit
        vm.mockCall(F_TOKEN_1, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));

        assertEq(fund.commit(ALICE, OPT_TWO, F_TOKEN_1, 5), true);
        Total memory t = fund.totals(ALICE, OPT_TWO, F_TOKEN_1);

        assertEq(t.commitCount, 1);
        assertEq(t.commitSum, 5);
        assertEq(fund.commitBalance(ALICE, OPT_TWO, F_TOKEN_1), 5);

        // second commit
        assertEq(fund.commit(ALICE, OPT_TWO, F_TOKEN_1, 10), true);
        t = fund.totals(ALICE, OPT_TWO, F_TOKEN_1);

        assertEq(t.commitCount, 2);
        assertEq(t.commitSum, 15);
        assertEq(fund.commitBalance(ALICE, OPT_TWO, F_TOKEN_1), 15);
        vm.stopPrank();

        // global totals
        t = fund.totals(address(fund), SALE_ID, F_TOKEN_1);
        assertEq(t.commitCount, 2);
        assertEq(t.commitSum, 15);
    }

    // ************************* Utility **************************

    function zero(address user, bytes32 option, address token) internal view returns (bool) {
        Total memory t = fund.totals(user, option, token);

        return t.commitCount == 0 && t.commitSum == 0;
    }
}
