// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {Script, console2} from "forge-std/Script.sol";
import {RapidEXChains} from "./RapidEXChains.sol";

contract PredictAddresses is Script {
    string[5] private ORDER = [
        "RapiddexV3Factory",
        "MinimalPositionDescriptor",
        "NonfungiblePositionManager",
        "SwapRouter",
        "QuoterV2"
    ];

    function run(address deployer, uint64 startingNonce) external view {
        console2.log("Deployer:", deployer);
        console2.log("Starting nonce:", startingNonce);
        console2.log("");

        for (uint256 i = 0; i < ORDER.length; i++) {
            address predicted = vm.computeCreateAddress(deployer, startingNonce + uint64(i));
            console2.log(string.concat(ORDER[i], ":"), predicted);
        }

        console2.log("");
        console2.log("These are identical on every chain where this deployer");
        console2.log("starts from this nonce and deploys in this same order.");
    }

    function runForChain(address deployer, uint64 startingNonce) external view {
        RapidEXChains.ChainConfig memory c = RapidEXChains.config(block.chainid);
        console2.log("Chain:", c.name, c.chainId);
        console2.log("Wrapped native:", c.wrappedNative);
        this.run(deployer, startingNonce);
    }
}
