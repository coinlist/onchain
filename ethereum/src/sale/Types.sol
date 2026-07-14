// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @dev the types of batch operations
enum BatchType {
    Commit,
    Remit,
    Distribute
}

/// @dev total amounts of commits and remits
struct SaleTotal {
    uint256 commitCount;
    uint256 commitSum;
    uint256 remitCount;
    uint256 remitSum;
}

struct DistTotal {
    uint256 distCount;
    uint256 distSum;
}
