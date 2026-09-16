// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Status} from "./Types.sol";

interface IReportable {
    /// @notice return the current Status of this contract
    function status() external view returns (Status memory);
}
