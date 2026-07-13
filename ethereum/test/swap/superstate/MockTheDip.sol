// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {TestToken} from "shared/TestToken.sol";
import {Market, MarketState} from "superstate/Types.sol";

contract MockTheDip is TestToken {
    bool public shouldRevert = false;

    /// @dev 1e6 decimal token by default
    uint256 public calculatedOutput = 1000000;
    /// @dev if non zero will return as actual amount spent
    uint256 public calculatedInput = 0;

    mapping(address => bool) private _whitelist;

    mapping(bytes32 => Market) public markets;

    constructor(string memory n, string memory s) TestToken(n, s) {}

    /// @notice override the 18 decimals to a stable coin 6
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice this contract will also serve as the IDip
    function dipContract() external view returns (address) {
        return address(this);
    }

    /// @notice checks the _whitelist
    function isAllowed(address addr) external view returns (bool) {
        return _whitelist[addr];
    }

    /// @notice mimic the ss buyTheDip call. we will transfer in the amount and mint sender the set calculatedAmount
    function buyTheDip(bytes32, uint256 amount, uint256, address token) external returns (uint256) {
        // force fail if desired..
        require(!shouldRevert, "womp womp");
        // caller must be whitelisted
        require(_whitelist[msg.sender], "unauthorized");
        // transferFrom the calling contract to here, *should have been approved*
        require(IERC20(token).transferFrom(msg.sender, address(this), amount));

        _mint(msg.sender, calculatedOutput);

        return calculatedOutput;
    }

    /// @notice IRL is a separate contract implementing the SS IDip interface, this is fine for mocking
    function calculateOutput(bytes32, uint256 amount, uint8) external view returns (uint256, uint256) {
        // not really needed on a read, but could happen with these args and the large amt of code on their side
        require(!shouldRevert, "womp womp");

        uint256 spent = calculatedInput > 0 ? calculatedInput : amount;
        return (spent, calculatedOutput);
    }

    /// @notice set the calculatedOutput to another value
    function setCalculatedOutput(uint256 amount) external returns (bool) {
        calculatedOutput = amount;
        return true;
    }

    function setCalculatedInput(uint256 amount) external returns (bool) {
        calculatedInput = amount;
        return true;
    }

    function setShouldRevert(bool state) external returns (bool) {
        shouldRevert = state;
        return true;
    }

    /// @notice given an address and a boolean set the values into the whitelist
    function whitelist(address addr, bool auth) external returns (bool) {
        _whitelist[addr] = auth;
        return true;
    }

    /// @notice set a new market into the mapping or change the value of an existing one
    function setMarket(bytes32 marketId, MarketState state) external returns (bool) {
        Market storage mkt = markets[marketId];
        mkt.state = state;
        return true;
    }
}
