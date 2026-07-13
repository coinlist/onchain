// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {OwnableRoles} from "solady/auth/OwnableRoles.sol";
import {Registry} from "registry/Registry.sol";
import {TokenSaleFund} from "sale/TokenSaleFund.sol";
import {TokenSaleDist} from "sale/TokenSaleDist.sol";
import {isContract} from "shared/Utils.sol";
import {IFactory} from "./IFactory.sol";

contract Factory is IFactory, OwnableRoles {
    // ************************ State ***************************************************************

    /// @dev non owner role that can deploy
    uint256 public constant DEPLOY_LEVEL = 2;
    /// @dev address of the deployed registry contract
    address public registry;
    /// @dev address set to owner of any deployed contracts
    address public deploymentOwner;

    constructor(address reg, address depOwner) {
        // invariant: non zero address is a contract
        require(reg != address(0) && isContract(reg), InvalidAddress());
        // invariant: deploymentOwner must be set to non zero
        require(depOwner != address(0), InvalidAddress());

        _initializeOwner(msg.sender);
        registry = reg;
        deploymentOwner = depOwner;
    }

    // ************************ Admin API ***********************************************************

    function deployFund(uint256 min, bytes32 id) external onlyRoles(DEPLOY_LEVEL) returns (bool) {
        (TokenSaleFund fund, uint256 kind, address addr) = _deployFund(min, id);

        fund.transferOwnership(deploymentOwner);

        // invariant: registration succeeds
        require(Registry(registry).register(id, kind, addr));

        return true;
    }

    function deployFund(uint256 min, bytes32 id, address admin) external onlyRoles(DEPLOY_LEVEL) returns (bool) {
        require(admin != address(0), InvalidAddress());

        (TokenSaleFund fund, uint256 kind, address addr) = _deployFund(min, id);

        fund.grantRoles(admin, fund.COMMIT_LEVEL() + fund.REMIT_LEVEL());
        fund.transferOwnership(deploymentOwner);

        // invariant: registration succeeds
        require(Registry(registry).register(id, kind, addr));

        return true;
    }

    function _deployFund(uint256 min, bytes32 id) internal returns (TokenSaleFund, uint256, address) {
        TokenSaleFund fund = new TokenSaleFund(min, id);
        uint256 kind = fund.KIND();
        address addr = address(fund);

        emit Deployed(id, kind, addr);

        return (fund, kind, addr);
    }

    function deployDist(address dToken, bytes32 id) external onlyRoles(DEPLOY_LEVEL) returns (bool) {
        (TokenSaleDist dist, uint256 kind, address addr) = _deployDist(dToken, id);

        dist.transferOwnership(deploymentOwner);

        // invariant: registration succeeds
        require(Registry(registry).register(id, kind, addr));

        return true;
    }

    function deployDist(address dToken, bytes32 id, address admin) external onlyRoles(DEPLOY_LEVEL) returns (bool) {
        require(admin != address(0), InvalidAddress());

        (TokenSaleDist dist, uint256 kind, address addr) = _deployDist(dToken, id);

        dist.grantRoles(admin, dist.DISTRIBUTE_LEVEL());
        dist.transferOwnership(deploymentOwner);

        // invariant: registration succeeds
        require(Registry(registry).register(id, kind, addr));

        return true;
    }

    function _deployDist(address dToken, bytes32 id) internal returns (TokenSaleDist, uint256, address) {
        TokenSaleDist dist = new TokenSaleDist(dToken, id);
        uint256 kind = dist.KIND();
        address addr = address(dist);

        emit Deployed(id, kind, addr);

        return (dist, kind, addr);
    }

    // ************************ Owner API ***********************************************************

    function setDeploymentOwner(address depOwner) external onlyOwner returns (bool) {
        // invariant: deployment owner cannot be 0 address
        require(depOwner != address(0), InvalidAddress());

        deploymentOwner = depOwner;

        return true;
    }
}
