// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {Script, console2} from "forge-std/Script.sol";
import {RapidEXChains} from "./RapidEXChains.sol";
import {RapidEXFeeRouter} from "../src/RapidEXFeeRouter.sol";
import {MinimalPositionDescriptor} from "../src/MinimalPositionDescriptor.sol";

interface IRapiddexV3Factory {
    function owner() external view returns (address);
    function setOwner(address) external;
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address);
    function feeAmountTickSpacing(uint24 fee) external view returns (int24);
}

contract DeployRapidEX is Script {
    uint256 private constant DEFAULT_FEE_BPS = 25;

    struct Deployed {
        address factory;
        address descriptor;
        address positionManager;
        address swapRouter;
        address quoterV2;
        address feeRouter;
    }

    function run() external {
        RapidEXChains.ChainConfig memory chain = RapidEXChains.config(block.chainid);

        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");
        uint256 feeBps = vm.envOr("PROTOCOL_FEE_BPS", DEFAULT_FEE_BPS);

        uint64 nonce = uint64(vm.getNonce(deployer));
        uint256 expected = vm.envOr("EXPECTED_NONCE", type(uint256).max);
        if (expected != type(uint256).max) {
            require(
                nonce == uint64(expected),
                "DeployRapidEX: deployer nonce differs from EXPECTED_NONCE; addresses would diverge from other chains"
            );
        }

        console2.log("Chain      :", chain.name);
        console2.log("Chain ID   :", chain.chainId);
        console2.log("Deployer   :", deployer);
        console2.log("Nonce      :", nonce);
        console2.log("WrappedNat :", chain.wrappedNative);
        console2.log("Fee        :", feeBps, "bps ->", feeRecipient);

        vm.startBroadcast(pk);

        Deployed memory d;

        d.factory = deployCode("RapiddexV3Factory.sol:RapiddexV3Factory");

        d.descriptor = address(
            new MinimalPositionDescriptor("RapidEX V3 liquidity position", deployer)
        );

        d.positionManager = deployCode(
            "NonfungiblePositionManager.sol:NonfungiblePositionManager",
            abi.encode(d.factory, chain.wrappedNative, d.descriptor)
        );

        d.swapRouter = deployCode(
            "SwapRouter.sol:SwapRouter",
            abi.encode(d.factory, chain.wrappedNative)
        );

        d.quoterV2 = deployCode(
            "QuoterV2.sol:QuoterV2",
            abi.encode(d.factory, chain.wrappedNative)
        );

        d.feeRouter = address(new RapidEXFeeRouter(d.swapRouter, feeBps, feeRecipient, deployer));

        vm.stopBroadcast();

        _report(chain, d, deployer, feeBps, feeRecipient);
        _write(chain, d, deployer, feeBps, feeRecipient);
    }

    function _report(
        RapidEXChains.ChainConfig memory chain,
        Deployed memory d,
        address deployer,
        uint256 feeBps,
        address feeRecipient
    ) private view {
        console2.log("");
        console2.log("=== Deployed on", chain.name, "===");
        console2.log("Factory          :", d.factory);
        console2.log("Descriptor       :", d.descriptor);
        console2.log("PositionManager  :", d.positionManager);
        console2.log("SwapRouter       :", d.swapRouter);
        console2.log("QuoterV2         :", d.quoterV2);
        console2.log("FeeRouter        :", d.feeRouter);
        console2.log("");
        console2.log("STILL TO DO:");
        console2.log(" - factory, descriptor and FeeRouter are all owned by:", deployer);
        console2.log("   RapidEX is single-admin by design. That one key IS the access");
        console2.log("   control model, so confirm it is the intended long-term admin.");
        console2.log(" - if the admin should differ from the deploy key, hand over NOW:");
        console2.log("     descriptor/FeeRouter: transferOwnership then acceptOwnership");
        console2.log("     factory.setOwner(<admin>) is ONE-STEP - a mistyped address is");
        console2.log("     unrecoverable and forfeits the protocol fee switch permanently");
        console2.log(" - create pools; they start with ZERO liquidity until seeded");
        console2.log(" - verify fee:", feeBps, "bps ->", feeRecipient);
    }

    function _write(
        RapidEXChains.ChainConfig memory chain,
        Deployed memory d,
        address deployer,
        uint256 feeBps,
        address feeRecipient
    ) private {
        string memory o = "deployment";
        vm.serializeUint(o, "chainId", chain.chainId);
        vm.serializeString(o, "name", chain.name);
        vm.serializeAddress(o, "deployer", deployer);
        vm.serializeAddress(o, "wrappedNative", chain.wrappedNative);
        vm.serializeAddress(o, "factory", d.factory);
        vm.serializeAddress(o, "positionDescriptor", d.descriptor);
        vm.serializeAddress(o, "positionManager", d.positionManager);
        vm.serializeAddress(o, "swapRouter", d.swapRouter);
        vm.serializeAddress(o, "quoterV2", d.quoterV2);
        vm.serializeUint(o, "protocolFeeBps", feeBps);
        vm.serializeAddress(o, "protocolFeeRecipient", feeRecipient);
        string memory json = vm.serializeAddress(o, "feeRouter", d.feeRouter);

        vm.writeJson(json, string.concat("deployments/", chain.slug, ".json"));
        console2.log("Wrote deployments/", chain.slug, ".json");
    }
}
