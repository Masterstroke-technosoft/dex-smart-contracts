// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

library RapidEXChains {
    struct ChainConfig {
        uint256 chainId;
        string name;
        string slug;
        address wrappedNative;
    }

    error UnsupportedChain(uint256 chainId);

    function config(uint256 chainId) internal pure returns (ChainConfig memory) {
        if (chainId == 1) {
            return ChainConfig(1, "Ethereum", "ethereum", 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        }
        if (chainId == 8453) {
            return ChainConfig(8453, "Base", "base", 0x4200000000000000000000000000000000000006);
        }
        if (chainId == 56) {
            return ChainConfig(56, "BNB Chain", "bnb", 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);
        }
        if (chainId == 137) {
            return ChainConfig(137, "Polygon", "polygon", 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
        }
        if (chainId == 80094) {
            return ChainConfig(80094, "Berachain", "berachain", 0x6969696969696969696969696969696969696969);
        }
        if (chainId == 4646) {
            return ChainConfig(4646, "MST Mainnet", "mst", 0x56EdE2EbC789fD31f978DdA79D54d6B9e42f9eCD);
        }
        revert UnsupportedChain(chainId);
    }
}
