// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.34;

import {Quote} from "./Types.sol";

/// @notice minimal interface for working with Ondo GMTokenManager contract
interface IManager {
    function mintWithAttestation(
        Quote calldata quote,
        bytes memory signature,
        address depositToken,
        uint256 depositAmount
    )
        external
        returns (
            uint256 /*receivedGmTokenAmount*/
        );

    function redeemWithAttestation(
        Quote calldata quote,
        bytes memory signature,
        address receiveToken,
        uint256 minimumReceiveAmount
    )
        external
        returns (
            uint256 /*redemptionUSDonValue*/
        );
}
