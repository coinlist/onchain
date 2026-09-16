// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {SidedStatus} from "./Types.sol";

interface ISidedReportable {
    /// @notice return the current status of this "sided" contract
    function status() external view returns (SidedStatus memory);
}
