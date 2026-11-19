// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solady/utils/FixedPointMathLib.sol";
import {Side, OptimizedSwapTotal as Total} from "swap/Types.sol";
import {State, SidedStatus} from "shared/operable/Types.sol";
import {isContract} from "shared/Utils.sol";
import {Quote} from "./Types.sol";
import {IPortfolioManager} from "./IManager.sol";
import {OndoBase} from "./OndoBase.sol";

contract OndoPortfolio is OndoBase {
    /// @dev the one stablecoin the manager settles in, read once at construction
    address public immutable stablecoin;
    /// @dev multiplier from stablecoin units to the 18 decimal format of a quote
    uint256 internal immutable stableMult;

    // forge-lint: disable-next-line(missing-zero-check)
    constructor(bytes32 swapId, address _coinList, address _manager) OndoBase(swapId, _coinList, _manager) {
        address stable = IPortfolioManager(_manager).stablecoin();
        // invariant: the stablecoin is a valid address and a deployed contract
        require(validAddr(stable) && isContract(stable), InvalidAddress());
        // invariant: cannot have > 18 decimals
        uint8 decimals = IERC20(stable).decimals();
        require(decimals <= 18, InvalidDecimals());

        stablecoin = stable;
        stableMult = 10 ** (18 - decimals);

        // the stablecoin is the only possible input, enabled from the start. NOTE _validInputToken reads the
        // immutable above, which is fine in a constructor as long as it was assigned first
        setInputToken(stable, true);
    }

    // **************** Public API ***************************************************

    function status(address asset) external view returns (SidedStatus memory) {
        // get any status set by us, or globally by ondo
        SidedStatus memory stat = status();

        if (stat.flags > 0) {
            return stat;
        }

        // if not globally paused, check the specific state of the given rwa
        IPortfolioManager man = IPortfolioManager(manager);

        if (stat.buyState == State.Active && man.portfolioTokenMintingPaused(asset)) {
            stat.buyState = State.Paused;
        }

        if (stat.sellState == State.Active && man.portfolioTokenRedemptionsPaused(asset)) {
            stat.sellState = State.Paused;
        }

        return stat;
    }

    /// @dev cost of the quote (quantity * price) in stablecoin units, rounded up
    function _cost(Quote calldata quote) internal view returns (uint256) {
        uint256 cost18 = FixedPointMathLib.mulDivUp(quote.quantity, quote.price, 1e18);
        return FixedPointMathLib.divUp(cost18, stableMult);
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

        // the cost of the quote in the stablecoin, rounded up. the manager pulls this exact amount
        uint256 cost = _cost(quote);
        // invariant: normalized delta (overpayment) is not larger than .01 Ether
        // NOTE: this quote is "fee aware". the manager pulls exactly the stablecoin cost (no USDon refund as on the
        // market side), so any amount over cost can only come from the caller overpaying, and stays on this contract
        require(input >= cost && (input - cost) * stableMult < 1e16, InvalidAmount());

        // pull amount from user
        if (!SafeTransferLib.trySafeTransferFrom(token, msg.sender, address(this), amount)) {
            revert SwapFailed(msg.sender, token);
        }

        // approve the manager to pull our input token, reverts on fail
        SafeTransferLib.safeApproveWithRetry(token, manager, cost);

        // vs relying on static return values, we capture the minted amount
        uint256 val = IERC20(quote.asset).balanceOf(address(this));

        // call manager with the appropriate args, ignoring static return
        // forge-lint: disable-next-line(unused-return)
        IPortfolioManager(manager).mintWithAttestation(quote, oSig);

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

        // get our current balance of the stable coin
        uint256 val = IERC20(token).balanceOf(address(this));

        // ignoring the returned stablecoin amount of the tx
        // forge-lint: disable-next-line(unused-return)
        IPortfolioManager(manager).redeemWithAttestation(quote, oSig);

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
