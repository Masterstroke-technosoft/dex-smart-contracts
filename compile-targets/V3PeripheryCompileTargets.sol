// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import "v3-periphery/NonfungiblePositionManager.sol";
import "v3-periphery/SwapRouter.sol";
import "v3-periphery/lens/QuoterV2.sol";

/// @notice Forces Foundry to compile the official Uniswap V3 periphery artifacts.
contract V3PeripheryCompileTargets {}
