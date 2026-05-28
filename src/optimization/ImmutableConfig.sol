// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract ImmutableConfig {
    address public immutable factory;
    address public immutable router;

    constructor(address _factory, address _router) {
        factory = _factory;
        router = _router;
    }
}
