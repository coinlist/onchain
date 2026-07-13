// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @notice total amounts of inputs and outputs, including fees collected and a count of all swaps
struct SwapTotal {
    uint256 inputSum;
    uint256 feeSum;
    uint256 outputSum;
    uint256 count;
}

/// @notice input, fee and output amounts, returned from the preview method
struct Preview {
    uint256 input;
    uint256 fee;
    uint256 output;
}
