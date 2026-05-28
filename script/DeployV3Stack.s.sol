// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {MinimalPositionDescriptor} from "../src/MinimalPositionDescriptor.sol";
import {IUniswapV3Factory} from "v3-core/interfaces/IUniswapV3Factory.sol";
import {INonfungiblePositionManager} from "v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";
import {IQuoterV2} from "v3-periphery/interfaces/IQuoterV2.sol";

/// @notice Deploys the official Uniswap V3 factory and periphery around an existing WMST.
/// @dev Set WMST_ADDRESS in .env to the address printed by DeployMST.s.sol.
contract DeployV3Stack is Script {
    struct V3Stack {
        address factory;
        address descriptor;
        address positionManager;
        address swapRouter;
        address quoterV2;
        address wmst;
    }

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address wmst = vm.envAddress("WMST_ADDRESS");

        vm.startBroadcast(pk);

        V3Stack memory stack = deploy(wmst);
        _logStack(stack);

        vm.stopBroadcast();
    }

    function deploy(address wmst) public returns (V3Stack memory stack) {
        require(wmst != address(0), "WMST required");

        stack.wmst = wmst;
        stack.factory = _deployFactory();

        MinimalPositionDescriptor descriptor = new MinimalPositionDescriptor("MST Swap V3 Position");
        stack.descriptor = address(descriptor);

        stack.positionManager = _deployPositionManager(stack.factory, wmst, stack.descriptor);
        stack.swapRouter = _deploySwapRouter(stack.factory, wmst);
        stack.quoterV2 = _deployQuoterV2(stack.factory, wmst);
    }

    function _logStack(V3Stack memory stack) internal pure {
        console.log("UniswapV3Factory:", stack.factory);
        console.log("MinimalPositionDescriptor:", stack.descriptor);
        console.log("NonfungiblePositionManager:", stack.positionManager);
        console.log("SwapRouter:", stack.swapRouter);
        console.log("QuoterV2:", stack.quoterV2);
        console.log("WMST:", stack.wmst);
    }

    function _deployFactory() internal returns (address factory) {
        bytes memory factoryCode = vm.getCode("UniswapV3FactoryImporter.sol:UniswapV3FactoryImporter");
        assembly {
            factory := create(0, add(factoryCode, 0x20), mload(factoryCode))
        }
        require(factory != address(0), "Factory deployment failed");
    }

    function _deployPositionManager(address factory, address wmst, address descriptor) internal returns (address positionManager) {
        bytes memory npmCode = vm.getCode("NonfungiblePositionManagerImporter.sol:NonfungiblePositionManagerImporter");
        bytes memory npmBytecode = abi.encodePacked(npmCode, abi.encode(factory, wmst, descriptor));
        assembly {
            positionManager := create(0, add(npmBytecode, 0x20), mload(npmBytecode))
        }
        require(positionManager != address(0), "PositionManager deployment failed");
    }

    function _deploySwapRouter(address factory, address wmst) internal returns (address swapRouter) {
        bytes memory routerCode = vm.getCode("SwapRouterImporter.sol:SwapRouterImporter");
        bytes memory routerBytecode = abi.encodePacked(routerCode, abi.encode(factory, wmst));
        assembly {
            swapRouter := create(0, add(routerBytecode, 0x20), mload(routerBytecode))
        }
        require(swapRouter != address(0), "SwapRouter deployment failed");
    }

    function _deployQuoterV2(address factory, address wmst) internal returns (address quoterV2) {
        bytes memory quoterCode = vm.getCode("QuoterV2Importer.sol:QuoterV2Importer");
        bytes memory quoterBytecode = abi.encodePacked(quoterCode, abi.encode(factory, wmst));
        assembly {
            quoterV2 := create(0, add(quoterBytecode, 0x20), mload(quoterBytecode))
        }
        require(quoterV2 != address(0), "QuoterV2 deployment failed");
    }
}
