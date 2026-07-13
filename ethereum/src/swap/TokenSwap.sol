// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {Ownable} from "solady/auth/OwnableRoles.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Operable} from "shared/operable/Operable.sol";
import {isContract} from "shared/Utils.sol";
import {ITokenSwap} from "./ITokenSwap.sol";
import {Preview, SwapTotal as Total} from "./Types.sol";

abstract contract TokenSwap is ITokenSwap, Operable, Ownable {
    /// @dev all swap contracts are kind 2
    uint16 public constant KIND = 2;
    uint16 public constant VERSION = 1;
    /// @dev constant representing the stopable act of performing a swap
    uint32 public constant SWAP_LEVEL = 2;

    /// @dev constant representing the basis point equivalent of 100%
    uint256 public constant ONE_HUNDRED_P = 10000;
    /// @dev the amount (if any) of an input token fee charged per swap (basis point format)
    uint256 public bps;

    address public outputToken;
    bytes32 public id;

    // @dev user => token => total
    mapping(address => mapping(address => Total)) internal _totals;

    constructor(address token, bytes32 swapId) {
        // invariant: output address is valid smart contract
        require(validAddr(token) && isContract(token), InvalidAddress());

        _initializeOwner(msg.sender);

        outputToken = token;
        id = swapId;
    }

    // **************** Public API ***************************************************

    function tokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function outputTokenBalance() external view returns (uint256) {
        return IERC20(outputToken).balanceOf(address(this));
    }

    function totals(address token) external view returns (Total memory) {
        return _totals[address(this)][token];
    }

    function totals(address user, address token) external view returns (Total memory) {
        return _totals[user][token];
    }

    function fee(uint256 amount) public view returns (uint256, uint256) {
        // if a bps has been set, validate the input and calculate the actual fee
        if (bps > 0) {
            // floor(a * b / c) as the adjusted amount
            uint256 adj = FixedPointMathLib.mulDiv(amount, ONE_HUNDRED_P, ONE_HUNDRED_P + bps);
            // returns fee as amount - adjusted amount, along with said adjusted amount
            return (amount - adj, adj);
        } else {
            // a zero bps is "no fee"
            return (bps, amount);
        }
    }

    function bpp(uint256 amount) public view returns (uint256) {
        return bps > 0 ? FixedPointMathLib.mulDiv(amount, bps, ONE_HUNDRED_P) : bps;
    }

    function authorized(address user) external view virtual returns (bool);

    function preview(address token, uint256 amount) external view virtual returns (Preview memory);

    function swap(address token, uint256 amount, uint256 slip) external virtual returns (uint256);

    // **************** Owner API ****************************************************

    function setBps(uint256 points) external onlyOwner returns (bool) {
        // invariant: points cannot meet or exceed 100%
        require(points < ONE_HUNDRED_P, InvalidAmount());

        emit BpsUpdated(bps, points);

        bps = points;

        return true;
    }

    function transfer(address to, uint256 amount) public onlyOwner returns (bool) {
        return transfer(to, outputToken, amount);
    }

    function transfer(address to, address token, uint256 amount) public onlyOwner returns (bool) {
        SafeTransferLib.safeTransfer(token, to, amount);
        emit Transferred(to, token, amount);
        return true;
    }

    function pause(uint32 level) public override onlyOwner returns (bool) {
        return super.pause(level);
    }

    function stop() public override onlyOwner returns (bool) {
        return super.stop();
    }

    // ***************** Utility *****************************************************

    /// @dev return true if the given address is NOT zero or this
    function validAddr(address addr) internal view returns (bool) {
        return addr != address(0) && addr != address(this);
    }
}
