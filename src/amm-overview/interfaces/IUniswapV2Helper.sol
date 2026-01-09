// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IUniswapV2Helper {
    // events

    // errors
    error UNISWAP_V2_HELPER_PAIR_DOES_NOT_EXIST();

    // functions
    function getPoolAndQuote(address tokenIn, address tokenOut, uint256 amountIn)
        external
        view
        returns (address pool, uint256 quote);
    function executeSwap(address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMin)
        external
        returns (uint256[] memory amounts);
}
