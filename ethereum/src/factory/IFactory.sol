// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

interface IFactory {
    // *************************** Events ***********************************************************

    /// @notice Emitted upon successful contract deployment
    event Deployed(bytes32 indexed id, uint256 indexed kind, address indexed deployment);

    // *************************** API **************************************************************

    /// @notice given a minimum amount and a sale id, deploy a new TokenSaleFund and register it
    /// @dev ownership is transferred to deploymentOwner on successful deployment and registration
    function deployFund(uint256 min, bytes32 id) external returns (bool);

    /// @notice given a minimum amount, a sale id and an address, deploy a new TokenSaleFund,
    /// set the address as admin level (commit + remit) role, and register it
    /// @dev ownership is transferred to deploymentOwner on successful deployment, assignment, and registration
    function deployFund(uint256 min, bytes32 id, address admin) external returns (bool);

    /// @notice given a distribution token and a sale id, deploy a new TokenSaleDist and register it
    /// @dev ownership is transferred to deploymentOwner on successful deployment and registration
    function deployDist(address dToken, bytes32 id) external returns (bool);

    /// @notice given a distribution token, a token sale id and an address, deploy a new TokenSaleDist,
    /// set the address as distribute level role, and register it
    /// @dev ownership is transferred to deploymentOwner on successful deployment, assignment, and registration
    function deployDist(address dToken, bytes32 id, address admin) external returns (bool);

    /// @notice set the address which will be used as the owner for any new deployments
    function setDeploymentOwner(address depOwner) external returns (bool);

    // *********************** Errors *********************************************************

    /// @dev the given address is invalid
    error InvalidAddress();
}
