// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IOperable} from "./IOperable.sol";

/// @notice an abstract base with the ability to be stopped and paused
abstract contract Operable is IOperable {
  bool public stopped;

  uint32 public paused;

  // ********************* API *****************************************************

  /// @dev override/extend in child contract in order to set appropriate enforcement of access control
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
