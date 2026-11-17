// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {Side, OptimizedSwapTotal as Total} from "swap/Types.sol";
import {State, SidedStatus} from "shared/operable/Types.sol";
import {Quote} from "./Types.sol";
import {IMarketManager} from "./IManager.sol";
import {OndoBase} from "./OndoBase.sol";

contract OndoMarket is OndoBase {
    constructor(bytes32 swapId, address _coinList, address _manager, address token)
        OndoBase(swapId, _coinList, _manager)
    {
        // if an initially whitelisted token is given
        if (token != address(0)) {
            setInputToken(token, true);
        }
    }

    // **************** Public API ***************************************************

    function status(address asset) external view returns (SidedStatus memory) {
        // get any status set by us, or globally by ondo
        SidedStatus memory stat = status();

        if (stat.flags > 0) {
            return stat;
        }

        // if not globally paused, check the specific state of the given rwa
        IMarketManager man = IMarketManager(manager);

        if (stat.buyState == State.Active && man.gmTokenMintingPaused(asset)) {
            stat.buyState = State.Paused;
        }

        if (stat.sellState == State.Active && man.gmTokenRedemptionsPaused(asset)) {
            stat.sellState = State.Paused;
        }

        return stat;
    }

    /// @dev abstracted logic for buy side swaps
    function buy(
        Quote calldata quote,
        bytes calldata oSig,
        address token,
        uint256 amount,
        bytes32 attribution,
        Total storage userData,
        Total storage conData
    ) internal override returns (uint256) {
        // buy side fee is taken on the input token amount
        (uint256 _fee, uint256 input) = super.fee(quote.side, amount);

        uint256 mult = 1 * 10 ** (18 - (IERC20(token).decimals())); // what we multiply by to get 18 decimal format
        // invariant: normalized delta (overpayment) is not larger than .01 Ether
        // expand the input if necessary, normalize the amt paid for quote (always 18 decimal format)
        // NOTE: this quote is "fee aware"
        require((input * mult) - ((quote.quantity * quote.price) / 1e18) < 1e16, InvalidAmount());

        // pull amount from user
        if (!SafeTransferLib.trySafeTransferFrom(token, msg.sender, address(this), amount)) {
            revert SwapFailed(msg.sender, token);
        }

        // approve the manager to pull our input token, reverts on fail
        SafeTransferLib.safeApproveWithRetry(token, manager, input);

        // vs relying on static return values, we capture the minted amount
        uint256 val = IERC20(quote.asset).balanceOf(address(this));

        // call manager with the appropriate args, NOTE input, ignoring static return
        // forge-lint: disable-next-line(unused-return)
        IMarketManager(manager).mintWithAttestation(quote, oSig, token, input);

        // clean up any residual allowance
        SafeTransferLib.safeApproveWithRetry(token, manager, 0);

        // invariant: minted amount is GTE quote.quantity
        val = IERC20(quote.asset).balanceOf(address(this)) - val;
        require(val >= quote.quantity, InsufficientAmount());

        // transfer the asset to the caller
        SafeTransferLib.safeTransfer(quote.asset, msg.sender, val);

        // accounting and emit events
        _recordTotals(userData, conData, input, _fee, val);
        emitSwapped(quote, token, attribution, val, _fee, amount);

        return val;
    }

    /// @dev abstracted logic for sell side swaps
    function sell(
        Quote calldata quote,
        bytes calldata oSig,
        address token,
        uint256 amount,
        bytes32 attribution,
        Total storage userData,
        Total storage conData
    ) internal override returns (uint256) {
        // pull RWA quote.quantity from user
        if (!SafeTransferLib.trySafeTransferFrom(quote.asset, msg.sender, address(this), quote.quantity)) {
            revert SwapFailed(msg.sender, quote.asset);
        }

        // approve the manager to pull our RWA token, reverts on fail
        SafeTransferLib.safeApproveWithRetry(quote.asset, manager, quote.quantity);

        // get our current balance of the selected output token
        uint256 val = IERC20(token).balanceOf(address(this));

        // ignoring the returned USDon value of the tx
        // forge-lint: disable-next-line(unused-return)
        IMarketManager(manager).redeemWithAttestation(quote, oSig, token, amount);

        // clean up any residual allowance
        SafeTransferLib.safeApproveWithRetry(quote.asset, manager, 0);

        // invariant: the amount transferred is at least the given amount (slippage)
        val = IERC20(token).balanceOf(address(this)) - val;
        require(val >= amount, InsufficientAmount());

        // sell fee is a simple muldiv with the set basis point percentage on the redeemed amount
        uint256 _fee = super.bpp(quote.side, val);
        // user gets value after we take fee
        uint256 out = val - _fee;

        // transfer caller their redeemed token - fee
        SafeTransferLib.safeTransfer(token, msg.sender, out);

        // accounting and emit events
        _recordTotals(userData, conData, quote.quantity, _fee, out);
        emitSwapped(quote, token, attribution, quote.quantity, _fee, val);

        return out;
    }
}
