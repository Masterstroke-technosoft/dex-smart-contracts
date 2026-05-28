// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/WMST.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV3Factory} from "v3-core/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {INonfungiblePositionManager} from "v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";
import {IQuoterV2} from "v3-periphery/interfaces/IQuoterV2.sol";
import {IPeripheryImmutableState} from "v3-periphery/interfaces/IPeripheryImmutableState.sol";
import {TickMathHelper} from "./utils/TickMathHelper.sol";

contract TestingTest is Test {
    WMST public wmst;
    IERC20 public usdc;

    address public factory;
    address public positionManager;
    address public swapRouter;
    address public quoter;

    address public pool;
    uint256 public tokenId;
    uint128 public liquidity;
    uint256 public amount0Used;
    uint256 public amount1Used;

    uint256 public priceMultiplier;
    uint160 public initialSqrtPriceX96;
    uint24 public constant POOL_FEE = 3000;
    int24 public initialTickLower;
    int24 public initialTickUpper;

    uint256 public constant DEFAULT_NATIVE_TOP_UP = 100 ether;
    uint256 public constant DEFAULT_INITIAL_WMST_LIQUIDITY = 100 ether;
    uint256 public constant DEFAULT_INITIAL_USDC_LIQUIDITY = 100 * 1e6;
    uint256 public constant DEFAULT_SWAP_WMST_AMOUNT = 1 ether;
    uint256 public constant DEFAULT_INCREASE_WMST_AMOUNT = 10 ether;
    uint256 public constant DEFAULT_INCREASE_USDC_AMOUNT = 10 * 1e6;

    address public user;
    uint256 public nativeTopUp;
    uint256 public initialWmstLiquidity;
    uint256 public initialUsdcLiquidity;
    uint256 public swapWmstAmount;
    uint256 public increaseWmstAmount;
    uint256 public increaseUsdcAmount;

    function setUp() public {
        console.log("\n========== SETUP ==========");

        uint256 forkId = vm.createFork(vm.envString("RPC_URL"));
        vm.selectFork(forkId);

        _loadDynamicConfig();

        wmst = WMST(payable(vm.envAddress("WMST_ADDRESS")));
        usdc = IERC20(vm.envAddress("USDC_ADDRESS"));
        positionManager = vm.envAddress("POSITION_MANAGER_ADDRESS");
        swapRouter = vm.envAddress("SWAP_ROUTER_ADDRESS");
        quoter = vm.envOr("QUOTER_V2_ADDRESS", vm.envOr("QUOTER_ADDRESS", address(0)));
        factory = vm.envOr("V3_FACTORY_ADDRESS", INonfungiblePositionManager(positionManager).factory());

        // Calculate dynamic initial ticks and sqrtPriceX96 based on priceMultiplier and active pool state
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
            60 // 3000 fee tier spacing is 60
        );

        console.log("Calculated Dynamic Pricing:");
        console.log("  priceMultiplier:", priceMultiplier);
        console.log("  initialSqrtPriceX96:", initialSqrtPriceX96);
        console.log("  initialTickLower:", initialTickLower);
        console.log("  initialTickUpper:", initialTickUpper);

        require(user != address(0), "TEST_USER or DEPLOYER required");
        _requireCode(address(wmst), "WMST_ADDRESS");
        _requireCode(address(usdc), "USDC_ADDRESS");
        _requireCode(factory, "V3_FACTORY_ADDRESS");
        _requireCode(positionManager, "POSITION_MANAGER_ADDRESS");
        _requireCode(swapRouter, "SWAP_ROUTER_ADDRESS");
        _requireCode(quoter, "QUOTER_V2_ADDRESS");

        if (nativeTopUp > 0) {
            vm.deal(user, nativeTopUp);
        }

        _prepareUserBalances();

        console.log("Factory:", factory);
        console.log("PositionManager:", positionManager);
        console.log("SwapRouter:", swapRouter);
        console.log("Quoter:", quoter);
        console.log("WMST:", address(wmst));
        console.log("USDC:", address(usdc));
        console.log("[PASS] Setup complete");
    }

    function _loadDynamicConfig() internal {
        priceMultiplier = vm.envOr("TEST_PRICE_MULTIPLIER", uint256(20)); // defaults to 20
        user = vm.envOr("TEST_USER", vm.envOr("DEPLOYER", address(0)));
        nativeTopUp = vm.envOr("TEST_NATIVE_TOP_UP", DEFAULT_NATIVE_TOP_UP);
        initialWmstLiquidity = vm.envOr("TEST_INITIAL_WMST_LIQUIDITY", DEFAULT_INITIAL_WMST_LIQUIDITY);
        initialUsdcLiquidity = vm.envOr("TEST_INITIAL_USDC_LIQUIDITY", DEFAULT_INITIAL_USDC_LIQUIDITY);
        swapWmstAmount = vm.envOr("TEST_SWAP_WMST_AMOUNT", DEFAULT_SWAP_WMST_AMOUNT);
        increaseWmstAmount = vm.envOr("TEST_INCREASE_WMST_AMOUNT", DEFAULT_INCREASE_WMST_AMOUNT);
        increaseUsdcAmount = vm.envOr("TEST_INCREASE_USDC_AMOUNT", DEFAULT_INCREASE_USDC_AMOUNT);

        console.log("Configured user:", user);
        console.log("Configured native top-up:", nativeTopUp);
        console.log("Configured initial WMST liquidity:", initialWmstLiquidity);
        console.log("Configured initial USDC liquidity:", initialUsdcLiquidity);
        console.log("Configured WMST swap amount:", swapWmstAmount);
    }

    function _requireCode(address target, string memory label) internal view {
        require(target != address(0), string.concat(label, " missing"));
        require(target.code.length > 0, string.concat(label, " has no code"));
    }

    function _prepareUserBalances() internal {
        uint256 requiredWmst = initialWmstLiquidity + increaseWmstAmount + swapWmstAmount;
        uint256 requiredUsdc = initialUsdcLiquidity + increaseUsdcAmount;

        _fundWmstIfNeeded(requiredWmst);
        require(
            usdc.balanceOf(user) >= requiredUsdc,
            "USDC balance too low on fork"
        );
    }

    function _fundWmstIfNeeded(uint256 requiredWmst) internal {
        uint256 currentWmst = IERC20(address(wmst)).balanceOf(user);
        if (currentWmst >= requiredWmst) return;

        uint256 missingWmst = requiredWmst - currentWmst;
        if (user.balance < missingWmst && nativeTopUp > 0) {
            vm.deal(user, missingWmst);
        }

        require(user.balance >= missingWmst, "native balance too low to wrap");

        vm.prank(user);
        wmst.deposit{value: missingWmst}();
    }

    function testFullFlow() public {
        console.log("\n========== STEP 1: VERIFY TESTNET TOKENS ==========");
        verifyTestnetTokens();

        console.log("\n========== STEP 2: CREATE OR FETCH POOL ==========");
        createPool();

        console.log("\n========== STEP 3: FETCH POOL ==========");
        fetchPool();

        console.log("\n========== STEP 4: VERIFY POOL INITIALIZED ==========");
        initializePool();

        console.log("\n========== STEP 5: ADD LIQUIDITY ==========");
        addLiquidity();

        console.log("\n========== STEP 6: VERIFY POSITION NFT ==========");
        verifyPosition();

        console.log("\n========== STEP 7: CHECK POOL LIQUIDITY ==========");
        checkPoolLiquidity();

        console.log("\n========== STEP 8: QUOTE SWAP ==========");
        uint256 quotedAmountOut = quoteSwap();

        console.log("\n========== STEP 9: EXECUTE SWAP ==========");
        uint256 actualAmountOut = executeSwap(quotedAmountOut);

        console.log("\n========== STEP 10: COMPARE QUOTE VS ACTUAL ==========");
        compareQuoteVsActual(quotedAmountOut, actualAmountOut);

        console.log("\n========== STEP 11: INCREASE LIQUIDITY ==========");
        increaseLiquidity();

        console.log("\n========== STEP 12: REMOVE LIQUIDITY ==========");
        removeLiquidity();

        console.log("\n========== STEP 13: COLLECT FEES ==========");
        collectFees();

        console.log("\n========== STEP 14: FINAL VERIFICATION ==========");
        finalVerification();

        console.log("\n========== ALL TESTS PASSED ==========\n");
    }

    function testDeploymentAddressesConnected() public view {
        assertEq(INonfungiblePositionManager(positionManager).factory(), factory, "PM factory mismatch");
        assertEq(INonfungiblePositionManager(positionManager).WETH9(), address(wmst), "PM WMST mismatch");
        assertEq(IPeripheryImmutableState(swapRouter).factory(), factory, "Router factory mismatch");
        assertEq(IPeripheryImmutableState(swapRouter).WETH9(), address(wmst), "Router WMST mismatch");
        assertEq(IPeripheryImmutableState(quoter).factory(), factory, "Quoter factory mismatch");
        assertEq(IPeripheryImmutableState(quoter).WETH9(), address(wmst), "Quoter WMST mismatch");

        console.log("[PASS] Testnet deployment addresses are connected");
    }

    function verifyTestnetTokens() public view {
        console.log("Token0 (WMST):", address(wmst));
        console.log("Token1 (USDC):", address(usdc));
        console.log("WMST Decimals: 18");
        console.log("USDC Decimals: assumed 6");

        assertNotEq(address(wmst), address(0), "WMST address missing");
        assertNotEq(address(usdc), address(0), "USDC address missing");

        uint256 userWMSTBalance = wmst.balanceOf(user);
        uint256 userUSDCBalance = usdc.balanceOf(user);

        console.log("User WMST Balance:", userWMSTBalance);
        console.log("User USDC Balance:", userUSDCBalance);

        assertGe(userWMSTBalance, initialWmstLiquidity + swapWmstAmount, "User has insufficient WMST");
        assertGe(userUSDCBalance, initialUsdcLiquidity, "User has insufficient USDC");

        console.log("[PASS] Testnet tokens verified");
    }

    function createPool() public {
        (address token0, address token1) = _orderedTokens();

        console.log("Creating or fetching pool:");
        console.log("  Token0:", token0);
        console.log("  Token1:", token1);
        console.log("  Fee:", POOL_FEE);

        pool = INonfungiblePositionManager(positionManager).createAndInitializePoolIfNecessary(
            token0,
            token1,
            POOL_FEE,
            initialSqrtPriceX96
        );

        console.log("Pool:", pool);

        assertNotEq(pool, address(0), "pool creation failed");
        assertEq(IUniswapV3Factory(factory).getPool(token0, token1, POOL_FEE), pool, "pool mismatch in factory");

        console.log("[PASS] Pool created or fetched successfully");
    }

    function fetchPool() public view {
        (address token0, address token1) = _orderedTokens();
        address fetchedPool = IUniswapV3Factory(factory).getPool(token0, token1, POOL_FEE);
        
        console.log("Fetched pool:", fetchedPool);
        console.log("Active pool:", pool);
        
        assertEq(fetchedPool, pool, "fetched pool mismatch");
        console.log("[PASS] Pool fetched and verified");
    }

    function initializePool() public view {
        (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex,,,, bool unlocked) = IUniswapV3Pool(pool).slot0();
        
        console.log("Pool initialized:");
        console.log("  sqrtPriceX96:", sqrtPriceX96);
        console.log("  tick:", tick);
        console.log("  observationIndex:", observationIndex);
        console.log("  unlocked:", unlocked);

        assertGt(sqrtPriceX96, 0, "pool is not initialized");
        assertTrue(unlocked, "pool locked");

        console.log("[PASS] Pool initialization verified");
    }

    function addLiquidity() public {
        (address token0, address token1) = _orderedTokens();
        (uint256 amount0Desired, uint256 amount1Desired) = _amountsByTokenOrder(
            initialWmstLiquidity,
            initialUsdcLiquidity
        );

        // Track pool-level liquidity before minting
        uint128 poolLiquidityBefore = IUniswapV3Pool(pool).liquidity();

        vm.startPrank(user);
        IERC20(token0).approve(positionManager, type(uint256).max);
        IERC20(token1).approve(positionManager, type(uint256).max);

        console.log("User approved tokens");
        console.log("Minting liquidity:");
        console.log("  amount0Desired:", amount0Desired);
        console.log("  amount1Desired:", amount1Desired);
        console.log("  tickLower:", initialTickLower);
        console.log("  tickUpper:", initialTickUpper);

        (tokenId, liquidity, amount0Used, amount1Used) = INonfungiblePositionManager(positionManager).mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: POOL_FEE,
                tickLower: initialTickLower,
                tickUpper: initialTickUpper,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                recipient: user,
                deadline: block.timestamp + 1200
            })
        );
        vm.stopPrank();

        console.log("Liquidity added:");
        console.log("  tokenId:", tokenId);
        console.log("  liquidity:", liquidity);
        console.log("  amount0Used:", amount0Used);
        console.log("  amount1Used:", amount1Used);

        assertGt(tokenId, 0, "invalid tokenId");
        assertGt(liquidity, 0, "no liquidity minted");
        assertLe(amount0Used, amount0Desired, "Too much token0 used");
        assertLe(amount1Used, amount1Desired, "Too much token1 used");

        // Verify pool liquidity actually increased on mint
        uint128 poolLiquidityAfter = IUniswapV3Pool(pool).liquidity();
        assertGt(
            poolLiquidityAfter,
            poolLiquidityBefore,
            "pool liquidity did not increase on initial add"
        );

        console.log("[PASS] Liquidity added");
    }

    function verifyPosition() public view {
        (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 positionLiquidity,
            ,
            ,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        ) = INonfungiblePositionManager(positionManager).positions(tokenId);

        console.log("Position details:");
        console.log("  nonce:", nonce);
        console.log("  operator:", operator);
        console.log("  token0:", token0);
        console.log("  token1:", token1);
        console.log("  fee:", fee);
        console.log("  tickLower:", tickLower);
        console.log("  tickUpper:", tickUpper);
        console.log("  liquidity:", positionLiquidity);
        console.log("  tokensOwed0:", tokensOwed0);
        console.log("  tokensOwed1:", tokensOwed1);

        (address expectedToken0, address expectedToken1) = _orderedTokens();
        assertEq(token0, expectedToken0, "token0 mismatch");
        assertEq(token1, expectedToken1, "token1 mismatch");
        assertEq(fee, POOL_FEE, "fee mismatch");
        assertEq(tickLower, initialTickLower, "tickLower mismatch");
        assertEq(tickUpper, initialTickUpper, "tickUpper mismatch");
        assertEq(positionLiquidity, liquidity, "liquidity mismatch");
        assertEq(INonfungiblePositionManager(positionManager).ownerOf(tokenId), user, "owner mismatch");

        console.log("[PASS] Position verified");
    }

    function checkPoolLiquidity() public view {
        uint128 poolLiquidity = IUniswapV3Pool(pool).liquidity();
        
        console.log("Pool liquidity:", poolLiquidity);
        
        assertGt(poolLiquidity, 0, "pool has no liquidity");
        assertGe(poolLiquidity, liquidity, "pool liquidity below minted");

        console.log("[PASS] Pool liquidity verified");
    }

    function quoteSwap() public returns (uint256 amountOut) {
        console.log("Quoting swap:");
        console.log("  tokenIn:", address(wmst));
        console.log("  tokenOut:", address(usdc));
        console.log("  amountIn:", swapWmstAmount);

        uint160 sqrtPriceX96After;
        uint32 initializedTicksCrossed;
        uint256 gasEstimate;

        (amountOut, sqrtPriceX96After, initializedTicksCrossed, gasEstimate) = IQuoterV2(quoter).quoteExactInputSingle(
            IQuoterV2.QuoteExactInputSingleParams({
                tokenIn: address(wmst),
                tokenOut: address(usdc),
                amountIn: swapWmstAmount,
                fee: POOL_FEE,
                sqrtPriceLimitX96: 0
            })
        );

        console.log("Quoted output:");
        console.log("  amountOut:", amountOut);
        console.log("  sqrtPriceX96After:", sqrtPriceX96After);
        console.log("  initializedTicksCrossed:", initializedTicksCrossed);
        console.log("  gasEstimate:", gasEstimate);

        // i1 - Weak Quote Validation
        // swapWmstAmount is 1 ether. Since the pool starts around a 1:1 ratio and both tokens have 18 decimals,
        // we require a meaningful minimum output (e.g. at least 90% of swapWmstAmount) to protect against broken pricing.
        uint256 minimumExpectedOut = (swapWmstAmount * 90) / 100;
        assertGe(amountOut, minimumExpectedOut, "quoted output too low");
        assertGt(sqrtPriceX96After, 0, "invalid quoted price");

        console.log("[PASS] Swap quoted");
    }

    function executeSwap(uint256 quotedAmountOut) public returns (uint256 amountOut) {
        vm.startPrank(user);
        wmst.approve(swapRouter, type(uint256).max);

        uint256 tokenInBefore = wmst.balanceOf(user);
        uint256 tokenOutBefore = usdc.balanceOf(user);

        console.log("Pre-swap balances:");
        console.log("  tokenIn:", tokenInBefore);
        console.log("  tokenOut:", tokenOutBefore);

        // i2 - No Slippage Protection
        // Enforce slippage protection on execution by setting amountOutMinimum to 99.5% of quote amount (0.5% tolerance)
        uint256 minAmountOut = (quotedAmountOut * 9950) / 10000;

        amountOut = ISwapRouter(swapRouter).exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(wmst),
                tokenOut: address(usdc),
                fee: POOL_FEE,
                recipient: user,
                deadline: block.timestamp + 1200,
                amountIn: swapWmstAmount,
                amountOutMinimum: minAmountOut,
                sqrtPriceLimitX96: 0
            })
        );

        uint256 tokenInAfter = wmst.balanceOf(user);
        uint256 tokenOutAfter = usdc.balanceOf(user);
        vm.stopPrank();

        console.log("Post-swap balances:");
        console.log("  tokenIn:", tokenInAfter);
        console.log("  tokenOut:", tokenOutAfter);
        console.log("  amountOut received:", amountOut);

        assertEq(tokenInBefore - tokenInAfter, swapWmstAmount, "tokenIn delta mismatch");
        assertEq(tokenOutAfter - tokenOutBefore, amountOut, "tokenOut delta mismatch");

        console.log("[PASS] Swap executed");
    }

    function compareQuoteVsActual(uint256 quotedAmountOut, uint256 actualAmountOut) public pure {
        uint256 difference = quotedAmountOut > actualAmountOut
            ? quotedAmountOut - actualAmountOut
            : actualAmountOut - quotedAmountOut;
        uint256 maxSlippage = (quotedAmountOut * 1) / 1000;

        console.log("Quote vs Actual:");
        console.log("  Quoted:", quotedAmountOut);
        console.log("  Actual:", actualAmountOut);
        console.log("  Difference:", difference);
        console.log("  Max Slippage (0.1%):", maxSlippage);

        assertApproxEqAbs(quotedAmountOut, actualAmountOut, maxSlippage, "slippage too high");

        console.log("[PASS] Quote vs actual verified");
    }

    function increaseLiquidity() public {
        (uint256 amount0Desired, uint256 amount1Desired) = _amountsByTokenOrder(
            increaseWmstAmount,
            increaseUsdcAmount
        );

        vm.startPrank(user);
        wmst.approve(positionManager, type(uint256).max);
        usdc.approve(positionManager, type(uint256).max);

        console.log("Increasing liquidity:");
        console.log("  amount0Desired:", amount0Desired);
        console.log("  amount1Desired:", amount1Desired);

        // i3 - Liquidity Validation Missing
        // Track pool-level liquidity before modification
        uint128 poolLiquidityBefore = IUniswapV3Pool(pool).liquidity();

        (uint128 liquidityAdded, uint256 amount0, uint256 amount1) = INonfungiblePositionManager(positionManager).increaseLiquidity(
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 1200
            })
        );
        vm.stopPrank();

        console.log("Liquidity increased:");
        console.log("  liquidityAdded:", liquidityAdded);
        console.log("  amount0:", amount0);
        console.log("  amount1:", amount1);

        assertGt(liquidityAdded, 0, "no liquidity added");
        liquidity += liquidityAdded;

        // Verify pool liquidity actually increased
        uint128 poolLiquidityAfter = IUniswapV3Pool(pool).liquidity();
        assertGt(
            poolLiquidityAfter,
            poolLiquidityBefore,
            "pool liquidity did not increase"
        );

        console.log("[PASS] Liquidity increased");
    }

    function removeLiquidity() public {
        uint128 liquidityToRemove = liquidity / 2;

        vm.startPrank(user);
        console.log("Removing liquidity:");
        console.log("  liquidityToRemove:", liquidityToRemove);

        // i3 - Liquidity Delta Validation
        // Track pool-level liquidity before removal
        uint128 poolLiquidityBefore = IUniswapV3Pool(pool).liquidity();

        (uint256 amount0, uint256 amount1) = INonfungiblePositionManager(positionManager).decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidityToRemove,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp + 1200
            })
        );
        vm.stopPrank();

        console.log("Liquidity removed:");
        console.log("  amount0:", amount0);
        console.log("  amount1:", amount1);

        assertTrue(amount0 > 0 || amount1 > 0, "no liquidity removed");
        liquidity -= liquidityToRemove;

        // Verify pool liquidity actually decreased
        uint128 poolLiquidityAfter = IUniswapV3Pool(pool).liquidity();
        assertLt(
            poolLiquidityAfter,
            poolLiquidityBefore,
            "pool liquidity did not decrease"
        );

        console.log("[PASS] Liquidity removed");
    }

    function collectFees() public {
        vm.startPrank(user);
        uint256 balance0Before = IERC20(_token0()).balanceOf(user);
        uint256 balance1Before = IERC20(_token1()).balanceOf(user);

        console.log("Pre-collect balances:");
        console.log("  balance0:", balance0Before);
        console.log("  balance1:", balance1Before);

        (uint256 amount0Collected, uint256 amount1Collected) = INonfungiblePositionManager(positionManager).collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: user,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        uint256 balance0After = IERC20(_token0()).balanceOf(user);
        uint256 balance1After = IERC20(_token1()).balanceOf(user);
        vm.stopPrank();

        console.log("Fees collected:");
        console.log("  amount0Collected:", amount0Collected);
        console.log("  amount1Collected:", amount1Collected);
        console.log("Post-collect balances:");
        console.log("  balance0:", balance0After);
        console.log("  balance1:", balance1After);

        assertEq(balance0After - balance0Before, amount0Collected, "token0 collect mismatch");
        assertEq(balance1After - balance1Before, amount1Collected, "token1 collect mismatch");

        console.log("[PASS] Fees collected");
    }

    function finalVerification() public view {
        (uint160 sqrtPriceX96, int24 tick,,,,, bool unlocked) = IUniswapV3Pool(pool).slot0();
        uint128 poolLiquidity = IUniswapV3Pool(pool).liquidity();

        console.log("Final pool state:");
        console.log("  sqrtPriceX96:", sqrtPriceX96);
        console.log("  tick:", tick);
        console.log("  liquidity:", poolLiquidity);
        console.log("  unlocked:", unlocked);

        assertGt(sqrtPriceX96, 0, "invalid final price");
        assertGt(poolLiquidity, 0, "no final liquidity");
        assertTrue(unlocked, "pool locked");

        // i4 - Final Verification Incomplete
        // 1. Verify that the position NFT still exists and is owned by the user
        assertEq(
            INonfungiblePositionManager(positionManager).ownerOf(tokenId),
            user,
            "invalid NFT owner"
        );

        // 2. Verify tick range
        assertTrue(
            tick >= initialTickLower && tick <= initialTickUpper,
            "tick out of range"
        );

        // 3. Verify pool address valid
        (address expectedToken0, address expectedToken1) = _orderedTokens();
        assertEq(
            IUniswapV3Factory(factory).getPool(expectedToken0, expectedToken1, POOL_FEE),
            pool,
            "invalid pool address"
        );

        // 4. Verify liquidity state matches expected remaining value
        (,,,,,,, uint128 positionLiquidity,,,,) = INonfungiblePositionManager(positionManager).positions(tokenId);
        assertEq(positionLiquidity, liquidity, "liquidity state mismatch");

        // 5. Verify tick spacing alignment
        int24 spacing = IUniswapV3Pool(pool).tickSpacing();
        assertEq(spacing, 60, "invalid tick spacing");
        assertEq(initialTickLower % spacing, 0, "initialTickLower not aligned with tick spacing");
        assertEq(initialTickUpper % spacing, 0, "initialTickUpper not aligned with tick spacing");

        console.log("[PASS] Final verification passed");
    }

    function _orderedTokens() internal view returns (address token0, address token1) {
        token0 = address(wmst);
        token1 = address(usdc);
        if (token0 > token1) {
            (token0, token1) = (token1, token0);
        }
    }

    function _token0() internal view returns (address token0) {
        (token0,) = _orderedTokens();
    }

    function _token1() internal view returns (address token1) {
        (, token1) = _orderedTokens();
    }

    function _amountsByTokenOrder(uint256 wmstAmount, uint256 usdcAmount)
        internal
        view
        returns (uint256 amount0, uint256 amount1)
    {
        (address token0,) = _orderedTokens();
        if (token0 == address(wmst)) {
            return (wmstAmount, usdcAmount);
        }
        return (usdcAmount, wmstAmount);
    }
}
