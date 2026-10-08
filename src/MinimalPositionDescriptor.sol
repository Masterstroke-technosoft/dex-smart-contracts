// SPDX-License-Identifier: MIT

pragma solidity =0.8.27;

import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

interface IPositionManagerView {
    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );
}

interface IERC20Symbol {
    function symbol() external view returns (string memory);
}

contract MinimalPositionDescriptor {
    function tokenURI(address positionManager, uint256 tokenId) external view returns (string memory) {
        (
            ,
            ,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            ,
            ,
            ,
        ) = IPositionManagerView(positionManager).positions(tokenId);

        string memory pair = string.concat(_symbol(token0), "/", _symbol(token1));

        string memory json = string.concat(
            '{"name":"RapidDex ',
            pair,
            " ",
            _feeLabel(fee),
            " #",
            Strings.toString(tokenId),
            '","description":"RapidDex V3 concentrated liquidity position. All values are read from the position manager on-chain.","attributes":[',
            '{"trait_type":"Pair","value":"',
            pair,
            '"},{"trait_type":"Token0","value":"',
            Strings.toChecksumHexString(token0),
            '"},{"trait_type":"Token1","value":"',
            Strings.toChecksumHexString(token1),
            '"},{"trait_type":"Fee","value":"',
            _feeLabel(fee),
            '"},',
            '{"trait_type":"Tick Lower","value":"',
            Strings.toStringSigned(tickLower),
            '"},{"trait_type":"Tick Upper","value":"',
            Strings.toStringSigned(tickUpper),
            '"},{"trait_type":"Liquidity","value":"',
            Strings.toString(liquidity),
            '"}]}'
        );

        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    function _symbol(address token) private view returns (string memory) {
        try IERC20Symbol(token).symbol() returns (string memory s) {
            if (bytes(s).length != 0) return s;
        } catch {}
        return Strings.toChecksumHexString(token);
    }

    function _feeLabel(uint24 fee) private pure returns (string memory) {
        uint256 whole = uint256(fee) / 10000;
        uint256 frac = uint256(fee) % 10000;
        if (frac == 0) return string.concat(Strings.toString(whole), "%");

        uint256 digits = 4;
        while (frac % 10 == 0) {
            frac /= 10;
            digits--;
        }
        string memory fracStr = Strings.toString(frac);
        while (bytes(fracStr).length < digits) {
            fracStr = string.concat("0", fracStr);
        }
        return string.concat(Strings.toString(whole), ".", fracStr, "%");
    }
}
