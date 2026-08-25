// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {TestToken} from "shared/TestToken.sol";
import {IRWA} from "ondo/IRWA.sol";
import {Side} from "swap/Types.sol";
import {Quote} from "ondo/Types.sol";

/// @dev make as a token as to capture USDon "overminting" behavior
contract GMock is TestToken {
    // an "expanded" (18 decimal) USD deposit amount must be greater than this..
    uint256 public minDeposit;
    // an "expanded" (18 decimal) USD redemption amount must be greater than this..
    uint256 public minRedemption;

    bool public quoteWillVerify = true;

    mapping(address => bool) public registered;

    constructor(string memory n, string memory s) TestToken(n, s) {}

    // *************** IManager API ***********************************/

    function mintWithAttestation(Quote calldata quote, bytes memory, address depositToken, uint256 depositAmount)
        external
        returns (uint256)
    {
        // invariant: depositToken can't be zero
        require(depositToken != address(0), "deposit token zero");

        // invariant: side is BUY
        require(quote.side == Side.Buy, "quote side not Buy");

        // invariant: msg.sender is registered
        require(registered[msg.sender], "unregistered user");

        // invariant: quote verifies - we will make this failure or success set-able
        require(quoteWillVerify, "invalid quote");

        // mimic the actual contract WRT usdon and fund values.
        // see https://etherscan.io/address/0x2c158bc456e027b2affccadf1bdbd9f5fc4c5c8c#code#F1#L194
        uint256 mintUSDon = (quote.quantity * quote.price) / 1e18;
        require(mintUSDon >= minDeposit, "quote amounts less than minimum");

        // there is an invariant WRT USDonManager. Skipping..

        // actual GMTM blindly transfers the deposit token here, doing the same
        // see exhibit A: i'd rather have your token than mine...
        SafeTransferLib.trySafeTransferFrom(depositToken, msg.sender, address(this), depositAmount);
        // next GMTM does some operations with its USDonManager that sends back a normalized amount for the depositToken
        // we will replicate that here by expanding to an "equivalent" 18 decimals if necessary
        // see https://etherscan.io/address/0x2c158bc456e027b2affccadf1bdbd9f5fc4c5c8c#code#F1#L222
        uint256 mult = 1 * 10 ** (18 - (IERC20(depositToken).decimals()));
        uint256 USD18 = depositAmount * mult;

        // invariant: the ondo RWAManager has a mindeposit the above must exceed
        require(USD18 >= minDeposit, "deposit amount less than minimum");

        // GMTM does more minting, transferring and burning, but the end result is the same
        // if USD18 is greater than mintUSDon the delta is "refunded" in USDon minted to the caller
        if (USD18 > mintUSDon) {
            _mint(msg.sender, USD18 - mintUSDon);
        }

        // mint the target asset quantity to the caller, the asset is assumed to be mintable
        IRWA(quote.asset).mint(msg.sender, quote.quantity);

        // this is the exact same return as GMTokenManager
        return quote.quantity;
    }

    function redeemWithAttestation(Quote calldata quote, bytes memory, address receiveToken, uint256 minRedeem)
        external
        returns (uint256)
    {
        // invariant: depositToken can't be zero
        require(receiveToken != address(0), "receive token zero");

        // invariant: side is Sell
        require(quote.side == Side.Sell, "quote side not Sell");

        // invariant: msg.sender is registered
        require(registered[msg.sender], "unregistered user");

        // invariant: quote verifies - we will make this failure or success set-able
        require(quoteWillVerify, "invalid quote");

        // redeem val as 18 decimal
        uint256 redeemUSDon = (quote.quantity * quote.price) / 1e18;
        require(redeemUSDon >= minRedemption, "quote amounts less than minimum");

        // pull the RWA quote.quantity (the actual manager burns it, but we can skip that)
        SafeTransferLib.trySafeTransferFrom(quote.asset, msg.sender, address(this), quote.quantity);

        // contract the 18 digit USDon value to 6 decimal USD*
        uint256 div = 1 * 10 ** (18 - (IERC20(receiveToken).decimals()));
        uint256 USD6 = redeemUSDon / div;

        // invariant: the supplied minimum must be met
        require(USD6 >= minRedeem, "redemption amount less than minimum");

        // transfer the caller a 6 decimal redemption amount, will fail if this contract does not have the balance
        SafeTransferLib.safeTransfer(receiveToken, msg.sender, USD6);

        // ondo returns the 18 decimal amount
        return redeemUSDon;
    }
    // *************** mock settings **********************************/

    function setQuoteWillVerify(bool val) external returns (bool) {
        quoteWillVerify = val;

        return true;
    }

    function setRegistered(address user, bool val) external returns (bool) {
        registered[user] = val;
        return true;
    }

    function setMinDeposit(uint256 val) external returns (bool) {
        minDeposit = val;
        return true;
    }

    function setMinRedemption(uint256 val) external returns (bool) {
        minRedemption = val;
        return true;
    }
}
