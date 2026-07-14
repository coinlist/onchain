// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {IStopable} from "shared/stopable/IStopable.sol";
import {FlyingTulipFund} from "flying-tulip/FlyingTulipFund.sol";
import {IFlyingTulipFund} from "flying-tulip/IFlyingTulipFund.sol";
import {ITokenSaleFund} from "sale/ITokenSaleFund.sol";

contract FlyingTulipInvestFor is Test {
    FlyingTulipFund public fund;
    address public constant PUT_MANAGER = 0x9090909090909090909090909090909090909090;
    address public constant F_TOKEN_1 = 0x4040404040404040404040404040404040404040;
    address public constant F_TOKEN_2 = 0x5050505050505050505050505050505050505050;
    address public constant ALICE = 0x6060606060606060606060606060606060606060;
    address public constant BOB = 0x7070707070707070707070707070707070707070;
    address public constant ADMIN = 0x8080808080808080808080808080808080808080;
    bytes32 public constant SALE_ID = keccak256("abc-123");
    bytes32 public constant OPT_ONE = keccak256("opt-12345");
    bytes32 public constant OPT_TWO = keccak256("opt-67890");
    bytes32 public constant THIS = keccak256("abc-456");
    bytes32 public constant THAT = keccak256("abc-789");
    bytes32[] public pwl = [THIS, THAT];
    address[] public users = [BOB, ALICE];
    address[] public tooManyUsers = [BOB, ALICE, ADMIN];
    bytes32[] public options = [OPT_ONE, OPT_TWO];
    address[] public tokens = [F_TOKEN_1, F_TOKEN_2];
    uint256[] public amounts = [100, 200];
    uint256[] public wrongAmounts = [10, 200];

    bytes4 public constant TRANSFER_FROM_SELECTOR = bytes4(keccak256("transferFrom(address,address,uint256)"));
    bytes4 public constant INVEST_SELECTOR = bytes4(keccak256("invest(address,uint256,address,uint256,bytes32[])"));

    function setUp() public {
        fund = new FlyingTulipFund(100, SALE_ID, PUT_MANAGER);
        fund.grantRoles(ADMIN, fund.COMMIT_LEVEL() + fund.REMIT_LEVEL());
    }

    function testRevertWhenStopped() public {
        // flying tulip used remit level for invest for
        fund.stop(fund.REMIT_LEVEL());
        vm.expectRevert(IStopable.IsStopped.selector);

        fund.investFor(ALICE, OPT_ONE, F_TOKEN_1, 100);
    }

    function testRevertWhenNotRemitter() public {
        vm.prank(ALICE);
        vm.expectRevert(Ownable.Unauthorized.selector);

        fund.investFor(ALICE, OPT_ONE, F_TOKEN_1, 100);
    }

    function testRevertWlNotSet() public {
        vm.prank(ADMIN);
        vm.expectRevert(IFlyingTulipFund.ProofWlNotSet.selector);

        fund.investFor(ALICE, OPT_ONE, F_TOKEN_1, 100);
    }

    function testBatchRevertWlNotSet() public {
        vm.prank(ADMIN);
        vm.expectRevert(IFlyingTulipFund.ProofWlNotSet.selector);

        fund.investFor(users, options, tokens, amounts);
    }

    function testRevertMinAmt() public {
        fund.setProofWl(pwl);

        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(ITokenSaleFund.InsufficientAmount.selector, 10, 100));

        fund.investFor(ALICE, OPT_ONE, F_TOKEN_1, 10);
    }

    function testRevertMinCommittment() public {
        fund.setProofWl(pwl);

        vm.prank(ADMIN);
        vm.expectRevert(
            abi.encodeWithSelector(ITokenSaleFund.InsufficientCommitment.selector, ALICE, OPT_ONE, F_TOKEN_1)
        );

        fund.investFor(ALICE, OPT_ONE, F_TOKEN_1, 100);
    }

    function testMinCommittmentOverride() public {
        fund.setProofWl(pwl);
        fund.toggleCommitBalanceOverride();

        vm.mockCall(PUT_MANAGER, abi.encodeWithSelector(INVEST_SELECTOR), abi.encode(1));

        vm.prank(ADMIN);
        assertEq(fund.investFor(ALICE, OPT_ONE, F_TOKEN_1, 100), true);
    }

    function testInvestFor() public {
        fund.setProofWl(pwl);

        // need a commit..
        vm.mockCall(F_TOKEN_1, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));
        vm.mockCall(PUT_MANAGER, abi.encodeWithSelector(INVEST_SELECTOR), abi.encode(1));

        vm.startPrank(ADMIN);
        assertEq(fund.commit(ALICE, OPT_ONE, F_TOKEN_1, 100), true);
        assertEq(fund.commitBalance(ALICE, OPT_ONE, F_TOKEN_1), 100);

        assertEq(fund.investFor(ALICE, OPT_ONE, F_TOKEN_1, 100), true);
        vm.stopPrank();
    }

    function testBatchRevertArrayLength() public {
        fund.setProofWl(pwl);

        vm.prank(ADMIN);
        vm.expectRevert(ITokenSaleFund.NonEquivalentListLength.selector);

        fund.investFor(tooManyUsers, options, tokens, amounts);
    }

    function testBatchLogFailAmount() public {
        fund.setProofWl(pwl);

        vm.mockCall(F_TOKEN_1, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));
        vm.mockCall(F_TOKEN_2, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));
        vm.startPrank(ADMIN);

        assertEq(fund.commit(users, options, tokens, amounts), true);

        vm.mockCall(PUT_MANAGER, abi.encodeWithSelector(INVEST_SELECTOR), abi.encode(1));
        // we'll see bob's fail and alice's succeed
        assertEq(fund.investFor(users, options, tokens, wrongAmounts), true);
        vm.stopPrank();
    }

    function testBatchLogFailCommittment() public {
        fund.setProofWl(pwl);

        // commits
        vm.mockCall(F_TOKEN_1, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));
        vm.mockCall(F_TOKEN_2, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));
        vm.startPrank(ADMIN);

        assertEq(fund.commit(users, options, tokens, amounts), true);

        // remit bob such that his commit bal check will fail
        assertEq(fund.remit(BOB, OPT_ONE, F_TOKEN_1, 50), true);

        vm.mockCall(PUT_MANAGER, abi.encodeWithSelector(INVEST_SELECTOR), abi.encode(1));
        // we'll see bob's fail and alice's succeed
        assertEq(fund.investFor(users, options, tokens, amounts), true);
        vm.stopPrank();
    }

    function testBatchInvestForWithOverride() public {
        fund.setProofWl(pwl);
        fund.toggleCommitBalanceOverride();

        // commits
        vm.mockCall(F_TOKEN_1, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));
        vm.mockCall(F_TOKEN_2, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));
        vm.startPrank(ADMIN);

        assertEq(fund.commit(users, options, tokens, amounts), true);

        // remit bob such that his commit bal check would fail, but is overridden
        assertEq(fund.remit(BOB, OPT_ONE, F_TOKEN_1, 50), true);

        vm.mockCall(PUT_MANAGER, abi.encodeWithSelector(INVEST_SELECTOR), abi.encode(1));
        // we'll see both succeed
        assertEq(fund.investFor(users, options, tokens, amounts), true);
        vm.stopPrank();
    }

    function testInvestForBatch() public {
        fund.setProofWl(pwl);

        // need commits..
        vm.mockCall(F_TOKEN_1, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));
        vm.mockCall(F_TOKEN_2, abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));
        vm.startPrank(ADMIN);

        assertEq(fund.commit(users, options, tokens, amounts), true);

        vm.mockCall(PUT_MANAGER, abi.encodeWithSelector(INVEST_SELECTOR), abi.encode(1));
        assertEq(fund.investFor(users, options, tokens, amounts), true);
        vm.stopPrank();
    }
}
