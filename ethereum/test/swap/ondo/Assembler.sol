// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.34;

// @notice assembles eip712 constructs for ondo to be signed

import {Side} from "swap/Types.sol";
import {Quote, VerifyRequest} from "ondo/Types.sol";

contract Assembler {
    uint256 public constant EXPIRY = 1234567890;

    // default of 100 whatever at $2 each (if 1e18 == $1)
    uint256 public quantity = 100e18; // quantities are in wei
    uint256 public price = 2e18; // prices are in wei

    address public rwa = 0x4040404040404040404040404040404040404040;
    // anvil -m 'test test test test test test test test test test test junk' address[0]
    address public addr = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    bytes32 public privateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    function quote(uint256 chainId, Side side) external view returns (Quote memory) {
        return Quote(chainId, 123, keccak256("idk"), rwa, price, quantity, EXPIRY, side, keccak256("idc"));
    }

    function digest(bytes32 ds, bytes32 hash) external pure returns (bytes32 hashed) {
        assembly {
            // Compute the digest.
            mstore(0x00, 0x1901000000000000) // Store "\x19\x01".
            mstore(0x1a, ds) // Store the domain separator.
            mstore(0x3a, hash) // Store the struct hash.
            hashed := keccak256(0x18, 0x42)
            // restore free memory so as not to revert
            mstore(0x3a, 0)
        }
    }

    function structHash(bytes32 req, Side side, address input, address output, address user, uint64 nonce, uint256 amt)
        external
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(req, side, input, output, user, nonce, EXPIRY, amt));
    }

    function encodeSig(uint8 v, bytes32 r, bytes32 s) external pure returns (bytes memory) {
        return abi.encodePacked(r, s, v);
    }

    // ************ setters for changing public vars at runtime *******************************

    function setQuantity(uint256 val) public returns (bool) {
        quantity = val;
        return true;
    }

    function setPrice(uint256 val) public returns (bool) {
        price = val;
        return true;
    }

    function setRwa(address val) public returns (bool) {
        rwa = val;
        return true;
    }

    function setAddr(address val) public returns (bool) {
        addr = val;
        return true;
    }

    function setPk(bytes32 val) public returns (bool) {
        privateKey = val;
        return true;
    }
}
