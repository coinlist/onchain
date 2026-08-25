// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {TestToken} from "shared/TestToken.sol";
import {Soms} from "swap/Soms.sol";
import {Side} from "swap/Types.sol";

contract Foo is Soms {
    constructor(bytes32 swapId) Soms(swapId) {}
}

contract SomsDefault is Test {
    Foo swap;
    address public constant SOMEONE = 0x6060606060606060606060606060606060606060;
    bytes32 public constant SALE_ID = keccak256("abc-123");

    function setUp() public {
        swap = new Foo(SALE_ID);
    }

    function testRevertNotOwnerSetBps() public {
        vm.expectRevert();
        vm.prank(SOMEONE);
        swap.setBps(Side.Buy, 85);
    }

    function testSetBps() public {
        assertEq(swap.setBps(Side.Buy, 85), true);
        assertEq(swap.bps(uint256(Side.Buy)), 85);
        assertEq(swap.setBps(Side.Sell, 50), true);
        assertEq(swap.bps(uint256(Side.Sell)), 50);
    }

    function testRevertExceedsSetBps() public {
        // cannot exceed 100%
        vm.expectRevert();
        swap.setBps(Side.Sell, 11000);

        // cannot meet 100%
        vm.expectRevert();
        swap.setBps(Side.Buy, 10000);
    }

    function testFeeIsZero() public {
        // with no bps in place, fee will always be zero
        (uint256 fee, uint256 adj) = swap.fee(Side.Buy, 1000000);
        assertEq(fee, 0);
        assertEq(adj, 1000000);

        (fee, adj) = swap.fee(Side.Sell, 1000000);
        assertEq(fee, 0);
        assertEq(adj, 1000000);
    }

    function testFee() public {
        assertEq(swap.setBps(Side.Buy, 85), true);
        uint256 total = 100000000;
        (uint256 fee, uint256 adj) = swap.fee(Side.Buy, total);
        // fee is total - adj
        assert(total - adj == fee);
        // we should see the two amounts adding back up to the given total
        assert(fee + adj == total);

        assertEq(swap.setBps(Side.Sell, 25), true);
        (fee, adj) = swap.fee(Side.Sell, total);
        // fee is total - adj
        assert(total - adj == fee);
        // we should see the two amounts adding back up to the given total
        assert(fee + adj == total);
    }

    function testBpp() public {
        assertEq(swap.setBps(Side.Buy, 85), true);
        uint256 total = 100000000;
        uint256 bp = swap.bpp(Side.Buy, total);
        assertEq(bp, 850000);

        assertEq(swap.setBps(Side.Sell, 25), true);
        bp = swap.bpp(Side.Sell, total);
        assertEq(bp, 250000);
    }
}
