// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function createAndInitializePoolIfNecessary(address token0, address token1, uint24 fee, uint160 sqrtPriceX96)
        external
        payable
        returns (address pool);

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

interface IRapidexV3Factory {
    function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address);
    function feeAmountTickSpacing(uint24 fee) external view returns (int24);
}

interface IBlacklistProtection {
    function protectedFromBlacklist(address account) external view returns (bool);
    function setBlacklistProtection(address account, bool isProtected) external;
    function owner() external view returns (address);
}

interface IRapidexV3Pool {
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );
    function liquidity() external view returns (uint128);
    function increaseObservationCardinalityNext(uint16 observationCardinalityNext) external;
}

contract SetupPools is Script {
    using SafeERC20 for IERC20;

    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = 887272;

    uint256 internal constant MINT_SLIPPAGE_BPS = 100;

    struct PoolSetup {
        address token0;
        address token1;
        uint256 amount0;
        uint256 amount1;
        int24 spacing;
        address pool;
        address lp;
    }

    function run(address tokenA, address tokenB, uint24 fee, uint256 amountA, uint256 amountB) external {
        require(tokenA != tokenB, "SetupPools: identical tokens");
        require(amountA > 0 && amountB > 0, "SetupPools: pool must be seeded, not just created");

        uint256 pk = vm.envUint("PRIVATE_KEY");
        INonfungiblePositionManager npm = INonfungiblePositionManager(vm.envAddress("POSITION_MANAGER"));
        IRapidexV3Factory factory = IRapidexV3Factory(vm.envAddress("V3_FACTORY"));

        PoolSetup memory ps;
        ps.lp = vm.addr(pk);

        (ps.token0, ps.token1, ps.amount0, ps.amount1) =
            tokenA < tokenB ? (tokenA, tokenB, amountA, amountB) : (tokenB, tokenA, amountB, amountA);

        ps.spacing = factory.feeAmountTickSpacing(fee);
        require(ps.spacing != 0, "SetupPools: fee tier not enabled on this factory");

        require(
            factory.getPool(ps.token0, ps.token1, fee) == address(0),
            "SetupPools: pool already exists - use an increase-liquidity flow instead"
        );

        uint160 sqrtPriceX96 = _encodeSqrtPrice(ps.amount1, ps.amount0);

        console2.log("token0      :", ps.token0);
        console2.log("token1      :", ps.token1);
        console2.log("fee         :", fee);
        console2.log("sqrtPriceX96:", sqrtPriceX96);

        vm.startBroadcast(pk);

        ps.pool = npm.createAndInitializePoolIfNecessary(ps.token0, ps.token1, fee, sqrtPriceX96);

        _protectFromBlacklist(ps.token0, ps.pool, ps.lp);
        _protectFromBlacklist(ps.token1, ps.pool, ps.lp);

        IERC20(ps.token0).forceApprove(address(npm), ps.amount0);
        IERC20(ps.token1).forceApprove(address(npm), ps.amount1);

        (uint256 tokenId, uint128 liquidity,,) = npm.mint(
            INonfungiblePositionManager.MintParams({
                token0: ps.token0,
                token1: ps.token1,
                fee: fee,
                tickLower: _minUsableTick(ps.spacing),
                tickUpper: _maxUsableTick(ps.spacing),
                amount0Desired: ps.amount0,
                amount1Desired: ps.amount1,
                amount0Min: (ps.amount0 * (10_000 - MINT_SLIPPAGE_BPS)) / 10_000,
                amount1Min: (ps.amount1 * (10_000 - MINT_SLIPPAGE_BPS)) / 10_000,
                recipient: ps.lp,
                deadline: block.timestamp + 20 minutes
            })
        );

        IERC20(ps.token0).forceApprove(address(npm), 0);
        IERC20(ps.token1).forceApprove(address(npm), 0);

        IRapidexV3Pool(ps.pool).increaseObservationCardinalityNext(10);

        vm.stopBroadcast();

        require(liquidity > 0, "SetupPools: mint produced no liquidity");

        console2.log("");
        console2.log("pool        :", ps.pool);
        console2.log("positionId  :", tokenId);
        console2.log("liquidity   :", liquidity);
    }

    function _protectFromBlacklist(address token, address pool, address broadcaster) internal {
        (bool found,) =
            token.staticcall(abi.encodeWithSelector(IBlacklistProtection.protectedFromBlacklist.selector, pool));
        if (!found) return;

        (bool hasOwner, bytes memory raw) =
            token.staticcall(abi.encodeWithSelector(IBlacklistProtection.owner.selector));
        address tokenOwner = hasOwner && raw.length == 32 ? abi.decode(raw, (address)) : address(0);

        if (tokenOwner != broadcaster) {
            console2.log("!! POOL NOT PROTECTED - broadcaster is not the token owner");
            console2.log("   token        :", token);
            console2.log("   token owner  :", tokenOwner);
            console2.log("   pool to exempt:", pool);
            console2.log("   -> call setBlacklistProtection(pool, true) from the owner");
            return;
        }

        IBlacklistProtection(token).setBlacklistProtection(pool, true);
        console2.log("blacklist-exempt pool:", pool);
    }

    function _encodeSqrtPrice(uint256 amount1, uint256 amount0) internal pure returns (uint160) {
        require(amount0 > 0, "SetupPools: zero amount0");
        require(amount1 < (1 << 160), "SetupPools: amount1 too large to price safely");

        uint256 ratioX96 = (amount1 << 96) / amount0;
        uint256 root = _sqrt(ratioX96) << 48;
        require(root <= type(uint160).max, "SetupPools: price overflow");
        require(root > 0, "SetupPools: price rounds to zero");
        return uint160(root);
    }

    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    function _minUsableTick(int24 spacing) internal pure returns (int24) {
        return (MIN_TICK / spacing) * spacing;
    }

    function _maxUsableTick(int24 spacing) internal pure returns (int24) {
        return (MAX_TICK / spacing) * spacing;
    }
}
