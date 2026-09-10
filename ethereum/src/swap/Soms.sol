// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;
import {Ownable} from "solady/auth/OwnableRoles.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Operable} from "shared/operable/Operable.sol";
import {isContract} from "shared/Utils.sol";
import {ISoms} from "./ISoms.sol";
import {Side, OptimizedSwapTotal} from "./Types.sol";

/*
 * @notice Storage.Optimized.Multi.Swap.
 * @dev this is similar to TokenSwap, but has a few key differences
 * the storage footprint for Total struct has been reduced to a single slot
 * has no global Total storage (TODO: discuss)
 * there are no parent-defined swap, authorized or preview methods
 * there is a Side (Buy, Sell)
 * fee bps amounts are separate per Side
*/
abstract contract Soms is ISoms, Operable, Ownable {
    bytes32 public id;
    uint32 public constant SWAP_LEVEL = 2;
    /// @dev storage optimized swap contracts are kind 3
    uint16 public constant KIND = 3;
    uint16 public constant VERSION = 1;
    /// @dev constant representing the basis point equivalent of 100%
    uint16 public constant ONE_HUNDRED_P = 10000;
    /// @dev fixed size array for our typed basis points. relative with the Side enum
    uint16[2] public bps;
    /// @dev tokens allowed as input
    mapping(address => bool) public inputTokens;
    // @dev user => inputToken => outputToken => totals
    mapping(address => mapping(address => mapping(address => OptimizedSwapTotal))) internal _totals;

    constructor(bytes32 swapId) {
        _initializeOwner(msg.sender);
        id = swapId;
    }

    // **************** Public API ***************************************************

    function tokenBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function totals(address user, address input, address output) external view returns (OptimizedSwapTotal memory) {
        return _totals[user][input][output];
    }

    function fee(Side side, uint256 amount) public view returns (uint256, uint256) {
        // if a bps has been set, validate the input and calculate the actual fee
        uint16 val = bps[uint256(side)];
        if (val > 0) {
            // floor(a * b / c) as the adjusted amount
            uint256 adj = FixedPointMathLib.mulDiv(amount, ONE_HUNDRED_P, ONE_HUNDRED_P + val);
            // returns fee as amount - adjusted amount, along with said adjusted amount
            return (amount - adj, adj);
        } else {
            // a zero bps is "no fee"
            return (0, amount);
        }
    }

    function bpp(Side side, uint256 amount) public view returns (uint256) {
        uint16 val = bps[uint256(side)];
        return val > 0 ? FixedPointMathLib.mulDiv(amount, val, ONE_HUNDRED_P) : 0;
    }

    // **************** Owner API ****************************************************

    function setBps(Side side, uint16 points) external onlyOwner returns (bool) {
        // invariant: points cannot meet or exceed 100%
        require(points < ONE_HUNDRED_P, InvalidAmount());

        // current value
        uint16 val = bps[uint256(side)];

        emit BpsUpdated(side, val, points);

        bps[uint256(side)] = points;

        return true;
    }

    function setInputToken(address token, bool val) public onlyOwner returns (bool) {
        // run constraints if adding
        if (val) {
            // invariant: address is valid
            require(validAddr(token) && isContract(token), InvalidAddress());

            // invariant: cannot have > 18 decimals
            require(IERC20(token).decimals() <= 18, InvalidDecimals());
        }

        emit InputTokenUpdated(token, inputTokens[token], val);

        inputTokens[token] = val;

        return true;
    }

    function transfer(address to, address token, uint256 amount) public onlyOwner returns (bool) {
        SafeTransferLib.safeTransfer(token, to, amount);

        emit Transferred(to, token, amount);

        return true;
    }

    /// @notice used either to pause/unpause for internal purposes or respond to transient upstream outages
    /// @dev accepts 0 to unpause, or any bitmask containing SWAP_LEVEL to pause swaps
    function pause(uint32 level) public override onlyOwner returns (bool) {
        // invariant: passed level is a value this contract honors (0, SWAP_LEVEL (or functionally equivalent))
        require(level == 0 || (SWAP_LEVEL & level) != 0, InvalidAmount());

        return super.pause(level);
    }

    /// @notice a permanent decomission of this contract
    function stop() public override onlyOwner returns (bool) {
        return super.stop();
    }

    /// @dev ownership of a SOMS will never be renounced
    function renounceOwnership() public payable override onlyOwner {
        revert Disabled();
    }

    // ***************** Utility *****************************************************

    /// @dev return true if the given address is NOT zero or this
    function validAddr(address addr) internal view returns (bool) {
        return addr != address(0) && addr != address(this);
    }
}
