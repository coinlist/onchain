// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {Registry} from "registry/Registry.sol";
import {Factory} from "factory/Factory.sol";
import {IFactory} from "factory/IFactory.sol";

contract FactoryDefault is Test {
    address public constant SOMEONE = 0x6060606060606060606060606060606060606060;
    address public constant BOB = 0x7070707070707070707070707070707070707070;
    bytes32 public constant SALE_ID = keccak256("abc-123");

    function testRevertZeroRegAddr() public {
        vm.expectRevert(IFactory.InvalidAddress.selector);
        new Factory(address(0), BOB);
    }

    function testRevertNotContract() public {
        vm.expectRevert(IFactory.InvalidAddress.selector);
        new Factory(SOMEONE, BOB);
    }

    function testRevertZeroDepOwner() public {
        Registry reg = new Registry();

        vm.expectRevert(IFactory.InvalidAddress.selector);
        new Factory(address(reg), address(0));
    }

    function testRegistryaddr() public {
        Registry reg = new Registry();
        Factory fact = new Factory(address(reg), BOB);

        assertEq(fact.registry(), address(reg));
    }

    function testDepOwneraddr() public {
        Registry reg = new Registry();
        Factory fact = new Factory(address(reg), BOB);

        assertEq(fact.deploymentOwner(), BOB);
    }

    function testRevertNotOwner() public {
        Registry reg = new Registry();
        Factory fact = new Factory(address(reg), BOB);

        vm.prank(BOB);
        vm.expectRevert(Ownable.Unauthorized.selector);
        fact.setDeploymentOwner(SOMEONE);
    }

    function testRevertSetDepOwner() public {
        Registry reg = new Registry();
        Factory fact = new Factory(address(reg), BOB);

        vm.expectRevert(IFactory.InvalidAddress.selector);
        fact.setDeploymentOwner(address(0));
    }

    function testSetDepOwner() public {
        Registry reg = new Registry();
        Factory fact = new Factory(address(reg), BOB);

        fact.setDeploymentOwner(SOMEONE);

        assertEq(fact.deploymentOwner(), SOMEONE);
    }
}
