// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Operable} from "./Operable.sol";
import {ISidedReportable} from "./ISidedReportable.sol";
import {State, SidedStatus} from "./Types.sol";

/// @notice a "side aware" abstract base with the ability to report its state,
/// @dev this base class will set both buy and sell state together if stopped or paused
abstract contract SidedReportable is Operable, ISidedReportable {

  /// @dev returns a Status if present on this contract
  function status() public virtual view returns (SidedStatus memory) {
    SidedStatus memory stat;

    // stopped takes precedence
    if (stopped) {
      stat.flags = 1;
      stat.buyState = State.Stopped;
      stat.sellState = State.Stopped;
      // we'll include a value in the flags here to indicate stopped came from us
    } else if (paused > 0) {
      stat.flags = paused;
      stat.buyState = State.Paused;
      stat.sellState = State.Paused;
    }

    return stat;
  }
}
