// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {TestStable} from "shared/TestToken.sol";
import {OndoMarket} from "ondo/OndoMarket.sol";
import {State, SidedStatus as Status} from "shared/operable/Types.sol";

contract Manager {}

contract OndoDefaultState is Test {
    bytes32 public constant REQ_TYPE_HASH = 0x79d6236ca1d588b1996795b0261d69b40eb4d5f89d56c5ac1301e8d7eda9acf1;
    address public constant ALICE = 0x6060606060606060606060606060606060606060;
    Manager man;
    OndoMarket swap;

    bytes4 public constant MINTING_PAUSED_SELECTOR = bytes4(keccak256("globalMintingPaused()"));
    bytes4 public constant REDEEMING_PAUSED_SELECTOR = bytes4(keccak256("globalRedeemingPaused()"));

    function setUp() public {
        man = new Manager();
        // can pass zero address for no input token at launch
        swap = new OndoMarket(keccak256("yolo"), ALICE, address(man), address(0));
    }

    function testRevertTokenConst() public {
        // alice obvs is not a valid token
        vm.expectRevert();
        new OndoMarket(keccak256("yolo"), ALICE, address(man), ALICE);
    }

    function testIdentity() public view {
        assertEq(swap.KIND(), 3);
        assertEq(swap.VERSION(), 2);
        assertEq(swap.manager(), address(man));
        assertEq(swap.coinList(), ALICE);
    }

    /// @dev the market side takes any valid token, only OndoPortfolio restricts its inputs
    function testAnyInputToken() public {
        TestStable one = new TestStable("one", "ONE");
        TestStable two = new TestStable("two", "TWO");
        assert(swap.setInputToken(address(one), true));
        assert(swap.setInputToken(address(two), true));
        assert(swap.inputTokens(address(one)));
        assert(swap.inputTokens(address(two)));
    }

    function testRevertManager() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        new OndoMarket(keccak256("yolo"), ALICE, ALICE, address(0));
        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        new OndoMarket(keccak256("yolo"), ALICE, address(0), address(0));
    }

    function testRequestTypeHash() public {
        assertEq(swap.VERIFY_REQUEST(), REQ_TYPE_HASH);
    }

    function testNotPaused() public {
        assertEq(swap.paused(), 0);

        // stub the managers global calls here
        vm.mockCall(address(man), abi.encodeWithSelector(MINTING_PAUSED_SELECTOR), abi.encode(false));
        vm.mockCall(address(man), abi.encodeWithSelector(REDEEMING_PAUSED_SELECTOR), abi.encode(false));

        Status memory s = swap.status();
        assertEq(uint8(s.buyState), uint8(State.Active));
        assertEq(uint8(s.sellState), uint8(State.Active));
        assertEq(s.flags, uint32(0));
    }

    function testRevertPause() public {
        vm.expectRevert(4);
        // should only accept 0 (unpause) and honored SWAP_LEVEL values
        swap.pause(1);
        // NOTE a decimal value of 3 would pass and behave as expected
        swap.pause(4);
        swap.pause(5);
        swap.pause(8);
    }

    function testPause() public {
        assertEq(swap.paused(), 0);
        assert(swap.pause(swap.SWAP_LEVEL()));
        assertEq(swap.paused(), swap.SWAP_LEVEL());
        // internal state will take precedence..
        Status memory s = swap.status();
        assertEq(uint8(s.buyState), uint8(State.Paused));
        assertEq(uint8(s.sellState), uint8(State.Paused));
        // we use flags as an indication that WE have caused the status
        assertEq(s.flags, swap.SWAP_LEVEL());

        // can be unpaused
        assert(swap.pause(0));

        vm.mockCall(address(man), abi.encodeWithSelector(MINTING_PAUSED_SELECTOR), abi.encode(false));
        vm.mockCall(address(man), abi.encodeWithSelector(REDEEMING_PAUSED_SELECTOR), abi.encode(false));

        s = swap.status();
        assertEq(uint8(s.buyState), uint8(State.Active));
        assertEq(uint8(s.sellState), uint8(State.Active));
        assertEq(s.flags, uint32(0));
    }
}
