// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {WMST} from "../src/WMST.sol";

/// @notice Deploys WMST, the wrapped native token used as WETH9 by V3 periphery.
/// @dev Deploy the factory, position manager, router, and quoter with DeployV3Stack.s.sol.
contract DeployMST is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        WMST wmst = deploy();
        console.log("WMST deployed at:", address(wmst));

        vm.stopBroadcast();
    }

    function deploy() public returns (WMST wmst) {
        wmst = new WMST();
    }
}
