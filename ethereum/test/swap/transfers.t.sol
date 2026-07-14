// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {TestToken} from "shared/TestToken.sol";
import {TokenSwap} from "swap/TokenSwap.sol";
import {Preview} from "swap/Types.sol";

// base contract is abstract, thus we must create child to deploy
contract TSwap is TokenSwap {
    constructor(address token, bytes32 swapId) TokenSwap(token, swapId) {}

    function swap(address, uint256, uint256) external override returns (uint256) {
        return 0;
    }

    function authorized(address user) external view override returns (bool) {
        return false;
    }

    function preview(address, uint256) external view override returns (Preview memory) {
        return Preview(0, 0, 0);
    }
}

contract Transfers is Test {
    TestToken public inT;
    TestToken public outT;
    address public constant SOMEONE = 0x1010101010101010101010101010101010101010;
    address public constant SOMEONE_ELSE = 0x6060606060606060606060606060606060606060;
    bytes32 public constant SALE_ID = keccak256("abc-123");
    TSwap public swap;

    function setUp() public {
        inT = new TestToken("InToken", "INTKN");
        outT = new TestToken("outToken", "OUTKN");
        swap = new TSwap(address(outT), SALE_ID);

        // mint the swap some bal..
        inT.mint(address(swap), 100);
        outT.mint(address(swap), 100);
    }

    function testRevertNotOwnerTxferInput() public {
        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(SOMEONE);

        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        swap.transfer(SOMEONE_ELSE, address(inT), 10000000000);
    }

    function testRevertNotOwnerTxferOutput() public {
        vm.expectRevert(Ownable.Unauthorized.selector);
        vm.prank(SOMEONE);

        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        swap.transfer(SOMEONE_ELSE, 10000000000);
    }

    function testTxferInput() public {
        assertEq(swap.tokenBalance(address(inT)), 100);
        assertEq(inT.balanceOf(SOMEONE), 0);
        assert(swap.transfer(SOMEONE, address(inT), 50));
        assertEq(inT.balanceOf(SOMEONE), 50);
        assertEq(swap.tokenBalance(address(inT)), 50);
    }

    function testTransferOutput() public {
        assertEq(swap.outputTokenBalance(), 100);
        assertEq(outT.balanceOf(SOMEONE), 0);
        assert(swap.transfer(SOMEONE, 50));
        assertEq(outT.balanceOf(SOMEONE), 50);
        assertEq(swap.outputTokenBalance(), 50);
    }
}
