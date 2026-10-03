// SPDX-License-Identifier: MIT
pragma solidity =0.8.27;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IRapidexSwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    function exactInputSingle(ExactInputSingleParams calldata params) external payable returns (uint256 amountOut);

    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);
}

contract RapidEXFeeRouter is Ownable2Step, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant MAX_FEE_BPS = 100;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    IRapidexSwapRouter public immutable swapRouter;

    uint256 public feeBps;
    address public feeRecipient;

    event FeeConfigUpdated(uint256 feeBps, address feeRecipient);
    event ProtocolFeeTaken(address indexed token, address indexed payer, uint256 amount);

    error ZeroAddress();
    error FeeTooHigh(uint256 feeBps, uint256 maxFeeBps);
    error AmountInZero();
    error FeeConsumesEntireInput();

    constructor(
        address swapRouter_,
        uint256 feeBps_,
        address feeRecipient_,
        address owner_
    ) Ownable(owner_) {
        if (swapRouter_ == address(0) || owner_ == address(0)) revert ZeroAddress();
        swapRouter = IRapidexSwapRouter(swapRouter_);
        _setFeeConfig(feeBps_, feeRecipient_);
    }

    function setFeeConfig(uint256 feeBps_, address feeRecipient_) external onlyOwner {
        _setFeeConfig(feeBps_, feeRecipient_);
    }

    function _setFeeConfig(uint256 feeBps_, address feeRecipient_) private {
        if (feeBps_ > MAX_FEE_BPS) revert FeeTooHigh(feeBps_, MAX_FEE_BPS);

        if (feeRecipient_ == address(0) && feeBps_ != 0) revert ZeroAddress();
        feeBps = feeBps_;
        feeRecipient = feeRecipient_;
        emit FeeConfigUpdated(feeBps_, feeRecipient_);
    }

    function quoteFee(uint256 amountIn) public view returns (uint256) {
        return (amountIn * feeBps) / BPS_DENOMINATOR;
    }

    function exactInputSingle(IRapidexSwapRouter.ExactInputSingleParams calldata params)
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        uint256 amountNet = _pullAndTakeFee(params.tokenIn, params.amountIn);

        IRapidexSwapRouter.ExactInputSingleParams memory p = params;
        p.amountIn = amountNet;

        p.recipient = params.recipient == address(this) ? msg.sender : params.recipient;

        _approveRouter(params.tokenIn, amountNet);
        amountOut = swapRouter.exactInputSingle(p);
        _clearApproval(params.tokenIn);
    }

    function exactInput(IRapidexSwapRouter.ExactInputParams calldata params, address tokenIn)
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        require(_firstTokenOf(params.path) == tokenIn, "RapidEX: tokenIn mismatch");

        uint256 amountNet = _pullAndTakeFee(tokenIn, params.amountIn);

        IRapidexSwapRouter.ExactInputParams memory p = params;
        p.amountIn = amountNet;
        p.recipient = params.recipient == address(this) ? msg.sender : params.recipient;

        _approveRouter(tokenIn, amountNet);
        amountOut = swapRouter.exactInput(p);
        _clearApproval(tokenIn);
    }

    function _pullAndTakeFee(address token, uint256 amountIn) private returns (uint256 amountNet) {
        if (amountIn == 0) revert AmountInZero();

        IERC20 erc20 = IERC20(token);
        uint256 balanceBefore = erc20.balanceOf(address(this));
        erc20.safeTransferFrom(msg.sender, address(this), amountIn);
        uint256 received = erc20.balanceOf(address(this)) - balanceBefore;

        uint256 fee = (received * feeBps) / BPS_DENOMINATOR;
        if (fee >= received) revert FeeConsumesEntireInput();

        if (fee > 0) {
            erc20.safeTransfer(feeRecipient, fee);
            emit ProtocolFeeTaken(token, msg.sender, fee);
        }

        amountNet = erc20.balanceOf(address(this)) - balanceBefore;
    }

    function _approveRouter(address token, uint256 amount) private {
        IERC20(token).forceApprove(address(swapRouter), amount);
    }

    function _clearApproval(address token) private {
        IERC20(token).forceApprove(address(swapRouter), 0);
    }

    function _firstTokenOf(bytes calldata path) private pure returns (address token) {
        require(path.length >= 20, "RapidEX: bad path");
        token = address(bytes20(path[:20]));
    }

    function rescueToken(address token, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        IERC20(token).safeTransfer(to, amount);
    }
}
