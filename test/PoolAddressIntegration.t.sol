// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;
pragma abicoder v2;

import "forge-std/Test.sol";
import "v3-core/interfaces/IRapiddexV3Factory.sol";
import "v3-core/interfaces/IRapiddexV3Pool.sol";
import "v3-periphery/interfaces/INonfungiblePositionManager.sol";
import "v3-periphery/interfaces/ISwapRouter.sol";
import "../src/WMST.sol";
import "../src/TestToken.sol";

/// @notice Proves the periphery's CREATE2 pool-address derivation (PoolAddress.POOL_INIT_CODE_HASH)
/// matches the actual deployed RapiddexV3Pool bytecode: mint + swap only succeed end-to-end if
/// CallbackValidation's computed pool address equals the real pool, since callbacks assert
/// `msg.sender == computedPoolAddress`.
/// @dev Deploys the =0.7.6-pinned core/periphery contracts via `deployCode` (compiled artifacts)
/// rather than `new`, since their exact pragma is incompatible with this file's ^0.8.19 in one
/// compilation unit.
contract PoolAddressIntegrationTest is Test {
    uint24 constant FEE = 3000;
    int24 constant TICK_SPACING = 60;
    uint160 constant SQRT_PRICE_1_1 = 79228162514264337593543950336; // TickMath.getSqrtRatioAtTick(0)

    IRapiddexV3Factory factory;
    WMST wmst;
    tMUSD musd;
    INonfungiblePositionManager nfpm;
    ISwapRouter router;

    address token0;
    address token1;

    function setUp() public {
        factory = IRapiddexV3Factory(deployCode("RapiddexV3Factory.sol:RapiddexV3Factory"));
        wmst = new WMST();
        musd = new tMUSD(address(this));

        nfpm = INonfungiblePositionManager(
            deployCode(
                "NonfungiblePositionManager.sol:NonfungiblePositionManager",
                abi.encode(address(factory), address(wmst), address(0))
            )
        );
        router = ISwapRouter(deployCode("SwapRouter.sol:SwapRouter", abi.encode(address(factory), address(wmst))));

        (token0, token1) = address(wmst) < address(musd) ? (address(wmst), address(musd)) : (address(musd), address(wmst));

        vm.deal(address(this), 100 ether);
        wmst.deposit{value: 50 ether}();
        musd.mint(address(this), 1_000_000e6);

        wmst.approve(address(nfpm), type(uint256).max);
        musd.approve(address(nfpm), type(uint256).max);
        wmst.approve(address(router), type(uint256).max);
        musd.approve(address(router), type(uint256).max);
    }

    function test_mintAndSwapSucceedWithCorrectInitCodeHash() public {
        address pool = nfpm.createAndInitializePoolIfNecessary(token0, token1, FEE, SQRT_PRICE_1_1);
        assertTrue(pool.code.length > 0, "pool must have code");

        (uint256 tokenId, uint128 liquidity, , ) = nfpm.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: FEE,
                tickLower: -TICK_SPACING * 10,
                tickUpper: TICK_SPACING * 10,
                amount0Desired: 100_000,
                amount1Desired: 100_000,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: block.timestamp
            })
        );

        assertGt(tokenId, 0);
        assertGt(liquidity, 0);

        uint256 amountOut = router.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(wmst),
                tokenOut: address(musd),
                fee: FEE,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: 1_000,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            })
        );

        assertGt(amountOut, 0, "swap must return nonzero output");
    }
}
