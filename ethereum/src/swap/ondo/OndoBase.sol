// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {ReentrancyGuard} from "solady/utils/ReentrancyGuard.sol";
import {EIP712} from "solady/utils/EIP712.sol";
import {ECDSA} from "solady/utils/ECDSA.sol";
import {Soms} from "swap/Soms.sol";
import {Side, OptimizedSwapTotal as Total} from "swap/Types.sol";
import {State, SidedStatus} from "shared/operable/Types.sol";
import {isContract} from "shared/Utils.sol";
import {Quote, VerifyRequest} from "./Types.sol";
import {IBaseOndoManager} from "./IManager.sol";

/**
 * @notice the pieces of an Ondo swap integration that do not depend on which Ondo manager is behind it:
 *         the swap entry point, CoinList request verification (EIP712), the global pause status and the Swapped event. buy/sell/status(asset) are intentionally
 *         left to the concrete contracts so they stay easy to change independently of each other.
 */
abstract contract OndoBase is Soms, ReentrancyGuard, EIP712 {
    uint16 public constant KIND = 3;
    uint16 public constant VERSION = 2;

    bytes32 public constant VERIFY_REQUEST = keccak256(
        "VerifyRequest(uint8 side,address inputToken,address outputToken,address sender,bytes32 attribution,uint256 nonce,uint256 expiry,uint256 amount)"
    );

    /// @dev the address we expect to be ecrecovered
    address public coinList;

    /// @dev the address of the designated Ondo manager, whose type depends on the concrete contract
    address public immutable manager;

    // forge-lint: disable-next-line(missing-zero-check)
    constructor(bytes32 swapId, address _coinList, address _manager) Soms(swapId) {
        // invariant: _coinList is a valid address
        require(validAddr(_coinList), InvalidAddress());
        // invariant: _manager is a valid address and a deployed contract
        require(validAddr(_manager) && isContract(_manager), InvalidAddress());

        manager = _manager;

        // forge-lint: disable-next-line(reentrancy-events)
        emit CoinListUpdated(coinList, _coinList);
        coinList = _coinList;
    }

    // **************** Public API ***************************************************

    /// @notice internal stop/pause state if present, as well as checking global pause state of the Ondo manager
    function status() public view override returns (SidedStatus memory) {
        SidedStatus memory stat = super.status();
        // non zero flags means we have either stopped or paused globally, short-circuit here
        if (stat.flags > 0) {
            return stat;
        }

        // check both manager globals
        IBaseOndoManager man = IBaseOndoManager(manager);
        stat.buyState = man.globalMintingPaused() ? State.Paused : State.Active;
        stat.sellState = man.globalRedeemingPaused() ? State.Paused : State.Active;

        return stat;
    }

    /**
     * @notice entry point for both Sides of a Swap
     * @param quote prepared Ondo quote
     * @param oSig valid Ondo signature for the quote
     * @param token input token when side is Buy. output token when side is Sell
     * @param amount input token deposited when side is Buy, min amount accepted (slippage) when side is Sell
     * @param attribution source of the swap, signed over by CoinList and emitted with the Swapped event
     * @param cSig valid CoinList signature for request verification
     */
    function swap(
        Quote calldata quote,
        bytes calldata oSig,
        address token,
        uint256 amount,
        bytes32 attribution,
        bytes calldata cSig
    ) external active(SWAP_LEVEL) nonReentrant returns (uint256) {
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
                    quote.side,
                    token,
                    quote.asset,
                    msg.sender,
                    attribution,
                    uint256(userData.count),
                    quote.expiration,
                    amount
                ),
                cSig
            );

            // Buy -> returns actual minted quantity of the RWA
            return buy(quote, oSig, token, amount, attribution, userData, conData);
        } else {
            userData = _totals[msg.sender][quote.asset][token];
            conData = _totals[address(this)][quote.asset][token];
            verify(
                VerifyRequest(
                    quote.side,
                    quote.asset,
                    token,
                    msg.sender,
                    attribution,
                    uint256(userData.count),
                    quote.expiration,
                    amount
                ),
                cSig
            );

            // Sell -> returns actual redeemed amount of user selected receive token
            return sell(quote, oSig, token, amount, attribution, userData, conData);
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

    /// @dev buy side swap logic of the concrete contract, returns the quantity of the RWA minted
    function buy(
        Quote calldata quote,
        bytes calldata oSig,
        address token,
        uint256 amount,
        bytes32 attribution,
        Total storage userData,
        Total storage conData
    ) internal virtual returns (uint256);

    /// @dev sell side swap logic of the concrete contract, returns the amount of the token paid to the caller
    function sell(
        Quote calldata quote,
        bytes calldata oSig,
        address token,
        uint256 amount,
        bytes32 attribution,
        Total storage userData,
        Total storage conData
    ) internal virtual returns (uint256);

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
                    req.attribution,
                    req.nonce,
                    req.expiry,
                    req.amount
                )
            )
        );

        require(ECDSA.recoverCalldata(digest, sig) == coinList, Unauthorized());
    }

    /// @dev separate frame for the event, buy and sell can't reach this many values on their own stack
    function emitSwapped(
        Quote calldata quote,
        address token,
        bytes32 attribution,
        uint256 assetAmount,
        uint256 _fee,
        uint256 paymentAmount
    ) internal {
        // forge-lint: disable-start(reentrancy-events)
        emit Swapped(
            msg.sender,
            quote.asset,
            token,
            attribution,
            quote.attestationId,
            quote.side,
            assetAmount,
            _fee,
            paymentAmount
        );
        // forge-lint: disable-end(reentrancy-events)
    }

    function _recordTotals(Total storage userData, Total storage conData, uint256 input, uint256 fee, uint256 output)
        internal
    {
        userData.count += 1;
        conData.count += 1;
        // forge-lint: disable-next-line(unsafe-typecast)
        userData.inputSum += uint128(input);
        // forge-lint: disable-next-line(unsafe-typecast)
        conData.inputSum += uint128(input);
        // forge-lint: disable-next-line(unsafe-typecast)
        userData.feeSum += uint128(fee);
        // forge-lint: disable-next-line(unsafe-typecast)
        conData.feeSum += uint128(fee);
        // forge-lint: disable-next-line(unsafe-typecast)
        userData.outputSum += uint128(output);
        // forge-lint: disable-next-line(unsafe-typecast)
        conData.outputSum += uint128(output);
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
