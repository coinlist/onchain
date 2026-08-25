// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @notice differentiation of swap types
enum Side {
    Buy,
    Sell
}

/// @notice total amounts of inputs and outputs, including fees collected and a count of all swaps
struct SwapTotal {
    uint256 inputSum;
    uint256 feeSum;
    uint256 outputSum;
    uint256 count;
}

/// @notice storage optimized multi-swap totals struct made to fit in a single slot
/// @dev count is allowed to be rolled over to 0 as its only used to sync signatures in the short term
struct OptimizedSwapTotal {
    uint88 inputSum;
    uint72 feeSum;
    uint88 outputSum;
    uint8 count;
}

/// @notice input, fee and output amounts, returned from the preview method
struct Preview {
    uint256 input;
    uint256 fee;
    uint256 output;
}
