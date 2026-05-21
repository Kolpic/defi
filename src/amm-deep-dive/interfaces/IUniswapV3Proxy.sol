// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IUniswapV3Proxy {
    // enums
    enum ActionType {
        SWAP,
        ADD_LIQUIDITY,
        REMOVE_LIQUIDITY
    }

    // struct
    struct UserRecord {
        ActionType action;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOut;
        uint256 timestamp;
        uint256 blockNumber;
    }

    // events
    event ActionLogged(address indexed user, ActionType action, uint256 amount);
    event SlippageUpdated(address indexed user, uint256 newSlippage);

    // errors
    error SlippageTooHigh(uint256 bps);

    // functions
    function swapExactInputSingle(address tokenIn, address tokenOut, uint256 amountIn)
        external
        returns (uint256 amountOut);
    function swapExactOutputSingle(address tokenIn, address tokenOut, uint256 amountOut, uint256 amountInMaximum)
        external
        returns (uint256 amountIn);
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint256 amountADesired,
        uint256 amountBDesired
    ) external returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    function removeLiquidity(uint256 tokenId, uint128 liquidity) external returns (uint256 amount0, uint256 amount1);
    function getUserHistory(address _user) external view returns (UserRecord[] memory);
    function setSlippageTolerance(uint256 _bps) external;
    function getSlippageTolerance(address _user) external view returns (uint256);
}
