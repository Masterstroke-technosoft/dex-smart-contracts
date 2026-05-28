// SPDX-License-Identifier: MIT

import { expect } from 'chai';
import { ethers, waffle } from 'hardhat';
import { MockTimeUniswapV3Pool } from '../typechain/MockTimeUniswapV3Pool';
import { TestERC20 } from '../typechain/TestERC20';
import { UniswapV3Factory } from '../typechain/UniswapV3Factory';
import { poolFixture, TEST_POOL_START_TIME } from './shared/fixtures';
import { FeeAmount, TICK_SPACINGS, encodePriceSqrt, getMinTick, getMaxTick } from './shared/utilities';

/**
 * Test that demonstrates how to initialize the ticks required for
 * `snapshotCumulativesInside` so that the call does not revert.
 *
 * The steps are:
 *   1. Deploy a pool via the `poolFixture` helper (which also deploys mock ERC20 tokens).
 *   2. Initialize the pool with a 1:1 price.
 *   3. Choose a tick spacing (the fixture uses the fee amount to set this).
 *   4. Mint a position that spans a lower and upper tick that are *initialized* – i.e.
 *      they are multiples of the pool's `tickSpacing`.
 *   5. Call `snapshotCumulativesInside` with those ticks and assert that the
 *      returned values are numbers (BigNumber) and that the call succeeds.
 */

describe('snapshotCumulativesInside – initialize ticks', function () {
  let wallet: any;
  let other: any;
  let pool: MockTimeUniswapV3Pool;
  let token0: TestERC20;
  let token1: TestERC20;
  let factory: UniswapV3Factory;

  const FEE = FeeAmount.MEDIUM; // 0.3% fee – typical tick spacing = 60

  before(async function () {
    // grab signers
    [wallet, other] = await (ethers as any).getSigners();
    const loadFixture = waffle.createFixtureLoader([wallet, other]);
    const fixture = await loadFixture(poolFixture);
    token0 = fixture.token0;
    token1 = fixture.token1;
    factory = fixture.factory;
    // create pool with chosen fee and spacing
    const createPool = fixture.createPool;
    pool = await createPool(FEE, TICK_SPACINGS[FEE]);
    // initialize at price 1:1 (sqrtPriceX96 = 2**96)
    const sqrtPriceX96 = ethers.BigNumber.from('79228162514264337593543950336'); // 2**96
    await pool.initialize(sqrtPriceX96);
  });

  it('should not revert when calling snapshotCumulativesInside on initialized ticks', async function () {
    // fetch the pool's tick spacing (should be 60 for medium fee)
    const tickSpacing = await pool.tickSpacing();
    // pick lower/upper ticks that are multiples of spacing and surround 0
    const tickLower = -tickSpacing; // e.g., -60
    const tickUpper = tickSpacing; // e.g., 60

    // mint a position that spans these ticks – this will mark them as initialized
    const liquidity = ethers.utils.parseUnits('1000', 18);
    // approve pool to move tokens (required for mint in the fixture's pool implementation)
    await token0.approve(pool.address, ethers.constants.MaxUint256);
    await token1.approve(pool.address, ethers.constants.MaxUint256);
    await pool.mint(wallet.address, tickLower, tickUpper, liquidity, '0x');

    // now snapshotCumulativesInside should succeed
    const result = await pool.snapshotCumulativesInside(tickLower, tickUpper);
    console.log('snapshotCumulativesInside result:', result);
    // sanity checks – the three returned values are big numbers (int56, uint160, uint32)
    expect(result.tickCumulativeInside).to.be.a('bigint');
    expect(result.secondsPerLiquidityInsideX128).to.be.a('bigint');
    expect(result.secondsInside).to.be.a('bigint');
  });
});
