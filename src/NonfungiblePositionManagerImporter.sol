// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "v3-periphery/NonfungiblePositionManager.sol";

contract NonfungiblePositionManagerImporter is NonfungiblePositionManager {
    constructor(
        address factory,
        address wmst,
        address tokenDescriptor
    ) NonfungiblePositionManager(factory, wmst, tokenDescriptor) {}
}
