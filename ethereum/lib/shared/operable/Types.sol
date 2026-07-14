// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

enum State {
  Active, // active by default
  Paused, // currently inactive, can be reactivated
  Stopped // inactive, cannot be reactivated
}

struct Status {
  State state; // one of the above
  uint32 flags; // indication of internal status
}
