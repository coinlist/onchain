// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {TokenSaleFund} from "sale/TokenSaleFund.sol";

contract FundTransfer is Test {
    TokenSaleFund public fund;
    address public constant F_TOKEN = 0x4040404040404040404040404040404040404040;
    address public constant SOMEPLACE = 0x6060606060606060606060606060606060606060;
    address public constant ADMIN = 0x1010101010101010101010101010101010101010;

    bytes4 public constant TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"));

    function setUp() public {
        fund = new TokenSaleFund(100, keccak256("abc-123"));
        // can both remit and commit, but still cannot transfer as not owner
        fund.grantRoles(ADMIN, fund.COMMIT_LEVEL() + fund.REMIT_LEVEL());
    }

    function testRevertWhenNotOwner() public {
        vm.prank(ADMIN);
        vm.expectRevert(Ownable.Unauthorized.selector);
        fund.transfer(SOMEPLACE, F_TOKEN, 10);
    }

    function testRevertTransfer() public {
        vm.mockCall(F_TOKEN, abi.encodeWithSelector(TRANSFER_SELECTOR), abi.encode(false));
        vm.expectRevert(SafeTransferLib.TransferFailed.selector);
        fund.transfer(SOMEPLACE, F_TOKEN, 10);
    }

    function testTransfer() public {
        vm.mockCall(F_TOKEN, abi.encodeWithSelector(TRANSFER_SELECTOR), abi.encode(true));

        assertEq(fund.transfer(SOMEPLACE, F_TOKEN, 50), true);
    }
}
