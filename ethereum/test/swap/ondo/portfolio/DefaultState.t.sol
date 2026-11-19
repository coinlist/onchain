// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {TestStable} from "shared/TestToken.sol";
import {OndoPortfolio} from "ondo/OndoPortfolio.sol";
import {State, SidedStatus as Status} from "shared/operable/Types.sol";

contract Manager {}

contract OndoPortfolioDefaultState is Test {
    bytes32 public constant REQ_TYPE_HASH = 0x79d6236ca1d588b1996795b0261d69b40eb4d5f89d56c5ac1301e8d7eda9acf1;
    address public constant ALICE = 0x6060606060606060606060606060606060606060;

    bytes4 public constant STABLECOIN_SELECTOR = bytes4(keccak256("stablecoin()"));
    bytes4 public constant MINTING_PAUSED_SELECTOR = bytes4(keccak256("globalMintingPaused()"));
    bytes4 public constant REDEEMING_PAUSED_SELECTOR = bytes4(keccak256("globalRedeemingPaused()"));

    TestStable usdz;
    Manager man;
    OndoPortfolio swap;

    function setUp() public {
        usdz = new TestStable("usdz", "USDZ");
        man = new Manager();
        vm.mockCall(address(man), abi.encodeWithSelector(STABLECOIN_SELECTOR), abi.encode(address(usdz)));
        swap = new OndoPortfolio(keccak256("yolo"), ALICE, address(man));
    }

    function testDefaults() public view {
        assertEq(swap.manager(), address(man));
        assertEq(swap.stablecoin(), address(usdz));
        assertEq(swap.coinList(), ALICE);
        assertEq(swap.KIND(), 3);
        assertEq(swap.VERSION(), 2);
        assertEq(swap.VERIFY_REQUEST(), REQ_TYPE_HASH);
        // the stablecoin is the one enabled input
        assert(swap.inputTokens(address(usdz)));
    }

    function testRevertManager() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidAddress()"));
        new OndoPortfolio(keccak256("yolo"), ALICE, ALICE);
    }

    function testNotPaused() public {
        assertEq(swap.paused(), 0);
        vm.mockCall(address(man), abi.encodeWithSelector(MINTING_PAUSED_SELECTOR), abi.encode(false));
        vm.mockCall(address(man), abi.encodeWithSelector(REDEEMING_PAUSED_SELECTOR), abi.encode(false));

        Status memory s = swap.status();
        assertEq(uint8(s.buyState), uint8(State.Active));
        assertEq(uint8(s.sellState), uint8(State.Active));
        assertEq(s.flags, uint32(0));
    }

    function testPause() public {
        assert(swap.pause(swap.SWAP_LEVEL()));
        // internal state takes precedence, the manager is never asked
        Status memory s = swap.status();
        assertEq(uint8(s.buyState), uint8(State.Paused));
        assertEq(uint8(s.sellState), uint8(State.Paused));
        assertEq(s.flags, swap.SWAP_LEVEL());

        assert(swap.pause(0));
        vm.mockCall(address(man), abi.encodeWithSelector(MINTING_PAUSED_SELECTOR), abi.encode(false));
        vm.mockCall(address(man), abi.encodeWithSelector(REDEEMING_PAUSED_SELECTOR), abi.encode(false));
        s = swap.status();
        assertEq(s.flags, uint32(0));
    }
}
