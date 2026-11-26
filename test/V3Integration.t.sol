// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {RapidEXFeeRouter, IRapidexSwapRouter} from "../src/RapidEXFeeRouter.sol";
import {WMSTC} from "../src/WMSTC.sol";

interface IFactory {
    function createPool(address, address, uint24) external returns (address);
    function getPool(address, address, uint24) external view returns (address);
    function feeAmountTickSpacing(uint24) external view returns (int24);
    function owner() external view returns (address);
    function setOwner(address) external;
}

interface IPool {
    function initialize(uint160) external;
    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool);
    function liquidity() external view returns (uint128);
    function fee() external view returns (uint24);
    function setFeeProtocol(uint8, uint8) external;
}

interface INPM {
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

    function createAndInitializePoolIfNecessary(address, address, uint24, uint160) external payable returns (address);
    function mint(MintParams calldata) external payable returns (uint256, uint128, uint256, uint256);
    function factory() external view returns (address);
    function WETH9() external view returns (address);
}

interface IQuoterV2 {
    struct QuoteExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint24 fee;
        uint160 sqrtPriceLimitX96;
    }

    function quoteExactInputSingle(QuoteExactInputSingleParams memory)
        external
        returns (uint256, uint160, uint32, uint256);
}

contract TestToken is ERC20 {
    constructor(string memory n) ERC20(n, n) {
        _mint(msg.sender, 1e30);
    }
}

