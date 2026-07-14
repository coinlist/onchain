// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {DistTotal as Total} from "./Types.sol";

interface ITokenSaleDist {
    // ********************** Events *******************************************************

    /// @notice Emitted upon successful distribution
    event Distributed(address indexed user, address indexed token, uint256 amount);

    /// @notice Emitted at the conclusion of a batch operation
    event Batched(uint256 kind, uint256 succeeded, uint256 failed);

    /// @notice Emitted when contract owner transfers distribution token balance elsewhere
    event Transferred(address indexed to, address indexed token, uint256 amount);

    // ********************* API ***********************************************************

    /// @notice the balance of this contract at the known distribution token
    function distributionTokenBalance() external returns (uint256);

    /// @notice return the global distribution totals
    function totals() external returns (Total memory);

    /// @notice given a user, return their distribution totals
    function totals(address user) external returns (Total memory);

    /// @notice given a user and an amount, push the token distribution to them
    /// @dev reverts on stopped, invalid user, unauthorized, insufficient amount or safeTransferFrom error
    function distribute(address user, uint256 amount) external returns (bool);

    /// @notice given a user and an amount, push the token distribution to them
    /// @dev reverts on stopped, unauthorized, nonequivalent list length, invalid user, insufficient amount or safeTransfer error
    function distribute(address[] calldata users, uint256[] calldata amounts) external returns (bool);

    /// @notice given a destination address, transfer dist token, available to owner only
    /// @dev reverts on unauthorized or safeTransfer error
    function transfer(address to, uint256 amount) external returns (bool);

    /// @notice given a destination address, a token and an amount, transfer the token, available to owner only
    /// @dev reverts on unauthorized or safeTransfer error
    function transfer(address to, address token, uint256 amount) external returns (bool);

    // *********************** Errors *********************************************************

    /// @dev if the given address is zero or otherwise invalid
    error InvalidAddress();

    /// @dev the contract itself has insufficient funds to distribute the given amount
    error InsufficientBalance(uint256 amount, uint256 balance);

    /// @dev the amount given is below the minimum distribution amount
    error InsufficientAmount();

    /// @dev the two lists given to batch distribute do not have equivalent length
    error NonEquivalentListLength();
}
