// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {LPStateStorage} from "../src/LPStateStorage.sol";

contract DeployLPStateStorage is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(pk);

        LPStateStorage storageContract = new LPStateStorage();
        console.log("LPStateStorage deployed at:", address(storageContract));

        vm.stopBroadcast();
    }
}
