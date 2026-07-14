// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {Registry} from "registry/Registry.sol";
import {Factory} from "factory/Factory.sol";
import {IFactory} from "factory/IFactory.sol";
import {TokenSaleFund} from "sale/TokenSaleFund.sol";
import {ITokenSaleFund} from "sale/ITokenSaleFund.sol";

contract DeployFund is Test {
    Registry public reg;
    Factory public fact;
    address public constant ADMIN = 0x1010101010101010101010101010101010101010;
    address public constant SOMEONE = 0x6060606060606060606060606060606060606060;
    address public constant BOB = 0x7070707070707070707070707070707070707070;
    uint256 public constant MINIMUM = 100;
    bytes32 public constant SALE_ID = keccak256("abc-123");

    bytes4 public constant REGISTER_SELECTOR = bytes4(keccak256("register(bytes32,uint256,address)"));

    function setUp() public {
        // intentionally a bit of an integration test
        reg = new Registry();
        // factory expects a registry address at construction
        fact = new Factory(address(reg), BOB);
        // factory needs to be assigned registrar
        reg.grantRoles(address(fact), reg.REGISTER_LEVEL());
        // must be a deployer level
        fact.grantRoles(ADMIN, fact.DEPLOY_LEVEL());
    }

    function testRevertNotDeployer() public {
        vm.prank(SOMEONE);
        vm.expectRevert(Ownable.Unauthorized.selector);
        fact.deployFund(MINIMUM, SALE_ID);
    }

    function testRevertMinAmount() public {
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(ITokenSaleFund.InsufficientAmount.selector, 0, 0));
        fact.deployFund(0, SALE_ID);
    }

    function testRevertAtRegistry() public {
        // the call fails at the registry for some reason...
        vm.mockCall(address(reg), abi.encodeWithSelector(REGISTER_SELECTOR), abi.encode(false));

        vm.prank(ADMIN);
        vm.expectRevert();

        fact.deployFund(MINIMUM, SALE_ID);

        // nothing registered
        address addr = reg.registered(SALE_ID, 0);
        assertEq(addr, address(0));
    }

    function testDeploy() public {
        vm.prank(ADMIN);
        fact.deployFund(MINIMUM, SALE_ID);

        // the address will be available at the registry
        address addr = reg.registered(SALE_ID, 0);
        // shouldn't be zero
        assertNotEq(addr, address(0));

        // owner is properly set
        assertEq(TokenSaleFund(addr).owner(), BOB);

        // no admin registered in this use case
        assertEq(TokenSaleFund(addr).rolesOf(ADMIN), 0);
    }

    function testRevertAdminZero() public {
        vm.prank(ADMIN);
        vm.expectRevert(IFactory.InvalidAddress.selector);
        fact.deployFund(MINIMUM, SALE_ID, address(0));
    }

    function testDeployAndGrantRole() public {
        vm.prank(ADMIN);
        fact.deployFund(MINIMUM, SALE_ID, ADMIN);

        // the address will be available at the registry
        address addr = reg.registered(SALE_ID, 0);

        // shouldn't be zero
        assertNotEq(addr, address(0));

        // owner is properly set
        assertEq(TokenSaleFund(addr).owner(), BOB);

        // admin is registered in this use case
        assertEq(TokenSaleFund(addr).rolesOf(ADMIN), 6);
    }
}
