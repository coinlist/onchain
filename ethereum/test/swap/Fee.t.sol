// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {TestToken} from "shared/TestToken.sol";
import {TokenSwap} from "swap/TokenSwap.sol";
import {ITokenSwap} from "swap/ITokenSwap.sol";
import {Preview} from "swap/Types.sol";

// base contract is abstract, thus we must create child to deploy
contract FSwap is TokenSwap {
    constructor(address token, bytes32 swapId) TokenSwap(token, swapId) {}

    function swap(address, uint256 amount, uint256) external override returns (uint256) {
        (uint256 fee,) = super.fee(amount);
        return fee;
    }

    function authorized(address user) external view override returns (bool) {
        return false;
    }

    function preview(address, uint256) external view override returns (Preview memory) {
        return Preview(0, 0, 0);
    }
}

contract Fee is Test {
    TestToken public outT;
    address public constant SOMEONE = 0x6060606060606060606060606060606060606060;
    bytes32 public constant SALE_ID = keccak256("abc-123");
    FSwap public swap;

    function setUp() public {
        outT = new TestToken("outToken", "OUTKN");
        swap = new FSwap(address(outT), SALE_ID);
    }

    function testRevertNotOwnerSetBps() public {
        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(SOMEONE);
        swap.setBps(85);
    }

    function testSetBps() public {
        assertEq(swap.setBps(85), true);
        assertEq(swap.bps(), 85);
    }

    function testRevertExceedsSetBps() public {
        // cannot exceed 100%
        vm.expectRevert(ITokenSwap.InvalidAmount.selector);
        swap.setBps(11000);

        // cannot meet 100%
        vm.expectRevert(ITokenSwap.InvalidAmount.selector);
        swap.setBps(10000);
    }

    function testFeeIsZero() public {
        // with no bps in place, fee will always be zero
        (uint256 fee, uint256 adj) = swap.fee(1000000);
        assertEq(fee, 0);
        assertEq(adj, 1000000);
    }

    function testFee() public {
        assertEq(swap.setBps(85), true);
        uint256 total = 100000000;
        (uint256 fee, uint256 adj) = swap.fee(total);
        // fee is total - adj
        assert(total - adj == fee);
        // we should see the two amounts adding back up to the given total
        assert(fee + adj == total);
    }
}
