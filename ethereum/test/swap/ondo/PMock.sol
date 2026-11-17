// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {IRWA} from "ondo/IRWA.sol";
import {Side} from "swap/Types.sol";
import {Quote} from "ondo/Types.sol";
import {IPortfolioManager} from "ondo/IManager.sol";

/// @dev mimics the Ondo PortfolioTokenManager: a single stablecoin, no deposit args, it pulls the quote cost itself
contract PMock is IPortfolioManager {
    address public override stablecoin;

    // an "expanded" (18 decimal) USD amount must be at least this
    uint256 public minDeposit;
    uint256 public minRedemption;

    bool public quoteWillVerify = true;
    bool public override globalMintingPaused;
    bool public override globalRedeemingPaused;

    mapping(address => bool) public override portfolioTokenMintingPaused;
    mapping(address => bool) public override portfolioTokenRedemptionsPaused;
    mapping(address => bool) public registered;

    constructor(address _stablecoin) {
        stablecoin = _stablecoin;
    }

    // *************** IPortfolioManager API ***********************************/

    function mintWithAttestation(Quote calldata quote, bytes memory) external override returns (uint256) {
        require(quote.side == Side.Buy, "quote side not Buy");
        require(registered[msg.sender], "unregistered user");
        require(quoteWillVerify, "invalid quote");

        // rounded up, as is the conversion to stablecoin units below
        uint256 usd18 = (quote.quantity * quote.price + 1e18 - 1) / 1e18;
        require(usd18 >= minDeposit, "quote amounts less than minimum");

        // pull the quote cost in the stablecoin, rounded up to its decimals
        uint256 div = 10 ** (18 - IERC20(stablecoin).decimals());
        uint256 cost = (usd18 + div - 1) / div;
        require(SafeTransferLib.trySafeTransferFrom(stablecoin, msg.sender, address(this), cost), "pull failed");

        IRWA(quote.asset).mint(msg.sender, quote.quantity);

        return quote.quantity;
    }

    function redeemWithAttestation(Quote calldata quote, bytes memory) external override returns (uint256) {
        require(quote.side == Side.Sell, "quote side not Sell");
        require(registered[msg.sender], "unregistered user");
        require(quoteWillVerify, "invalid quote");

        uint256 usd18 = (quote.quantity * quote.price) / 1e18;
        require(usd18 >= minRedemption, "quote amounts less than minimum");

        require(
            SafeTransferLib.trySafeTransferFrom(quote.asset, msg.sender, address(this), quote.quantity), "pull failed"
        );

        uint256 out = usd18 / (10 ** (18 - IERC20(stablecoin).decimals()));
        SafeTransferLib.safeTransfer(stablecoin, msg.sender, out);

        return out;
    }

    // *************** mock settings **********************************/

    function setGlobalMintingPaused(bool val) external {
        globalMintingPaused = val;
    }

    function setGlobalRedeemingPaused(bool val) external {
        globalRedeemingPaused = val;
    }

    function setPortfolioTokenMintingPaused(address asset, bool val) external {
        portfolioTokenMintingPaused[asset] = val;
    }

    function setPortfolioTokenRedemptionsPaused(address asset, bool val) external {
        portfolioTokenRedemptionsPaused[asset] = val;
    }

    function setQuoteWillVerify(bool val) external {
        quoteWillVerify = val;
    }

    function setRegistered(address user, bool val) external {
        registered[user] = val;
    }

    function setMinDeposit(uint256 val) external {
        minDeposit = val;
    }

    function setMinRedemption(uint256 val) external {
        minRedemption = val;
    }
}
