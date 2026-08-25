// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {EIP712} from "solady/utils/EIP712.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";
import {Soms} from "swap/Soms.sol";
import {Side, OptimizedSwapTotal as Total} from "swap/Types.sol";
import {isContract} from "shared/Utils.sol";
import {Quote, VerifyRequest} from "./Types.sol";
import {IManager} from "./IManager.sol";

contract Ondo is Soms, ReentrancyGuard, EIP712 {
    bytes32 public constant VERIFY_REQUEST = keccak256(
        "VerifyRequest(uint8 side,address inputToken,address outputToken,address sender,uint64 nonce,uint256 expiry,uint256 amount)"
    );

    /// @dev the address we expect to be ecrecovered
    address public coinList;
    /// @dev the address of a designated GMTokenManager
    address public manager;

    constructor(bytes32 swapId, address _coinList, address _manager) Soms(swapId) {
        // invariant: _coinList is a valid address
        require(validAddr(_coinList), InvalidAddress());
        // invariant: _manager is a valid address and a deployed contract
        require(validAddr(_manager) && isContract(_manager), InvalidAddress());
        coinList = _coinList;
        manager = _manager;
        // NOTE: USDC is accepted
        inputTokens[0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48] = true;
    }

    // **************** Public API ***************************************************

    /**
     * @notice entry point for both Sides of a Swap
     * @param quote prepared Ondo quote
     * @param oSig valid Ondo signature for the quote
     * @param token input token when side is Buy. output token when side is Sell
     * @param amount input token deposited when side is Buy, min amount accepted (slippage) when side is Sell
     * @param cSig valid CoinList signature for request verification
     */
    function swap(Quote calldata quote, bytes calldata oSig, address token, uint256 amount, bytes calldata cSig)
        external
        active(SWAP_LEVEL)
        nonReentrant
        returns (uint256)
    {
        // invariant: the given token address is an approved input (applies equally to Sell side output)
        require(inputTokens[token], InvalidAddress());

        Total storage data;

        if (quote.side == Side.Buy) {
            data = _totals[msg.sender][token][quote.asset];
            // invariant: cSig ecrecovers our set coinlist address
            verify(
                VerifyRequest(quote.side, token, quote.asset, msg.sender, uint64(data.count), quote.expiration, amount),
                cSig
            );

            // Buy -> returns actual minted quantity of the RWA
            return buy(quote, oSig, token, amount, data);
        } else {
            data = _totals[msg.sender][quote.asset][token];
            verify(
                VerifyRequest(quote.side, quote.asset, token, msg.sender, uint64(data.count), quote.expiration, amount),
                cSig
            );

            // Sell -> returns actual redeemed amount of user selected receive token
            return sell(quote, oSig, token, amount, data);
        }
    }

    // ********************** Owner API **********************************************************/

    /// @dev set the address a swap verification request should ecrecover. owner only
    function setCoinListAddress(address addr) external onlyOwner returns (bool) {
        coinList = addr;
        return true;
    }

    /// @dev utility to fetch the domainSeparator for debugging if needed. owner only
    function domainSeparator() external view onlyOwner returns (bytes32) {
        return _domainSeparator();
    }

    // **************** Internals  ***************************************************

    /// @dev ecrecover the signed request, fails if not the designated coinlist address
    function verify(VerifyRequest memory req, bytes calldata sig) internal view {
        bytes32 digest = _hashTypedData(
            keccak256(
                abi.encode(
                    VERIFY_REQUEST,
                    req.side,
                    req.inputToken,
                    req.outputToken,
                    req.sender,
                    req.nonce,
                    req.expiry,
                    req.amount
                )
            )
        );

        require(ECDSA.recover(digest, sig) == coinList, Unauthorized());
    }

    /// @dev abstracted logic for buy side swaps
    function buy(Quote calldata quote, bytes calldata oSig, address token, uint256 amount, Total storage data)
        internal
        returns (uint256)
    {
        // buy side fee is taken on the input token amount
        (uint256 _fee, uint256 input) = super.fee(quote.side, amount);

        { // stack management
            uint256 mult = 1 * 10 ** (18 - (IERC20(token).decimals())); // what we multiply by to get 18 decimal format
            // invariant: normalized delta (overpayment) is not larger than .01 Ether
            require(
                // expand if necessary
                (input * mult)
                        // normalize the amt paid for quote (always 18 decimal format)
                        // NOTE: this quote is "fee aware"
                        - ((quote.quantity * quote.price) / 1e18) < 1e16,
                InvalidAmount()
            );
        }

        // pull amount from user
        if (!SafeTransferLib.trySafeTransferFrom(token, msg.sender, address(this), amount)) {
            revert SwapFailed(msg.sender, token);
        }

        // this can roll over as it is only ever used to synchronize signatures from CL backend
        data.count = data.count == type(uint8).max ? 0 : data.count + 1;

        // optimized bookkeeping for the caller
        // forge-lint: disable-next-line(unsafe-typecast)
        data.inputSum += uint88(input); // sum of stable given minus fees
        // forge-lint: disable-next-line(unsafe-typecast)
        data.feeSum += uint72(_fee); // sum of fees paid in above stable

        // approve the manager to pull our input token, reverts on fail
        SafeTransferLib.safeApproveWithRetry(token, manager, input);

        // vs relying on static return values, we capture the minted amount
        uint256 val = IERC20(quote.asset).balanceOf(address(this));

        // call manager with the appropriate args, NOTE input, ignoring static return
        IManager(manager).mintWithAttestation(quote, oSig, token, input);

        // invariant: minted amount is GTE quote.quantity
        val = IERC20(quote.asset).balanceOf(address(this)) - val;
        require(val >= quote.quantity, InsufficientAmount());

        // buy side output sums are the actual minted amounts
        // forge-lint: disable-next-line(unsafe-typecast)
        data.outputSum += uint88(val);

        // transfer the asset to the caller
        SafeTransferLib.safeTransfer(quote.asset, msg.sender, val);

        // inputAmount is inclusive of fee here
        emit Swapped(msg.sender, token, quote.asset, amount, val, quote.price);

        return val;
    }

    /// @dev abstracted logic for sell side swaps
    function sell(Quote calldata quote, bytes calldata oSig, address token, uint256 amount, Total storage data)
        internal
        returns (uint256)
    {
        // pull RWA quote.quantity from user
        if (!SafeTransferLib.trySafeTransferFrom(quote.asset, msg.sender, address(this), quote.quantity)) {
            revert SwapFailed(msg.sender, quote.asset);
        }

        data.count = data.count == type(uint8).max ? 0 : data.count + 1;

        // sell side input sums are quote.quantity
        // forge-lint: disable-next-line(unsafe-typecast)
        data.inputSum += uint88(quote.quantity);

        // approve the manager to pull our RWA token, reverts on fail
        SafeTransferLib.safeApproveWithRetry(quote.asset, manager, quote.quantity);

        // get our current balance of the stable coin
        uint256 val = IERC20(token).balanceOf(address(this));

        // ignoring the returned USDon value of the tx
        IManager(manager).redeemWithAttestation(quote, oSig, token, amount);

        // invariant: the amount transferred is at least the given amount (slippage)
        val = IERC20(token).balanceOf(address(this)) - val;
        require(val >= amount, InsufficientAmount());

        // sell fee is a simple muldiv with the set basis point percentage on the redeemed amount
        uint256 _fee = super.bpp(quote.side, val);
        uint256 output = val - _fee;

        // forge-lint: disable-next-line(unsafe-typecast)
        data.feeSum += uint72(_fee);
        // forge-lint: disable-next-line(unsafe-typecast)
        data.outputSum += uint88(output);

        // transfer caller their redeemed token - fee
        SafeTransferLib.safeTransfer(token, msg.sender, output);

        // output amount is exclusive of fee here
        emit Swapped(msg.sender, quote.asset, token, quote.quantity, output, quote.price);

        return output;
    }

    /// @dev required override for solady's EIP712 class
    function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
        name = "CoinList";
        version = "1";
    }

    /// @dev overridden to allow owner verification of domain separator
    function _domainSeparator() internal view override returns (bytes32) {
        return super._domainSeparator();
    }
}
