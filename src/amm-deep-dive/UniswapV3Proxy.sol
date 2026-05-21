// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IQuoterV2} from "./interfaces/IQuoterV2.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IUniswapV3Proxy} from "./interfaces/IUniswapV3Proxy.sol";

contract UniswapV3Proxy is IUniswapV3Proxy, ReentrancyGuard {
    using SafeERC20 for IERC20;

    ISwapRouter public immutable swapRouter;
    IQuoterV2 public immutable quoter;
    INonfungiblePositionManager public immutable posManager;
    IUniswapV3Factory public immutable factory;

    uint24[] public feeTiers = [500, 3000, 10000]; // 0.05%, 0.3%, 1%
    uint256 public constant DEFAULT_SLIPPAGE = 500; // 5% (basis points)
    uint256 public constant BPS_DENOMINATOR = 10000;

    mapping(address => uint256) public userSlippageTolerance; // In basis points
    mapping(address => UserRecord[]) public userHistory;

    constructor(address _router, address _posManager, address _factory, address _quoter) {
        swapRouter = ISwapRouter(_router);
        posManager = INonfungiblePositionManager(_posManager);
        factory = IUniswapV3Factory(_factory);
        quoter = IQuoterV2(_quoter);
    }

    function swapExactInputSingle(address tokenIn, address tokenOut, uint256 amountIn)
        external
        override
        nonReentrant
        returns (uint256 amountOut)
    {
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).forceApprove(address(swapRouter), amountIn);

        uint24 bestFee = _getBestPool(tokenIn, tokenOut);

        (uint256 expectedOut,,,) = quoter.quoteExactInputSingle(tokenIn, tokenOut, bestFee, amountIn, 0);
        uint256 minOut = (expectedOut * (BPS_DENOMINATOR - getSlippageTolerance(msg.sender))) / BPS_DENOMINATOR;

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: bestFee,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: minOut,
            sqrtPriceLimitX96: 0
        });

        amountOut = swapRouter.exactInputSingle(params);

        _logAction(ActionType.SWAP, tokenIn, tokenOut, amountIn, amountOut);
    }

    function swapExactOutputSingle(address tokenIn, address tokenOut, uint256 amountOut, uint256 amountInMaximum)
        external
        override
        nonReentrant
        returns (uint256 amountIn)
    {
        uint24 bestFee = _getBestPool(tokenIn, tokenOut);

        (uint256 expectedIn,,,) = quoter.quoteExactOutputSingle(tokenIn, tokenOut, bestFee, amountOut, 0);

        uint256 maxInWithSlippage =
            (expectedIn * (BPS_DENOMINATOR + getSlippageTolerance(msg.sender))) / BPS_DENOMINATOR;

        uint256 effectiveMaxIn = maxInWithSlippage < amountInMaximum ? maxInWithSlippage : amountInMaximum;

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), effectiveMaxIn);
        IERC20(tokenIn).forceApprove(address(swapRouter), effectiveMaxIn);

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: bestFee,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountOut: amountOut,
            amountInMaximum: effectiveMaxIn,
            sqrtPriceLimitX96: 0
        });

        amountIn = swapRouter.exactOutputSingle(params);

        // Refund excess tokenIn
        if (amountIn < amountInMaximum) {
            IERC20(tokenIn).safeTransfer(msg.sender, effectiveMaxIn - amountIn);
        }

        _logAction(ActionType.SWAP, tokenIn, tokenOut, amountIn, amountOut);
    }

    // --- Liquidity Operations ---

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint256 amountADesired,
        uint256 amountBDesired
    ) external override nonReentrant returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) {
        IERC20(tokenA).safeTransferFrom(msg.sender, address(this), amountADesired);
        IERC20(tokenB).safeTransferFrom(msg.sender, address(this), amountBDesired);

        IERC20(tokenA).forceApprove(address(posManager), amountADesired);
        IERC20(tokenB).forceApprove(address(posManager), amountBDesired);

        // Apply slippage to the minimum tokens accepted into the pool
        uint256 slippage = getSlippageTolerance(msg.sender);
        uint256 amount0Min = (amountADesired * (BPS_DENOMINATOR - slippage)) / BPS_DENOMINATOR;
        uint256 amount1Min = (amountBDesired * (BPS_DENOMINATOR - slippage)) / BPS_DENOMINATOR;

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: tokenA < tokenB ? tokenA : tokenB,
            token1: tokenA < tokenB ? tokenB : tokenA,
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: tokenA < tokenB ? amountADesired : amountBDesired,
            amount1Desired: tokenA < tokenB ? amountBDesired : amountADesired,
            amount0Min: tokenA < tokenB ? amount0Min : amount1Min,
            amount1Min: tokenA < tokenB ? amount1Min : amount0Min,
            recipient: msg.sender,
            deadline: block.timestamp
        });

        (tokenId, liquidity, amount0, amount1) = posManager.mint(params);
        _logAction(ActionType.ADD_LIQUIDITY, tokenA, tokenB, amount0, amount1);
    }

    function removeLiquidity(uint256 tokenId, uint128 liquidity)
        external
        override
        nonReentrant
        returns (uint256 amount0, uint256 amount1)
    {
        // Position NFT must be approved/sent to this contract first
        INonfungiblePositionManager.DecreaseLiquidityParams memory params =
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId, liquidity: liquidity, amount0Min: 0, amount1Min: 0, deadline: block.timestamp
            });

        (amount0, amount1) = posManager.decreaseLiquidity(params);
        _logAction(ActionType.REMOVE_LIQUIDITY, address(0), address(0), amount0, amount1);
    }

    function getUserHistory(address _user) external view override returns (UserRecord[] memory) {
        return userHistory[_user];
    }

    // --- Configuration ---

    function setSlippageTolerance(uint256 _bps) external override {
        if (_bps > 2000) {
            revert SlippageTooHigh(_bps);
        }
        userSlippageTolerance[msg.sender] = _bps;
        emit SlippageUpdated(msg.sender, _bps);
    }

    function getSlippageTolerance(address _user) public view override returns (uint256) {
        uint256 slippage = userSlippageTolerance[_user];
        return slippage == 0 ? DEFAULT_SLIPPAGE : slippage;
    }

    // --- Internal Helpers ---

    function _getBestPool(address tokenA, address tokenB) internal view returns (uint24 bestFee) {
        uint128 maxLiquidity = 0;
        bestFee = 3000; // Default to 0.3%

        for (uint256 i = 0; i < feeTiers.length; i++) {
            address poolAddress = factory.getPool(tokenA, tokenB, feeTiers[i]);
            if (poolAddress != address(0)) {
                uint128 poolLiquidity = IUniswapV3Pool(poolAddress).liquidity();
                if (poolLiquidity > maxLiquidity) {
                    maxLiquidity = poolLiquidity;
                    bestFee = feeTiers[i];
                }
            }
        }
    }

    function _logAction(ActionType action, address tIn, address tOut, uint256 aIn, uint256 aOut) internal {
        userHistory[msg.sender].push(
            UserRecord({
                action: action,
                tokenIn: tIn,
                tokenOut: tOut,
                amountIn: aIn,
                amountOut: aOut,
                timestamp: block.timestamp,
                blockNumber: block.number
            })
        );
        emit ActionLogged(msg.sender, action, aIn);
    }
}
