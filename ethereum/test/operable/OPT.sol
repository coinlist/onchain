// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Ownable} from "solady/auth/Ownable.sol";
import {State, Status} from "shared/operable/Types.sol";
import {Operable} from "shared/operable/Operable.sol";

/// @notice a test dummy for validating the operable lib
contract OPT is Ownable, Operable {
    // use as extended functionality for status method override
    uint8 public otherStatus;
    uint8 public foo;
    uint8 public bar;

    // some example operation levels that can be paused
    uint32 public constant FOO_LEVEL = 2;
    uint32 public constant BAR_LEVEL = 4;

    constructor() {
        _initializeOwner(msg.sender);
    }

    function setOtherStatus(uint8 n) external returns (bool) {
        otherStatus = n;
        return true;
    }

    // extend the status method to check other status as well..
    function status() public view override returns (Status memory) {
        Status memory stat = super.status();
        // only set a state if we have not already as ours take precedence
        // let's say target other thing has {0,1,2,3,4} with us mapping them to our own values
        if (stat.state == State.Active && otherStatus != 1) {
            // we'll say their 0 and 2 are equivalent to paused
            if (otherStatus < 3) {
                stat.state = State.Paused;
            } else {
                // and 3,4 mean stopped to us
                stat.state = State.Stopped;
            }
        }

        return stat;
    }

    function pause(uint32 level) public override onlyOwner returns (bool) {
        return super.pause(level);
    }

    function stop() public override onlyOwner returns (bool) {
        return super.stop();
    }

    function setFoo(uint8 newFoo) external active(FOO_LEVEL) returns (bool) {
        foo = newFoo;
        return true;
    }

    function setBar(uint8 newBar) external active(BAR_LEVEL) returns (bool) {
        bar = newBar;
        return true;
    }
}
