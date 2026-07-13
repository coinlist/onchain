// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IOperable} from "shared/operable/IOperable.sol";
// import {console} from "forge-std/console.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {TestToken} from "shared/TestToken.sol";
import {Preview, SwapTotal as Total} from "swap/Types.sol";
import {Superstate} from "superstate/Superstate.sol";
import {ITokenSwap} from "swap/ITokenSwap.sol";
import {IDippable} from "superstate/IDippable.sol";

// create a faux ss output token which implements IDippable
contract BTD is TestToken, IDippable {
    address private constant AUTHORIZED = 0x6060606060606060606060606060606060606060;
    address public constant ALSO_AUTHORIZED = 0x8080808080808080808080808080808080808080;
    address private constant DIP_CONTRACT = 0x7070707070707070707070707070707070707070;

    constructor(string memory n, string memory s) TestToken(n, s) {}

    function isAllowed(address user) external view override returns (bool) {
        return user == AUTHORIZED || user == ALSO_AUTHORIZED;
    }

    function dipContract() external view override returns (address) {
        return DIP_CONTRACT;
    }

    function buyTheDip(bytes32, uint256 amount, uint256 slip, address token) external override returns (uint256) {
        // transferFrom the calling contract to here, should have been approved
        require(IERC20(token).transferFrom(msg.sender, address(this), amount));
        // mint the slippage floor such that our ss swap contract can calculate a delta
        _mint(msg.sender, slip);

        return slip;
    }
}

