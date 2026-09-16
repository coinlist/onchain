// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Operable} from "./Operable.sol";
import {IReportable} from "./IReportable.sol";
import {State, Status} from "./Types.sol";

/// @notice an abstract base with the ability to report its state
abstract contract Reportable is Operable, IReportable {

  /// @dev returns a Status if present on this contract
  function status() public virtual view returns (Status memory) {
    Status memory stat;

    // stopped takes precedence
    if (stopped) {
      // we'll include a value in the flags here to indicate stopped came from us
      stat.flags = 1;
      stat.state = State.Stopped;
    } else if (paused > 0) {
      stat.flags = paused;
      stat.state = State.Paused;
    }

    return stat;
  }
}
