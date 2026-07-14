// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

import {ERC20} from "solady/tokens/ERC20.sol";

contract TestToken is ERC20 {
    string private _name;
    string private _symbol;

    constructor(string memory n, string memory s) {
        _name = n;
        _symbol = s;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    // so that we can easily create balances in tests
    function mint(address to, uint256 amount) public returns (bool) {
        _mint(to, amount);
        return true;
    }
}
