// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {Test} from "forge-std/Test.sol";
import {MMock} from "../MMock.sol";

contract MMockDefaultState is Test {
    address public constant SOMEONE = 0x6060606060606060606060606060606060606060;
    MMock mock;

    function setUp() public {
        mock = new MMock("Gmock", "GMT");
    }

    function testMetaData() public {
        assertEq(mock.name(), "Gmock");
        assertEq(mock.symbol(), "GMT");
    }

    function testMinDeposit() public {
        // is 0 by default
        assertEq(mock.minDeposit(), 0);
        // can be set
        assert(mock.setMinDeposit(1e18));
        assertEq(mock.minDeposit(), 1e18);
    }

    function testQuoteWillVerify() public {
        // is true by default
        assert(mock.quoteWillVerify());
        // can be set to false
        assert(mock.setQuoteWillVerify(false));
        assertEq(mock.quoteWillVerify(), false);
    }

    function testRegistered() public {
        // false by default
        assertEq(mock.registered(SOMEONE), false);
        // can be set
        assert(mock.setRegistered(SOMEONE, true));
        assertEq(mock.registered(SOMEONE), true);
        // can be unset
        assert(mock.setRegistered(SOMEONE, false));
        assertEq(mock.registered(SOMEONE), false);
    }
}