contract V3IntegrationTest is Test {
    IFactory factory;
    INPM npm;
    IQuoterV2 quoter;
    address swapRouter;
    RapidEXFeeRouter feeRouter;
    WMSTC weth;

    TestToken tokenA;
    TestToken tokenB;
    address token0;
    address token1;

    address lp = address(this);
    address trader = address(0xBEEF);
    address feeRecipient = address(0xFEE);
    address owner = address(0xA11CE);

    uint24 constant FEE = 3000;
    uint256 constant FEE_BPS = 25;
    uint256 constant MAX_BPS = 100;

    function setUp() public {
        weth = new WMSTC();

        factory = IFactory(deployCode("RapiddexV3Factory.sol:RapiddexV3Factory"));
        address descriptor = address(0xDEAD);
        npm = INPM(
            deployCode(
                "NonfungiblePositionManager.sol:NonfungiblePositionManager",
                abi.encode(address(factory), address(weth), descriptor)
            )
        );
        swapRouter = deployCode("SwapRouter.sol:SwapRouter", abi.encode(address(factory), address(weth)));
        quoter = IQuoterV2(deployCode("QuoterV2.sol:QuoterV2", abi.encode(address(factory), address(weth))));
        feeRouter = new RapidEXFeeRouter(swapRouter, FEE_BPS, feeRecipient, owner);

        tokenA = new TestToken("A");
        tokenB = new TestToken("B");
        (token0, token1) =
            address(tokenA) < address(tokenB) ? (address(tokenA), address(tokenB)) : (address(tokenB), address(tokenA));
    }

    function test_poolInitCodeHashMatchesDeployedPool() public {
        address created = factory.createPool(token0, token1, FEE);
        assertTrue(created != address(0), "factory created a pool");

        address viaPeriphery = npm.createAndInitializePoolIfNecessary(token0, token1, FEE, _sqrtOneToOne());
        assertEq(viaPeriphery, created, "periphery computes the factory's actual pool address");
    }

    function test_peripheryWiredToCorrectFactoryAndWeth() public view {
        assertEq(npm.factory(), address(factory), "NPM points at our factory");
        assertEq(npm.WETH9(), address(weth), "NPM points at our wrapped native");
    }

    function test_enabledFeeTiers() public view {
        assertEq(factory.feeAmountTickSpacing(500), 10);
        assertEq(factory.feeAmountTickSpacing(3000), 60);
        assertEq(factory.feeAmountTickSpacing(10000), 200);
        assertEq(factory.feeAmountTickSpacing(100), 0, "0.01% tier is not enabled");
    }

    function test_duplicatePoolRejected() public {
        factory.createPool(token0, token1, FEE);
        vm.expectRevert();
        factory.createPool(token0, token1, FEE);
    }

    function test_endToEndSwapThroughFeeRouter() public {
        _createAndSeedPool();

        uint256 amountIn = 1e18;
        IERC20(token0).transfer(trader, amountIn);

        (uint256 quoted,,,) = quoter.quoteExactInputSingle(
            IQuoterV2.QuoteExactInputSingleParams({
                tokenIn: token0,
                tokenOut: token1,
                amountIn: amountIn - (amountIn * FEE_BPS) / 10_000,
                fee: FEE,
                sqrtPriceLimitX96: 0
            })
        );
        assertGt(quoted, 0, "quoter returns a price");

        vm.startPrank(trader);
        IERC20(token0).approve(address(feeRouter), amountIn);
        uint256 out = feeRouter.exactInputSingle(
            IRapidexSwapRouter.ExactInputSingleParams({
                tokenIn: token0,
                tokenOut: token1,
                fee: FEE,
                recipient: trader,
                deadline: block.timestamp + 1,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            }),
            MAX_BPS
        );
        vm.stopPrank();

        assertEq(out, quoted, "executed price matches the quote");
        assertEq(IERC20(token1).balanceOf(trader), out, "trader received output");
        assertEq(
            IERC20(token0).balanceOf(feeRecipient),
            (amountIn * FEE_BPS) / 10_000,
            "protocol fee collected on the input"
        );
    }

    function test_protocolFeeDoesNotTouchLpFee() public {
        address pool = _createAndSeedPool();
        uint256 amountIn = 1e18;

        IERC20(token0).transfer(trader, amountIn);
        vm.startPrank(trader);
        IERC20(token0).approve(address(feeRouter), amountIn);
        feeRouter.exactInputSingle(
            IRapidexSwapRouter.ExactInputSingleParams({
                tokenIn: token0,
                tokenOut: token1,
                fee: FEE,
                recipient: trader,
                deadline: block.timestamp + 1,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            }),
            MAX_BPS
        );
        vm.stopPrank();

        uint256 net = amountIn - (amountIn * FEE_BPS) / 10_000;
        assertEq(IERC20(token0).balanceOf(pool), 10e18 + net, "pool received the full post-fee input");
        assertEq(IPool(pool).fee(), FEE, "pool tier unchanged");
    }

    function test_poolProtocolFeeIsFractionOfLpFeeOnly() public {
        address pool = _createAndSeedPool();

        vm.prank(factory.owner());
        IPool(pool).setFeeProtocol(4, 4);

        vm.prank(factory.owner());
        vm.expectRevert();
        IPool(pool).setFeeProtocol(3, 3);
    }

    function test_onlyFactoryOwnerSetsProtocolFee() public {
        address pool = _createAndSeedPool();
        vm.prank(trader);
        vm.expectRevert();
        IPool(pool).setFeeProtocol(4, 4);
    }

    function test_uninitializedPoolCannotBeSwapped() public {
        address pool = factory.createPool(token0, token1, FEE);
        (uint160 sqrtPriceX96,,,,,,) = IPool(pool).slot0();
        assertEq(sqrtPriceX96, 0, "pool starts uninitialized");

        IERC20(token0).transfer(trader, 1e18);
        vm.startPrank(trader);
        IERC20(token0).approve(address(feeRouter), 1e18);
        vm.expectRevert();
        feeRouter.exactInputSingle(
            IRapidexSwapRouter.ExactInputSingleParams({
                tokenIn: token0,
                tokenOut: token1,
                fee: FEE,
                recipient: trader,
                deadline: block.timestamp + 1,
                amountIn: 1e18,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            }),
            MAX_BPS
        );
        vm.stopPrank();
    }

    function test_slippageGuardRevertsOnUnmetMinimum() public {
        _createAndSeedPool();
        uint256 amountIn = 1e18;
        IERC20(token0).transfer(trader, amountIn);

        vm.startPrank(trader);
        IERC20(token0).approve(address(feeRouter), amountIn);
        vm.expectRevert(bytes("Too little received"));
        feeRouter.exactInputSingle(
            IRapidexSwapRouter.ExactInputSingleParams({
                tokenIn: token0,
                tokenOut: token1,
                fee: FEE,
                recipient: trader,
                deadline: block.timestamp + 1,
                amountIn: amountIn,
                amountOutMinimum: 100e18,
                sqrtPriceLimitX96: 0
            }),
            MAX_BPS
        );
        vm.stopPrank();
    }

    function test_expiredDeadlineReverts() public {
        _createAndSeedPool();
        uint256 amountIn = 1e18;
        IERC20(token0).transfer(trader, amountIn);

        vm.warp(block.timestamp + 1000);
        vm.startPrank(trader);
        IERC20(token0).approve(address(feeRouter), amountIn);
        vm.expectRevert(bytes("Transaction too old"));
        feeRouter.exactInputSingle(
            IRapidexSwapRouter.ExactInputSingleParams({
                tokenIn: token0,
                tokenOut: token1,
                fee: FEE,
                recipient: trader,
                deadline: block.timestamp - 1,
                amountIn: amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            }),
            MAX_BPS
        );
        vm.stopPrank();
    }


    function _sqrtOneToOne() internal pure returns (uint160) {
        return 79228162514264337593543950336;
    }

    function _createAndSeedPool() internal returns (address pool) {
        pool = npm.createAndInitializePoolIfNecessary(token0, token1, FEE, _sqrtOneToOne());

        IERC20(token0).approve(address(npm), type(uint256).max);
        IERC20(token1).approve(address(npm), type(uint256).max);

        npm.mint(
            INPM.MintParams({
                token0: token0,
                token1: token1,
                fee: FEE,
                tickLower: -887220,
                tickUpper: 887220,
                amount0Desired: 10e18,
                amount1Desired: 10e18,
                amount0Min: 0,
                amount1Min: 0,
                recipient: lp,
                deadline: block.timestamp + 1
            })
        );
        assertGt(IPool(pool).liquidity(), 0, "pool seeded");
    }
}
