// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @notice minimal interface for working with Superstate Dippable contracts
interface IDippable {
    /// @notice return the address of the Dip implementation
    function dipContract() external view returns (address);
    /// @notice given an address, return its allowlist state
    function isAllowed(address user) external view returns (bool);
    /// @notice call the Superstate Dippable method to perform the swap
    /// @param marketId: superstate market ...
    /// @param amount: the input amount (which fee may be taken from)
    /// @param slip: slippage floor
    /// @param token: the payment token
    /// @dev the market will have a known recipient address, the msg.sender of this call must have approved/permitted that address
    function buyTheDip(bytes32 marketId, uint256 amount, uint256 slip, address token) external returns (uint256);
}
