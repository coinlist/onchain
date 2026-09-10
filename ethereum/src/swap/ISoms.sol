// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Side, OptimizedSwapTotal} from "./Types.sol";

interface ISoms {
    // ********************* Events **************************************************

    /// @notice Emitted upon a successful swap
    /// @dev fee prices are included in buy side inputs and excluded from sell side outputs
    event Swapped(
        address indexed user,
        address indexed inputToken, // address of stable or asset
        address indexed outputToken, // address of stable or asset
        uint256 inputAmount, // amount of stable or asset
        uint256 outputAmount, // amount of stable or asset,
        uint256 assetPrice // price of the asset in this tx
    );

    /// @notice Emitted when contract owner transfers input token balance (from fees) elsewhere
    event Transferred(address indexed to, address indexed token, uint256 amount);

    /// @notice Emitted when contract owner updates the basis point fee value for a swap
    event BpsUpdated(Side side, uint16 prev, uint16 next);

    /// @notice emitted on any value change to the input tokens whitelist
    event InputTokenUpdated(address indexed token, bool prev, bool next);

    // ********************* API *****************************************************

    /// @notice return this contract's balance of the given token
    /// @dev used for checking balances of input tokens
    function tokenBalance(address token) external view returns (uint256);

    /// @notice given a user and input/output pair, return their totals
    /// @dev the number's decimal format is that of the token itself
    function totals(address user, address input, address output) external view returns (OptimizedSwapTotal memory);

    /// @notice given a side and amount, calculate and return (fee, adjustedAmount)
    /// @dev this method calculates inclusively
    function fee(Side side, uint256 amount) external view returns (uint256, uint256);

    /// @notice given a side and amount, calculate and return the set basis point percentage of it
    function bpp(Side side, uint256 amount) external view returns (uint256);

    /// @notice set the given basis points for a swap (per side) as the bps needed for fee calculation, available to owner only
    /// @dev reverts on unauthorized or basis points being set to 100% or above
    function setBps(Side side, uint16 points) external returns (bool);

    /// @notice given a token address and a boolean representing whitelist status, set those values
    /// @dev reverts (when adding) if address is invalid, or token decimals > 18
    function setInputToken(address token, bool val) external returns (bool);

    /// @notice given a token, an address and an amount transfer the token, available to owner only
    /// @dev reverts on safeTransfer error
    function transfer(address to, address token, uint256 amount) external returns (bool);

    // ********************* Errors **************************************************

    /// @dev if the given addr is zero or this contract address
    error InvalidAddress();
    /// @dev if a given amount is not valid for the requested operation
    error InvalidAmount();
    /// @dev if a given amount is specifically less than expected
    error InsufficientAmount();
    /// @dev a given token has decimals larger than 18
    error InvalidDecimals();
    /// @dev the swap call has failed
    error SwapFailed(address user, address token);
    /// @dev the called method is disabled
    error Disabled();
}
