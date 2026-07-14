// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {isContract} from "shared/Utils.sol";
import {State, Status} from "shared/operable/Types.sol";
import {TokenSwap} from "swap/TokenSwap.sol";
import {Preview, SwapTotal as Total} from "swap/Types.sol";
import {IDip} from "./IDip.sol";
import {IDippable} from "./IDippable.sol";
import {Market, MarketState} from "./Types.sol";

contract Superstate is TokenSwap, ReentrancyGuard {
    /// @dev identifier of the market this integration is serving
    bytes32 public marketId;
    /// @dev superstate allows these tokens as input
    mapping(address => bool) public inputTokens;

    /// @param token: address of the swap output token
    /// @param mktId: the superstate market id this integration is for
    /// @param swapId: the coinlist id for this integration
    constructor(address token, bytes32 mktId, bytes32 swapId) TokenSwap(token, swapId) {
        marketId = mktId;
        // USDC is a known valid input for this integration
        inputTokens[0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48] = true;
    }

    // **************** Public API ***************************************************

    function status() public view override returns (Status memory) {
        // get any status set by us
        Status memory stat = super.status();
        // if any is present, just short circuit here
        if (stat.state != State.Active) {
            return stat;
        } else {
            // check the market state from superstate
            address con = IDippable(outputToken).dipContract();
            Market memory mkt = IDip(con).markets(marketId);
            if (mkt.state != MarketState.Active) {
                // we consider initialized as paused
                if (mkt.state == MarketState.Initialized || mkt.state == MarketState.Paused) {
                    stat.state = State.Paused;
                } else {
                    // any other market states we consider stopped
                    stat.state = State.Stopped;
                }
            }

            return stat;
        }
    }

    function authorized(address user) external view override returns (bool) {
        return IDippable(outputToken).isAllowed(user);
    }

    function preview(address token, uint256 amount) public view override returns (Preview memory) {
        uint256 _fee;

        // get the correct fee to amount ratio
        (_fee, amount) = super.fee(amount);

        // check that amount can be spent
        address con = IDippable(outputToken).dipContract();
        (uint256 input, uint256 yield) = IDip(con).calculateOutput(marketId, amount, IERC20(token).decimals());

        // not enough supply for desired input, revise it down
        if (input < amount) {
            // with a revised input, we can simply calculate our basis point percentage and make it inclusive
            _fee = super.bpp(input);
        }

        return Preview(input, _fee, yield);
    }

    function swap(address token, uint256 amount, uint256 slip)
        external
        override
        active(SWAP_LEVEL)
        nonReentrant
        returns (uint256)
    {
        // invariant: the given token address is an approved input
        require(inputTokens[token], InvalidAddress());
        // invariant: the msg.sender is authorized
        require(IDippable(outputToken).isAllowed(msg.sender), Unauthorized());

        Preview memory pre = preview(token, amount);

        // pull input and fee from user
        if (!SafeTransferLib.trySafeTransferFrom(token, msg.sender, address(this), (pre.input + pre.fee))) {
            revert SwapFailed(msg.sender, token);
        }

        // bookkeeping for the caller and global state input and fee
        Total storage userData = _totals[msg.sender][token];
        Total storage conData = _totals[address(this)][token];

        userData.count += 1;
        userData.inputSum += pre.input;
        userData.feeSum += pre.fee;
        conData.count += 1;
        conData.inputSum += pre.input;
        conData.feeSum += pre.fee;

        // approve the output token contract to pull our inputToken, reverts on fail
        SafeTransferLib.safeApproveWithRetry(token, outputToken, pre.input);

        // get this contract's current balance of the input token, we will compare post buyTheDip to track spend
        uint256 inBal = IERC20(token).balanceOf(address(this));

        // buy the dip returns the amount minted
        uint256 minted = IDippable(outputToken).buyTheDip(marketId, pre.input, slip, token);

        // invariant: the amount minted >= the user defined slippage protection
        require(minted >= slip, InsufficientAmount());

        // invariant: the actual spend matches our approved amount
        require(inBal - IERC20(token).balanceOf(address(this)) == pre.input, SwapFailed(msg.sender, token));

        // transfer the caller their minted tokens
        SafeTransferLib.safeTransfer(outputToken, msg.sender, minted);

        // bookkeeping for the caller and global output
        userData.outputSum += minted;
        // NOTE: this is simply a sum of all tokens minted and transferred, this token's balanceOf (output token) should be 0
        conData.outputSum += minted;

        emit Swapped(msg.sender, token, outputToken, pre.input, pre.fee, minted);

        return minted;
    }

    // **************** Owner API ****************************************************

    /// @notice given a token address and a boolean representing whitelist status, set those values
    /// @dev reverts if address is invalid
    function setInputToken(address token, bool val) external onlyOwner returns (bool) {
        // invariant: address is valid
        require(validAddr(token) && isContract(token), InvalidAddress());

        emit InputTokenUpdated(token, inputTokens[token], val);

        inputTokens[token] = val;

        return true;
    }

    // **************** Events ****************************************************

    /// @notice emitted on any value change to the input tokens whitelist status
    event InputTokenUpdated(address indexed token, bool prev, bool next);
}
