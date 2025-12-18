// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";

/**
 * @title TWAPPriceProvider
 * @dev A contract that provides TWAP (Time-Weighted Average Price) quotes from Uniswap V3 pools
 * for predefined token pairs.
 */
contract TWAPPriceProvider is Ownable {
    // Struct to store pool information
    struct PoolInfo {
        address pool;
        uint24 fee;
        bool isActive;
    }

    // Mapping from token pair hash to pool info
    mapping(bytes32 => PoolInfo) public pools;

    // Array to track all registered pairs
    bytes32[] public registeredPairs;

    // Minimum observation time for TWAP calculation (30 minutes)
    uint32 public constant MIN_OBSERVATION_TIME = 30 minutes;

    // Maximum observation time for TWAP calculation (2 hours)
    uint32 public constant MAX_OBSERVATION_TIME = 2 hours;

    // Default observation time (1 hour)
    uint32 public defaultObservationTime = 1 hours;

    // Events
    event PoolRegistered(
        bytes32 indexed pairHash, address indexed token0, address indexed token1, address pool, uint24 fee
    );
    event PoolDeactivated(bytes32 indexed pairHash);
    event PoolActivated(bytes32 indexed pairHash);
    event DefaultObservationTimeUpdated(uint32 oldTime, uint32 newTime);

    error PoolNotFound();
    error PoolInactive();
    error InvalidObservationTime();
    error InvalidTokens();
    error ZeroAddress();

    /**
     * @dev Constructor
     * @param _owner The owner of the contract
     */
    constructor(address _owner) Ownable(_owner) {
        if (_owner == address(0)) revert ZeroAddress();
    }

    /**
     * @dev Register a new pool for a token pair
     * @param token0 First token address
     * @param token1 Second token address
     * @param pool Uniswap V3 pool address
     * @param fee Pool fee tier
     */
    function registerPool(address token0, address token1, address pool, uint24 fee) external onlyOwner {
        if (token0 == address(0) || token1 == address(0) || pool == address(0)) {
            revert ZeroAddress();
        }
        if (token0 == token1) revert InvalidTokens();

        bytes32 pairHash = _getPairHash(token0, token1);

        pools[pairHash] = PoolInfo({pool: pool, fee: fee, isActive: true});

        // Add to registered pairs if not already present
        bool exists = false;
        for (uint256 i = 0; i < registeredPairs.length; i++) {
            if (registeredPairs[i] == pairHash) {
                exists = true;
                break;
            }
        }
        if (!exists) {
            registeredPairs.push(pairHash);
        }

        emit PoolRegistered(pairHash, token0, token1, pool, fee);
    }

    /**
     * @dev Deactivate a pool
     * @param token0 First token address
     * @param token1 Second token address
     */
    function deactivatePool(address token0, address token1) external onlyOwner {
        bytes32 pairHash = _getPairHash(token0, token1);
        if (pools[pairHash].pool == address(0)) revert PoolNotFound();

        pools[pairHash].isActive = false;
        emit PoolDeactivated(pairHash);
    }

    /**
     * @dev Activate a pool
     * @param token0 First token address
     * @param token1 Second token address
     */
    function activatePool(address token0, address token1) external onlyOwner {
        bytes32 pairHash = _getPairHash(token0, token1);
        if (pools[pairHash].pool == address(0)) revert PoolNotFound();

        pools[pairHash].isActive = true;
        emit PoolActivated(pairHash);
    }

    /**
     * @dev Update the default observation time
     * @param newTime New observation time in seconds
     */
    function updateDefaultObservationTime(uint32 newTime) external onlyOwner {
        if (newTime < MIN_OBSERVATION_TIME || newTime > MAX_OBSERVATION_TIME) {
            revert InvalidObservationTime();
        }

        uint32 oldTime = defaultObservationTime;
        defaultObservationTime = newTime;
        emit DefaultObservationTimeUpdated(oldTime, newTime);
    }

    /**
     * @dev Get TWAP price for a token pair
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Amount of input tokens
     * @return amountOut Amount of output tokens
     * @return price Price of tokenIn in terms of tokenOut
     */
    function getTWAPPrice(address tokenIn, address tokenOut, uint256 amountIn)
        external
        view
        returns (uint256 amountOut, uint256 price)
    {
        return getTWAPPrice(tokenIn, tokenOut, amountIn, defaultObservationTime);
    }

    /**
     * @dev Get TWAP price for a token pair with custom observation time
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Amount of input tokens
     * @param observationTime Observation time for TWAP calculation
     * @return amountOut Amount of output tokens
     * @return price Price of tokenIn in terms of tokenOut
     */
    function getTWAPPrice(address tokenIn, address tokenOut, uint256 amountIn, uint32 observationTime)
        public
        view
        returns (uint256 amountOut, uint256 price)
    {
        if (observationTime < MIN_OBSERVATION_TIME || observationTime > MAX_OBSERVATION_TIME) {
            revert InvalidObservationTime();
        }

        bytes32 pairHash = _getPairHash(tokenIn, tokenOut);

        PoolInfo memory poolInfo = pools[pairHash];

        if (poolInfo.pool == address(0)) revert PoolNotFound();
        if (!poolInfo.isActive) revert PoolInactive();

        (int56 arithmeticMeanTick,) = OracleLibrary.consult(poolInfo.pool, observationTime);
        int24 averageTick = int24(arithmeticMeanTick);

        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(averageTick);

        // Calculate amount out based on current price
        amountOut = _getAmountOut(amountIn, tokenIn, tokenOut, sqrtPriceX96);

        // Calculate price (normalized to 18 decimals)
        uint256 scaledAmountIn = amountIn * (10 ** (18 - IERC20Metadata(tokenIn).decimals()));
        uint256 scaledAmountOut = amountOut * (10 ** (18 - IERC20Metadata(tokenOut).decimals()));
        if (scaledAmountIn == 0) {
            price = 0;
        } else {
            price = (scaledAmountOut * 1e18) / scaledAmountIn;
        }

        return (amountOut, price);
    }

    /**
     * @dev Gets the required input amount for a desired output amount based on the TWAP.
     * @param tokenIn The address of the input token.
     * @param tokenOut The address of the output token.
     * @param amountOut The desired amount of output tokens.
     * @return amountIn The calculated required amount of input tokens.
     */
    function getAmountInForExactOut(address tokenIn, address tokenOut, uint256 amountOut)
        external
        view
        returns (uint256 amountIn)
    {
        uint32 observationTime = defaultObservationTime;
        bytes32 pairHash = _getPairHash(tokenIn, tokenOut);
        PoolInfo memory poolInfo = pools[pairHash];

        if (poolInfo.pool == address(0)) revert PoolNotFound();
        if (!poolInfo.isActive) revert PoolInactive();

        (int56 arithmeticMeanTick,) = OracleLibrary.consult(poolInfo.pool, observationTime);
        int24 averageTick = int24(arithmeticMeanTick);

        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(averageTick);

        amountIn = _getAmountIn(amountOut, tokenIn, tokenOut, sqrtPriceX96);
    }

    /**
     * @dev Get quote for a swap (same as getTWAPPrice but returns only amountOut)
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Amount of input tokens
     * @return amountOut Amount of output tokens
     */
    function getQuote(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256 amountOut) {
        (amountOut,) = getTWAPPrice(tokenIn, tokenOut, amountIn, defaultObservationTime);
        return amountOut;
    }

    /**
     * @dev Get all registered pairs
     * @return pairs Array of pair hashes
     */
    function getAllRegisteredPairs() external view returns (bytes32[] memory) {
        return registeredPairs;
    }

    /**
     * @dev Get pool info for a token pair
     * @param token0 First token address
     * @param token1 Second token address
     * @return poolInfo Pool information
     */
    function getPoolInfo(address token0, address token1) external view returns (PoolInfo memory) {
        bytes32 pairHash = _getPairHash(token0, token1);
        return pools[pairHash];
    }

    /**
     * @dev Internal function to get pair hash
     * @param tokenA First token address
     * @param tokenB Second token address
     * @return pairHash Hash of the token pair
     */
    function _getPairHash(address tokenA, address tokenB) internal pure returns (bytes32) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return keccak256(abi.encodePacked(token0, token1));
    }

    /**
     * @dev Internal function to calculate the required input amount for a desired output amount.
     */
    function _getAmountIn(uint256 amountOut, address tokenIn, address tokenOut, uint160 sqrtPriceX96)
        internal
        view
        returns (uint256 amountIn)
    {
        require(amountOut > 0, "Amount must be greater than 0");
        require(sqrtPriceX96 > 0, "Invalid price");

        (address token0,) = tokenIn < tokenOut ? (tokenIn, tokenOut) : (tokenOut, tokenIn);
        uint8 decimalsIn = IERC20Metadata(tokenIn).decimals();
        uint8 decimalsOut = IERC20Metadata(tokenOut).decimals();

        // Normalize amountOut to 18 decimals for calculation
        uint256 amountOutScaled = amountOut * (10 ** (18 - decimalsOut));
        uint256 amountInScaled;

        if (tokenIn == token0) {
            // Swapping token0 for token1, need to find amountIn of token0
            // Reverse of token0 -> token1: amountIn = amountOut / price
            amountInScaled = (amountOutScaled << 192) / (uint256(sqrtPriceX96) * uint256(sqrtPriceX96));
        } else {
            // Swapping token1 for token0, need to find amountIn of token1
            // Reverse of token1 -> token0: amountIn = amountOut * price
            amountInScaled = (amountOutScaled * uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) >> 192;
        }

        // Scale the result back down to the correct number of decimals for the input token
        return amountInScaled / (10 ** (18 - decimalsIn));
    }

    function _getAmountOut(uint256 amountIn, address tokenIn, address tokenOut, uint160 sqrtPriceX96)
        internal
        view
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "Amount must be greater than 0");
        require(sqrtPriceX96 > 0, "Invalid price");

        (address token0,) = tokenIn < tokenOut ? (tokenIn, tokenOut) : (tokenOut, tokenIn);
        uint8 decimalsIn = IERC20Metadata(tokenIn).decimals();
        uint8 decimalsOut = IERC20Metadata(tokenOut).decimals();
        uint256 amountInScaled = amountIn * (10 ** (18 - decimalsIn));
        uint256 amountOutScaled;
        if (tokenIn == token0) {
            amountOutScaled = (amountInScaled * uint256(sqrtPriceX96) * uint256(sqrtPriceX96)) >> 192;
        } else {
            amountOutScaled = (amountInScaled << 192) / (uint256(sqrtPriceX96) * uint256(sqrtPriceX96));
        }
        return amountOutScaled / (10 ** (18 - decimalsOut));
    }
}
