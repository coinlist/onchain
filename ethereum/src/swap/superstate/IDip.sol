// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Market} from "./Types.sol";

/// @notice the minimal interface for working with Superstate Dip implementing contracts
interface IDip {
    /// @notice getter for a market given its marketId
    function markets(bytes32 marketId) external view returns (Market memory);
    /// @dev returns the actual amount that would be taken (could be less than given depending on supply) and payout
    function calculateOutput(bytes32 marketId, uint256 amount, uint8 decimals) external view returns (uint256, uint256);
}
