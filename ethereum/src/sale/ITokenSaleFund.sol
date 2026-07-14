// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {SaleTotal as Total} from "./Types.sol";

interface ITokenSaleFund {
    // ********************** Events *******************************************************

    /// @notice Emitted upon successful Commit transfer
    event Committed(address indexed user, bytes32 indexed option, address indexed token, uint256 amount);

    /// @notice Emitted upon successful Remit transfer
    event Remitted(address indexed user, bytes32 indexed option, address indexed token, uint256 amount);

    /// @notice emitted, in-loop, during a partial fail allowing batch
    event BatchFail(uint256 kind, address indexed user, bytes32 indexed option, address indexed token, uint256 amount);

    /// @notice Emitted at the conclusion of a batch operation
    event Batched(uint256 kind, uint256 succeeded, uint256 failed);

    /// @notice Emitted when contract owner transfers funding token balance elsewhere
    event Transferred(address indexed to, address indexed token, uint256 amount);

    /// @notice Emitted when contract owner approves a spender for a given amount
    event Approved(address indexed spender, address indexed token, uint256 amount);

    // ********************* API ***********************************************************

    /// @notice return the full balance held by this contract at the given token
    function fundingTokenBalance(address token) external view returns (uint256);

    /// @notice return the current global commitment balance (commit sum - remit sum ) for a given token
    function commitBalance(address token) external view returns (uint256);

    /// @notice return the current commitment balance (commit sum - remit sum ) for a given user, option and token
    function commitBalance(address user, bytes32 option, address token) external view returns (uint256);

    /// @notice given a token return the global commit and remit totals
    function totals(address token) external view returns (Total memory);

    /// @notice given a user, option and token return the respective commit and remit totals
    function totals(address user, bytes32 option, address token) external view returns (Total memory);

    /// @notice given a user, an option, a token and an amount, transfer funding
    /// @dev reverts on stopped, invalid user, unauthorized, insufficient amount or safeTransferFrom error
    function commit(address user, bytes32 option, address token, uint256 amount) external returns (bool);

    /// @notice given lists of users, options, tokens and amounts transfer funding
    /// @dev reverts on stopped, nonEquivalentListLength or unauthorized
    /// @dev logs batch failure on invalid user, insufficient amount or transferFrom error
    function commit(
        address[] calldata users,
        bytes32[] calldata options,
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external returns (bool);

    /// @notice given a user, an option, a token and an amount, return the given amount
    /// @dev reverts on stopped, invalid user, unauthorized, insufficient amount, insufficient commitment or safeTransfer error
    function remit(address user, bytes32 option, address token, uint256 amount) external returns (bool);

    /// @notice given a list of users, an option, a token and a list of amounts, remit them
    /// @dev reverts on stopped, invalid user, nonequivalent list length, unauthorized, insufficient amount,
    /// insufficient commitment or safeTransfer error
    function remit(address[] calldata users, bytes32 option, address token, uint256[] calldata amounts)
        external
        returns (bool);

    /// @notice given a spender, a token address and an amount approve the spender at the token
    /// @dev reverts on unauthorized or safeApprove error
    function approve(address spender, address token, uint256 amount) external returns (bool);

    /// @notice given a destination address, a token and an amount, transfer it, available to owner only
    /// @dev reverts on unauthorized or safeTransfer error
    function transfer(address to, address token, uint256 amount) external returns (bool);

    // *********************** Errors *********************************************************

    /// @dev if the given user is zero or the contract address
    error InvalidUser();

    /// @dev the amount given is below the minimum amount accepted for this operation
    error InsufficientAmount(uint256 amount, uint256 minimum);

    /// @dev the user does not have sufficient committed funds for the requested remit
    error InsufficientCommitment(address user, bytes32 option, address token);

    /// @dev the two lists given to batch remit do not have equivalent length
    error NonEquivalentListLength();

    /// @dev the transferFrom for a supposed commit has failed
    error CommitFailed(address user, bytes32 option, address token);
}
