// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {OwnableRoles} from "solady/auth/OwnableRoles.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Stopable} from "shared/stopable/Stopable.sol";
import {isContract} from "shared/Utils.sol";
import {ITokenSaleDist} from "./ITokenSaleDist.sol";
import {BatchType, DistTotal as Total} from "./Types.sol";

contract TokenSaleDist is ITokenSaleDist, Stopable, OwnableRoles {
    // ********************** State ********************************************************

    /// @dev all distribution contracts are kind 1
    uint256 public constant KIND = 1;
    /// @dev updated as features are added/refined
    uint256 public constant VERSION = 1;
    /// @dev non-owner role that may distribute
    uint256 public constant DISTRIBUTE_LEVEL = 2;
    /// @dev the minimum amount enforced for distribute operations
    uint256 public constant MIN_DIST = 1;
    /// @dev the address of the token to be distributed
    address public distToken;
    /// @dev unique identifier of the sale for which this contract serves
    bytes32 public id;
    /// @dev distribution totals for the given user
    mapping(address => Total) internal _totals;

    constructor(address dToken, bytes32 saleId) {
        // invariant: dToken is not zero and is a deployed contract
        require(dToken != address(0) && isContract(dToken), InvalidAddress());

        _initializeOwner(msg.sender);

        distToken = dToken;
        id = saleId;
    }

    // ********************* Public API ****************************************************

    function distributionTokenBalance() external view returns (uint256) {
        return IERC20(distToken).balanceOf(address(this));
    }

    function totals() external view returns (Total memory) {
        return _totals[address(this)];
    }

    function totals(address user) external view returns (Total memory) {
        return _totals[user];
    }

    // ********************* Admin API *****************************************************

    function distribute(address user, uint256 amount)
        external
        started(DISTRIBUTE_LEVEL)
        onlyRoles(DISTRIBUTE_LEVEL)
        returns (bool)
    {
        _distribute(user, amount);

        return true;
    }

    function distribute(address[] calldata users, uint256[] calldata amounts)
        external
        started(DISTRIBUTE_LEVEL)
        onlyRoles(DISTRIBUTE_LEVEL)
        returns (bool)
    {
        uint256 len = users.length;
        // invariant: the lists are of the same length
        require(len == amounts.length, NonEquivalentListLength());

        for (uint256 i = 0; i < len; ++i) {
            address user = users[i];
            uint256 amount = amounts[i];

            _distribute(user, amount);
        }

        // distribute operations do not allow partial success at this time
        emit Batched(uint256(BatchType.Distribute), len, 0);

        return true;
    }

    function _distribute(address user, uint256 amount) internal {
        // invariant: user is valid
        require(validAddress(user), InvalidAddress());

        // invariant: amount is >= min
        require(amount >= MIN_DIST, InsufficientAmount());

        // store the user sums
        Total storage userData = _totals[user];
        userData.distCount += 1;
        userData.distSum += amount;

        // store the contract sums
        Total storage conData = _totals[address(this)];
        conData.distCount += 1;
        conData.distSum += amount;

        SafeTransferLib.safeTransfer(distToken, user, amount);

        emit Distributed(user, distToken, amount);
    }

    // ********************* Owner API *****************************************************

    function transfer(address to, uint256 amount) external onlyOwner returns (bool) {
        SafeTransferLib.safeTransfer(distToken, to, amount);

        emit Transferred(to, distToken, amount);

        return true;
    }

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
    function validAddress(address addr) internal view returns (bool) {
        return addr != address(0) && addr != address(this);
    }
}
