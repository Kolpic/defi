// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
// import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";
interface ITWAPPriceProvider {
    function getQuote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view returns (uint256 amountOut);

    function getAmountInForExactOut(
        address tokenIn,
        address tokenOut,
        uint256 amountOut
    ) external view returns (uint256 amountIn);
}

contract UniswapV3Swapper {
    using SafeERC20 for IERC20;

    // The address of the Uniswap V3 Router
    ISwapRouter public immutable swapRouter;

    // The address of the Uniswap V3 QuoterV2
    // IQuoterV2 public immutable quoter;

    // TWAP Price Provider
    ITWAPPriceProvider public immutable priceProvider;

    // Slippage tolerance in basis points. 50 = 0.5%
    uint256 public slippageTolerance;

    // Store contract owner to manage settings
    address public owner;

    event Swapped (
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    constructor(address _router, address _priceProvider) {
        swapRouter = ISwapRouter(_router);
        priceProvider = ITWAPPriceProvider(_priceProvider);
        owner = msg.sender;
        slippageTolerance = 50; // 0.5%
    }

    function swapExactInput (
        address[] calldata path,
        uint24[] calldata fees,
        uint256 amountIn
    ) external returns (uint256 amountOut) {
        require(path.length - 1 == fees.length, "Invalid path/fees");

        // Transfer the input token from the user to this contract
        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountIn);

        // Approve the router to send the input token
        IERC20(path[0]).forceApprove(address(swapRouter), amountIn);

        // encode the path for multi-hop swap
        bytes memory encodedPath = _encodePath(path, fees);

        // Use the quoter to get an estimate of the output amount
        uint256 expectedAmountOut = priceProvider.getQuote(
            path[0],
            path[path.length - 1],
            amountIn
        );

        // calculate minimum amount out considering slippage
        uint256 amountOutMinimum = expectedAmountOut - _calculateSlippage(expectedAmountOut);

        // prepare the parameters for the swap
        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: encodedPath,
            recipient: msg.sender,
            deadline: block.timestamp + 300, // 5 minutes deadline
            amountIn: amountIn,
            amountOutMinimum: amountOutMinimum
        });

        // Execute the swap
        amountOut = swapRouter.exactInput(params);

        emit Swapped(path[0], path[path.length - 1], amountIn, amountOut);
    }

    function swapExactOutput(
        address[] calldata path,
        uint24[] calldata fees,
        uint256 amountOut
    ) external returns (uint256 amountIn){
        require(path.length - 1 == fees.length, "Invalid path/fees");

        // encode the path for multi-hop swap
        bytes memory encodedPath = _encodePath(path,fees);

        uint256 expectedAmountIn = priceProvider.getAmountInForExactOut(
            path[0],
            path[path.length - 1],
            amountOut
        );

        // Calculate maximum amount in considering slippage
        uint256 amountInMaximum = expectedAmountIn + _calculateSlippage(expectedAmountIn);

        // Transfer the required input tokens from the user
        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountInMaximum);

        // Aprove the router to spend the input token
        IERC20(path[0]).forceApprove(address(swapRouter), amountInMaximum);

        // Prepare the parameters for the swap
        ISwapRouter.ExactOutputParams memory params = ISwapRouter
            .ExactOutputParams({
                path: encodedPath,
                recipient: msg.sender,
                deadline: block.timestamp + 300, // 5 minutes deadline
                amountOut: amountOut,
                amountInMaximum: amountInMaximum
            });
            
        // execute the swap
        amountIn = swapRouter.exactOutput(params);

        // refund any unsend input tokens
        if (amountIn < amountInMaximum) {
            IERC20(path[0]).safeTransfer(msg.sender, amountInMaximum - amountIn);
        }

        emit Swapped(path[0], path[path.length -1], amountIn, amountOut);
    }

    function setSlippage(uint256 _newSlippageTolerance) external {
        require(msg.sender == owner, "Not owner");
        slippageTolerance = _newSlippageTolerance;
    }

    function _encodePath(
        address[] calldata path,
        uint24[] calldata fees
    ) private pure returns (bytes memory) {
        bytes memory encodedPath = abi.encodePacked(path[0]);
        for (uint i = 0; i < fees.length; i++) {
            encodedPath = abi.encodePacked(
                encodedPath,
                fees[i],
                path[i + 1]
            );
        }
        return encodedPath;
    }

    function _calculateSlippage(uint256 amount) private view returns (uint256) {
        return (amount * slippageTolerance) / 10000;
    }
}