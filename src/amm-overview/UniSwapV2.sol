// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IUniswapV2Factory} from "../amm-overview/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router02} from "../amm-overview/interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Helper} from "../amm-overview/interfaces/IUniswapV2Helper.sol";

contract UniswapV2Helper is IUniswapV2Helper, ReentrancyGuard {
    using SafeERC20 for IERC20;
    // mainnet address from notion
    address public constant FACTORY = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    // mainnet address from notion
    address public constant ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    uint256 public constant DEADLINE = 300;

    /// @notice Returns the pool address and the expected output amount
    /// @param tokenIn The address of the input token
    /// @param tokenOut The address of the output token
    /// @param amountIn The amount of input tokens
    function getPoolAndQuote(address tokenIn, address tokenOut, uint256 amountIn)
        external
        view
        override
        returns (address pool, uint256 quote)
    {
        pool = IUniswapV2Factory(FACTORY).getPair(tokenIn, tokenOut);
        if (pool == address(0)) {
            revert UNISWAP_V2_HELPER_PAIR_DOES_NOT_EXIST();
        }

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        uint256[] memory amounts = IUniswapV2Router02(ROUTER).getAmountsOut(amountIn, path);
        quote = amounts[1];
    }

    /// @notice Directly executes a swap from tokenIn to tokenOut
    /// @dev User must call approve() on the tokenIn contract for this contract first
    function executeSwap(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMin)
        external
        override
        nonReentrant
        returns (uint256[] memory amounts)
    {
        // IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        IERC20(tokenIn).approve(ROUTER, 0);
        IERC20(tokenIn).approve(ROUTER, amountIn);

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        amounts = IUniswapV2Router02(ROUTER)
            .swapExactTokensForTokens(amountIn, amountOutMin, path, msg.sender, block.timestamp + DEADLINE);
    }
}
