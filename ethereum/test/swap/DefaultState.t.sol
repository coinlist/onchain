// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {TestToken} from "shared/TestToken.sol";
import {TokenSwap} from "swap/TokenSwap.sol";
import {ITokenSwap} from "swap/ITokenSwap.sol";
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
    TestToken public outT;
    address public constant SOMEONE = 0x6060606060606060606060606060606060606060;
    bytes32 public constant SALE_ID = keccak256("abc-123");

    function setUp() public {
        outT = new TestToken("outToken", "OUTKN");
    }

    function testRevertZeroOutToken() public {
        vm.expectRevert(ITokenSwap.InvalidAddress.selector);
        new DSwap(address(0), SALE_ID);
    }

    function testRevertNotContractOutToken() public {
        vm.expectRevert(ITokenSwap.InvalidAddress.selector);
        new DSwap(SOMEONE, SALE_ID);
    }

    function testConstructionGetters() public {
        DSwap swap = new DSwap(address(outT), SALE_ID);

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
    }

    function testRevertPauseWhenNotOwner() public {
        DSwap swap = new DSwap(address(outT), SALE_ID);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(SOMEONE);

        swap.pause(2);
    }

    function testRevertStopWhenNotOwner() public {
        DSwap swap = new DSwap(address(outT), SALE_ID);

        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(SOMEONE);

        swap.stop();
    }

    function testPausable() public {
        DSwap swap = new DSwap(address(outT), SALE_ID);
        swap.pause(42);
        assertEq(swap.paused(), 42);
    }

    function testStopable() public {
        DSwap swap = new DSwap(address(outT), SALE_ID);
        swap.stop();
        assert(swap.stopped());
    }
}
