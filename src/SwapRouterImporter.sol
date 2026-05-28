// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "v3-periphery/SwapRouter.sol";

contract SwapRouterImporter is SwapRouter {
    constructor(address factory, address wmst) SwapRouter(factory, wmst) {}
}
