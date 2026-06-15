// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {WMST} from "../src/WMST.sol";
import {TestToken} from "../src/TestToken.sol";
import {LPStateStorage} from "../src/LPStateStorage.sol";
import {TestingExecutor} from "../src/testingexecutor.sol";
import {INonfungiblePositionManager} from "v3-periphery/interfaces/INonfungiblePositionManager.sol";

contract DeployCleanDex is Script {
    uint160 internal constant SQRT_PRICE_1_TO_1 = 79228162514264337593543950336;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address factory = vm.envAddress("V3_FACTORY_ADDRESS");
        address positionManager = vm.envAddress("POSITION_MANAGER_ADDRESS");
        address swapRouter = vm.envAddress("SWAP_ROUTER_ADDRESS");
        address quoter = vm.envAddress("QUOTER_V2_ADDRESS");

        vm.startBroadcast(pk);

        // 1. Deploy fresh WMST
        WMST wmst = new WMST();
        console.log("WMST deployed at:", address(wmst));

        // 2. Deploy fresh USDC (TestToken)
        uint256 initialSupply = 1000000 * 1e18; // 1M tokens
        TestToken usdc = new TestToken("USD Coin", "USDC", 18, initialSupply);
        console.log("USDC deployed at:", address(usdc));

        // 3. Deploy fresh LPStateStorage
        LPStateStorage lpStateStorage = new LPStateStorage();
        console.log("LPStateStorage deployed at:", address(lpStateStorage));

        // 4. Deploy fresh TestingExecutor
        TestingExecutor executor = new TestingExecutor(
            factory,
            positionManager,
            swapRouter,
            quoter,
            address(wmst),
            address(usdc),
            address(lpStateStorage)
        );
        console.log("TestingExecutor deployed at:", address(executor));

        // 5. Transfer ownership of LPStateStorage to TestingExecutor
        lpStateStorage.transferOwnership(address(executor));
        console.log("Ownership of LPStateStorage transferred to TestingExecutor");

        // 6. Sort tokens for pool creation
        address token0 = address(wmst) < address(usdc) ? address(wmst) : address(usdc);
        address token1 = address(wmst) < address(usdc) ? address(usdc) : address(wmst);

        // 7. Initialize pool for each tier (500, 3000, 10000) with 0 liquidity at 1-to-1 ratio
        INonfungiblePositionManager manager = INonfungiblePositionManager(positionManager);

        address pool500 = manager.createAndInitializePoolIfNecessary(token0, token1, 500, SQRT_PRICE_1_TO_1);
        console.log("0.05% Pool created and initialized at:", pool500);

        address pool3000 = manager.createAndInitializePoolIfNecessary(token0, token1, 3000, SQRT_PRICE_1_TO_1);
        console.log("0.30% Pool created and initialized at:", pool3000);

        address pool10000 = manager.createAndInitializePoolIfNecessary(token0, token1, 10000, SQRT_PRICE_1_TO_1);
        console.log("1.00% Pool created and initialized at:", pool10000);

        vm.stopBroadcast();
    }
}
