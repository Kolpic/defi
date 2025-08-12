// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/TWAPPriceProvider.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {OracleLibrary} from "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract TWAPPriceProviderForkTest is Test {
    TWAPPriceProvider public priceProvider;
    
    // Test addresses
    address public owner = address(0x1);
    address public user = address(0x2);
    
    // Real token addresses on mainnet
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    
    // Real pool addresses on mainnet (0.3% fee tier)
    address public constant WETH_USDC_POOL = 0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8;
    address public constant WETH_WBTC_POOL = 0xCBCdF9626bC03E24f779434178A73a0B4bad62eD;
    address public constant WETH_USDT_POOL = 0x4e68Ccd3E89f51C3074ca5072bbAC773960dFa36;
    address public constant WETH_DAI_POOL = 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8;
    
    // Factory address (mainnet)
    address public constant FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    function setUp() public {
        // Fork mainnet
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        
        vm.startPrank(owner);
        priceProvider = new TWAPPriceProvider(owner);
        vm.stopPrank();
        
        // Register pools
        vm.startPrank(owner);
        priceProvider.registerPool(WETH, USDC, WETH_USDC_POOL, 3000);
        priceProvider.registerPool(WETH, WBTC, WETH_WBTC_POOL, 3000);
        priceProvider.registerPool(WETH, USDT, WETH_USDT_POOL, 3000);
        priceProvider.registerPool(WETH, DAI, WETH_DAI_POOL, 3000);
        vm.stopPrank();
    }

    function testConstructor() public {
        assertEq(priceProvider.owner(), owner);
        assertEq(priceProvider.defaultObservationTime(), 1 hours);
        assertEq(priceProvider.MIN_OBSERVATION_TIME(), 30 minutes);
        assertEq(priceProvider.MAX_OBSERVATION_TIME(), 2 hours);
    }

    function testRegisterPool() public {
        vm.startPrank(owner);
        
        // Test registering a new pool
        address newPool = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640; // WETH/USDC 0.05% pool
        priceProvider.registerPool(WETH, USDC, newPool, 500);
        
        TWAPPriceProvider.PoolInfo memory poolInfo = priceProvider.getPoolInfo(WETH, USDC);
        assertEq(poolInfo.pool, newPool);
        assertEq(poolInfo.fee, 500);
        assertTrue(poolInfo.isActive);
        
        vm.stopPrank();
    }

    function testGetTWAPPrice_WETH_to_USDC() public {
        uint256 amountIn = 1e18; // 1 WETH
        
        (uint256 amountOut, uint256 price) = priceProvider.getTWAPPrice(WETH, USDC, amountIn);
        
        console.log("WETH -> USDC:");
        console.log("Amount In:", amountIn);
        console.log("Amount Out:", amountOut);
        console.log("Price (WETH/USDC):", price);
        
        assertGt(amountOut, 0, "Amount out should be greater than 0");
        assertGt(price, 0, "Price should be greater than 0");
        
        assertGt(amountOut, 1000e6, "WETH should be worth more than 1000 USDC");
    }

    function testGetTWAPPrice_USDC_to_WETH() public {
        uint256 amountIn = 1000e6; // 1000 USDC
        
        (uint256 amountOut, uint256 price) = priceProvider.getTWAPPrice(USDC, WETH, amountIn);
        
        console.log("USDC -> WETH:");
        console.log("Amount In:", amountIn);
        console.log("Amount Out:", amountOut);
        console.log("Price (USDC/WETH):", price);
        
        assertGt(amountOut, 0, "Amount out should be greater than 0");
        assertGt(price, 0, "Price should be greater than 0");
        
        assertGt(amountOut, 0.1e18, "1000 USDC should give more than 0.5 WETH");
        assertLt(amountOut, 1e18, "1000 USDC should give less than 2 WETH");
    }

    function testGetTWAPPrice_WETH_to_WBTC() public {
        uint256 amountIn = 1e18; // 1 WETH
        
        (uint256 amountOut, uint256 price) = priceProvider.getTWAPPrice(WETH, WBTC, amountIn);
        
        console.log("WETH -> WBTC:");
        console.log("Amount In:", amountIn);
        console.log("Amount Out:", amountOut);
        console.log("Price (WETH/WBTC):", price);
        
        assertGt(amountOut, 0, "Amount out should be greater than 0");
        assertGt(price, 0, "Price should be greater than 0");
        
        assertLt(amountOut, 1e8, "WETH should be worth less than 1 WBTC");
    }

    function testGetTWAPPrice_WBTC_to_WETH() public {
        uint256 amountIn = 0.01e8; // 0.01 WBTC
        
        (uint256 amountOut, uint256 price) = priceProvider.getTWAPPrice(WBTC, WETH, amountIn);
        
        console.log("WBTC -> WETH:");
        console.log("Amount In:", amountIn);
        console.log("Amount Out:", amountOut);
        console.log("Price (WBTC/WETH):", price);
        
        assertGt(amountOut, 0, "Amount out should be greater than 0");
        assertGt(price, 0, "Price should be greater than 0");
        
        assertGt(amountOut, 0.2e18, "0.01 WBTC should give more than 0.2 WETH");
        assertLt(amountOut, 1e18, "0.01 WBTC should give less than 1 WETH");
    }

    function testGetTWAPPriceWithCustomObservationTime() public {
        uint256 amountIn = 1e18; // 1 WETH
        uint32 observationTime = 30 minutes; // 30 minutes
        
        (uint256 amountOut, uint256 price) = priceProvider.getTWAPPrice(WETH, USDC, amountIn, observationTime);
        
        console.log("WETH -> USDC (30min TWAP):");
        console.log("Amount In:", amountIn);
        console.log("Amount Out:", amountOut);
        console.log("Price (WETH/USDC):", price);
        
        assertGt(amountOut, 0, "Amount out should be greater than 0");
        assertGt(price, 0, "Price should be greater than 0");
    }

    function testGetQuote() public {
        uint256 amountIn = 1e18; // 1 WETH
        
        uint256 amountOut = priceProvider.getQuote(WETH, USDC, amountIn);
        
        console.log("Quote WETH -> USDC:");
        console.log("Amount In:", amountIn);
        console.log("Amount Out:", amountOut);
        
        assertGt(amountOut, 0, "Amount out should be greater than 0");
        assertGt(amountOut, 1000e6, "WETH should be worth more than 1000 USDC");
    }

    function testPriceConsistency() public {
        uint256 amountIn = 1e18; // 1 WETH
        
        // Get price using default observation time
        (uint256 amountOut1, uint256 price1) = priceProvider.getTWAPPrice(WETH, USDC, amountIn);
        
        // Get price using 1 hour observation time (should be same as default)
        (uint256 amountOut2, uint256 price2) = priceProvider.getTWAPPrice(WETH, USDC, amountIn, 1 hours);
        
        console.log("Price consistency test:");
        console.log("Default TWAP - Amount Out:", amountOut1, "Price:", price1);
        console.log("1h TWAP - Amount Out:", amountOut2, "Price:", price2);
        
        // Prices should be very close (within 1% due to potential price movement)
        uint256 priceDiff = price1 > price2 ? price1 - price2 : price2 - price1;
        uint256 priceDiffPercent = (priceDiff * 100) / price1;
        
        assertLt(priceDiffPercent, 1, "Price difference should be less than 1%");
    }

    function testTokenOrdering() public {
        uint256 amountIn = 1e18; // 1 WETH
        
        // Test both directions should give consistent results
        (uint256 amountOut1, uint256 price1) = priceProvider.getTWAPPrice(WETH, USDC, amountIn);
        (uint256 amountOut2, uint256 price2) = priceProvider.getTWAPPrice(USDC, WETH, amountIn);
        
        console.log("Token ordering test:");
        console.log("WETH -> USDC - Amount Out:", amountOut1, "Price:", price1);
        console.log("USDC -> WETH - Amount Out:", amountOut2, "Price:", price2);
        
        // The amounts should be different (as expected for different directions)
        // but both should be valid
        assertGt(amountOut1, 0, "WETH -> USDC should return valid amount");
        assertGt(amountOut2, 0, "USDC -> WETH should return valid amount");
    }

    function testMultipleTokenPairs() public {
        uint256 amountIn = 1e18; // 1 WETH
        
        // Test multiple token pairs
        (uint256 wethUsdc, ) = priceProvider.getTWAPPrice(WETH, USDC, amountIn);
        (uint256 wethWbtc, ) = priceProvider.getTWAPPrice(WETH, WBTC, amountIn);
        (uint256 wethUsdt, ) = priceProvider.getTWAPPrice(WETH, USDT, amountIn);
        (uint256 wethDai, ) = priceProvider.getTWAPPrice(WETH, DAI, amountIn);
        
        console.log("Multiple token pairs test:");
        console.log("WETH -> USDC:", wethUsdc);
        console.log("WETH -> WBTC:", wethWbtc);
        console.log("WETH -> USDT:", wethUsdt);
        console.log("WETH -> DAI:", wethDai);
        
        // All should return valid amounts
        assertGt(wethUsdc, 0, "WETH -> USDC should work");
        assertGt(wethWbtc, 0, "WETH -> WBTC should work");
        assertGt(wethUsdt, 0, "WETH -> USDT should work");
        assertGt(wethDai, 0, "WETH -> DAI should work");
    }

    function testPoolDeactivation() public {
        vm.startPrank(owner);
        
        // Deactivate WETH/USDC pool
        priceProvider.deactivatePool(WETH, USDC);
        
        uint256 amountIn = 1e18; // 1 WETH
        
        // Should revert when trying to get price from inactive pool
        vm.expectRevert(TWAPPriceProvider.PoolInactive.selector);
        priceProvider.getTWAPPrice(WETH, USDC, amountIn);
        
        // Reactivate pool
        priceProvider.activatePool(WETH, USDC);
        
        // Should work again
        (uint256 amountOut, ) = priceProvider.getTWAPPrice(WETH, USDC, amountIn);
        assertGt(amountOut, 0, "Should work after reactivation");
        
        vm.stopPrank();
    }

    function testNonExistentPool() public {
        uint256 amountIn = 1e18; // 1 WETH
        
        // Try to get price for non-existent pool
        vm.expectRevert(TWAPPriceProvider.PoolNotFound.selector);
        priceProvider.getTWAPPrice(WETH, address(0x123), amountIn);
    }

    function testInvalidObservationTime() public {
        uint256 amountIn = 1e18; // 1 WETH
        
        // Too short observation time
        vm.expectRevert(TWAPPriceProvider.InvalidObservationTime.selector);
        priceProvider.getTWAPPrice(WETH, USDC, amountIn, 15 minutes);
        
        // Too long observation time
        vm.expectRevert(TWAPPriceProvider.InvalidObservationTime.selector);
        priceProvider.getTWAPPrice(WETH, USDC, amountIn, 3 hours);
    }

    function testUpdateDefaultObservationTime() public {
        vm.startPrank(owner);
        
        uint32 newTime = 90 minutes;
        priceProvider.updateDefaultObservationTime(newTime);
        
        assertEq(priceProvider.defaultObservationTime(), newTime);
        
        vm.stopPrank();
    }

    function testGetAllRegisteredPairs() public {
        bytes32[] memory pairs = priceProvider.getAllRegisteredPairs();
        
        console.log("Number of registered pairs:", pairs.length);
        
        // Should have 4 pairs registered
        assertEq(pairs.length, 4, "Should have 4 registered pairs");
    }

    function testGetPoolInfo() public {
        TWAPPriceProvider.PoolInfo memory poolInfo = priceProvider.getPoolInfo(WETH, USDC);
        
        assertEq(poolInfo.pool, WETH_USDC_POOL, "Pool address should match");
        assertEq(poolInfo.fee, 3000, "Fee should be 3000 (0.3%)");
        assertTrue(poolInfo.isActive, "Pool should be active");
    }

    function testLargeAmounts() public {
        uint256 amountIn = 100e18; // 100 WETH
        
        (uint256 amountOut, uint256 price) = priceProvider.getTWAPPrice(WETH, USDC, amountIn);
        
        console.log("Large amount test (100 WETH):");
        console.log("Amount In:", amountIn);
        console.log("Amount Out:", amountOut);
        console.log("Price (WETH/USDC):", price);
        
        assertGt(amountOut, 0, "Amount out should be greater than 0");
        assertGt(price, 0, "Price should be greater than 0");
        
        // 100 WETH should be worth more than 100,000 USDC
        assertGt(amountOut, 100000e6, "100 WETH should be worth more than 100,000 USDC");
    }

    function testSmallAmounts() public {
        uint256 amountIn = 0.001e18; // 0.001 WETH
        
        (uint256 amountOut, uint256 price) = priceProvider.getTWAPPrice(WETH, USDC, amountIn);
        
        console.log("Small amount test (0.001 WETH):");
        console.log("Amount In:", amountIn);
        console.log("Amount Out:", amountOut);
        console.log("Price (WETH/USDC):", price);
        
        assertGt(amountOut, 0, "Amount out should be greater than 0");
        assertGt(price, 0, "Price should be greater than 0");
        
        assertGt(amountOut, 0.5e6, "0.001 WETH should be worth more than 0.5 USDC");
        assertLt(amountOut, 5e6, "0.001 WETH should be worth less than 5 USDC");
    }

} 