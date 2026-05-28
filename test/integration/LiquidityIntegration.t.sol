// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {INonfungiblePositionManager} from "v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {WMST} from "../../src/WMST.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";

contract LiquidityIntegrationTest is Test {
    address public positionManager;
    address public wmst;
    address public usdc;
    address public pool;
    address public deployer;
    address public swapRouter;
    uint256 public lpTokenId;

    function setUp() public {
        string memory rpcUrl = vm.envString("RPC_URL");
        uint256 forkId = vm.createFork(rpcUrl);
        vm.selectFork(forkId);

        positionManager = vm.envAddress("POSITION_MANAGER_ADDRESS");
        wmst = vm.envAddress("WMST_ADDRESS");
        usdc = vm.envAddress("USDC_ADDRESS");
        deployer = vm.envAddress("DEPLOYER");
        swapRouter = vm.envAddress("SWAP_ROUTER_ADDRESS");

        require(positionManager != address(0), "POSITION_MANAGER_ADDRESS missing");
        require(wmst != address(0), "WMST_ADDRESS missing");
        require(usdc != address(0), "USDC_ADDRESS missing");
        require(deployer != address(0), "DEPLOYER missing");
        require(swapRouter != address(0), "SWAP_ROUTER_ADDRESS missing");
    }

    function testFullMintFlowOnFork() public {
        vm.startPrank(deployer);

        vm.deal(deployer, 2 ether);

        WMST(payable(wmst)).deposit{value: 1 ether}();

        IERC20(wmst).approve(positionManager, type(uint256).max);
        IERC20(usdc).approve(positionManager, type(uint256).max);

        address token0 = wmst < usdc ? wmst : usdc;
        address token1 = wmst < usdc ? usdc : wmst;

        address poolAddr = INonfungiblePositionManager(positionManager)
            .createAndInitializePoolIfNecessary(
                token0,
                token1,
                3000,
                79228162514264337593543950336
            );

        assertTrue(poolAddr != address(0), "pool creation failed");

        INonfungiblePositionManager.MintParams memory params;

        params.token0 = token0;
        params.token1 = token1;
        params.fee = 3000;
        params.tickLower = -887220;
        params.tickUpper = 887220;
        params.amount0Desired = 1 ether;
        params.amount1Desired = 1 ether;
        params.amount0Min = 0;
        params.amount1Min = 0;
        params.recipient = deployer;
        params.deadline = block.timestamp + 1 hours;

        (
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        ) = INonfungiblePositionManager(positionManager).mint(params);

        lpTokenId = tokenId;

        assertGt(tokenId, 0, "tokenId should be returned");
        assertGt(liquidity, 0, "liquidity should be > 0");
        assertGt(amount0, 0, "amount0 should be > 0");
        assertGt(amount1, 0, "amount1 should be > 0");

        (
            ,
            ,
            address posToken0,
            address posToken1,
            uint24 posFee,
            int24 posTickLower,
            int24 posTickUpper,
            uint128 posLiquidity,
            ,
            ,
            ,
        ) = INonfungiblePositionManager(positionManager).positions(lpTokenId);

        assertEq(posToken0, token0, "token0 mismatch");
        assertEq(posToken1, token1, "token1 mismatch");
        assertEq(posFee, 3000, "fee mismatch");
        assertEq(posTickLower, -887220, "tick lower mismatch");
        assertEq(posTickUpper, 887220, "tick upper mismatch");
        assertGt(posLiquidity, 0, "position liquidity must be > 0");

        address owner = INonfungiblePositionManager(positionManager).ownerOf(lpTokenId);
        assertEq(owner, deployer, "owner mismatch");

        // perform a small swap via SwapRouter to generate fees
        uint256 swapAmountIn = 100000000000000000; // 0.1 WMST
        // ensure deployer has WMST for the swap (mint consumed initial deposit)
        WMST(payable(wmst)).deposit{value: swapAmountIn}();
        IERC20(wmst).approve(swapRouter, swapAmountIn);

        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: wmst,
            tokenOut: usdc,
            fee: 3000,
            recipient: deployer,
            deadline: block.timestamp + 1 hours,
            amountIn: swapAmountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        uint256 amountOut = ISwapRouter(swapRouter).exactInputSingle(swapParams);
        assertGt(amountOut, 0, "swap should return amountOut > 0");

        // decrease half of the liquidity
        INonfungiblePositionManager.DecreaseLiquidityParams memory decParams;
        decParams.tokenId = lpTokenId;
        decParams.liquidity = posLiquidity / 2;
        decParams.amount0Min = 0;
        decParams.amount1Min = 0;
        decParams.deadline = block.timestamp + 1 hours;

        (uint256 decAmount0, uint256 decAmount1) = INonfungiblePositionManager(positionManager).decreaseLiquidity(decParams);
        assertGt(decAmount0, 0, "decrease returned amount0");
        assertGt(decAmount1, 0, "decrease returned amount1");

        // collect fees
        INonfungiblePositionManager.CollectParams memory collectParams;
        collectParams.tokenId = lpTokenId;
        collectParams.recipient = deployer;
        collectParams.amount0Max = type(uint128).max;
        collectParams.amount1Max = type(uint128).max;
        INonfungiblePositionManager(positionManager).collect(collectParams);

        // verify remaining liquidity is half
        (, , , , , , , uint128 remainingLiquidity, , , , ) = INonfungiblePositionManager(positionManager).positions(lpTokenId);
        assertApproxEqAbs(remainingLiquidity, posLiquidity / 2, 1, "remaining liquidity should be approx half");

        vm.stopPrank();
    }
}
