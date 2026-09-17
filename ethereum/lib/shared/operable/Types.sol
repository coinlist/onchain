// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

enum State {
  Active, // active by default
  Paused, // currently inactive, can be reactivated
  Stopped // inactive, cannot be reactivated
}

struct Status {
  uint32 flags; // indication of internal status
  State state; // one of the above
}

// a status struct that has fields for buying and selling
struct SidedStatus {
  uint32 flags;
  State buyState; 
  State sellState;
}
