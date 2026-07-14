// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice the interface for the flying tulip contract we will be calling
interface IPutManager {
    function invest(address token, uint256 amount, address recipient, uint256 proofAmount, bytes32[] calldata proofWl)
        external
        returns (uint256);
}

interface IFlyingTulipFund {
    // ********************* Events *******************************************************************

    /// @notice emitted upon successful invest call
    event Invested(address indexed user, address indexed token, uint256 amount);

    // ******************** API ***********************************************************************

    /// @notice convenience method to see if the proofWl has been set
    function isProofWlSet() external view returns (bool);

    /// @notice given a user, an option, a funding token and an amount, call FT invest on that user's behalf
    /// @dev reverts on stopped, proof WL not set, insufficient amount and insufficient commit balance (if not overridden)
    function investFor(address user, bytes32 option, address token, uint256 amount) external returns (bool);

    /// @notice given lists of users, funding tokens and amounts, call FT invest on those user's behalf
    /// @dev reverts on stopped, non equivalent list length and proof WL not set
    /// @dev logs batch fail on insufficient amount, insufficient commit balance (if not overridden) and investFor fail
    function investFor(
        address[] calldata users,
        bytes32[] calldata options,
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external returns (bool);

    /// @notice setter for the flying tulip proofWl, available to owner only
    function setProofWl(bytes32[] calldata pwl) external returns (bool);

    // ******************** Errors ********************************************************************

    /// @dev the put manager address cannot be zero
    error PutManagerIsZero();
    /// @dev the FT proofWl was not set
    error ProofWlNotSet();
}
