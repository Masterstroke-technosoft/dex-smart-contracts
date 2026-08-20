// SPDX-License-Identifier: MIT

pragma solidity =0.8.27;

contract LPStateStorage {
    address public owner;
    address public pendingOwner;
    address public poolAddress;
    uint256 public lpTokenId;
    uint256 public lpLiquidity;
    uint256 public lpAmount0;
    uint256 public lpAmount1;

    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event PoolAddressUpdated(address indexed previousPool, address indexed newPool);
    event PositionUpdated(uint256 lpTokenId, uint256 lpLiquidity, uint256 lpAmount0, uint256 lpAmount1);
    event ValuesUpdated(
        address indexed poolAddress,
        uint256 lpTokenId,
        uint256 lpLiquidity,
        uint256 lpAmount0,
        uint256 lpAmount1
    );

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
        pendingOwner = newOwner;
        emit OwnershipTransferStarted(owner, newOwner);
    }

    function acceptOwnership() external {
        require(msg.sender == pendingOwner, "LPStateStorage: caller is not pending owner");
        emit OwnershipTransferred(owner, pendingOwner);
        owner = pendingOwner;
        pendingOwner = address(0);
    }

    function setValues(
        address _poolAddress,
        uint256 _lpTokenId,
        uint256 _lpLiquidity,
        uint256 _lpAmount0,
        uint256 _lpAmount1
    ) external onlyOwner {
        require(_poolAddress != address(0), "LPStateStorage: pool address cannot be zero");
        poolAddress = _poolAddress;
        lpTokenId = _lpTokenId;
        lpLiquidity = _lpLiquidity;
        lpAmount0 = _lpAmount0;
        lpAmount1 = _lpAmount1;

        emit ValuesUpdated(_poolAddress, _lpTokenId, _lpLiquidity, _lpAmount0, _lpAmount1);
    }

    function setPoolAddress(address _poolAddress) external onlyOwner {
        require(_poolAddress != address(0), "LPStateStorage: pool address cannot be zero");
        emit PoolAddressUpdated(poolAddress, _poolAddress);
        poolAddress = _poolAddress;
    }

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

        emit PositionUpdated(_lpTokenId, _lpLiquidity, _lpAmount0, _lpAmount1);
    }
}
