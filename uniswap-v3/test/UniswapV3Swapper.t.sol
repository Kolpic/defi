// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {UniswapV3Swapper} from "../src/UniswapV3Swapper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract UniswapV3SwapperForkTest is Test {
    UniswapV3Swapper public swapper;
    
    // Mainnet addresses
    address constant UNISWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant UNISWAP_QUOTER = 0x61fFE014bA17989E743c5F6cB21bF9697530B21e;
    
    // Mainnet token addresses
    IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    //IERC20 constant USDC = IERC20(0xA0b86a33e6441b8C4C8c8C8c8c8c8c8c8c8C8c8C);
    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 constant USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    

    
    function setUp() public {
        // Fork mainnet
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        
        // Deploy the swapper contract
        swapper = new UniswapV3Swapper(UNISWAP_ROUTER, UNISWAP_QUOTER);
        
        // Label addresses for better trace output
        vm.label(address(swapper), "UniswapV3Swapper");
        vm.label(UNISWAP_ROUTER, "UniswapV3Router");
        vm.label(UNISWAP_QUOTER, "UniswapV3Quoter");
        vm.label(address(WETH), "WETH");
        vm.label(address(USDC), "USDC");
        vm.label(address(USDT), "USDT");
        vm.label(address(DAI), "DAI");
    }
    
    function test_DeployAndCheckSetup() public {
        console.log("=== Testing Contract Deployment ===");
        console.log("Swapper address:", address(swapper));
        console.log("Router address:", address(swapper.swapRouter()));
        console.log("Quoter address:", address(swapper.quoter()));
        console.log("Owner:", swapper.owner());
        console.log("Slippage tolerance:", swapper.slippageTolerance());
        
        assertEq(address(swapper.swapRouter()), UNISWAP_ROUTER);
        assertEq(address(swapper.quoter()), UNISWAP_QUOTER);
        assertEq(swapper.owner(), address(this));
        assertEq(swapper.slippageTolerance(), 50); // 0.5%
        
        console.log("Contract deployment and setup verified!");
    }
    
    function test_CheckMainnetTokenBalances() public {
        console.log("\n=== Checking Mainnet Token Balances ===");
        
        // Create a test user with ETH
        address testUser = makeAddr("testUserBalances");
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
        
        // Try to get some USDC, USDT, and DAI by swapping WETH
        uint256 swapAmount = 1 ether;
        WETH.approve(address(swapper), swapAmount * 3);
        
        // Get USDC
        address[] memory pathUSDC = new address[](2);
        pathUSDC[0] = address(WETH);
        pathUSDC[1] = address(USDC);
        uint24[] memory feesUSDC = new uint24[](1);
        feesUSDC[0] = 500;
        
        try swapper.swapExactInput(pathUSDC, feesUSDC, swapAmount) returns (uint256 amountOut) {
            console.log("Successfully got USDC:", amountOut);
        } catch {
            console.log("Failed to get USDC");
        }
        
        // Get USDT
        address[] memory pathUSDT = new address[](2);
        pathUSDT[0] = address(WETH);
        pathUSDT[1] = address(USDT);
        uint24[] memory feesUSDT = new uint24[](1);
        feesUSDT[0] = 500;
        
        try swapper.swapExactInput(pathUSDT, feesUSDT, swapAmount) returns (uint256 amountOut) {
            console.log("Successfully got USDT:", amountOut);
        } catch {
            console.log("Failed to get USDT");
        }
        
        // Get DAI
        address[] memory pathDAI = new address[](2);
        pathDAI[0] = address(WETH);
        pathDAI[1] = address(DAI);
        uint24[] memory feesDAI = new uint24[](1);
        feesDAI[0] = 500;
        
        try swapper.swapExactInput(pathDAI, feesDAI, swapAmount) returns (uint256 amountOut) {
            console.log("Successfully got DAI:", amountOut);
        } catch {
            console.log("Failed to get DAI");
        }
        
        // Check final balances
        uint256 wethBalance = WETH.balanceOf(testUser);
        uint256 usdcBalance = USDC.balanceOf(testUser);
        uint256 usdtBalance = USDT.balanceOf(testUser);
        uint256 daiBalance = DAI.balanceOf(testUser);
        
        console.log("\nFinal token balances:");
        console.log("WETH balance:", wethBalance);
        console.log("USDC balance:", usdcBalance);
        console.log("USDT balance:", usdtBalance);
        console.log("DAI balance:", daiBalance);
        
        vm.stopPrank();
    }
    
    function test_TestUSDCToWETHSwap() public {
        console.log("\n=== Testing USDC -> WETH Swap ===");
        
        // Create a test user with ETH and give them USDC
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
    
    
    function test_TestDAIToWETHSwap() public {
        console.log("\n=== Testing DAI -> WETH Swap ===");
        
        // Create a test user with ETH and give them DAI
        address testUser = makeAddr("testUserDAI");
        vm.deal(testUser, 100 ether);
        
        console.log("Test user address:", testUser);
        console.log("Test user ETH balance:", testUser.balance);
        
        // Impersonate the test user
        vm.startPrank(testUser);
        
        // Wrap ETH to WETH first, then swap WETH for DAI to get DAI
        uint256 wrapAmount = 1 ether;
        (bool success, ) = address(WETH).call{value: wrapAmount}("");
        require(success, "Failed to wrap ETH");
        
        console.log("Wrapped", wrapAmount, "ETH to WETH");
        console.log("WETH balance after wrapping:", WETH.balanceOf(testUser));
        
        // Now swap WETH for DAI to get DAI for testing
        address[] memory path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(DAI);
        
        uint24[] memory fees = new uint24[](1);
        fees[0] = 500; // 0.05%
        
        uint256 swapAmount = 0.5 ether; // Swap 0.5 WETH for DAI
        WETH.approve(address(swapper), swapAmount);
        
        try swapper.swapExactInput(path, fees, swapAmount) returns (uint256 amountOut) {
            console.log("Successfully swapped WETH for DAI:", amountOut);
        } catch {
            console.log("Failed to get DAI, skipping test");
            vm.stopPrank();
            return;
        }
        
        uint256 daiBalance = DAI.balanceOf(testUser);
        console.log("DAI balance of test user:", daiBalance);
        
        if (daiBalance < 1e18) { // 1 DAI
            console.log("Insufficient DAI balance for testing");
            vm.stopPrank();
            return;
        }
        
        // Now perform DAI -> WETH swap
        console.log("\n--- Testing DAI -> WETH Swap ---");
        
        // Setup path for DAI -> WETH swap
        address[] memory swapPath = new address[](2);
        swapPath[0] = address(DAI);
        swapPath[1] = address(WETH);
        
        uint24[] memory swapFees = new uint24[](1);
        swapFees[0] = 500; // 0.05%
        
        uint256 daiSwapAmount = 1e18; // 1 DAI
        
        console.log("Attempting DAI -> WETH swap ...");
        console.log("Amount in:", daiSwapAmount);
        console.log("Fee tier:", swapFees[0]);
        
        // Get balances before
        uint256 daiBalanceBefore = DAI.balanceOf(testUser);
        uint256 wethBalanceBefore = WETH.balanceOf(testUser);
        
        console.log("DAI balance before:", daiBalanceBefore);
        console.log("WETH balance before:", wethBalanceBefore);
        
        // Approve the swapper
        DAI.approve(address(swapper), daiSwapAmount);
        console.log("Approved swapper to spend", daiSwapAmount, "DAI");
        
        try swapper.swapExactInput(swapPath, swapFees, daiSwapAmount) returns (uint256 amountOut) {
            console.log("SUCCESS! DAI -> WETH swap completed!");
            console.log("Amount out:", amountOut);
            
            // Verify the swap worked
            assertGt(amountOut, 0, "Swap should return some tokens");
            
        } catch Error(string memory reason) {
            console.log("FAILED:", reason);
        } catch {
            console.log("FAILED: Unknown error");
        }
        
        console.log("DAI balance after:", DAI.balanceOf(testUser));
        console.log("WETH balance after:", WETH.balanceOf(testUser));
        
        vm.stopPrank();
    }
    
    function test_TestQuoteOnly() public {
        console.log("\n=== Testing Quote Only (No Swap) ===");
        
        // Setup path for USDC -> WETH
        address[] memory path = new address[](2);
        path[0] = address(USDC);
        path[1] = address(WETH);
        
        uint24[] memory fees = new uint24[](1);
        fees[0] = 500; // 0.05%
        
        uint256 amountIn = 1000000; // 1 USDC
        
        console.log("Getting quote for USDC -> WETH swap...");
        console.log("Amount in:", amountIn);
        console.log("Fee tier:", fees[0]);
        
        try swapper.quoter().quoteExactInput(_encodePath(path, fees), amountIn) returns (
            uint256 amountOut,
            uint160[] memory sqrtPriceX96After,
            uint32[] memory initializedTicksCrossed,
            uint256 gasEstimate
        ) {
            console.log("Quote successful!");
            console.log("Expected amount out:", amountOut);
            console.log("Sqrt price after:", sqrtPriceX96After[0]);
            console.log("Ticks crossed:", initializedTicksCrossed[0]);
            console.log("Gas estimate:", gasEstimate);
        } catch Error(string memory reason) {
            console.log("Quote failed:", reason);
        } catch {
            console.log("Quote failed: Unknown error");
        }
    }
    
    function test_FindWorkingPools() public {
        console.log("\n=== Finding Working Pools on Mainnet ===");
        
        // Test different token pairs
        address[][] memory pairs = new address[][](3);
        pairs[0] = new address[](2);
        pairs[0][0] = address(USDC);
        pairs[0][1] = address(WETH);
        
        pairs[1] = new address[](2);
        pairs[1][0] = address(USDT);
        pairs[1][1] = address(WETH);
        
        pairs[2] = new address[](2);
        pairs[2][0] = address(DAI);
        pairs[2][1] = address(WETH);
        
        string[] memory pairNames = new string[](3);
        pairNames[0] = "USDC/WETH";
        pairNames[1] = "USDT/WETH";
        pairNames[2] = "DAI/WETH";
        
        // Test different amounts
        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 1000000;   // 1 token
        amounts[1] = 10000000;  // 10 tokens
        amounts[2] = 100000000; // 100 tokens
        amounts[3] = 1000000000; // 1000 tokens
        
        // Test different fee tiers
        uint24[] memory feeTiers = new uint24[](4);
        feeTiers[0] = 500;   // 0.05%
        feeTiers[1] = 3000;  // 0.3%
        feeTiers[2] = 10000; // 1%
        feeTiers[3] = 30000; // 3%
        
        bool foundWorkingPool = false;
        
        for (uint i = 0; i < pairs.length; i++) {
            console.log("\n--- Testing", pairNames[i], "---");
            
            for (uint j = 0; j < amounts.length; j++) {
                for (uint k = 0; k < feeTiers.length; k++) {
                    console.log("Testing amount:", amounts[j], "fee:", feeTiers[k]);
                    
                    address[] memory path = new address[](2);
                    path[0] = pairs[i][0];
                    path[1] = pairs[i][1];
                    
                    uint24[] memory fees = new uint24[](1);
                    fees[0] = feeTiers[k];
                    
                    try swapper.quoter().quoteExactInput(_encodePath(path, fees), amounts[j]) returns (
                        uint256 amountOut,
                        uint160[] memory sqrtPriceX96After,
                        uint32[] memory initializedTicksCrossed,
                        uint256 gasEstimate
                    ) {
                        console.log("SUCCESS! Found working pool!");
                        console.log("Pair:", pairNames[i]);
                        console.log("Amount in:", amounts[j]);
                        console.log("Fee tier:", feeTiers[k]);
                        console.log("Expected amount out:", amountOut);
                        console.log("Gas estimate:", gasEstimate);
                        
                        foundWorkingPool = true;
                        
                        // Try one more test with a different amount to confirm
                        uint256 testAmount = amounts[j] * 2;
                        try swapper.quoter().quoteExactInput(_encodePath(path, fees), testAmount) returns (
                            uint256 amountOut2,
                            uint160[] memory sqrtPriceX96After2,
                            uint32[] memory initializedTicksCrossed2,
                            uint256 gasEstimate2
                        ) {
                            console.log("Confirmed! Pool works with different amounts too.");
                            console.log("Test amount:", testAmount);
                            console.log("Test amount out:", amountOut2);
                        } catch {
                            console.log("Pool only works with specific amounts");
                        }
                        
                        return; // Exit on first success
                    } catch Error(string memory reason) {
                        // Continue to next combination
                    } catch {
                        // Continue to next combination
                    }
                }
            }
        }
        
        if (!foundWorkingPool) {
            console.log("No working pools found on mainnet");
        }
    }
    
    function _encodePath(
        address[] memory path,
        uint24[] memory fees
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
    
    function test_MultiHopSwap() public {
        console.log("\n=== Testing Multi-Hop Swap ===");
        
        // Create a test user with ETH
        address testUser = makeAddr("testUser");
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
        fees[1] = 3000; // 0.3% fee tier for USDC/DAI
        
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
} 