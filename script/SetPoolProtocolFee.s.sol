// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "v3-core/interfaces/IUniswapV3Pool.sol";

/// @notice Sets the protocol fee split on a pool. Only the RapidexV3Factory owner may call this

contract SetPoolProtocolFee is Script {
    function run() external {
        address pool = vm.envAddress("POOL_ADDRESS");
        uint8 feeProtocol0 = uint8(vm.envUint("FEE_PROTOCOL_0"));
        uint8 feeProtocol1 = uint8(vm.envUint("FEE_PROTOCOL_1"));
        uint256 ownerKey = vm.envUint("FACTORY_OWNER_PRIVATE_KEY");

        vm.startBroadcast(ownerKey);
        IUniswapV3Pool(pool).setFeeProtocol(feeProtocol0, feeProtocol1);
        vm.stopBroadcast();

        console2.log("Set feeProtocol on pool", pool);
        console2.log("feeProtocol0", feeProtocol0);
        console2.log("feeProtocol1", feeProtocol1);
    }
}
