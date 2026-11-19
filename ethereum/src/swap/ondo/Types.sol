// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Side} from "swap/Types.sol";

/**
 * @notice Quote struct that is signed by the attestation signer
 * @dev    This struct must exactly match https://etherscan.io/address/0x2c158bc456e027b2affccadf1bdbd9f5fc4c5c8c#code#F13#L44
 * @param  chainId        The chain ID of the quote is intended for
 * @param  attestationId  The ID of the quote
 * @param  userId         The user ID of CoinList's integration contract
 * @param  asset          The address of the GM token being bought or sold
 * @param  price          The price of the GM token in USD with 18 decimals
 * @param  quantity       The quantity of GM tokens being bought or sold
 * @param  expiration     The expiration of the quote in seconds since the epoch
 * @param  side           The direction of the quote (Buy or Sell)
 * @param  additionalData Any additional data that is needed for the quote
 */
struct Quote {
    uint256 chainId;
    uint256 attestationId;
    bytes32 userId;
    address asset;
    uint256 price;
    uint256 quantity;
    uint256 expiration;
    Side side;
    bytes32 additionalData;
}

/// @notice EIP-712 Type Hash for CoinList prepared payloads
/// @dev result: 0x79d6236ca1d588b1996795b0261d69b40eb4d5f89d56c5ac1301e8d7eda9acf1
struct VerifyRequest {
    Side side;
    address inputToken;
    address outputToken;
    address sender;
    bytes32 attribution;
    uint256 nonce;
    uint256 expiry;
    uint256 amount;
}
