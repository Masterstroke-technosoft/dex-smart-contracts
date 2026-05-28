// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Stores LP position and pool metadata on-chain for easy reuse across scripts.
contract LPStateStorage {
    address public owner;
    address public poolAddress;
    uint256 public lpTokenId;
    uint256 public lpLiquidity;
    uint256 public lpAmount0;
    uint256 public lpAmount1;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "LPStateStorage: caller is not the owner");
        _;
    }

    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), msg.sender);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "LPStateStorage: new owner is the zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    event ValuesUpdated(
        address indexed poolAddress,
        uint256 lpTokenId,
        uint256 lpLiquidity,
        uint256 lpAmount0,
        uint256 lpAmount1
    );

    /// @notice Update all LP-related values in a single transaction.
    /// @dev Only the contract owner may call this.
    function setValues(
        address _poolAddress,
        uint256 _lpTokenId,
        uint256 _lpLiquidity,
        uint256 _lpAmount0,
        uint256 _lpAmount1
    ) external onlyOwner {
        poolAddress = _poolAddress;
        lpTokenId = _lpTokenId;
        lpLiquidity = _lpLiquidity;
        lpAmount0 = _lpAmount0;
        lpAmount1 = _lpAmount1;

        emit ValuesUpdated(_poolAddress, _lpTokenId, _lpLiquidity, _lpAmount0, _lpAmount1);
    }

    /// @notice Update only the pool address.
    function setPoolAddress(address _poolAddress) external onlyOwner {
        poolAddress = _poolAddress;
    }

    /// @notice Update only the LP position fields.
    function setPosition(
        uint256 _lpTokenId,
        uint256 _lpLiquidity,
        uint256 _lpAmount0,
        uint256 _lpAmount1
    ) external onlyOwner {
        lpTokenId = _lpTokenId;
        lpLiquidity = _lpLiquidity;
        lpAmount0 = _lpAmount0;
        lpAmount1 = _lpAmount1;
    }
}
