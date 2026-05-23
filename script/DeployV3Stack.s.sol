// SPDX-License-Identifier: MIT
pragma solidity =0.8.24;

import "forge-std/Script.sol";
import {MinimalPositionDescriptor} from "../src/MinimalPositionDescriptor.sol";

/// @notice Deploys the official Uniswap V3 factory and periphery around an existing WMST.
/// @dev Set WMST_ADDRESS in .env to the address printed by DeployMST.s.sol.
contract DeployV3Stack is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address wmst = vm.envAddress("WMST_ADDRESS");

        vm.startBroadcast(pk);

        address factory = _deployArtifact("UniswapV3Factory.sol:UniswapV3Factory", "");
        MinimalPositionDescriptor descriptor = new MinimalPositionDescriptor("MST Swap V3 Position");
        address positionManager = _deployArtifact(
            "NonfungiblePositionManager.sol:NonfungiblePositionManager",
            abi.encode(factory, wmst, address(descriptor))
        );
        address swapRouter =
            _deployArtifact("SwapRouter.sol:SwapRouter", abi.encode(factory, wmst));
        address quoterV2 =
            _deployArtifact("QuoterV2.sol:QuoterV2", abi.encode(factory, wmst));

        console.log("WMST:", wmst);
        console.log("UniswapV3Factory:", factory);
        console.log("MinimalPositionDescriptor:", address(descriptor));
        console.log("NonfungiblePositionManager:", positionManager);
        console.log("SwapRouter:", swapRouter);
        console.log("QuoterV2:", quoterV2);

        vm.stopBroadcast();
    }

    function _deployArtifact(string memory artifact, bytes memory constructorArgs) internal returns (address deployed) {
        bytes memory bytecode = abi.encodePacked(vm.getCode(artifact), constructorArgs);
        require(bytecode.length > constructorArgs.length, string.concat("missing artifact: ", artifact));

        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }

        require(deployed != address(0), string.concat("deploy failed: ", artifact));
    }
}
