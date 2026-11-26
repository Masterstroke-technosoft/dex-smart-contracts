// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {RapidEXFeeRouter, IRapidexSwapRouter} from "../src/RapidEXFeeRouter.sol";

contract MockToken is ERC20 {
    uint8 private immutable _decimals;

    constructor(string memory n, string memory s, uint8 d) ERC20(n, s) {
        _decimals = d;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract FeeOnTransferToken is ERC20 {
    constructor() ERC20("FeeOnTransfer", "FOT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            uint256 burned = value / 100;
            super._update(from, address(0), burned);
            super._update(from, to, value - burned);
        } else {
            super._update(from, to, value);
        }
    }
}

contract MockSwapRouter {
    uint256 public lastAmountIn;
    address public lastRecipient;
    bytes public lastPath;

    function exactInputSingle(IRapidexSwapRouter.ExactInputSingleParams calldata p)
        external
        payable
        returns (uint256 amountOut)
    {
        lastAmountIn = p.amountIn;
        lastRecipient = p.recipient;
        IERC20(p.tokenIn).transferFrom(msg.sender, address(this), p.amountIn);
        amountOut = p.amountIn * 2;
        MockToken(p.tokenOut).mint(p.recipient, amountOut);
        require(amountOut >= p.amountOutMinimum, "slippage");
    }

    function exactInput(IRapidexSwapRouter.ExactInputParams calldata p)
        external
        payable
        returns (uint256 amountOut)
    {
        lastAmountIn = p.amountIn;
        lastRecipient = p.recipient;
        lastPath = p.path;
        address tokenIn = address(bytes20(p.path[:20]));
        address tokenOut = address(bytes20(p.path[p.path.length - 20:]));
        IERC20(tokenIn).transferFrom(msg.sender, address(this), p.amountIn);
        amountOut = p.amountIn * 2;
        MockToken(tokenOut).mint(p.recipient, amountOut);
        require(amountOut >= p.amountOutMinimum, "slippage");
    }
}

contract RapidEXFeeRouterTest is Test {
    RapidEXFeeRouter router;
    MockSwapRouter swapRouter;
    MockToken tokenIn;
    MockToken tokenOut;

    address owner = address(0xA11CE);
    address feeRecipient = address(0xFEE);
    address trader = address(0xB0B);

    uint256 constant FEE_BPS = 25;
    uint256 constant MAX_BPS = 100;
    uint256 constant AMOUNT = 1_000e18;

    function setUp() public {
        swapRouter = new MockSwapRouter();
        tokenIn = new MockToken("In", "IN", 18);
        tokenOut = new MockToken("Out", "OUT", 18);
        router = new RapidEXFeeRouter(address(swapRouter), FEE_BPS, feeRecipient, owner);

        tokenIn.mint(trader, AMOUNT * 10);
        vm.prank(trader);
        tokenIn.approve(address(router), type(uint256).max);
    }

    function _singleParams(uint256 amountIn, uint256 minOut)
        internal
        view
        returns (IRapidexSwapRouter.ExactInputSingleParams memory)
    {
        return IRapidexSwapRouter.ExactInputSingleParams({
            tokenIn: address(tokenIn),
            tokenOut: address(tokenOut),
            fee: 3000,
            recipient: trader,
            deadline: block.timestamp + 1,
            amountIn: amountIn,
            amountOutMinimum: minOut,
            sqrtPriceLimitX96: 0
        });
    }

    function test_takesExactly25Bps() public {
        vm.prank(trader);
        router.exactInputSingle(_singleParams(AMOUNT, 0), MAX_BPS);

        uint256 expectedFee = (AMOUNT * FEE_BPS) / 10_000;
        assertEq(expectedFee, 2.5e18, "fee is 2.5");
        assertEq(tokenIn.balanceOf(feeRecipient), expectedFee, "fee recipient paid");
        assertEq(swapRouter.lastAmountIn(), AMOUNT - expectedFee, "swap on net amount");
    }

    function test_outputGoesToTrader() public {
        vm.prank(trader);
        uint256 amountOut = router.exactInputSingle(_singleParams(AMOUNT, 0), MAX_BPS);

        assertEq(swapRouter.lastRecipient(), trader, "paid to trader");
        assertEq(tokenOut.balanceOf(trader), amountOut, "trader received output");
    }

    function test_routerKeepsNothing() public {
        vm.prank(trader);
        router.exactInputSingle(_singleParams(AMOUNT, 0), MAX_BPS);

        assertEq(tokenIn.balanceOf(address(router)), 0, "no input retained");
        assertEq(tokenOut.balanceOf(address(router)), 0, "no output retained");
        assertEq(tokenIn.allowance(address(router), address(swapRouter)), 0, "approval cleared");
    }

    function test_zeroFeeWhenDisabled() public {
        vm.prank(owner);
        router.setFeeConfig(0, address(0));

        vm.prank(trader);
        router.exactInputSingle(_singleParams(AMOUNT, 0), MAX_BPS);

        assertEq(tokenIn.balanceOf(feeRecipient), 0, "no fee taken");
        assertEq(swapRouter.lastAmountIn(), AMOUNT, "full amount swapped");
    }

    function testFuzz_feeNeverExceedsCap(uint256 amountIn) public {
        amountIn = bound(amountIn, 1e6, AMOUNT * 5);
        tokenIn.mint(trader, amountIn);

        vm.prank(trader);
        router.exactInputSingle(_singleParams(amountIn, 0), MAX_BPS);

        uint256 fee = tokenIn.balanceOf(feeRecipient);
        assertLe(fee * 10_000, amountIn * FEE_BPS, "fee within configured bps");
        assertEq(fee + swapRouter.lastAmountIn(), amountIn, "fee + swapped == input");
    }

    function test_slippageStillEnforcedAfterFee() public {
        vm.prank(trader);
        vm.expectRevert(bytes("slippage"));
        router.exactInputSingle(_singleParams(AMOUNT, 1996e18), MAX_BPS);
    }

    function test_revertsOnZeroAmount() public {
        vm.prank(trader);
        vm.expectRevert(RapidEXFeeRouter.AmountInZero.selector);
        router.exactInputSingle(_singleParams(0, 0), MAX_BPS);
    }

    function test_recipientCannotBeRouter() public {
        IRapidexSwapRouter.ExactInputSingleParams memory p = _singleParams(AMOUNT, 0);
        p.recipient = address(router);

        vm.prank(trader);
        router.exactInputSingle(p, MAX_BPS);

        assertEq(swapRouter.lastRecipient(), trader, "redirected to caller");
        assertEq(tokenOut.balanceOf(address(router)), 0, "nothing left in router");
    }

    function test_onlyOwnerSetsFee() public {
        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, trader));
        router.setFeeConfig(50, feeRecipient);
    }

    function test_feeCapEnforced() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(RapidEXFeeRouter.FeeTooHigh.selector, 101, FEE_BPS));
        router.setFeeConfig(101, feeRecipient);
    }

    function test_cannotSetNonZeroFeeWithoutRecipient() public {
        vm.prank(owner);
        vm.expectRevert(RapidEXFeeRouter.ZeroAddress.selector);
        router.setFeeConfig(25, address(0));
    }

    function test_constructorRejectsFeeAboveCap() public {
        vm.expectRevert(abi.encodeWithSelector(RapidEXFeeRouter.FeeTooHigh.selector, 500, 100));
        new RapidEXFeeRouter(address(swapRouter), 500, feeRecipient, owner);
    }

    function test_exactInputTakesFeeOnFirstToken() public {
        bytes memory path = abi.encodePacked(address(tokenIn), uint24(3000), address(tokenOut));

        vm.prank(trader);
        router.exactInput(
            IRapidexSwapRouter.ExactInputParams({
                path: path,
                recipient: trader,
                deadline: block.timestamp + 1,
                amountIn: AMOUNT,
                amountOutMinimum: 0
            }),
            address(tokenIn),
            MAX_BPS
        );

        assertEq(tokenIn.balanceOf(feeRecipient), (AMOUNT * FEE_BPS) / 10_000, "fee on path's first token");
    }

    function test_exactInputRejectsMismatchedTokenIn() public {
        bytes memory path = abi.encodePacked(address(tokenIn), uint24(3000), address(tokenOut));

        vm.prank(trader);
        vm.expectRevert(bytes("RapidEX: tokenIn mismatch"));
        router.exactInput(
            IRapidexSwapRouter.ExactInputParams({
                path: path,
                recipient: trader,
                deadline: block.timestamp + 1,
                amountIn: AMOUNT,
                amountOutMinimum: 0
            }),
            address(tokenOut),
            MAX_BPS
        );
    }

    function test_feeOnTransferTokenCannotOverApprove() public {
        FeeOnTransferToken fot = new FeeOnTransferToken();
        fot.mint(trader, AMOUNT);

        vm.startPrank(trader);
        fot.approve(address(router), type(uint256).max);

        IRapidexSwapRouter.ExactInputSingleParams memory p = _singleParams(AMOUNT, 0);
        p.tokenIn = address(fot);
        router.exactInputSingle(p, MAX_BPS);
        vm.stopPrank();

        assertEq(fot.balanceOf(address(router)), 0, "no residue");
        assertEq(fot.allowance(address(router), address(swapRouter)), 0, "approval cleared");
    }

    function test_rescueOnlyByOwner() public {
        tokenIn.mint(address(router), 1e18);

        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, trader));
        router.rescueToken(address(tokenIn), trader, 1e18);

        vm.prank(owner);
        router.rescueToken(address(tokenIn), owner, 1e18);
        assertEq(tokenIn.balanceOf(owner), 1e18, "owner recovered tokens");
    }


    function test_feeHikeCannotFrontrunAnInflightSwap() public {
        vm.prank(owner);
        router.queueFeeIncrease(100);
        vm.warp(block.timestamp + 2 days);
        router.applyFeeIncrease();
        assertEq(router.feeBps(), 100, "fee is now 1%");

        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(RapidEXFeeRouter.FeeExceedsCallerLimit.selector, 100, FEE_BPS));
        router.exactInputSingle(_singleParams(AMOUNT, 0), FEE_BPS);

        assertEq(tokenIn.balanceOf(feeRecipient), 0, "no fee extracted");
    }

    function test_swapSucceedsWhenFeeWithinCallerLimit() public {
        vm.prank(trader);
        router.exactInputSingle(_singleParams(AMOUNT, 0), FEE_BPS);
        assertEq(tokenIn.balanceOf(feeRecipient), (AMOUNT * FEE_BPS) / 10_000);
    }

    function test_feeIncreaseRequiresTimelock() public {
        vm.prank(owner);
        router.queueFeeIncrease(100);
        assertEq(router.feeBps(), FEE_BPS, "unchanged until applied");

        vm.expectRevert(
            abi.encodeWithSelector(RapidEXFeeRouter.TimelockNotElapsed.selector, block.timestamp + 2 days)
        );
        router.applyFeeIncrease();

        vm.warp(block.timestamp + 2 days);
        router.applyFeeIncrease();
        assertEq(router.feeBps(), 100, "applies after the delay");
    }

    function test_setFeeConfigCannotRaiseFee() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(RapidEXFeeRouter.FeeTooHigh.selector, 100, FEE_BPS));
        router.setFeeConfig(100, feeRecipient);
    }

    function test_feeDecreaseIsImmediate() public {
        vm.prank(owner);
        router.setFeeConfig(5, feeRecipient);
        assertEq(router.feeBps(), 5, "decrease applies at once");
    }

    function test_queuedIncreaseCanBeCancelled() public {
        vm.startPrank(owner);
        router.queueFeeIncrease(100);
        router.cancelFeeIncrease();
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);
        vm.expectRevert(RapidEXFeeRouter.NoPendingFeeIncrease.selector);
        router.applyFeeIncrease();
        assertEq(router.feeBps(), FEE_BPS, "fee untouched");
    }

    function test_onlyOwnerQueuesIncrease() public {
        vm.prank(trader);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, trader));
        router.queueFeeIncrease(100);
    }

    function test_renounceOwnershipDisabled() public {
        vm.prank(owner);
        vm.expectRevert(RapidEXFeeRouter.RenounceDisabled.selector);
        router.renounceOwnership();
    }

    function test_feeCanNeverExceedHardCap() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(RapidEXFeeRouter.FeeTooHigh.selector, 101, 100));
        router.queueFeeIncrease(101);
    }
}
