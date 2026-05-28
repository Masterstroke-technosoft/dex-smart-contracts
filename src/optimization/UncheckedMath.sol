// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract UncheckedMath {
    function sum(uint256[] calldata values) external pure returns (uint256 total) {
        for (uint256 i; i < values.length; ) {
            unchecked {
                total += values[i];
                ++i;
            }
        }
    }
}
