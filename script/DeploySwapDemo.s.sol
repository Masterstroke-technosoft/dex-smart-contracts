// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {INonfungiblePositionManager} from "v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {WMST} from "../src/WMST.sol";
import {LPStateStorage} from "../src/LPStateStorage.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Uses an on-chain USDC token to seed a WMST/USDC V3 pool on MST testnet.
contract DeploySwapDemo is Script {
    struct SwapDemoDeployment {
        address pool;
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0;
        uint256 amount1;
        address lpStateStorage;
    }

    uint160 internal constant SQRT_PRICE_1_TO_1 = 79228162514264337593543950336;
    uint24 internal constant FEE = 3000;
    int24 internal constant TICK_LOWER = -887220;
    int24 internal constant TICK_UPPER = 887220;
    uint256 internal constant DEFAULT_WMST_DEPOSIT = 0.01 ether;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address wmstAddress = vm.envAddress("WMST_ADDRESS");
        address positionManagerAddress = vm.envAddress("POSITION_MANAGER_ADDRESS");
        address usdcAddress = vm.envAddress("USDC_ADDRESS");
        address deployer = vm.addr(pk);

        require(wmstAddress != address(0), "WMST_ADDRESS required");
        require(positionManagerAddress != address(0), "POSITION_MANAGER_ADDRESS required");
        require(usdcAddress != address(0), "USDC_ADDRESS required");

        vm.startBroadcast(pk);

        deployDemo(
            wmstAddress,
            positionManagerAddress,
            usdcAddress,
            deployer,
            DEFAULT_WMST_DEPOSIT,
            10 * 1e6
        );

        vm.stopBroadcast();
    }

    function deployDemo(
        address wmstAddress,
        address positionManagerAddress,
        address usdcAddress,
        address deployer,
        uint256 wmstLiquidity,
        uint256 usdcLiquidity
    ) public payable returns (SwapDemoDeployment memory deployment) {
        require(wmstAddress != address(0), "WMST_ADDRESS required");
        require(positionManagerAddress != address(0), "POSITION_MANAGER_ADDRESS required");
        require(usdcAddress != address(0), "USDC_ADDRESS required");
        require(deployer != address(0), "deployer required");

        WMST wmst = WMST(payable(wmstAddress));
        IERC20 usdc = IERC20(usdcAddress);
        INonfungiblePositionManager manager = INonfungiblePositionManager(positionManagerAddress);

        console.log("Deployer:", deployer);
        console.log("WMST balance (wei):", wmst.balanceOf(deployer));
        uint256 usdcBal = usdc.balanceOf(deployer);
        console.log("USDC balance (whole units):", usdcBal / 1e6);
        console.log("USDC balance (micro units):", usdcBal % 1e6);

        wmst.approve(positionManagerAddress, type(uint256).max);
        usdc.approve(positionManagerAddress, type(uint256).max);

        deployment = _mintAndLogPosition(
            manager,
            wmstAddress,
            usdcAddress,
            deployer,
            wmstLiquidity,
            usdcLiquidity
        );
    }

    function _mintAndLogPosition(
        INonfungiblePositionManager manager,
        address wmstAddress,
        address usdcAddress,
        address deployer,
        uint256 wmstLiquidity,
        uint256 usdcLiquidity
    ) internal returns (SwapDemoDeployment memory deployment) {
        INonfungiblePositionManager.MintParams memory params =
            _buildMintParams(wmstAddress, usdcAddress, deployer, wmstLiquidity, usdcLiquidity);

        deployment.pool = manager.createAndInitializePoolIfNecessary(params.token0, params.token1, FEE, SQRT_PRICE_1_TO_1);
        (deployment.tokenId, deployment.liquidity, deployment.amount0, deployment.amount1) = manager.mint(params);

        console.log("USDC_ADDRESS=", usdcAddress);
        console.log("POOL_ADDRESS=", deployment.pool);
        console.log("LP_TOKEN_ID=", deployment.tokenId);
        console.log("LP_LIQUIDITY=", uint256(deployment.liquidity));
        console.log("LP_AMOUNT0=", deployment.amount0);
        console.log("LP_AMOUNT1=", deployment.amount1);

        // Always deploy a fresh LPStateStorage and update it so no env var is required.
        LPStateStorage storageContract = new LPStateStorage();
        deployment.lpStateStorage = address(storageContract);
        console.log("LPStateStorage deployed at:", deployment.lpStateStorage);
        storageContract.setValues(
            deployment.pool,
            deployment.tokenId,
            uint256(deployment.liquidity),
            deployment.amount0,
            deployment.amount1
        );
        console.log("LPStateStorage updated at:", deployment.lpStateStorage);
    }

    function _buildMintParams(
        address wmstAddress,
        address usdcAddress,
        address deployer,
        uint256 wmstLiquidity,
        uint256 usdcLiquidity
    ) internal view returns (INonfungiblePositionManager.MintParams memory params) {
        params.token0 = wmstAddress < usdcAddress ? wmstAddress : usdcAddress;
        params.token1 = wmstAddress < usdcAddress ? usdcAddress : wmstAddress;
        params.fee = FEE;
        params.tickLower = TICK_LOWER;
        params.tickUpper = TICK_UPPER;
        params.amount0Desired = params.token0 == wmstAddress ? wmstLiquidity : usdcLiquidity;
        params.amount1Desired = params.token1 == wmstAddress ? wmstLiquidity : usdcLiquidity;
        params.recipient = deployer;
        params.deadline = block.timestamp + 20 minutes;
    }
}
