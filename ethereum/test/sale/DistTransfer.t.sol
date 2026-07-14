// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {TestToken} from "shared/TestToken.sol";
import {TokenSaleDist} from "sale/TokenSaleDist.sol";

contract DistTransfer is Test {
    TestToken public token;
    TokenSaleDist public dist;
    address public constant A_TOKEN = 0x4040404040404040404040404040404040404040;
    address public constant SOMEPLACE = 0x6060606060606060606060606060606060606060;
    address public constant ADMIN = 0x1010101010101010101010101010101010101010;

    bytes4 public constant TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"));

    function setUp() public {
        token = new TestToken("TestToken", "TEST");
        dist = new TokenSaleDist(address(token), keccak256("abc-123"));
        dist.grantRoles(ADMIN, dist.DISTRIBUTE_LEVEL());
    }

    function testRevertWhenNotOwner() public {
        vm.prank(ADMIN);
        vm.expectRevert(Ownable.Unauthorized.selector);
        // assert doesn't matter here...
        assertEq(dist.transfer(SOMEPLACE, 10), false);
    }

    function testRevertWhenNotOwnerExt() public {
        vm.prank(ADMIN);
        vm.expectRevert(Ownable.Unauthorized.selector);
        assertEq(dist.transfer(SOMEPLACE, A_TOKEN, 10), false);
    }

    function testRevertTransfer() public {
        vm.mockCall(address(token), abi.encodeWithSelector(TRANSFER_SELECTOR), abi.encode(false));
        vm.expectRevert(SafeTransferLib.TransferFailed.selector);
        assertEq(dist.transfer(SOMEPLACE, 10), false);
    }

    function testRevertTransferExt() public {
        vm.mockCall(A_TOKEN, abi.encodeWithSelector(TRANSFER_SELECTOR), abi.encode(false));
        vm.expectRevert(SafeTransferLib.TransferFailed.selector);
        dist.transfer(SOMEPLACE, A_TOKEN, 10);
    }

    function testTransfer() public {
        // get a balance
        token.mint(address(dist), 50);

        assertEq(dist.distributionTokenBalance(), 50);
        assertEq(dist.transfer(SOMEPLACE, 50), true);
        // should have a zero bal
        assertEq(dist.distributionTokenBalance(), 0);
    }

    function testTransferExt() public {
        vm.mockCall(A_TOKEN, abi.encodeWithSelector(TRANSFER_SELECTOR), abi.encode(true));
        assertEq(dist.transfer(SOMEPLACE, A_TOKEN, 50), true);
    }
}
