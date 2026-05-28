// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal metadata descriptor for Uniswap V3 position NFTs.
/// @dev The official SVG descriptor can be swapped in later; this keeps deployment small
/// and avoids extra descriptor-only dependencies while preserving ERC721 tokenURI support.
contract MinimalPositionDescriptor {
    string private _baseDescription;

    constructor(string memory baseDescription_) {
        _baseDescription = baseDescription_;
    }

    function tokenURI(address, uint256 tokenId) external view returns (string memory) {
        return string.concat(_baseDescription, " #", _toString(tokenId));
    }

    function _toString(uint256 value) private pure returns (string memory) {
        if (value == 0) return "0";

        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            // forge-lint: disable-next-line(unsafe-typecast)
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }

        return string(buffer);
    }
}
