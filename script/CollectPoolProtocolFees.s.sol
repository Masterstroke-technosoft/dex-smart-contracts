// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "v3-core/interfaces/IUniswapV3Pool.sol";

/// @notice Collects accrued protocol fees from a pool to a recipient. Only the RapidexV3Factory

contract CollectPoolProtocolFees is Script {
    function run() external {
        address pool = vm.envAddress("POOL_ADDRESS");
        address recipient = vm.envAddress("FEE_RECIPIENT");
        uint128 amount0Requested = uint128(vm.envUint("AMOUNT_0_REQUESTED"));
        uint128 amount1Requested = uint128(vm.envUint("AMOUNT_1_REQUESTED"));
        uint256 ownerKey = vm.envUint("FACTORY_OWNER_PRIVATE_KEY");

        vm.startBroadcast(ownerKey);
        (uint128 amount0, uint128 amount1) = IUniswapV3Pool(pool).collectProtocol(
            recipient,
            amount0Requested,
            amount1Requested
        );
        vm.stopBroadcast();

        console2.log("Collected protocol fees from pool", pool);
        console2.log("amount0", amount0);
        console2.log("amount1", amount1);
    }
}
