// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "solady/auth/Ownable.sol";
import {TestToken} from "shared/TestToken.sol";
import {Registry} from "registry/Registry.sol";
import {Factory} from "factory/Factory.sol";
import {IFactory} from "factory/IFactory.sol";
import {TokenSaleFund} from "sale/TokenSaleFund.sol";
import {TokenSaleDist} from "sale/TokenSaleDist.sol";

contract DeployDist is Test {
    TestToken public token;
    Registry public reg;
    Factory public fact;
    address public constant ADMIN = 0x1010101010101010101010101010101010101010;
    address public constant SOMEONE = 0x6060606060606060606060606060606060606060;
    address public constant BOB = 0x7070707070707070707070707070707070707070;
    bytes32 public constant SALE_ID = keccak256("abc-123");

    bytes4 public constant REGISTER_SELECTOR = bytes4(keccak256("register(bytes32,uint256,address)"));

    function setUp() public {
        // intentionally a bit of an integration test
        token = new TestToken("TestToken", "TEST");
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
        fact.deployDist(address(token), SALE_ID);
    }

    function testRevertDtoken() public {
        vm.prank(ADMIN);
        vm.expectRevert(IFactory.InvalidAddress.selector);
        fact.deployDist(address(0), SALE_ID);
    }

    function testRevertAtRegistry() public {
        // the call fails at the registry for some reason...
        vm.mockCall(address(reg), abi.encodeWithSelector(REGISTER_SELECTOR), abi.encode(false));

        vm.prank(ADMIN);
        vm.expectRevert();

        fact.deployDist(address(token), SALE_ID);

        // nothing registered
        address addr = reg.registered(SALE_ID, 1);
        assertEq(addr, address(0));
    }

    function testDeploy() public {
        vm.prank(ADMIN);
        fact.deployDist(address(token), SALE_ID);

        // the address will be available at the registry
        address addr = reg.registered(SALE_ID, 1);
        // shouldn't be zero
        assertNotEq(addr, address(0));

        // owner is properly set
        assertEq(TokenSaleDist(addr).owner(), BOB);

        // no admin registered in this use case
        assertEq(TokenSaleDist(addr).rolesOf(ADMIN), 0);
    }

    function testRevertAdminZero() public {
        vm.prank(ADMIN);
        vm.expectRevert(IFactory.InvalidAddress.selector);
        fact.deployDist(address(token), SALE_ID, address(0));
    }

    function testDeployAndGrantRole() public {
        vm.prank(ADMIN);
        fact.deployDist(address(token), SALE_ID, ADMIN);

        // the address will be available at the registry
        address addr = reg.registered(SALE_ID, 1);

        // shouldn't be zero
        assertNotEq(addr, address(0));

        // owner is properly set
        assertEq(TokenSaleDist(addr).owner(), BOB);

        // admin is registered in this use case
        assertEq(TokenSaleDist(addr).rolesOf(ADMIN), 2);
    }

    // should be able to deploy fund and dist for same sale id, and be correctly registered (id: kind: addr)
    function testDeployFundAndDist() public {
        vm.startPrank(ADMIN);
        fact.deployFund(100, SALE_ID, ADMIN);
        fact.deployDist(address(token), SALE_ID, ADMIN);

        // both addrs registered
        address depFund = reg.registered(SALE_ID, 0);
        address depDist = reg.registered(SALE_ID, 1);

        assertNotEq(depFund, address(0));
        assertNotEq(depDist, address(0));
        assertEq(TokenSaleFund(depFund).owner(), BOB);
        assertEq(TokenSaleDist(depDist).owner(), BOB);
        assertEq(TokenSaleFund(depFund).rolesOf(ADMIN), 6);
        assertEq(TokenSaleDist(depDist).rolesOf(ADMIN), 2);
    }
}
