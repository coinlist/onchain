// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {TestToken} from "shared/TestToken.sol";
import {TokenSwap} from "swap/TokenSwap.sol";
import {Preview} from "swap/Types.sol";

// base contract is abstract, thus we must create child to deploy
contract DSwap is TokenSwap {
    constructor(address token, bytes32 swapId) TokenSwap(token, swapId) {}

    function swap(address, uint256 amount, uint256) external override returns (uint256) {
        // just return some bs
        return amount;
    }

    function authorized(address user) external view override returns (bool) {
        return false;
    }

    function preview(address, uint256) external view override returns (Preview memory) {
        return Preview(0, 0, 0);
    }
}

contract SwapDefault is Test {
    TestToken public inT;
    TestToken public outT;
    DSwap swap;
    address public constant SOMEONE = 0x6060606060606060606060606060606060606060;
    bytes32 public constant SALE_ID = keccak256("abc-123");

    function setUp() public {
        inT = new TestToken("inToken", "INTKN");
        outT = new TestToken("outToken", "OUTKN");
        swap = new DSwap(address(outT), SALE_ID);
    }

    function testRevertZeroOutToken() public {
        vm.expectRevert();
        new DSwap(address(0), SALE_ID);
    }

    function testRevertNotContractOutToken() public {
        vm.expectRevert();
        new DSwap(SOMEONE, SALE_ID);
    }

    function testConstructionGetters() public {
        // is owned
        assertEq(swap.owner(), address(this));
        // is not paused
        assertEq(swap.paused(), 0);
        // is not stopped
        assertEq(swap.stopped(), false);

        assertEq(swap.outputToken(), address(outT));
        assertEq(swap.id(), SALE_ID);

        // fee is zero, amount is unchanged
        (uint256 fee, uint256 adj) = swap.fee(1000000);
        assertEq(fee, 0);
        assertEq(adj, 1000000);

        // inT token is not allowed by default
        assertEq(swap.inputTokens(address(inT)), false);
    }

    function testRevertSetInputNotOwner() public {
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vm.prank(SOMEONE);

        swap.setInputToken(address(inT), true);
    }

    function testInputCanBeSet() public {
        swap.setInputToken(address(inT), true);
        assert(swap.inputTokens(address(inT)));
    }

    function testRevertPauseWhenNotOwner() public {
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vm.prank(SOMEONE);

        swap.pause(2);
    }

    function testRevertStopWhenNotOwner() public {
        vm.expectRevert(abi.encodeWithSignature("Unauthorized()"));
        vm.prank(SOMEONE);

        swap.stop();
    }

    function testPausable() public {
        swap.pause(42);
        assertEq(swap.paused(), 42);
    }

    function testStopable() public {
        swap.stop();
        assert(swap.stopped());
    }
}
