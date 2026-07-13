// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

interface IStopable {
    // ********************** Events *******************************************************

    /// @notice Emitted when owner has set a new value for the stopped level
    event Stopped(uint256 previous, uint256 next);

    // ********************* API ***********************************************************

    /// @notice stop method to be overriden in child contracts
    /// @dev should take a level, set it as the current stop value. being available to owner only
    /// @dev levels use bitmask values to work in conjunction with the ownableRoles library
    /// see the abstract contract's `started` modifier for implementation
    function stop(uint256 level) external returns (bool);

    // *********************** Errors *********************************************************

    /// @dev the sale feature has been stopped by an owner
    error IsStopped();
}
