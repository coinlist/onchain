// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IOperable} from "./IOperable.sol";
import {State, Status} from "./Types.sol";

abstract contract Operable is IOperable {
  bool public stopped;

  uint32 public paused;

  // ********************* API *****************************************************

  /// @dev returns a Status if present on this contract
  function status() public virtual view returns (Status memory) {
    Status memory stat;

    // stopped takes precedence
    if (stopped) {
      stat.state = State.Stopped;
      // we'll include a value in the flags here to indicate stopped came from us
      stat.flags = 1;
    } else if (paused > 0) {
      stat.state = State.Paused;
      stat.flags = paused;
    }

    return stat;
  }

  /// @dev override in child contract in order to set appropriate access control
  function pause(uint32 level) public virtual returns (bool) {
    uint32 prev = paused;

    paused = level;

    emit Paused(prev, paused);

    return true;
  }

  /// @dev override in child contract in order to set appropriate access control
  function stop() public virtual returns (bool) {
    // NOTE: cannot be undone 
    stopped = true;

    emit Stopped();

    return stopped;
  }

  // ********************* Modifiers *****************************************************

  modifier active(uint32 level) {
    _active(level);
    _;
  }

  function _active(uint32 level) internal view {
    // stopped takes precedence regardless
    require(!stopped, IsStopped());
    // treat paused as a bitmask
    require((paused & level) == 0, IsPaused(level));
  }
}
