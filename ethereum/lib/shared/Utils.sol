// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

function isContract(address deployment) view returns (bool) {
    uint32 size;

    assembly {
        size := extcodesize(deployment)
    }

    return size > 0;
}
