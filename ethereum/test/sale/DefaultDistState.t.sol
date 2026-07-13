// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {TestToken} from "shared/TestToken.sol";
import {TokenSaleDist} from "sale/TokenSaleDist.sol";
import {ITokenSaleDist} from "sale/ITokenSaleDist.sol";

contract DistDefault is Test {
    TestToken public token;
    address public constant SOMEONE = 0x6060606060606060606060606060606060606060;
    address public constant BOB = 0x7070707070707070707070707070707070707070;
    bytes32 public constant SALE_ID = keccak256("abc-123");

    function setUp() public {
        token = new TestToken("TestToken", "TEST");
    }

    function testRevertZeroDistTokenAddr() public {
        vm.expectRevert(ITokenSaleDist.InvalidAddress.selector);
        new TokenSaleDist(address(0), SALE_ID);
    }

    function testRevertNotContract() public {
        vm.expectRevert(ITokenSaleDist.InvalidAddress.selector);
        new TokenSaleDist(SOMEONE, SALE_ID);
    }

    function testDistToken() public {
        TokenSaleDist dist = new TokenSaleDist(address(token), SALE_ID);
        assertEq(dist.distToken(), address(token));
    }

    function testRevertStopWhenNotOwner() public {
        TokenSaleDist dist = new TokenSaleDist(address(token), SALE_ID);

        vm.prank(BOB);
        vm.expectRevert(Ownable.Unauthorized.selector);

        dist.stop(2);
    }
}
