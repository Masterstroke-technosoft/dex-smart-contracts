// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {Script, console2} from "forge-std/Script.sol";
import {RapidEXChains} from "./RapidEXChains.sol";
import {WMSTC} from "../src/WMSTC.sol";
import {RapidEXFeeRouter} from "../src/RapidEXFeeRouter.sol";

interface IRapiddexV3Factory {
    function owner() external view returns (address);
    function feeAmountTickSpacing(uint24 fee) external view returns (int24);
}

interface IPositionDescriptor {
    function metadataFrozen() external view returns (bool);
}

interface IPeripheryImmutableState {
    function factory() external view returns (address);
    function WETH9() external view returns (address);
}

contract MigrateWmstc is Script {
    uint256 private constant DEFAULT_FEE_BPS = 25;

    struct Deployed {
        address wmstc;
        address positionManager;
        address swapRouter;
        address quoterV2;
        address feeRouter;
    }

    function run() external {
        RapidEXChains.ChainConfig memory chain = RapidEXChains.config(block.chainid);

        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        address factory = vm.envAddress("V3_FACTORY");
        address descriptor = vm.envAddress("POSITION_DESCRIPTOR");
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");
        uint256 feeBps = vm.envOr("PROTOCOL_FEE_BPS", DEFAULT_FEE_BPS);

        address oldWmstc = chain.wrappedNative;

        require(factory.code.length > 0, "MigrateWmstc: V3_FACTORY has no code");
        require(descriptor.code.length > 0, "MigrateWmstc: POSITION_DESCRIPTOR has no code");
        require(
            IRapiddexV3Factory(factory).feeAmountTickSpacing(3000) == 60,
            "MigrateWmstc: V3_FACTORY does not behave like a Rapiddex V3 factory"
        );
        IPositionDescriptor(descriptor).metadataFrozen();

        console2.log("Chain            :", chain.name);
        console2.log("Deployer         :", deployer);
        console2.log("Factory (REUSED) :", factory);
        console2.log("Descriptor(REUSE):", descriptor);
        console2.log("Old WMSTC        :", oldWmstc);
        console2.log("");

        vm.startBroadcast(pk);

        Deployed memory d;

        d.wmstc = address(new WMSTC());

        d.positionManager = deployCode(
            "NonfungiblePositionManager.sol:NonfungiblePositionManager",
            abi.encode(factory, d.wmstc, descriptor)
        );
        d.swapRouter = deployCode("SwapRouter.sol:SwapRouter", abi.encode(factory, d.wmstc));
        d.quoterV2 = deployCode("QuoterV2.sol:QuoterV2", abi.encode(factory, d.wmstc));

        d.feeRouter = address(new RapidEXFeeRouter(d.swapRouter, feeBps, feeRecipient, deployer));

        vm.stopBroadcast();

        _verify(d, factory, oldWmstc);
        _report(d, factory, descriptor, oldWmstc, deployer, feeBps, feeRecipient);
    }

    function _verify(Deployed memory d, address factory, address oldWmstc) private view {
        address[3] memory periphery = [d.positionManager, d.swapRouter, d.quoterV2];

        for (uint256 i = 0; i < periphery.length; i++) {
            require(
                IPeripheryImmutableState(periphery[i]).factory() == factory,
                "MigrateWmstc: periphery points at the wrong factory"
            );
            require(
                IPeripheryImmutableState(periphery[i]).WETH9() == d.wmstc,
                "MigrateWmstc: periphery points at the wrong WMSTC"
            );
            require(
                IPeripheryImmutableState(periphery[i]).WETH9() != oldWmstc,
                "MigrateWmstc: periphery still points at the OLD WMSTC"
            );
        }

        require(d.wmstc != oldWmstc, "MigrateWmstc: new WMSTC equals the old one");
        require(WMSTC(payable(d.wmstc)).totalSupply() == 0, "MigrateWmstc: fresh WMSTC should start empty");
    }

    function _report(
        Deployed memory d,
        address factory,
        address descriptor,
        address oldWmstc,
        address deployer,
        uint256 feeBps,
        address feeRecipient
    ) private view {
        console2.log("=== NEW (update deployments.json + addresses.json) ===");
        console2.log("WMSTC            :", d.wmstc);
        console2.log("PositionManager  :", d.positionManager);
        console2.log("SwapRouter       :", d.swapRouter);
        console2.log("QuoterV2         :", d.quoterV2);
        console2.log("FeeRouter        :", d.feeRouter);
        console2.log("");
        console2.log("=== UNCHANGED (reused) ===");
        console2.log("Factory          :", factory);
        console2.log("Descriptor       :", descriptor);
        console2.log("");
        console2.log("STILL TO DO:");
        console2.log(" - move these to doNotUse in deployments.json:");
        console2.log("     old WMSTC    :", oldWmstc);
        console2.log("   plus the old PositionManager, SwapRouter and QuoterV2");
        console2.log(" - update next-frontend/src/config/addresses.json, then run its");
        console2.log("   deployment-parity test - it fails until both files agree");
        console2.log(" - create and seed pools; the new WMSTC has ZERO supply, so wrap");
        console2.log("   MSTC through the NEW wrapper before seeding");
        console2.log(" - LP positions in the OLD position manager do NOT migrate; exit");
        console2.log("   them there. Old WMSTC still allows withdraw() to native MSTC.");
        console2.log(" - single-admin owner of descriptor + FeeRouter:", deployer);
        console2.log(" - verify fee:", feeBps, "bps ->", feeRecipient);
    }
}
