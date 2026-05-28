// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract PackedStorage {
    struct Position {
        uint128 liquidity;
        int24 tickLower;
        int24 tickUpper;
        uint80 nonce;
    }

    mapping(uint256 => Position) public positions;
}
