// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {OwnableRoles} from "solady/auth/OwnableRoles.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Stopable} from "shared/stopable/Stopable.sol";
import {ITokenSaleFund} from "./ITokenSaleFund.sol";
import {BatchType, SaleTotal as Total} from "./Types.sol";

contract TokenSaleFund is ITokenSaleFund, Stopable, OwnableRoles {
    // ********************** State ********************************************************

    /// @dev all funding contracts are kind 0
    uint256 public constant KIND = 0;
    /// @dev updated as features are added/refined
    uint256 public constant VERSION = 2;
    /// @dev non-owner role that may commit
    uint256 public constant COMMIT_LEVEL = 2;
    /// @dev non-owner role that may remit
    uint256 public constant REMIT_LEVEL = 4;
    /// @dev the minimum amount enforced for remit operations
    uint256 public constant MIN_REMIT = 1;
    /// @dev the minimum amount enforced for commit operations
    uint256 public minCommit;
    /// @dev unique identifier of the sale for which this contract serves
    bytes32 public id;
    /// @dev commit and remit totals for the given user, option and funding token
    mapping(address => mapping(bytes32 => mapping(address => Total))) internal _totals;

    /// @dev the given id is a keccak (equivalent) hash of the appropriate sale identifier
    constructor(uint256 min, bytes32 saleId) {
        // invariant: min > 0
        require(min > 0, InsufficientAmount(min, 0));

        _initializeOwner(msg.sender);
        minCommit = min;
        id = saleId;
    }

    // ********************* Public API ****************************************************

    function fundingTokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function commitBalance(address token) external view returns (uint256) {
        Total memory data = _totals[address(this)][id][token];
        return data.commitSum - data.remitSum;
    }

    function commitBalance(address user, bytes32 option, address token) external view returns (uint256) {
        Total memory data = _totals[user][option][token];
        return data.commitSum - data.remitSum;
    }

    function totals(address token) external view returns (Total memory) {
        return _totals[address(this)][id][token];
    }

    function totals(address user, bytes32 option, address token) external view returns (Total memory) {
        return _totals[user][option][token];
    }

    // ********************* Admin API *****************************************************

    function commit(address user, bytes32 option, address token, uint256 amount)
        external
        started(COMMIT_LEVEL)
        onlyRoles(COMMIT_LEVEL)
        returns (bool)
    {
        // invariant: user is valid
        require(validUser(user), InvalidUser());

        // invariant: amount is sufficient
        require(amount >= minCommit, InsufficientAmount(amount, minCommit));

        if (!SafeTransferLib.trySafeTransferFrom(token, user, address(this), amount)) {
            revert CommitFailed(user, option, token);
        }

        _commit(user, option, token, amount);

        return true;
    }

    function commit(
        address[] calldata users,
        bytes32[] calldata options,
        address[] calldata tokens,
        uint256[] calldata amounts
    ) external started(COMMIT_LEVEL) onlyRoles(COMMIT_LEVEL) returns (bool) {
        uint256 batched = 0;
        uint256 len = users.length;

        // invariant: the lists are of the same length
        require(len == options.length && len == tokens.length && len == amounts.length, NonEquivalentListLength());

        for (uint256 i = 0; i < len; ++i) {
            address user = users[i];
            bytes32 option = options[i];
            address token = tokens[i];
            uint256 amount = amounts[i];

            // invariants: user valid, amount is sufficient (and tx succeeds)
            if (
                validUser(user) && amount >= minCommit
                    && SafeTransferLib.trySafeTransferFrom(token, user, address(this), amount)
            ) {
                _commit(user, option, token, amount);

                unchecked {
                    batched += 1;
                }
            } else {
                emit BatchFail(uint256(BatchType.Commit), user, option, token, amount);
            }
        }

        emit Batched(uint256(BatchType.Commit), batched, len - batched);

        return true;
    }

    /// @dev abstraction for the identical logic used by each commit method
    function _commit(address user, bytes32 option, address token, uint256 amount) internal {
        Total storage userData = _totals[user][option][token];
        Total storage conData = _totals[address(this)][id][token];
        // store user commit totals for this token
        userData.commitCount += 1;
        userData.commitSum += amount;
        // store contract commit totals for this token
        conData.commitCount += 1;
        conData.commitSum += amount;

        emit Committed(user, option, token, amount);
    }

    function remit(address user, bytes32 option, address token, uint256 amount)
        external
        started(REMIT_LEVEL)
        onlyRoles(REMIT_LEVEL)
        returns (bool)
    {
        _remit(user, option, token, amount);

        return true;
    }

    function remit(address[] calldata users, bytes32 option, address token, uint256[] calldata amounts)
        external
        started(REMIT_LEVEL)
        onlyRoles(REMIT_LEVEL)
        returns (bool)
    {
        uint256 len = users.length;
        // invariant: the lists are of the same length
        require(len == amounts.length, NonEquivalentListLength());

        for (uint256 i = 0; i < len; ++i) {
            address user = users[i];
            uint256 amount = amounts[i];

            _remit(user, option, token, amount);
        }

        // remit operations do not allow partial success at this time
        emit Batched(uint256(BatchType.Remit), len, 0);

        return true;
    }

    /// @dev abstraction for the identical logic used by each remit method
    function _remit(address user, bytes32 option, address token, uint256 amount) internal {
        // invariant: user is valid
        require(validUser(user), InvalidUser());
        // invariant: amount is non zero
        require(amount >= MIN_REMIT, InsufficientAmount(amount, MIN_REMIT));

        // invariant: the user has sufficient commitment
        Total storage userData = _totals[user][option][token];
        require(userData.commitSum - userData.remitSum >= amount, InsufficientCommitment(user, option, token));

        // store the user sums
        userData.remitCount += 1;
        userData.remitSum += amount;
        // store the contract sums
        Total storage conData = _totals[address(this)][id][token];
        conData.remitCount += 1;
        conData.remitSum += amount;

        SafeTransferLib.safeTransfer(token, user, amount);

        emit Remitted(user, option, token, amount);
    }

    // ********************* Owner API *****************************************************

    function approve(address spender, address token, uint256 amount) external onlyOwner returns (bool) {
        SafeTransferLib.safeApproveWithRetry(token, spender, amount);

        emit Approved(spender, token, amount);

        return true;
    }

    /// @dev the to address will have been confirmed to exist by this point
    function transfer(address to, address token, uint256 amount) external onlyOwner returns (bool) {
        SafeTransferLib.safeTransfer(token, to, amount);

        emit Transferred(to, token, amount);

        return true;
    }

    function stop(uint256 level) public override onlyOwner returns (bool) {
        return super.stop(level);
    }

    // ********************* Utility *******************************************************

    /// @dev return true if the given address is NOT zero or this
    function validUser(address user) internal view returns (bool) {
        return user != address(0) && user != address(this);
    }
}
