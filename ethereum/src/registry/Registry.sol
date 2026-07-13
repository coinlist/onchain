// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {OwnableRoles} from "solady/auth/OwnableRoles.sol";
import {IRegistry} from "./IRegistry.sol";
import {isContract} from "shared/Utils.sol";

contract Registry is IRegistry, OwnableRoles {
    // ************************ State ***************************************************************

    /// @dev non owner role that may register, typically a factory contract
    uint256 public constant REGISTER_LEVEL = 2;
    /// @dev non owner role that may zero entries in the registry
    uint256 public constant DEREGISTER_LEVEL = 4;
    /// @dev kinds and addresses for any registered contract per sale id
    mapping(bytes32 => mapping(uint256 => address)) public registered;

    constructor() {
        _initializeOwner(msg.sender);
    }

    // ************************ Admin API ***********************************************************

    function register(bytes32 id, uint256 kind, address deployment) external onlyRoles(REGISTER_LEVEL) returns (bool) {
        // invariant: the address is a deployed contract (any deployment sent here should be out of construction phase)
        require(isContract(deployment), NotContract(deployment));

        // invariant: the id, kind composite key has no assigned value
        require(registered[id][kind] == address(0), NotZero(id, kind));

        registered[id][kind] = deployment;

        emit Registered(id, kind, deployment);

        return true;
    }

    function deregister(bytes32 id, uint256 kind) external onlyRoles(DEREGISTER_LEVEL) returns (bool) {
        registered[id][kind] = address(0);

        emit Deregistered(id, kind);

        return true;
    }
}
