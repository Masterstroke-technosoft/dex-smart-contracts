// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {WMST} from "../src/WMST.sol";
import {TestToken} from "../src/TestToken.sol";
import {DeployV3Stack} from "./DeployV3Stack.s.sol";

/// @notice Full reset: deploys a brand-new WMST, a brand-new test USDC, and a fresh
/// V3 factory/periphery stack around them. Use when the old pools/addresses need to
/// be abandoned entirely (they cannot be deleted on-chain, only orphaned).
contract DeployFullStack is DeployV3Stack {
    function run() external override {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);

        WMST wmst = new WMST();
        console.log("WMST deployed at:", address(wmst));

        TestToken usdc = new TestToken("USD Coin", "USDC", 18, 1_000_000 ether);
        console.log("USDC deployed at:", address(usdc));

        V3Stack memory stack = deploy(address(wmst));

        console.log("RapidexV3Factory:", stack.factory);
        console.log("MinimalPositionDescriptor:", stack.descriptor);
        console.log("NonfungiblePositionManager:", stack.positionManager);
        console.log("SwapRouter:", stack.swapRouter);
        console.log("QuoterV2:", stack.quoterV2);
        console.log("Deployer:", deployer);

        vm.stopBroadcast();
    }
}
