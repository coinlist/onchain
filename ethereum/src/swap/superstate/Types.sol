// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

enum MarketState {
    Initialized, // Created, not yet active
    Active, // Live for purchases (one per instrument)
    Paused, // Suspended, reactivatable
    Closed, // Complete (target reached)
    Cancelled // Terminated by admin
}

struct Market {
    MarketState state;
}
