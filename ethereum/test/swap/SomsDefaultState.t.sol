// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {TestToken} from "shared/TestToken.sol";
import {Soms} from "swap/Soms.sol";
import {Side} from "swap/Types.sol";

contract TooManyD is TestToken {
    constructor(string memory n, string memory s) TestToken(n, s) {}

    function decimals() public pure override returns (uint8) {
        return 26;
    }
}

contract Foo is Soms {
    constructor(bytes32 swapId) Soms(swapId) {}
}

contract SomsDefault is Test {
    TestToken public inT;
    TestToken public outT;
    Foo swap;
    address public constant SOMEONE = 0x6060606060606060606060606060606060606060;
    bytes32 public constant SALE_ID = keccak256("abc-123");

    function setUp() public {
        inT = new TestToken("inToken", "INTKN");
        outT = new TestToken("outToken", "OUTKN");
        swap = new Foo(SALE_ID);
    }

    function testConstructionGetters() public {
        // is owned
        assertEq(swap.owner(), address(this));
        // is not paused
        assertEq(swap.paused(), 0);
        // is not stopped
        assertEq(swap.stopped(), false);

        assertEq(swap.id(), SALE_ID);

        // mint fee is zero, amount is unchanged
        (uint256 fee, uint256 adj) = swap.fee(Side.Buy, 1000000);
        assertEq(fee, 0);
        assertEq(adj, 1000000);

        // redeem fee is zero, amount is unchanged
        (fee, adj) = swap.fee(Side.Sell, 1000000);
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

    function testRevertInputDecimals() public {
        TooManyD t = new TooManyD("tooManyD", "tmd");

        vm.expectRevert(abi.encodeWithSignature("InvalidDecimals()"));
        swap.setInputToken(address(t), true);
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
