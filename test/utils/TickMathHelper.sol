// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TickMath08} from "./TickMath08.sol";
import {IUniswapV3Factory} from "v3-core/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";

/// @notice Dynamic decimals interface
interface IERC20Decimals {
    function decimals() external view returns (uint8);
}

library TickMathHelper {
    /// @notice Computes Babylonian square root of a uint256
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    /// @notice Calculates the Uniswap V3 sqrtPriceX96 based on a given real price multiplier
    function calculateSqrtPriceX96(
        address tokenA,
        address tokenB,
        uint256 priceMultiplier,
        address tokenABase
    ) internal view returns (uint160 sqrtPriceX96) {
        address token0 = tokenA < tokenB ? tokenA : tokenB;
        address token1 = tokenA < tokenB ? tokenB : tokenA;

        uint8 decimals0 = IERC20Decimals(token0).decimals();
        uint8 decimals1 = IERC20Decimals(token1).decimals();

        uint256 ratio;

        if (token0 == tokenABase) {
            if (decimals1 >= decimals0) {
                ratio = priceMultiplier * (10 ** (decimals1 - decimals0)) * (2 ** 192);
            } else {
                ratio = (priceMultiplier * (2 ** 192)) / (10 ** (decimals0 - decimals1));
            }
        } else {
            if (decimals1 >= decimals0) {
                ratio = ((10 ** (decimals1 - decimals0)) * (2 ** 192)) / priceMultiplier;
            } else {
                ratio = (2 ** 192) / (priceMultiplier * (10 ** (decimals0 - decimals1)));
            }
        }

        uint256 sqrtRatio = sqrt(ratio);
        // forge-lint: disable-next-line(unsafe-typecast)
        sqrtPriceX96 = uint160(sqrtRatio);
    }

    /// @notice Estimates or queries the active tick range for LP placement
    function getActiveTickRange(
        address factory,
        address tokenA,
        address tokenB,
        uint24 fee,
        uint160 initialSqrtPriceX96,
        int24 tickSpacing
    ) internal view returns (int24 tickLower, int24 tickUpper) {
        address token0 = tokenA < tokenB ? tokenA : tokenB;
        address token1 = tokenA < tokenB ? tokenB : tokenA;
        
        address pool = IUniswapV3Factory(factory).getPool(token0, token1, fee);
        
        int24 targetTick;
        if (pool != address(0) && pool.code.length > 0) {
            (, targetTick,,,,,) = IUniswapV3Pool(pool).slot0();
        } else {
            targetTick = TickMath08.getTickAtSqrtRatio(initialSqrtPriceX96);
        }

        // Align tick using subtraction of remainder (avoids divide-before-multiply lint warning and saves gas)
        int24 alignedTick = targetTick - (targetTick % tickSpacing);
        tickLower = alignedTick - (tickSpacing * 100);
        tickUpper = alignedTick + (tickSpacing * 100);

        int24 minAligned = TickMath08.MIN_TICK - (TickMath08.MIN_TICK % tickSpacing);
        int24 maxAligned = TickMath08.MAX_TICK - (TickMath08.MAX_TICK % tickSpacing);
        
        if (tickLower < minAligned) tickLower = minAligned;
        if (tickUpper > maxAligned) tickUpper = maxAligned;
    }
}
