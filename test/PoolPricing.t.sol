// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {Test} from "forge-std/Test.sol";
import {SetupPools} from "../script/SetupPools.s.sol";

contract Harness is SetupPools {
    function encode(uint256 amount1, uint256 amount0) external pure returns (uint160) {
        return _encodeSqrtPrice(amount1, amount0);
    }
}

contract PoolPricingTest is Test {
    Harness h;

    uint256 constant USDC = 1e6;
    uint256 constant WMSTC = 1e18;

    function setUp() public {
        h = new Harness();
    }

    function test_tenWmstcEncodesToTenCents() public view {
        uint160 sq = h.encode(10 * WMSTC, 1 * USDC);
        assertEq(sq, 250541448375047931186159242635640832, "known-good $0.10 encoding");
    }

    function test_largeAmountsEncodeToTheSamePrice() public view {
        uint160 small = h.encode(10 * WMSTC, 1 * USDC);
        uint160 large = h.encode(5000 * WMSTC, 500 * USDC);

        assertEq(large, small, "same ratio must give the same price at any size");
    }

    function test_priceIsScaleInvariantAcrossTheOldOverflowBoundary() public view {
        uint160 baseline = h.encode(10 * WMSTC, 1 * USDC);

        uint256[7] memory sizes = [uint256(1), 18, 19, 100, 500, 5000, 1_000_000];
        for (uint256 i = 0; i < sizes.length; i++) {
            uint256 w = sizes[i];
            uint160 got = h.encode(w * WMSTC, (w * USDC) / 10);
            assertEq(got, baseline, "ratio 10:1 must encode the same at every scale");
        }
    }

    function test_higherRatioMeansHigherPrice() public view {
        uint160 at10 = h.encode(10 * WMSTC, 1 * USDC);
        uint160 at5 = h.encode(5 * WMSTC, 1 * USDC);
        uint160 at100 = h.encode(100 * WMSTC, 1 * USDC);

        assertGt(at100, at10, "100:1 encodes above 10:1");
        assertGt(at10, at5, "10:1 encodes above 5:1");
    }

    function test_rejectsZeroAmount0() public {
        vm.expectRevert("SetupPools: zero amount0");
        h.encode(1 * WMSTC, 0);
    }

    function test_revertsRatherThanTruncatingOnAbsurdAmounts() public {
        vm.expectRevert("SetupPools: amount1 too large to price safely");
        h.encode(1 << 160, 1 * USDC);
    }

    function test_encodesBothDirectionsOfARealPair() public view {
        uint160 a = h.encode(10 * WMSTC, 1 * USDC);
        uint160 b = h.encode(1 * USDC, 10 * WMSTC);

        assertGt(a, 0, "forward encodes");
        assertGt(b, 0, "inverse encodes");
        assertTrue(a != b, "the two orientations are different prices");
    }
}
