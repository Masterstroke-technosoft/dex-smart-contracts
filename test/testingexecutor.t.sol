// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/testingexecutor.sol";
import "../src/WMST.sol";
import "../src/LPStateStorage.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {TickMathHelper} from "./utils/TickMathHelper.sol";

contract TestingExecutorTest is Test {
    TestingExecutor public executor;
    WMST public wmst;
    IERC20 public usdc;
    LPStateStorage public lpStateStorage;

    address public user;
    address public deployer;

    uint256 public priceMultiplier;
    uint160 public initialSqrtPriceX96;
    uint24 public constant POOL_FEE = 3000;
    int24 public initialTickLower;
    int24 public initialTickUpper;

    function setUp() public {
        uint256 forkId = vm.createFork(vm.envString("RPC_URL"));
        vm.selectFork(forkId);

        address wmstAddr = vm.envAddress("WMST_ADDRESS");
        address usdcAddr = vm.envAddress("USDC_ADDRESS");
        address factory = vm.envAddress("V3_FACTORY_ADDRESS");
        address positionManager = vm.envAddress("POSITION_MANAGER_ADDRESS");
        address swapRouter = vm.envAddress("SWAP_ROUTER_ADDRESS");
        address quoter = vm.envOr("QUOTER_V2_ADDRESS", vm.envOr("QUOTER_ADDRESS", address(0)));
        address lpStateStorageAddr = vm.envAddress("LP_STATE_STORAGE_ADDRESS");

        wmst = WMST(payable(wmstAddr));
        usdc = IERC20(usdcAddr);
        lpStateStorage = LPStateStorage(lpStateStorageAddr);

        user = vm.envOr("TEST_USER", vm.envOr("DEPLOYER", address(0)));
        deployer = vm.envAddress("DEPLOYER");
        priceMultiplier = vm.envOr("TEST_PRICE_MULTIPLIER", uint256(20)); // defaults to 20
        initialSqrtPriceX96 = TickMathHelper.calculateSqrtPriceX96(
            address(wmst),
            address(usdc),
            priceMultiplier,
            address(wmst)
        );

        (initialTickLower, initialTickUpper) = TickMathHelper.getActiveTickRange(
            factory,
            address(wmst),
            address(usdc),
            POOL_FEE,
            initialSqrtPriceX96,
            60
        );

        vm.deal(user, 1000 ether);

        executor = new TestingExecutor(
            factory,
            positionManager,
            swapRouter,
            quoter,
            wmstAddr,
            usdcAddr,
            lpStateStorageAddr
        );

        // Ownership transfer is required to let Executor update state
        vm.prank(lpStateStorage.owner());
        lpStateStorage.transferOwnership(address(executor));
    }

    function testFullOrchestratorFlow() public {
        uint256 wmstLiquidity = 10 ether;
        uint256 usdcLiquidity = 10 ether;

        vm.startPrank(user);
        wmst.deposit{value: wmstLiquidity + 5 ether}();
        wmst.approve(address(executor), type(uint256).max);
        usdc.approve(address(executor), type(uint256).max);
        vm.stopPrank();

        // 1. Initiate Pool and Mint LP Position
        vm.startPrank(user);
        TestingExecutor.PoolParams memory params = TestingExecutor.PoolParams({
            fee: POOL_FEE,
            sqrtPriceX96: initialSqrtPriceX96,
            wmstDesired: wmstLiquidity,
            usdcDesired: usdcLiquidity,
            tickLower: initialTickLower,
            tickUpper: initialTickUpper
        });
        (
            address pool,
            uint256 tokenId,
            uint128 liquidity,
            uint256 amount0,
            uint256 amount1
        ) = executor.initiatePoolAndLiquidity(params);
        vm.stopPrank();

        assertNotEq(pool, address(0), "Pool not created");
        assertEq(executor.activeTokenId(), tokenId, "tokenId mismatch");
        assertGt(liquidity, 0, "liquidity is 0");
        assertGt(amount0, 0, "amount0 is 0");
        assertGt(amount1, 0, "amount1 is 0");
        assertEq(lpStateStorage.poolAddress(), pool, "storage pool mismatch");

        // 2. Perform Swap and Compare with Quote
        uint256 swapAmount = 0.5 ether;
        uint256 expectedOut = executor.quoteSwapWmstForUsdc(swapAmount, POOL_FEE);
        
        vm.startPrank(user);
        uint256 usdcBefore = usdc.balanceOf(user);
        
        // i2 - Production Security fix: apply 0.5% slippage tolerance
        uint256 minAmountOut = (expectedOut * 9950) / 10000;
        uint256 actualOut = executor.swapWmstForUsdc(swapAmount, minAmountOut, POOL_FEE);
        uint256 usdcAfter = usdc.balanceOf(user);
        vm.stopPrank();

        assertEq(usdcAfter - usdcBefore, actualOut, "balance delta mismatch");
        assertEq(actualOut, expectedOut, "quote mismatch");

        // 3. Increase concentrated liquidity
        uint256 extraWmst = 1 ether;
        uint256 extraUsdc = 1 ether;

        vm.startPrank(user);
        (uint128 liquidityAdded, , ) = executor.increaseActiveLiquidity(
            extraWmst,
            extraUsdc
        );
        vm.stopPrank();

        assertGt(liquidityAdded, 0, "liquidityAdded is 0");

        // 4. Decrease liquidity and collect fees
        uint128 currentLiquidity = uint128(lpStateStorage.lpLiquidity());
        uint128 halfLiquidity = currentLiquidity / 2;

        vm.startPrank(user);
        executor.decreaseActiveLiquidity(halfLiquidity);
        (uint256 collected0, uint256 collected1) = executor.collectActiveFees();
        vm.stopPrank();

        assertEq(lpStateStorage.lpLiquidity(), uint256(currentLiquidity - halfLiquidity), "liquidity decrement mismatch");
        assertGt(collected0 + collected1, 0, "fees not collected");
    }
}
