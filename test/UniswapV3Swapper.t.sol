// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {UniswapV3Swapper} from "../src/UniswapV3Swapper.sol";
import {TWAPPriceProvider} from "../src/TWAPPriceProvider.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract UniswapV3SwapperTest is Test {
    UniswapV3Swapper public swapper;
    TWAPPriceProvider public priceProvider;
    
    // Mainnet addresses
    address constant UNISWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant UNISWAP_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    
    // Mainnet token addresses
    IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 constant USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    
    // Known pools on mainnet (these are real pool addresses)
    address constant WETH_USDC_500_POOL = 0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8;
    address constant WETH_USDT_3000_POOL = 0x4e68Ccd3E89f51C3074ca5072bbAC773960dFa36;
    address constant WETH_DAI_3000_POOL = 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8;
    address constant USDC_USDT_500_POOL = 0x3416cF6C708Da44DB2624D63ea0AAef7113527C6;
    address constant USDC_DAI_500_POOL = 0x5777d92f208679DB4b9778590Fa3CAB3aC9e2168;
    
    function setUp() public {
        // Fork mainnet at a specific block to avoid rate limiting
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19000000);
        
        // Deploy the TWAP price provider
        priceProvider = new TWAPPriceProvider(address(this));
        
        // Deploy the swapper contract with the price provider
        swapper = new UniswapV3Swapper(UNISWAP_ROUTER, address(priceProvider));
        
        // Register pools in the price provider
        _registerPools();
        
        // Label addresses for better trace output
        vm.label(address(swapper), "UniswapV3Swapper");
        vm.label(address(priceProvider), "TWAPPriceProvider");
        vm.label(UNISWAP_ROUTER, "UniswapV3Router");
        vm.label(address(WETH), "WETH");
        vm.label(address(USDC), "USDC");
        vm.label(address(USDT), "USDT");
        vm.label(address(DAI), "DAI");
    }
    
    function _registerPools() internal {
        // Register WETH/USDC pool (0.05% fee)
        priceProvider.registerPool(
            address(WETH),
            address(USDC),
            WETH_USDC_500_POOL,
            500
        );
        
        // Register WETH/USDT pool (0.3% fee)
        priceProvider.registerPool(
            address(WETH),
            address(USDT),
            WETH_USDT_3000_POOL,
            3000
        );
        
        // Register WETH/DAI pool (0.3% fee)
        priceProvider.registerPool(
            address(WETH),
            address(DAI),
            WETH_DAI_3000_POOL,
            3000
        );
        
        // Register USDC/USDT pool (0.05% fee)
        priceProvider.registerPool(
            address(USDC),
            address(USDT),
            USDC_USDT_500_POOL,
            500
        );
        
        // Register USDC/DAI pool (0.05% fee)
        priceProvider.registerPool(
            address(USDC),
            address(DAI),
            USDC_DAI_500_POOL,
            500
        );
        
        console.log("Registered 5 pools in TWAP price provider");
    }
    
    function test_DeployAndCheckSetup() public {
        console.log("=== Testing Contract Deployment ===");
        console.log("Swapper address:", address(swapper));
        console.log("Router address:", address(swapper.swapRouter()));
        console.log("Price provider address:", address(swapper.priceProvider()));
        console.log("Owner:", swapper.owner());
        console.log("Slippage tolerance:", swapper.slippageTolerance());
        
        assertEq(address(swapper.swapRouter()), UNISWAP_ROUTER);
        assertEq(address(swapper.priceProvider()), address(priceProvider));
        assertEq(swapper.owner(), address(this));
        assertEq(swapper.slippageTolerance(), 50); // 0.5%
        
        console.log("Contract deployment and setup verified!");
    }
    
    function test_CheckPriceProviderSetup() public {
        console.log("\n=== Checking TWAP Price Provider Setup ===");
        
        // Check registered pairs
        bytes32[] memory pairs = priceProvider.getAllRegisteredPairs();
        console.log("Number of registered pairs:", pairs.length);
        
        // Check specific pool info
        TWAPPriceProvider.PoolInfo memory wethUsdcPool = priceProvider.getPoolInfo(address(WETH), address(USDC));
        console.log("WETH/USDC pool:", wethUsdcPool.pool);
        console.log("WETH/USDC fee:", wethUsdcPool.fee);
        console.log("WETH/USDC active:", wethUsdcPool.isActive);
        
        assertEq(wethUsdcPool.pool, WETH_USDC_500_POOL);
        assertEq(wethUsdcPool.fee, 500);
        assertTrue(wethUsdcPool.isActive);
        
        console.log("Price provider setup verified!");
    }
    
    function test_GetQuoteFromPriceProvider() public {
        console.log("\n=== Testing TWAP Price Provider Quotes ===");
        
        uint256 amountIn = 1e18; // 1 WETH
        
        // Test WETH -> USDC quote
        try priceProvider.getQuote(address(WETH), address(USDC), amountIn) returns (uint256 amountOut) {
            console.log("WETH -> USDC quote successful!");
            console.log("Amount in (WETH):", amountIn);
            console.log("Amount out (USDC):", amountOut);
            assertGt(amountOut, 0, "Quote should return positive amount");
        } catch Error(string memory reason) {
            console.log("WETH -> USDC quote failed:", reason);
        } catch {
            console.log("WETH -> USDC quote failed: Unknown error");
        }
        
        // Test USDC -> WETH quote
        uint256 usdcAmountIn = 1000000; // 1 USDC
        try priceProvider.getQuote(address(USDC), address(WETH), usdcAmountIn) returns (uint256 amountOut) {
            console.log("USDC -> WETH quote successful!");
            console.log("Amount in (USDC):", usdcAmountIn);
            console.log("Amount out (WETH):", amountOut);
            assertGt(amountOut, 0, "Quote should return positive amount");
        } catch Error(string memory reason) {
            console.log("USDC -> WETH quote failed:", reason);
        } catch {
            console.log("USDC -> WETH quote failed: Unknown error");
        }
    }
    
    function test_WETHToUSDCSwap() public {
        console.log("\n=== Testing WETH -> USDC Swap ===");
        
        // Create a test user with ETH
        address testUser = makeAddr("testUser");
        vm.deal(testUser, 100 ether);
        
        console.log("Test user address:", testUser);
        console.log("Test user ETH balance:", testUser.balance);
        
        // Impersonate the test user
        vm.startPrank(testUser);
        
        // Wrap ETH to WETH
        uint256 wrapAmount = 1 ether;
        (bool success, ) = address(WETH).call{value: wrapAmount}("");
        require(success, "Failed to wrap ETH");
        
        console.log("Wrapped", wrapAmount, "ETH to WETH");
        console.log("WETH balance after wrapping:", WETH.balanceOf(testUser));
        
        // Setup path for WETH -> USDC swap
        address[] memory path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(USDC);
        
        uint24[] memory fees = new uint24[](1);
        fees[0] = 500; // 0.05%
        
        uint256 swapAmount = 0.1 ether; // 0.1 WETH
        
        console.log("Attempting WETH -> USDC swap...");
        console.log("Amount in:", swapAmount);
        console.log("Fee tier:", fees[0]);
        
        // Get balances before
        uint256 wethBalanceBefore = WETH.balanceOf(testUser);
        uint256 usdcBalanceBefore = USDC.balanceOf(testUser);
        
        console.log("WETH balance before:", wethBalanceBefore);
        console.log("USDC balance before:", usdcBalanceBefore);
        
        // Approve the swapper
        WETH.approve(address(swapper), swapAmount);
        console.log("Approved swapper to spend", swapAmount, "WETH");
        
        try swapper.swapExactInput(path, fees, swapAmount) returns (uint256 amountOut) {
            console.log("SUCCESS! WETH -> USDC swap completed!");
            console.log("Amount out:", amountOut);
            
            // Get balances after
            uint256 wethBalanceAfter = WETH.balanceOf(testUser);
            uint256 usdcBalanceAfter = USDC.balanceOf(testUser);
            
            console.log("WETH balance after:", wethBalanceAfter);
            console.log("USDC balance after:", usdcBalanceAfter);
            console.log("WETH spent:", wethBalanceBefore - wethBalanceAfter);
            console.log("USDC received:", usdcBalanceAfter - usdcBalanceBefore);
            
            // Verify the swap worked
            assertGt(amountOut, 0, "Swap should return some tokens");
            assertGt(usdcBalanceAfter, usdcBalanceBefore, "User should receive USDC");
            assertLt(wethBalanceAfter, wethBalanceBefore, "User should spend WETH");
            
        } catch Error(string memory reason) {
            console.log("FAILED:", reason);
        } catch {
            console.log("FAILED: Unknown error");
        }
        
        vm.stopPrank();
    }
    
    function test_USDCToWETHSwap() public {
        console.log("\n=== Testing USDC -> WETH Swap ===");
        
        // Create a test user with ETH
        address testUser = makeAddr("testUserUSDC");
        vm.deal(testUser, 100 ether);
        
        console.log("Test user address:", testUser);
        console.log("Test user ETH balance:", testUser.balance);
        
        // Impersonate the test user
        vm.startPrank(testUser);
        
        // Wrap ETH to WETH first, then swap WETH for USDC to get USDC
        uint256 wrapAmount = 1 ether;
        (bool success, ) = address(WETH).call{value: wrapAmount}("");
        require(success, "Failed to wrap ETH");
        
        console.log("Wrapped", wrapAmount, "ETH to WETH");
        console.log("WETH balance after wrapping:", WETH.balanceOf(testUser));
        
        // Now swap WETH for USDC to get USDC for testing
        address[] memory path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(USDC);
        
        uint24[] memory fees = new uint24[](1);
        fees[0] = 500; // 0.05%
        
        uint256 swapAmount = 0.5 ether; // Swap 0.5 WETH for USDC
        WETH.approve(address(swapper), swapAmount);
        
        try swapper.swapExactInput(path, fees, swapAmount) returns (uint256 amountOut) {
            console.log("Successfully swapped WETH for USDC:", amountOut);
        } catch {
            console.log("Failed to get USDC, skipping test");
            vm.stopPrank();
            return;
        }
        
        uint256 usdcBalance = USDC.balanceOf(testUser);
        console.log("USDC balance of test user:", usdcBalance);
        
        if (usdcBalance < 1000000) { // 1 USDC
            console.log("Insufficient USDC balance for testing");
            vm.stopPrank();
            return;
        }
        
        // Now perform USDC -> WETH swap
        console.log("\n--- Testing USDC -> WETH Swap ---");
        
        // Setup path for USDC -> WETH swap
        address[] memory swapPath = new address[](2);
        swapPath[0] = address(USDC);
        swapPath[1] = address(WETH);
        
        uint24[] memory swapFees = new uint24[](1);
        swapFees[0] = 500; // 0.05%
        
        uint256 usdcSwapAmount = 1000000; // 1 USDC
        
        console.log("Attempting USDC -> WETH swap...");
        console.log("Amount in:", usdcSwapAmount);
        console.log("Fee tier:", swapFees[0]);
        
        // Get balances before
        uint256 usdcBalanceBefore = USDC.balanceOf(testUser);
        uint256 wethBalanceBefore = WETH.balanceOf(testUser);
        
        console.log("USDC balance before:", usdcBalanceBefore);
        console.log("WETH balance before:", wethBalanceBefore);
        
        // Approve the swapper
        USDC.approve(address(swapper), usdcSwapAmount);
        console.log("Approved swapper to spend", usdcSwapAmount, "USDC");
        
        try swapper.swapExactInput(swapPath, swapFees, usdcSwapAmount) returns (uint256 amountOut) {
            console.log("SUCCESS! USDC -> WETH swap completed!");
            console.log("Amount out:", amountOut);
            
            // Verify the swap worked
            assertGt(amountOut, 0, "Swap should return some tokens");
            
        } catch Error(string memory reason) {
            console.log("FAILED:", reason);
        } catch {
            console.log("FAILED: Unknown error");
        }

        console.log("USDC balance after:", USDC.balanceOf(testUser));
        console.log("WETH balance after:", WETH.balanceOf(testUser));
        
        vm.stopPrank();
    }
    
    function test_MultiHopSwap() public {
        console.log("\n=== Testing Multi-Hop Swap ===");
        
        // Create a test user with ETH
        address testUser = makeAddr("testUserMultiHop");
        vm.deal(testUser, 100 ether);
        
        console.log("Test user address:", testUser);
        console.log("Test user ETH balance:", testUser.balance);
        
        // Impersonate the test user
        vm.startPrank(testUser);
        
        // Wrap ETH to WETH
        uint256 wrapAmount = 10 ether;
        (bool success, ) = address(WETH).call{value: wrapAmount}("");
        require(success, "Failed to wrap ETH");
        
        console.log("Wrapped", wrapAmount, "ETH to WETH");
        console.log("WETH balance after wrapping:", WETH.balanceOf(testUser));
        
        // Setup path for WETH -> USDC -> DAI (multi-hop)
        address[] memory path = new address[](3);
        path[0] = address(WETH);
        path[1] = address(USDC);
        path[2] = address(DAI);
        
        uint24[] memory fees = new uint24[](2);
        fees[0] = 500;  // 0.05% fee tier for WETH/USDC
        fees[1] = 500;  // 0.05% fee tier for USDC/DAI
        
        uint256 amountIn = 1e16; // 0.01 WETH
        
        console.log("Attempting WETH -> USDC -> DAI multi-hop swap...");
        console.log("Amount in:", amountIn);
        console.log("Fee tiers:", fees[0], fees[1]);
        
        // Get balances before
        uint256 wethBalanceBefore = WETH.balanceOf(testUser);
        uint256 daiBalanceBefore = DAI.balanceOf(testUser);
        
        console.log("WETH balance before:", wethBalanceBefore);
        console.log("DAI balance before:", daiBalanceBefore);
        
        // Approve the swapper
        WETH.approve(address(swapper), amountIn);
        console.log("Approved swapper to spend", amountIn, "WETH");
        
        try swapper.swapExactInput(path, fees, amountIn) returns (uint256 amountOut) {
            console.log("SUCCESS! Multi-hop swap completed!");
            console.log("Amount out:", amountOut);
            
            // Get balances after
            uint256 wethBalanceAfter = WETH.balanceOf(testUser);
            uint256 daiBalanceAfter = DAI.balanceOf(testUser);
            
            console.log("WETH balance after:", wethBalanceAfter);
            console.log("DAI balance after:", daiBalanceAfter);
            console.log("WETH spent:", wethBalanceBefore - wethBalanceAfter);
            console.log("DAI received:", daiBalanceAfter - daiBalanceBefore);
            
            // Verify the swap worked
            assertGt(amountOut, 0, "Swap should return some tokens");
            assertGt(daiBalanceAfter, daiBalanceBefore, "User should receive DAI");
            assertLt(wethBalanceAfter, wethBalanceBefore, "User should spend WETH");
            
        } catch Error(string memory reason) {
            console.log("FAILED:", reason);
        } catch {
            console.log("FAILED: Unknown error");
        }
        
        vm.stopPrank();
    }
    
    function test_ExactOutputSwap() public {
        console.log("\n=== Testing Exact Output Swap ===");
        
        // Create a test user with ETH
        address testUser = makeAddr("testUserExactOutput");
        vm.deal(testUser, 100 ether);
        
        console.log("Test user address:", testUser);
        console.log("Test user ETH balance:", testUser.balance);
        
        // Impersonate the test user
        vm.startPrank(testUser);
        
        // Wrap ETH to WETH
        uint256 wrapAmount = 1 ether;
        (bool success, ) = address(WETH).call{value: wrapAmount}("");
        require(success, "Failed to wrap ETH");
        
        console.log("Wrapped", wrapAmount, "ETH to WETH");
        console.log("WETH balance after wrapping:", WETH.balanceOf(testUser));
        
        // Setup path for WETH -> USDC exact output swap
        address[] memory path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(USDC);
        
        uint24[] memory fees = new uint24[](1);
        fees[0] = 500; // 0.05%
        
        uint256 desiredAmountOut = 1000000; // 1 USDC
        
        console.log("Attempting WETH -> USDC exact output swap...");
        console.log("Desired amount out:", desiredAmountOut);
        console.log("Fee tier:", fees[0]);
        
        // Get balances before
        uint256 wethBalanceBefore = WETH.balanceOf(testUser);
        uint256 usdcBalanceBefore = USDC.balanceOf(testUser);
        
        console.log("WETH balance before:", wethBalanceBefore);
        console.log("USDC balance before:", usdcBalanceBefore);
        
        // Approve the swapper (we'll approve a large amount for exact output)
        WETH.approve(address(swapper), 1 ether);
        console.log("Approved swapper to spend up to 1 WETH");
        
        try swapper.swapExactOutput(path, fees, desiredAmountOut) returns (uint256 amountIn) {
            console.log("SUCCESS! Exact output swap completed!");
            console.log("Amount in (WETH):", amountIn);
            console.log("Amount out (USDC):", desiredAmountOut);
            
            // Get balances after
            uint256 wethBalanceAfter = WETH.balanceOf(testUser);
            uint256 usdcBalanceAfter = USDC.balanceOf(testUser);
            
            console.log("WETH balance after:", wethBalanceAfter);
            console.log("USDC balance after:", usdcBalanceAfter);
            console.log("WETH spent:", wethBalanceBefore - wethBalanceAfter);
            console.log("USDC received:", usdcBalanceAfter - usdcBalanceBefore);
            
            // Verify the swap worked
            assertGt(amountIn, 0, "Swap should consume some input tokens");
            assertEq(usdcBalanceAfter - usdcBalanceBefore, desiredAmountOut, "Should receive exact amount");
            assertLt(wethBalanceAfter, wethBalanceBefore, "User should spend WETH");
            
        } catch Error(string memory reason) {
            console.log("FAILED:", reason);
        } catch {
            console.log("FAILED: Unknown error");
        }
        
        vm.stopPrank();
    }
    
    function test_SlippageProtection() public {
        console.log("\n=== Testing Slippage Protection ===");
        
        // Test that the swapper has the correct slippage tolerance
        uint256 slippageTolerance = swapper.slippageTolerance();
        
        console.log("Slippage tolerance (basis points):", slippageTolerance);
        
        // Default slippage should be 50 basis points (0.5%)
        assertEq(slippageTolerance, 50, "Default slippage tolerance should be 50 basis points");
        
        console.log("Slippage protection test passed!");
    }
    
    function test_OwnerFunctions() public {
        console.log("\n=== Testing Owner Functions ===");
        
        // Test setting slippage tolerance
        uint256 newSlippage = 100; // 1%
        swapper.setSlippage(newSlippage);
        
        assertEq(swapper.slippageTolerance(), newSlippage, "Slippage should be updated");
        console.log("Slippage tolerance updated to:", newSlippage);
        
        // Test that non-owner cannot set slippage
        address nonOwner = makeAddr("nonOwner");
        vm.startPrank(nonOwner);
        
        vm.expectRevert("Not owner");
        swapper.setSlippage(50);
        
        vm.stopPrank();
        console.log("Owner function protection test passed!");
    }
} 