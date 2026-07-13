// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

interface IRegistry {
    // *************************** Events ***********************************************************

    /// @notice Emitted upon successful registration
    event Registered(bytes32 indexed id, uint256 indexed kind, address indexed deployment);
    /// @notice Emitted upon successful deregistration
    event Deregistered(bytes32 indexed id, uint256 indexed kind);

    // *************************** API **************************************************************

    /// @notice given an id, kind and deployment address register a deployed contract
    function register(bytes32 id, uint256 kind, address deployment) external returns (bool);
    /// @notice given an id and a kind  deregister a contract
    function deregister(bytes32 id, uint256 kind) external returns (bool);

    // ************************** Errors ************************************************************

    /// @dev if a given address is not an actual deployed contract
    error NotContract(address deployment);
    /// @dev the given id/kind is already registered
    error NotZero(bytes32 id, uint256 kind);
}
