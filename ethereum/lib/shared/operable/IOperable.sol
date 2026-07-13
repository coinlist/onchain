// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Status} from "./Types.sol";

interface IOperable {
    // ********************** Events *******************************************************

    /// @notice Emitted when owner has set a new value for the paused level
    event Paused(uint32 previous, uint32 next);

    /// @notice Emitted when owner has permanently stopped this contract
    event Stopped();

    // ********************* API ***********************************************************

    /// @notice return the current Status of this contract
    function status() external view returns (Status memory);

    /// @notice pause or unpause a chosen operation level
    function pause(uint32 level) external returns (bool);

    /// @notice stop any and all future operations in this contract
    /// @dev reads will still be available
    function stop() external returns (bool);

    // *********************** Errors *********************************************************

    /// @notice contract is paused at a given level
    error IsPaused(uint32 level);

    error IsStopped();
}
