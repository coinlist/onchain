// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Quote} from "./Types.sol";

interface IBaseOndoManager {
    function globalMintingPaused() external view returns (bool);

    function globalRedeemingPaused() external view returns (bool);
}

/// @notice minimal interface for working with Ondo GMTokenManager contract
interface IMarketManager is IBaseOndoManager {
    function gmTokenMintingPaused(address asset) external view returns (bool);

    function gmTokenRedemptionsPaused(address asset) external view returns (bool);

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

/// @notice minimal interface for working with Ondo PortfolioTokenManager contract
interface IPortfolioManager is IBaseOndoManager {
    function stablecoin() external view returns (address);

    function portfolioTokenMintingPaused(address asset) external view returns (bool);

    function portfolioTokenRedemptionsPaused(address asset) external view returns (bool);

    function mintWithAttestation(Quote calldata quote, bytes memory signature)
        external
        returns (
            uint256 /*portfolioTokenAmount*/
        );

    function redeemWithAttestation(Quote calldata quote, bytes memory signature)
        external
        returns (
            uint256 /*stablecoinAmount*/
        );
}
