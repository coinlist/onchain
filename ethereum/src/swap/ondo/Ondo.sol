// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "solady/utils/SafeTransferLib.sol";
import {EIP712} from "solady/utils/EIP712.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";
import {Soms} from "swap/Soms.sol";
import {Side, OptimizedSwapTotal as Total} from "swap/Types.sol";
import {State, SidedStatus} from "shared/operable/Types.sol";
import {isContract} from "shared/Utils.sol";
import {Quote, VerifyRequest} from "./Types.sol";
import {IManager} from "./IManager.sol";

contract Ondo is Soms, ReentrancyGuard, EIP712 {
    bytes32 public constant VERIFY_REQUEST = keccak256(
        "VerifyRequest(uint8 side,address inputToken,address outputToken,address sender,uint256 nonce,uint256 expiry,uint256 amount)"
    );

    /// @dev the address we expect to be ecrecovered
    address public coinList;
    /// @dev the address of a designated GMTokenManager
    address public manager;

    constructor(bytes32 swapId, address _coinList, address _manager, address token) Soms(swapId) {
        // invariant: _coinList is a valid address
        require(validAddr(_coinList), InvalidAddress());
        // invariant: _manager is a valid address and a deployed contract
        require(validAddr(_manager) && isContract(_manager), InvalidAddress());

        emit CoinListUpdated(coinList, _coinList);
        coinList = _coinList;

        manager = _manager;

        // if an initially whitelisted token is given
        if (token != address(0)) {
            setInputToken(token, true);
        }
    }

    // **************** Public API ***************************************************

    /// @notice internal stop/pause state if present, as well as checking global pause state of the IManager
    function status() public view override returns (SidedStatus memory) {
        SidedStatus memory stat = super.status();
        // non zero flags means we have either stopped or paused globally, short-circuit here
        if (stat.flags > 0) {
            return stat;
        }

        // check both manager globals
        IManager man = IManager(manager);
        stat.buyState = man.globalMintingPaused() ? State.Paused : State.Active;
        stat.sellState = man.globalRedeemingPaused() ? State.Paused : State.Active;

        return stat;
    }

    function status(address asset) external view returns (SidedStatus memory) {
        // get any status set by us, or globally by ondo
        SidedStatus memory stat = status();

        if (stat.flags > 0) {
            return stat;
        }

        // if not globally paused, check the specific state of the given rwa
        IManager man = IManager(manager);

        if (stat.buyState == State.Active && man.gmTokenMintingPaused(asset)) {
            stat.buyState = State.Paused;
        }

        if (stat.sellState == State.Active && man.gmTokenRedemptionsPaused(asset)) {
            stat.sellState = State.Paused;
        }

        return stat;
    }

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

        Total storage userData;
        Total storage conData;

        if (quote.side == Side.Buy) {
            userData = _totals[msg.sender][token][quote.asset];
            conData = _totals[address(this)][token][quote.asset];
            // invariant: cSig ecrecovers our set coinlist address
            verify(
                VerifyRequest(
                    quote.side, token, quote.asset, msg.sender, uint256(userData.count), quote.expiration, amount
                ),
                cSig
            );

            // Buy -> returns actual minted quantity of the RWA
            return buy(quote, oSig, token, amount, userData, conData);
        } else {
            userData = _totals[msg.sender][quote.asset][token];
            conData = _totals[address(this)][quote.asset][token];
            verify(
                VerifyRequest(
                    quote.side, quote.asset, token, msg.sender, uint256(userData.count), quote.expiration, amount
                ),
                cSig
            );

            // Sell -> returns actual redeemed amount of user selected receive token
            return sell(quote, oSig, token, amount, userData, conData);
        }
    }

    /// @notice expose the EIP712 _domainSeparator for testing/debugging
    function domainSeparator() external view returns (bytes32) {
        return super._domainSeparator();
    }

    // ********************** Owner API **********************************************************/

    /// @dev set the address a swap verification request should ecrecover. owner only
    function setCoinListAddress(address addr) external onlyOwner returns (bool) {
        emit CoinListUpdated(coinList, addr);
        coinList = addr;

        return true;
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
    function buy(
        Quote calldata quote,
        bytes calldata oSig,
        address token,
        uint256 amount,
        Total storage userData,
        Total storage conData
    ) internal returns (uint256) {
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

        userData.count += 1;
        conData.count += 1;

        // optimized bookkeeping for the caller
        // forge-lint: disable-next-line(unsafe-typecast)
        userData.inputSum += uint128(input); // sum of stable given minus fees
        // forge-lint: disable-next-line(unsafe-typecast)
        conData.inputSum += uint128(input);
        // forge-lint: disable-next-line(unsafe-typecast)
        userData.feeSum += uint128(_fee); // sum of fees paid in above stable
        // forge-lint: disable-next-line(unsafe-typecast)
        conData.feeSum += uint128(_fee);

        // approve the manager to pull our input token, reverts on fail
        SafeTransferLib.safeApproveWithRetry(token, manager, input);

        // vs relying on static return values, we capture the minted amount
        uint256 val = IERC20(quote.asset).balanceOf(address(this));

        // call manager with the appropriate args, NOTE input, ignoring static return
        IManager(manager).mintWithAttestation(quote, oSig, token, input);

        // clean up any residual allowance
        SafeTransferLib.safeApproveWithRetry(token, manager, 0);

        // invariant: minted amount is GTE quote.quantity
        val = IERC20(quote.asset).balanceOf(address(this)) - val;
        require(val >= quote.quantity, InsufficientAmount());

        // buy side output sums are the actual minted amounts
        // forge-lint: disable-next-line(unsafe-typecast)
        userData.outputSum += uint128(val);
        // forge-lint: disable-next-line(unsafe-typecast)
        conData.outputSum += uint128(val);

        // transfer the asset to the caller
        SafeTransferLib.safeTransfer(quote.asset, msg.sender, val);

        emit Swapped(msg.sender, token, quote.asset, quote.attestationId, quote.side, amount, _fee, val);

        return val;
    }

    /// @dev abstracted logic for sell side swaps
    function sell(
        Quote calldata quote,
        bytes calldata oSig,
        address token,
        uint256 amount,
        Total storage userData,
        Total storage conData
    ) internal returns (uint256) {
        // pull RWA quote.quantity from user
        if (!SafeTransferLib.trySafeTransferFrom(quote.asset, msg.sender, address(this), quote.quantity)) {
            revert SwapFailed(msg.sender, quote.asset);
        }

        userData.count += 1;
        conData.count += 1;

        // sell side input sums are quote.quantity
        // forge-lint: disable-next-line(unsafe-typecast)
        userData.inputSum += uint128(quote.quantity);
        // forge-lint: disable-next-line(unsafe-typecast)
        conData.inputSum += uint128(quote.quantity);

        // approve the manager to pull our RWA token, reverts on fail
        SafeTransferLib.safeApproveWithRetry(quote.asset, manager, quote.quantity);

        // get our current balance of the stable coin
        uint256 val = IERC20(token).balanceOf(address(this));

        // ignoring the returned USDon value of the tx
        IManager(manager).redeemWithAttestation(quote, oSig, token, amount);

        // clean up any residual allowance
        SafeTransferLib.safeApproveWithRetry(quote.asset, manager, 0);

        // invariant: the amount transferred is at least the given amount (slippage)
        val = IERC20(token).balanceOf(address(this)) - val;
        require(val >= amount, InsufficientAmount());

        // sell fee is a simple muldiv with the set basis point percentage on the redeemed amount
        uint256 _fee = super.bpp(quote.side, val);

        // "output" value is (val - _fee)

        // forge-lint: disable-next-line(unsafe-typecast)
        userData.feeSum += uint128(_fee);
        // forge-lint: disable-next-line(unsafe-typecast)
        conData.feeSum += uint128(_fee);
        // forge-lint: disable-next-line(unsafe-typecast)
        userData.outputSum += uint128((val - _fee));
        // forge-lint: disable-next-line(unsafe-typecast)
        conData.outputSum += uint128((val - _fee));

        // transfer caller their redeemed token - fee
        SafeTransferLib.safeTransfer(token, msg.sender, (val - _fee));

        emit Swapped(msg.sender, quote.asset, token, quote.attestationId, quote.side, quote.quantity, _fee, val);

        return val - _fee;
    }

    /// @dev required override for solady's EIP712 class
    function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
        name = "CoinList";
        version = "1";
    }

    // **************** Events  ******************************************************

    /// @notice Emitted when the coinlist signer address is updated
    event CoinListUpdated(address prev, address next);
}
