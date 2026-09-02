// SPDX-License-Identifier: MIT

pragma solidity =0.8.27;

contract MinimalPositionDescriptor {
    address public owner;
    address public pendingOwner;
    string private _baseDescription;
    bool public frozen;

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event BaseDescriptionUpdated(string oldDescription, string newDescription);
    event MetadataFrozen();

    modifier onlyOwner() {
        require(msg.sender == owner, "MinimalPositionDescriptor: caller is not the owner");
        _;
    }

    constructor(string memory baseDescription_) {
        owner = msg.sender;
        _baseDescription = baseDescription_;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "MinimalPositionDescriptor: zero address");
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "MinimalPositionDescriptor: caller is not pending owner");
        emit OwnershipTransferred(owner, pendingOwner);
        owner = pendingOwner;
        pendingOwner = address(0);
    }

    function setBaseDescription(string memory newDescription) external onlyOwner {
        require(!frozen, "MinimalPositionDescriptor: metadata frozen");
        emit BaseDescriptionUpdated(_baseDescription, newDescription);
        _baseDescription = newDescription;
    }

    function freeze() external onlyOwner {
        require(!frozen, "MinimalPositionDescriptor: already frozen");
        frozen = true;
        emit MetadataFrozen();
    }

    function baseDescription() external view returns (string memory) {
        return _baseDescription;
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

            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }

        return string(buffer);
    }
}