contract BuyTheDip is Test {
    TestToken public inT;
    BTD public outT;
    Superstate public ss;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant ALICE = 0x6060606060606060606060606060606060606060;
    address public constant BOB = 0x7070707070707070707070707070707070707070;
    address public constant TIMMY = 0x8080808080808080808080808080808080808080;
    bytes32 public constant MKT_ID = keccak256("abc-123");
    bytes32 public constant SALE_ID = keccak256("bcd-234");

    bytes4 public constant TRANSFER_FROM_SELECTOR = bytes4(keccak256("transferFrom(address,address,uint256)"));
    bytes4 public constant APPROVE_SELECTOR = bytes4(keccak256("approve(address,uint256)"));
    bytes4 public constant IS_ALLOWED_SELECTOR = bytes4(keccak256("isAllowed(address)"));
    bytes4 public constant CALCULATE_OUTPUT_SELECTOR = bytes4(keccak256("calculateOutput(bytes32,uint256,uint8)"));

    function setUp() public {
        inT = new TestToken("InToken", "INTKN");
        outT = new BTD("outToken", "OUTKN");
        ss = new Superstate(address(outT), MKT_ID, SALE_ID);
        // input tokens must be whitelisted
        ss.setInputToken(address(inT), true);
    }

    function testMarketId() public {
        assertEq(ss.marketId(), MKT_ID);
    }

    function testUSDCApproved() public {
        assert(ss.inputTokens(USDC));
    }

    function testSetInputTokenValues() public {
        assert(ss.inputTokens(address(inT)));
        // can be unwhitelisted
        ss.setInputToken(address(inT), false);
        assertEq(ss.inputTokens(address(inT)), false);
    }

    function testRevertPaused() public {
        assert(ss.pause(ss.SWAP_LEVEL()));
        vm.expectRevert(abi.encodeWithSelector(IOperable.IsPaused.selector, ss.SWAP_LEVEL()));
        ss.swap(address(inT), 100000000, 100);
    }

    function testRevertStopped() public {
        assert(ss.stop());
        vm.expectRevert(IOperable.IsStopped.selector);
        ss.swap(address(inT), 100000000, 100);
    }

    function testRevertInputToken() public {
        vm.expectRevert(ITokenSwap.InvalidAddress.selector);
        ss.swap(TIMMY, 100000000, 100);
    }

    function testRevertTransferFrom() public {
        vm.mockCall(address(inT), abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(false));
        vm.mockCall(outT.dipContract(), abi.encodeWithSelector(CALCULATE_OUTPUT_SELECTOR), abi.encode([100000000, 100]));
        vm.expectRevert(abi.encodeWithSelector(ITokenSwap.SwapFailed.selector, ALICE, address(inT)));
        vm.prank(ALICE);
        ss.swap(address(inT), 100000000, 100);
    }

    function testRevertApprove() public {
        vm.mockCall(address(inT), abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));
        vm.mockCall(address(inT), abi.encodeWithSelector(APPROVE_SELECTOR), abi.encode(false));
        vm.mockCall(outT.dipContract(), abi.encodeWithSelector(CALCULATE_OUTPUT_SELECTOR), abi.encode([100000000, 100]));
        vm.expectRevert(SafeTransferLib.ApproveFailed.selector);
        vm.prank(ALICE);
        ss.swap(address(inT), 100000000, 100);

        // no bookkeeping set
        assert(zero(ALICE));
    }

    function testRevertMintedAmount() public {
        vm.mockCall(address(inT), abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));
        vm.mockCall(address(inT), abi.encodeWithSelector(APPROVE_SELECTOR), abi.encode(true));
        vm.mockCall(outT.dipContract(), abi.encodeWithSelector(CALCULATE_OUTPUT_SELECTOR), abi.encode([100000000, 100]));
        // force bTD to return under the slippage
        vm.mockCall(
            address(outT),
            abi.encodeWithSelector(BTD.buyTheDip.selector, MKT_ID, 100000000, 100, address(inT)),
            abi.encode(99)
        );

        vm.expectRevert(ITokenSwap.InsufficientAmount.selector);
        vm.prank(ALICE);
        ss.swap(address(inT), 100000000, 100);

        assert(zero(ALICE));
    }

    function testRevertBuyTheDip() public {
        vm.mockCall(address(inT), abi.encodeWithSelector(TRANSFER_FROM_SELECTOR), abi.encode(true));
        vm.mockCall(address(inT), abi.encodeWithSelector(APPROVE_SELECTOR), abi.encode(true));
        vm.mockCall(outT.dipContract(), abi.encodeWithSelector(CALCULATE_OUTPUT_SELECTOR), abi.encode([100000000, 100]));

        // force the call to bTD to revert
        vm.mockCallRevert(
            address(outT),
            abi.encodeWithSelector(BTD.buyTheDip.selector, MKT_ID, 100000000, 100, address(inT)),
            abi.encodeWithSelector(bytes4(0x08c379a0), "nope")
        );

        vm.expectRevert(abi.encodeWithSelector(bytes4(0x08c379a0), "nope"));
        vm.prank(ALICE);
        ss.swap(address(inT), 100000000, 100);

        assert(zero(ALICE));
    }

    function testAuthorized() public {
        assert(ss.authorized(ALICE));
        assertEq(ss.authorized(BOB), false);
    }

    function testPreview() public {
        // BTD will call its dip contract...
        vm.mockCall(
            outT.dipContract(), abi.encodeWithSelector(CALCULATE_OUTPUT_SELECTOR), abi.encode([100000000, 200000000])
        );

        // it wont matter that decimals is 18 here..
        Preview memory pre = ss.preview(address(inT), 100000000);
        assertEq(pre.input, 100000000);
        assertEq(pre.fee, 0);
        assertEq(pre.output, 200000000);
    }

    function testBuyTheDip() public {
        // alice needs balance of input token
        inT.mint(ALICE, 200000000);
        assertEq(inT.balanceOf(ALICE), 200000000);

        // alice must approve the ss contract
        vm.prank(ALICE);
        assert(inT.approve(address(ss), 100000000));
        assertEq(inT.allowance(ALICE, address(ss)), 100000000);

        // atm the output token has no input token balance
        assertEq(inT.balanceOf(address(outT)), 0);

        vm.mockCall(outT.dipContract(), abi.encodeWithSelector(CALCULATE_OUTPUT_SELECTOR), abi.encode([100000000, 100]));

        vm.prank(ALICE);
        uint256 minted = ss.swap(address(inT), 100000000, 100);
        assertEq(minted, 100);

        // the output token should now have alices input amount
        assertEq(inT.balanceOf(address(outT)), 100000000);

        Total memory t = ss.totals(ALICE, address(inT));

        assertEq(t.count, 1);
        assertEq(t.inputSum, 100000000);
        assertEq(t.outputSum, 100);
        assertEq(t.feeSum, 0);

        // the contract totals will mirror alice's here
        t = ss.totals(address(inT));
        assertEq(t.count, 1);
        assertEq(t.inputSum, 100000000);
        assertEq(t.outputSum, 100);
        assertEq(t.feeSum, 0);

        // now timmy...

        inT.mint(TIMMY, 400000000);
        assertEq(inT.balanceOf(TIMMY), 400000000);

        vm.prank(TIMMY);
        assert(inT.approve(address(ss), 200000000));
        assertEq(inT.allowance(TIMMY, address(ss)), 200000000);

        // atm the output token has alice's
        assertEq(inT.balanceOf(address(outT)), 100000000);

        vm.mockCall(outT.dipContract(), abi.encodeWithSelector(CALCULATE_OUTPUT_SELECTOR), abi.encode([200000000, 200]));

        vm.prank(TIMMY);
        minted = ss.swap(address(inT), 200000000, 200);
        assertEq(minted, 200);

        // the output token should now have alice's and timmy's input amount
        assertEq(inT.balanceOf(address(outT)), 300000000);

        t = ss.totals(TIMMY, address(inT));

        assertEq(t.count, 1);
        assertEq(t.inputSum, 200000000);
        assertEq(t.outputSum, 200);
        assertEq(t.feeSum, 0);

        // the contract totals will reflects alice's and bob's now
        t = ss.totals(address(inT));
        assertEq(t.count, 2);
        assertEq(t.inputSum, 300000000);
        assertEq(t.outputSum, 300);
        assertEq(t.feeSum, 0);

        // in a zero-fee scenario we hold no balance of the input token
        assertEq(ss.tokenBalance(address(inT)), 0);
    }

    function testBuyTheDipWithFee() public {
        assert(ss.setBps(100));

        // alice needs balance of input token
        inT.mint(ALICE, 200000000);
        assertEq(inT.balanceOf(ALICE), 200000000);

        // alice must approve the ss contract
        vm.prank(ALICE);
        assert(inT.approve(address(ss), 100000000));
        assertEq(inT.allowance(ALICE, address(ss)), 100000000);

        // atm the output token has no input token balance
        assertEq(inT.balanceOf(address(outT)), 0);

        // we can know alice's fee ahead of time
        (uint256 fee, uint256 aliceInputSum) = ss.fee(100000000);

        // mock the calc output call, don't send back more than passed in..
        vm.mockCall(
            outT.dipContract(), abi.encodeWithSelector(CALCULATE_OUTPUT_SELECTOR), abi.encode([aliceInputSum, 100])
        );

        vm.prank(ALICE);
        uint256 minted = ss.swap(address(inT), 100000000, 100);
        assertEq(minted, 100);

        // the output token should now have alices input amount
        assertEq(inT.balanceOf(address(outT)), aliceInputSum);

        Total memory t = ss.totals(ALICE, address(inT));

        assertEq(t.count, 1);
        assertEq(t.inputSum, aliceInputSum);
        assertEq(t.outputSum, 100);
        assertEq(t.feeSum, fee);

        // the contract totals will mirror alice's here
        t = ss.totals(address(inT));
        assertEq(t.count, 1);
        assertEq(t.inputSum, aliceInputSum);
        assertEq(t.outputSum, 100);
        assertEq(t.feeSum, fee);

        // now timmy...
        inT.mint(TIMMY, 400000000);
        assertEq(inT.balanceOf(TIMMY), 400000000);

        vm.prank(TIMMY);
        assert(inT.approve(address(ss), 200000000));
        assertEq(inT.allowance(TIMMY, address(ss)), 200000000);

        uint256 prevfee = fee;

        // timmy's fee amounts
        uint256 timmyInputSum;
        (fee, timmyInputSum) = ss.fee(200000000);

        // timmy's returned amount needs to be set..
        vm.mockCall(
            outT.dipContract(), abi.encodeWithSelector(CALCULATE_OUTPUT_SELECTOR), abi.encode([timmyInputSum, 200])
        );

        vm.prank(TIMMY);
        minted = ss.swap(address(inT), 200000000, 200);
        assertEq(minted, 200);

        // the output token should now have alice's and timmy's input amount
        assertEq(inT.balanceOf(address(outT)), aliceInputSum + timmyInputSum);

        t = ss.totals(TIMMY, address(inT));

        assertEq(t.count, 1);
        assertEq(t.inputSum, timmyInputSum);
        assertEq(t.outputSum, 200);
        assertEq(t.feeSum, fee);

        // the contract totals will reflects alice's and timmy's now
        t = ss.totals(address(inT));
        assertEq(t.count, 2);
        assertEq(t.inputSum, aliceInputSum + timmyInputSum);
        assertEq(t.outputSum, 300);
        assertEq(t.feeSum, prevfee + fee);

        // in a fee collecting scenario, until transferred, the input token balance will reflect the feeSum
        assertEq(ss.tokenBalance(address(inT)), t.feeSum);
    }

    function testSuccessiveSwaps() public {
        // run swaps in quick succession assuring balance is not falsely reported
        // contract calls are atomic so this isn't technically necessary...
        inT.mint(ALICE, 200000000);
        inT.mint(TIMMY, 300000000);

        vm.prank(ALICE);
        assert(inT.approve(address(ss), 100000000));
        vm.prank(TIMMY);
        assert(inT.approve(address(ss), 200000000));

        vm.mockCall(outT.dipContract(), abi.encodeWithSelector(CALCULATE_OUTPUT_SELECTOR), abi.encode([100000000, 100]));
        vm.prank(ALICE);
        uint256 aliceMinted = ss.swap(address(inT), 100000000, 100);

        vm.mockCall(outT.dipContract(), abi.encodeWithSelector(CALCULATE_OUTPUT_SELECTOR), abi.encode([200000000, 200]));
        vm.prank(TIMMY);
        uint256 bobMinted = ss.swap(address(inT), 200000000, 200);

        // if the calls were not atomic we'd accidentally txfer bob more than his 200 as the delta could be wrong
        assertEq(aliceMinted, 100);
        assertEq(bobMinted, 200);
    }

    // ************************* Utility **************************

    function zero(address user) internal view returns (bool) {
        Total memory t = ss.totals(user, address(inT));
        return t.count == 0 && t.inputSum == 0 && t.outputSum == 0 && t.feeSum == 0;
    }
}
