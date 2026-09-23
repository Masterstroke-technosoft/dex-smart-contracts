// SPDX-License-Identifier: MIT

pragma solidity =0.8.27;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

contract MinimalPositionDescriptor is Ownable2Step {
    string private _baseDescription;
    bool public metadataFrozen;

    event BaseDescriptionUpdated(string oldDescription, string newDescription);
    event MetadataFrozen();

    error MetadataIsFrozen();

    constructor(string memory baseDescription_, address initialOwner) Ownable(initialOwner) {
        _baseDescription = baseDescription_;
    }

    /// @dev Until this is called, one write changes the displayed label of every position
    /// NFT ever minted, including positions already sold or transferred.
    function freezeMetadata() external onlyOwner {
        metadataFrozen = true;
        emit MetadataFrozen();
    }

    function setBaseDescription(string memory newDescription) external onlyOwner {
        if (metadataFrozen) revert MetadataIsFrozen();
        emit BaseDescriptionUpdated(_baseDescription, newDescription);
        _baseDescription = newDescription;
    }

    function baseDescription() external view returns (string memory) {
        return _baseDescription;
    }

    /// @dev First argument is the calling position manager; upstream descriptors use it to
    /// read pool state, this implementation doesn't and ignores it.
    function tokenURI(address, uint256 tokenId) external view returns (string memory) {
        string memory label = string.concat(_baseDescription, " #", Strings.toString(tokenId));
        string memory json = string.concat(
            '{"name":"',
            label,
            '","description":"',
            _baseDescription,
            '. This NFT represents a liquidity position in a Rapiddex V3 pool. The owner can modify or redeem the position.","attributes":[{"trait_type":"Token ID","value":"',
            Strings.toString(tokenId),
            '"}]}'
        );
        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }
}
