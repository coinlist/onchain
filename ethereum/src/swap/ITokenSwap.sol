// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Preview, SwapTotal as Total} from "./Types.sol";

interface ITokenSwap {
    // ********************* Events **************************************************

    /// @notice Emitted upon a successful Swap
    event Swapped(
        address indexed user,
        address indexed inputToken,
        address indexed outputToken,
        uint256 inputAmount,
        uint256 fee,
        uint256 outputAmount
    );

    /// @notice Emitted when contract owner transfers input token balance (from fees) elsewhere
    event Transferred(address indexed to, address indexed token, uint256 amount);

    /// @notice Emitted when contract owner updates the basis point fee value
    event BpsUpdated(uint256 prev, uint256 next);

    // ********************* API *****************************************************

    /// @notice return this contract's balance of the given token
    /// @dev used for checking balances of input tokens
    function tokenBalance(address token) external view returns (uint256);

    /// @notice return this contract's balance of the output token
    function outputTokenBalance() external view returns (uint256);

    /// @notice given an input token address, return global input and output totals
    function totals(address token) external view returns (Total memory);

    /// @notice given a user return their input and output totals
    function totals(address user, address token) external view returns (Total memory);

    /// @notice given a total amount calculate and return (fee, adjustedAmount)
    function fee(uint256 amount) external view returns (uint256, uint256);

    /// @notice given an amount calculate and return the set basis point percentage of it
    function bpp(uint256 amount) external view returns (uint256);

    /// @notice returns a boolean reflecting the ability of the given address to participate in this swap
    function authorized(address user) external view returns (bool);

    /// @notice given a token address and the intended input amount, return a hydrated Preview
    /// @dev actual-amount-spent could be less than given amount in some scenarios
    /// @dev it is expected that `token` implement ERC20.decimals() metadata method
    function preview(address token, uint256 amount) external view returns (Preview memory);

    /// @notice given a token, an amount and a slippage protection minimum, perform a swap
    /// @dev the base contract will calculate and return a fee amount, if any
    /// @return the amount of output token rewarded
    function swap(address token, uint256 amount, uint256 slip) external returns (uint256);

    /// @notice given an address and an amount transfer output token, available to owner only
    /// @dev reverts on safeTransfer error
    function transfer(address to, uint256 amount) external returns (bool);

    /// @notice given a token, an address and an amount transfer the token, available to owner only
    /// @dev reverts on safeTransfer error
    function transfer(address to, address token, uint256 amount) external returns (bool);

    /// @notice set the given basis points as the bps needed for fee calculation, available to owner only
    /// @dev use of the fee mechanism is optional and may be written into a child's `swap` method if so chosen
    /// @dev reverts on unauthorized or basis points being set to 100% or above
    function setBps(uint256 points) external returns (bool);

    // ********************* Errors **************************************************

    /// @dev if the given addr is zero or this contract address
    error InvalidAddress();
    /// @dev if a given amount is not valid for the requested operation
    error InvalidAmount();
    /// @dev if a given amount is specifically less than expected
    error InsufficientAmount();
    /// @dev the swap call has failed
    error SwapFailed(address user, address token);
}
