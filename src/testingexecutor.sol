// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IUniswapV3Factory} from "v3-core/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "v3-core/interfaces/IUniswapV3Pool.sol";
import {INonfungiblePositionManager} from "v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {ISwapRouter} from "v3-periphery/interfaces/ISwapRouter.sol";
import {IQuoterV2} from "v3-periphery/interfaces/IQuoterV2.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {WMST} from "./WMST.sol";
import {LPStateStorage} from "./LPStateStorage.sol";

// Helper contract to orchestrate and demonstrate the Uniswap V3 lifecycle on-chain.
contract TestingExecutor is IERC721Receiver {
    error ZeroAddress();
    error ZeroAmount();
    error NotNFTOwner();
    error FactoryMismatch();
    error WMSTMismatch();
    error PoolNotInitialized();
    error SafeTransferFailed();

    // Packed struct to prevent Stack Too Deep compiler error
    struct PoolParams {
        uint24 fee;
        uint160 sqrtPriceX96;
        uint256 wmstDesired;
        uint256 usdcDesired;
        int24 tickLower;
        int24 tickUpper;
    }

    IUniswapV3Factory public immutable factory;
    INonfungiblePositionManager public immutable positionManager;
    ISwapRouter public immutable swapRouter;
    IQuoterV2 public immutable quoter;
    WMST public immutable wmst;
    IERC20 public immutable usdc;
    LPStateStorage public immutable lpStateStorage;

    uint256 public activeTokenId;

    event PoolOrchestrated(address indexed poolAddress, uint256 indexed tokenId, uint128 liquidity);
    event SwapExecuted(address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    event LiquidityIncreased(uint256 indexed tokenId, uint128 liquidityAdded, uint256 amount0, uint256 amount1);
    event LiquidityDecreased(uint256 indexed tokenId, uint128 liquidityRemoved, uint256 amount0, uint256 amount1);
    event FeesCollected(uint256 indexed tokenId, address indexed recipient, uint256 amount0, uint256 amount1);

    constructor(
        address _factory,
        address _positionManager,
        address _swapRouter,
        address _quoter,
        address _wmst,
        address _usdc,
        address _lpStateStorage
    ) {
        if (_factory == address(0)) revert ZeroAddress();
        if (_positionManager == address(0)) revert ZeroAddress();
        if (_swapRouter == address(0)) revert ZeroAddress();
        if (_quoter == address(0)) revert ZeroAddress();
        if (_wmst == address(0)) revert ZeroAddress();
        if (_usdc == address(0)) revert ZeroAddress();
        if (_lpStateStorage == address(0)) revert ZeroAddress();

        factory = IUniswapV3Factory(_factory);
        positionManager = INonfungiblePositionManager(_positionManager);
        swapRouter = ISwapRouter(_swapRouter);
        quoter = IQuoterV2(_quoter);
        wmst = WMST(payable(_wmst));
        usdc = IERC20(_usdc);
        lpStateStorage = LPStateStorage(_lpStateStorage);
    }

    receive() external payable {
        if (msg.value > 0) {
            wmst.deposit{value: msg.value}();
        }
    }

    // Wraps MST, sets up the pool, mints LP NFT to this contract, and updates LPStateStorage.
    function initiatePoolAndLiquidity(
        PoolParams calldata params
    ) external payable returns (address pool, uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) {
        if (msg.value > 0) {
            wmst.deposit{value: msg.value}();
        }

        if (params.usdcDesired > 0) {
            bool success = usdc.transferFrom(msg.sender, address(this), params.usdcDesired);
            if (!success) revert SafeTransferFailed();
        }

        if (params.wmstDesired > msg.value) {
            uint256 extraWmst;
            unchecked {
                extraWmst = params.wmstDesired - msg.value;
            }
            bool success = wmst.transferFrom(msg.sender, address(this), extraWmst);
            if (!success) revert SafeTransferFailed();
        }

        address token0 = address(wmst) < address(usdc) ? address(wmst) : address(usdc);
        address token1 = address(wmst) < address(usdc) ? address(usdc) : address(wmst);

        pool = positionManager.createAndInitializePoolIfNecessary(token0, token1, params.fee, params.sqrtPriceX96);
        if (pool == address(0)) revert PoolNotInitialized();

        if (wmst.allowance(address(this), address(positionManager)) < params.wmstDesired) {
            wmst.approve(address(positionManager), type(uint256).max);
        }
        if (usdc.allowance(address(this), address(positionManager)) < params.usdcDesired) {
            usdc.approve(address(positionManager), type(uint256).max);
        }

        uint256 amount0Desired = token0 == address(wmst) ? params.wmstDesired : params.usdcDesired;
        uint256 amount1Desired = token1 == address(wmst) ? params.wmstDesired : params.usdcDesired;

        uint256 deadlineVal;
        unchecked {
            deadlineVal = block.timestamp + 600;
        }

        (tokenId, liquidity, amount0, amount1) = positionManager.mint(
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: params.fee,
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
                deadline: deadlineVal
            })
        );

        activeTokenId = tokenId;

        try lpStateStorage.setValues(pool, tokenId, uint256(liquidity), amount0, amount1) {} catch {}

        emit PoolOrchestrated(pool, tokenId, liquidity);
    }

    // Fetches estimated output from QuoterV2
    function quoteSwapWmstForUsdc(uint256 amountIn, uint24 fee) external returns (uint256 amountOut) {
        if (amountIn == 0) revert ZeroAmount();
        (amountOut, , , ) = quoter.quoteExactInputSingle(
            IQuoterV2.QuoteExactInputSingleParams({
                tokenIn: address(wmst),
                tokenOut: address(usdc),
                amountIn: amountIn,
                fee: fee,
                sqrtPriceLimitX96: 0
            })
        );
    }

    // Swaps WMST for USDC and routes outputs to msg.sender
    function swapWmstForUsdc(uint256 amountIn, uint256 amountOutMin, uint24 fee) external returns (uint256 amountOut) {
        if (amountIn == 0) revert ZeroAmount();

        bool success = wmst.transferFrom(msg.sender, address(this), amountIn);
        if (!success) revert SafeTransferFailed();

        if (wmst.allowance(address(this), address(swapRouter)) < amountIn) {
            wmst.approve(address(swapRouter), type(uint256).max);
        }

        uint256 deadlineVal;
        unchecked {
            deadlineVal = block.timestamp + 600;
        }

        amountOut = swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(wmst),
                tokenOut: address(usdc),
                fee: fee,
                recipient: msg.sender,
                deadline: deadlineVal,
                amountIn: amountIn,
                amountOutMinimum: amountOutMin,
                sqrtPriceLimitX96: 0
            })
        );

        emit SwapExecuted(address(wmst), address(usdc), amountIn, amountOut);
    }

    // Swaps USDC for WMST and routes outputs to msg.sender
    function swapUsdcForWmst(uint256 amountIn, uint256 amountOutMin, uint24 fee) external returns (uint256 amountOut) {
        if (amountIn == 0) revert ZeroAmount();

        bool success = usdc.transferFrom(msg.sender, address(this), amountIn);
        if (!success) revert SafeTransferFailed();

        if (usdc.allowance(address(this), address(swapRouter)) < amountIn) {
            usdc.approve(address(swapRouter), type(uint256).max);
        }

        uint256 deadlineVal;
        unchecked {
            deadlineVal = block.timestamp + 600;
        }

        amountOut = swapRouter.exactInputSingle(
            ISwapRouter.ExactInputSingleParams({
                tokenIn: address(usdc),
                tokenOut: address(wmst),
                fee: fee,
                recipient: msg.sender,
                deadline: deadlineVal,
                amountIn: amountIn,
                amountOutMinimum: amountOutMin,
                sqrtPriceLimitX96: 0
            })
        );

        emit SwapExecuted(address(usdc), address(wmst), amountIn, amountOut);
    }

    // Adds more tokens to the active LP position
    function increaseActiveLiquidity(
        uint256 wmstDesired,
        uint256 usdcDesired
    ) external payable returns (uint128 liquidityAdded, uint256 amount0, uint256 amount1) {
        uint256 tokenId = activeTokenId;
        if (tokenId == 0) revert NotNFTOwner();

        if (msg.value > 0) {
            wmst.deposit{value: msg.value}();
        }

        if (usdcDesired > 0) {
            bool success = usdc.transferFrom(msg.sender, address(this), usdcDesired);
            if (!success) revert SafeTransferFailed();
        }

        if (wmstDesired > msg.value) {
            uint256 extraWmst;
            unchecked {
                extraWmst = wmstDesired - msg.value;
            }
            bool success = wmst.transferFrom(msg.sender, address(this), extraWmst);
            if (!success) revert SafeTransferFailed();
        }

        address token0 = address(wmst) < address(usdc) ? address(wmst) : address(usdc);
        uint256 amount0Desired = token0 == address(wmst) ? wmstDesired : usdcDesired;
        uint256 amount1Desired = token0 == address(wmst) ? usdcDesired : wmstDesired;

        if (wmst.allowance(address(this), address(positionManager)) < wmstDesired) {
            wmst.approve(address(positionManager), type(uint256).max);
        }
        if (usdc.allowance(address(this), address(positionManager)) < usdcDesired) {
            usdc.approve(address(positionManager), type(uint256).max);
        }

        uint256 deadlineVal;
        unchecked {
            deadlineVal = block.timestamp + 600;
        }

        (liquidityAdded, amount0, amount1) = positionManager.increaseLiquidity(
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: amount0Desired,
                amount1Desired: amount1Desired,
                amount0Min: 0,
                amount1Min: 0,
                deadline: deadlineVal
            })
        );

        _syncLPState();

        emit LiquidityIncreased(tokenId, liquidityAdded, amount0, amount1);
    }

    // Partially removes liquidity from the active LP position
    function decreaseActiveLiquidity(uint128 liquidityToRemove) external returns (uint256 amount0, uint256 amount1) {
        uint256 tokenId = activeTokenId;
        if (tokenId == 0) revert NotNFTOwner();

        uint256 deadlineVal;
        unchecked {
            deadlineVal = block.timestamp + 600;
        }

        (amount0, amount1) = positionManager.decreaseLiquidity(
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId,
                liquidity: liquidityToRemove,
                amount0Min: 0,
                amount1Min: 0,
                deadline: deadlineVal
            })
        );

        _syncLPState();

        emit LiquidityDecreased(tokenId, liquidityToRemove, amount0, amount1);
    }

    // Collects trading fees accrued in the active LP position
    function collectActiveFees() external returns (uint256 amount0Collected, uint256 amount1Collected) {
        uint256 tokenId = activeTokenId;
        if (tokenId == 0) revert NotNFTOwner();

        (amount0Collected, amount1Collected) = positionManager.collect(
            INonfungiblePositionManager.CollectParams({
                tokenId: tokenId,
                recipient: msg.sender,
                amount0Max: type(uint128).max,
                amount1Max: type(uint128).max
            })
        );

        emit FeesCollected(tokenId, msg.sender, amount0Collected, amount1Collected);
    }

    // Internal helper to sync metadata with LPStateStorage
    function _syncLPState() internal {
        uint256 tokenId = activeTokenId;
        if (tokenId == 0) return;

        (
            ,
            ,
            address token0,
            address token1,
            uint24 fee,
            ,
            ,
            uint128 positionLiquidity,
            ,
            ,
            ,
        ) = positionManager.positions(tokenId);

        address pool = factory.getPool(token0, token1, fee);

        try lpStateStorage.setValues(
            pool,
            tokenId,
            uint256(positionLiquidity),
            IERC20(token0).balanceOf(pool),
            IERC20(token1).balanceOf(pool)
        ) {} catch {}
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
