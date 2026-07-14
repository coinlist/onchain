// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {IStopable} from "./IStopable.sol";

abstract contract Stopable is IStopable {
    /// @dev flag which represents the contract's current stop level
    uint256 public stopped;

    // ********************* API *****************************************************
    
    function stop(uint256 level) public virtual returns (bool) {
        uint256 prev = stopped;

        stopped = level;

        emit Stopped(prev, stopped);

        return true;
    }

    // ********************* Modifiers *****************************************************

    modifier started(uint256 level) {
        _started(level);
        _;
    }

    function _started(uint256 level) internal view {
        // treat stopped as a bitmask
        require((stopped & level) == 0, IsStopped());
    }
}
