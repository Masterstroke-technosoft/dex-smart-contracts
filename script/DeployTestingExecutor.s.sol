// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {TestingExecutor} from "../src/testingexecutor.sol";

contract DeployTestingExecutor is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");

        address factory = vm.envAddress("V3_FACTORY_ADDRESS");
        address positionManager = vm.envAddress("POSITION_MANAGER_ADDRESS");
        address swapRouter = vm.envAddress("SWAP_ROUTER_ADDRESS");
        address quoter = vm.envOr("QUOTER_V2_ADDRESS", vm.envOr("QUOTER_ADDRESS", address(0)));
        address wmst = vm.envAddress("WMST_ADDRESS");
        address usdc = vm.envAddress("USDC_ADDRESS");
        address lpStateStorage = vm.envAddress("LP_STATE_STORAGE_ADDRESS");

        require(factory != address(0), "V3_FACTORY_ADDRESS is required");
        require(positionManager != address(0), "POSITION_MANAGER_ADDRESS is required");
        require(swapRouter != address(0), "SWAP_ROUTER_ADDRESS is required");
        require(quoter != address(0), "QUOTER_V2_ADDRESS or QUOTER_ADDRESS is required");
        require(wmst != address(0), "WMST_ADDRESS is required");
        require(usdc != address(0), "USDC_ADDRESS is required");
        require(lpStateStorage != address(0), "LP_STATE_STORAGE_ADDRESS is required");

        vm.startBroadcast(pk);

        TestingExecutor executor = new TestingExecutor(
            factory,
            positionManager,
            swapRouter,
            quoter,
            wmst,
            usdc,
            lpStateStorage
        );

        console.log("TestingExecutor deployed at:", address(executor));

        vm.stopBroadcast();
    }
}
