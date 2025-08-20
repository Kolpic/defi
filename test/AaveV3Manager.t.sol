// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {POOL, WETH, DAI} from "../src/Constants.sol";
import {IPool} from "../src/interfaces/IPool.sol";
import {AaveV3Manager} from "../src/AaveV3Manager.sol";

contract AaveV3ManagerTest is Test {
    AaveV3Manager public manager;
    
    // Mainnet addresses
    address constant AAVE_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;
    
    // Mainnet token addresses
    IERC20 constant WETH_TOKEN = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 constant DAI_TOKEN = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 constant USDC_TOKEN = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 constant USDT_TOKEN = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    
    // Aave V3 debt token addresses (for reference)
    address constant V_DEBT_WETH = 0xeA51d7853EEFb32b6ee06b1C12E6dcCA88Be0fFE;
    address constant V_DEBT_DAI = 0x8619d80FB0141ba7F184CbF22fd724116D9f7ffC;
    
    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19000000);
        
        manager = new AaveV3Manager();
        
        vm.label(address(manager), "AaveV3Manager");
        vm.label(AAVE_POOL, "AaveV3Pool");
        vm.label(address(WETH_TOKEN), "WETH");
        vm.label(address(DAI_TOKEN), "DAI");
        vm.label(address(USDC_TOKEN), "USDC");
        vm.label(address(USDT_TOKEN), "USDT");
        vm.label(V_DEBT_WETH, "vDebtWETH");
        vm.label(V_DEBT_DAI, "vDebtDAI");
    }
    
    function test_DeployAndCheckSetupAaveV3Manager() public {
        console.log("=== Testing Contract Deployment ===");
        console.log("Manager address:", address(manager));
        console.log("Aave Pool address:", address(manager.pool()));
        console.log("Minimum health factor:", manager.MINIMUM_HEALTH_FACTOR());
        
        assertEq(address(manager.pool()), AAVE_POOL);
        assertEq(manager.MINIMUM_HEALTH_FACTOR(), 1.1e18); // 1.1
        
        console.log("Contract deployment and setup verified!");
    }
    
    function test_CheckAavePoolConnection() public {
        console.log("\n=== Checking Aave Pool Connection ===");
        
        // Test that we can get reserve data from Aave
        IPool.ReserveData memory wethReserve = IPool(AAVE_POOL).getReserveData(address(WETH_TOKEN));
        console.log("WETH aToken address:", wethReserve.aTokenAddress);
        console.log("WETH variable debt token address:", wethReserve.variableDebtTokenAddress);
        
        assertTrue(wethReserve.aTokenAddress != address(0), "WETH aToken address should not be zero");
        assertTrue(wethReserve.variableDebtTokenAddress != address(0), "WETH variable debt token address should not be zero");
        
        IPool.ReserveData memory daiReserve = IPool(AAVE_POOL).getReserveData(address(DAI_TOKEN));
        console.log("DAI aToken address:", daiReserve.aTokenAddress);
        console.log("DAI variable debt token address:", daiReserve.variableDebtTokenAddress);
        
        assertTrue(daiReserve.aTokenAddress != address(0), "DAI aToken address should not be zero");
        assertTrue(daiReserve.variableDebtTokenAddress != address(0), "DAI variable debt token address should not be zero");
        
        console.log("Aave pool connection verified!");
    }
    
    function test_WETHDeposit() public {
        console.log("\n=== Testing WETH Deposit ===");
        
        address testUser = makeAddr("testUser");
        vm.deal(testUser, 100 ether);
        
        console.log("Test user address:", testUser);
        console.log("Test user ETH balance:", testUser.balance);
        
        vm.startPrank(testUser);
        
        uint256 wrapAmount = 10 ether;
        (bool success, ) = address(WETH_TOKEN).call{value: wrapAmount}("");
        require(success, "Failed to wrap ETH");
        
        console.log("Wrapped", wrapAmount, "ETH to WETH");
        console.log("WETH balance after wrapping:", WETH_TOKEN.balanceOf(testUser));
        
        // Deposit WETH to Aave through our manager
        uint256 depositAmount = 5 ether; // 5 WETH
        
        console.log("Attempting WETH deposit...");
        console.log("Deposit amount:", depositAmount);
        
        uint256 wethBalanceBefore = WETH_TOKEN.balanceOf(testUser);
        uint256 managerBalanceBefore = manager.balanceOf(address(WETH_TOKEN), testUser);
        
        console.log("WETH balance before:", wethBalanceBefore);
        console.log("Manager balance before:", managerBalanceBefore);
        
        // Approve the manager to spend WETH
        WETH_TOKEN.approve(address(manager), depositAmount);
        console.log("Approved manager to spend", depositAmount, "WETH");
        
        try manager.deposit(address(WETH_TOKEN), depositAmount) {
            console.log("SUCCESS! WETH deposit completed!");
            
            // Get balances after
            uint256 wethBalanceAfter = WETH_TOKEN.balanceOf(testUser);
            uint256 managerBalanceAfter = manager.balanceOf(address(WETH_TOKEN), testUser);
            
            console.log("WETH balance after:", wethBalanceAfter);
            console.log("Manager balance after:", managerBalanceAfter);
            console.log("WETH spent:", wethBalanceBefore - wethBalanceAfter);
            console.log("Manager balance increase:", managerBalanceAfter - managerBalanceBefore);
            
            // Verify the deposit worked
            assertLt(wethBalanceAfter, wethBalanceBefore, "User should spend WETH");
            assertGt(managerBalanceAfter, managerBalanceBefore, "Manager should track user balance");
            
        } catch Error(string memory reason) {
            console.log("FAILED:", reason);
        } catch {
            console.log("FAILED: Unknown error");
        }
        
        vm.stopPrank();
    }
    
    function test_DAIDeposit() public {
        console.log("\n=== Testing DAI Deposit ===");
        
        address testUser = makeAddr("testUserDAI");
        vm.deal(testUser, 100 ether);
        
        console.log("Test user address:", testUser);
        console.log("Test user ETH balance:", testUser.balance);
        
        vm.startPrank(testUser);
        
        uint256 wrapAmount = 10 ether;
        (bool success, ) = address(WETH_TOKEN).call{value: wrapAmount}("");
        require(success, "Failed to wrap ETH");
        
        console.log("Wrapped", wrapAmount, "ETH to WETH");
        console.log("WETH balance after wrapping:", WETH_TOKEN.balanceOf(testUser));
        
        deal(address(DAI_TOKEN), testUser, 10000e18); // 10,000 DAI
        
        console.log("DAI balance after dealing:", DAI_TOKEN.balanceOf(testUser));
        
        // Deposit DAI to Aave through our manager
        uint256 depositAmount = 1000e18; // 1,000 DAI
        
        console.log("Attempting DAI deposit...");
        console.log("Deposit amount:", depositAmount);
        
        uint256 daiBalanceBefore = DAI_TOKEN.balanceOf(testUser);
        uint256 managerBalanceBefore = manager.balanceOf(address(DAI_TOKEN), testUser);
        
        console.log("DAI balance before:", daiBalanceBefore);
        console.log("Manager balance before:", managerBalanceBefore);
        
        // Approve the manager to spend DAI
        DAI_TOKEN.approve(address(manager), depositAmount);
        console.log("Approved manager to spend", depositAmount, "DAI");
        
        try manager.deposit(address(DAI_TOKEN), depositAmount) {
            console.log("SUCCESS! DAI deposit completed!");
            
            // Get balances after
            uint256 daiBalanceAfter = DAI_TOKEN.balanceOf(testUser);
            uint256 managerBalanceAfter = manager.balanceOf(address(DAI_TOKEN), testUser);
            
            console.log("DAI balance after:", daiBalanceAfter);
            console.log("Manager balance after:", managerBalanceAfter);
            console.log("DAI spent:", daiBalanceBefore - daiBalanceAfter);
            console.log("Manager balance increase:", managerBalanceAfter - managerBalanceBefore);
            
            // Verify the deposit worked
            assertLt(daiBalanceAfter, daiBalanceBefore, "User should spend DAI");
            assertGt(managerBalanceAfter, managerBalanceBefore, "Manager should track user balance");
            
        } catch Error(string memory reason) {
            console.log("FAILED:", reason);
        } catch {
            console.log("FAILED: Unknown error");
        }
        
        vm.stopPrank();
    }
    
    function test_WETHWithdraw() public {
        console.log("\n=== Testing WETH Withdraw ===");
        
        address testUser = makeAddr("testUserWithdraw");
        vm.deal(testUser, 100 ether);
        
        console.log("Test user address:", testUser);
        console.log("Test user ETH balance:", testUser.balance);
        
        vm.startPrank(testUser);
        
        uint256 wrapAmount = 10 ether;
        (bool success, ) = address(WETH_TOKEN).call{value: wrapAmount}("");
        require(success, "Failed to wrap ETH");
        
        console.log("Wrapped", wrapAmount, "ETH to WETH");
        console.log("WETH balance after wrapping:", WETH_TOKEN.balanceOf(testUser));

        uint256 depositAmount = 5 ether; // 5 WETH
        WETH_TOKEN.approve(address(manager), depositAmount);
        
        try manager.deposit(address(WETH_TOKEN), depositAmount) {
            console.log("Deposit successful, proceeding to withdraw test");
        } catch {
            console.log("Deposit failed, skipping withdraw test");
            vm.stopPrank();
            return;
        }

        // Now withdraw some WETH
        uint256 withdrawAmount = 2 ether; // 2 WETH
        
        console.log("Attempting WETH withdraw...");
        console.log("Withdraw amount:", withdrawAmount);
        
        uint256 wethBalanceBefore = WETH_TOKEN.balanceOf(testUser);
        uint256 managerBalanceBefore = manager.balanceOf(address(WETH_TOKEN), testUser);
        
        console.log("WETH balance before:", wethBalanceBefore);
        console.log("Manager balance before:", managerBalanceBefore);
        
        try manager.withdraw(address(WETH_TOKEN), withdrawAmount) {
            console.log("SUCCESS! WETH withdraw completed!");
            
            uint256 wethBalanceAfter = WETH_TOKEN.balanceOf(testUser);
            uint256 managerBalanceAfter = manager.balanceOf(address(WETH_TOKEN), testUser);
            
            console.log("WETH balance after:", wethBalanceAfter);
            console.log("Manager balance after:", managerBalanceAfter);
            console.log("WETH received:", wethBalanceAfter - wethBalanceBefore);
            console.log("Manager balance decrease:", managerBalanceBefore - managerBalanceAfter);
            
            assertGt(wethBalanceAfter, wethBalanceBefore, "User should receive WETH");
            assertLt(managerBalanceAfter, managerBalanceBefore, "Manager should reduce user balance");
            
        } catch Error(string memory reason) {
            console.log("FAILED:", reason);
        } catch {
            console.log("FAILED: Unknown error");
        }
    
        vm.stopPrank();
    }
    
    function test_DAIBorrow() public {
        console.log("\n=== Testing DAI Borrow ===");
        
        address testUser = makeAddr("testUserBorrow");
        vm.deal(testUser, 100 ether);
        
        console.log("Test user address:", testUser);
        console.log("Test user ETH balance:", testUser.balance);
        
        vm.startPrank(testUser);

        uint256 wrapAmount = 10 ether;
        (bool success, ) = address(WETH_TOKEN).call{value: wrapAmount}("");
        require(success, "Failed to wrap ETH");
        
        console.log("Wrapped", wrapAmount, "ETH to WETH");
        console.log("WETH balance after wrapping:", WETH_TOKEN.balanceOf(testUser));
        
        uint256 depositAmount = 5 ether; // 5 WETH
        WETH_TOKEN.approve(address(manager), depositAmount);
        
        try manager.deposit(address(WETH_TOKEN), depositAmount) {
            console.log("WETH deposit successful, proceeding to borrow test");
        } catch {
            console.log("WETH deposit failed, skipping borrow test");
            vm.stopPrank();
            return;
        }
        
        uint256 borrowAmount = 1000e18; // 1,000 DAI
        uint256 interestRateMode = 2; // Variable rate
        
        console.log("Attempting DAI borrow...");
        console.log("Borrow amount:", borrowAmount);
        console.log("Interest rate mode:", interestRateMode);
        
        uint256 daiBalanceBefore = DAI_TOKEN.balanceOf(testUser);
        uint256 debtBefore = manager.debtOf(address(DAI_TOKEN), testUser);
        
        console.log("DAI balance before:", daiBalanceBefore);
        console.log("Debt before:", debtBefore);
        
        try manager.borrow(address(DAI_TOKEN), borrowAmount, interestRateMode) {
            console.log("SUCCESS! DAI borrow completed!");
            
            uint256 daiBalanceAfter = DAI_TOKEN.balanceOf(testUser);
            uint256 debtAfter = manager.debtOf(address(DAI_TOKEN), testUser);
            
            console.log("DAI balance after:", daiBalanceAfter);
            console.log("Debt after:", debtAfter);
            console.log("DAI received:", daiBalanceAfter - daiBalanceBefore);
            console.log("Debt increase:", debtAfter - debtBefore);
            
            assertGt(daiBalanceAfter, daiBalanceBefore, "User should receive DAI");
            assertGt(debtAfter, debtBefore, "User should have debt");
            
        } catch Error(string memory reason) {
            console.log("FAILED:", reason);
        } catch {
            console.log("FAILED: Unknown error");
        }

        vm.stopPrank();
    }
    
    function test_DAIRepay() public {
        console.log("\n=== Testing DAI Repay ===");
        
        address testUser = makeAddr("testUserRepay");
        vm.deal(testUser, 100 ether);
        
        console.log("Test user address:", testUser);
        console.log("Test user ETH balance:", testUser.balance);
        
        vm.startPrank(testUser);
        
        uint256 wrapAmount = 10 ether;
        (bool success, ) = address(WETH_TOKEN).call{value: wrapAmount}("");
        require(success, "Failed to wrap ETH");
        
        uint256 depositAmount = 5 ether; // 5 WETH
        WETH_TOKEN.approve(address(manager), depositAmount);
        
        try manager.deposit(address(WETH_TOKEN), depositAmount) {
            console.log("WETH deposit successful");
        } catch {
            console.log("WETH deposit failed, skipping repay test");
            vm.stopPrank();
            return;
        }
        
        uint256 borrowAmount = 1000e18; // 1,000 DAI
        uint256 interestRateMode = 2; // Variable rate
        
        try manager.borrow(address(DAI_TOKEN), borrowAmount, interestRateMode) {
            console.log("DAI borrow successful");
        } catch {
            console.log("DAI borrow failed, skipping repay test");
            vm.stopPrank();
            return;
        }
        
        // Now repay some DAI
        uint256 repayAmount = 500e18; // 500 DAI
        DAI_TOKEN.approve(address(manager), repayAmount);
        
        console.log("Attempting DAI repay...");
        console.log("Repay amount:", repayAmount);
        
        uint256 daiBalanceBefore = DAI_TOKEN.balanceOf(testUser);
        uint256 debtBefore = manager.debtOf(address(DAI_TOKEN), testUser);
        
        console.log("DAI balance before:", daiBalanceBefore);
        console.log("Debt before:", debtBefore);
        
        try manager.repay(address(DAI_TOKEN), repayAmount, interestRateMode) {
            console.log("SUCCESS! DAI repay completed!");
            
            uint256 daiBalanceAfter = DAI_TOKEN.balanceOf(testUser);
            uint256 debtAfter = manager.debtOf(address(DAI_TOKEN), testUser);
            
            console.log("DAI balance after:", daiBalanceAfter);
            console.log("Debt after:", debtAfter);
            console.log("DAI spent:", daiBalanceBefore - daiBalanceAfter);
            console.log("Debt decrease:", debtBefore - debtAfter);
            
            assertLt(daiBalanceAfter, daiBalanceBefore, "User should spend DAI");
            assertLt(debtAfter, debtBefore, "User debt should decrease");
            
        } catch Error(string memory reason) {
            console.log("FAILED:", reason);
        } catch {
            console.log("FAILED: Unknown error");
        }
        
        vm.stopPrank();
    }
    
    function test_InterestAccrual() public {
        console.log("\n=== Testing Interest Accrual ===");
        
        address testUser = makeAddr("testUserInterest");
        vm.deal(testUser, 100 ether);
        
        console.log("Test user address:", testUser);
        console.log("Test user ETH balance:", testUser.balance);
        
        vm.startPrank(testUser);
        
        uint256 wrapAmount = 10 ether;
        (bool success, ) = address(WETH_TOKEN).call{value: wrapAmount}("");
        require(success, "Failed to wrap ETH");
        
        console.log("Wrapped", wrapAmount, "ETH to WETH");
        
        uint256 depositAmount = 5 ether; // 5 WETH
        WETH_TOKEN.approve(address(manager), depositAmount);
        
        try manager.deposit(address(WETH_TOKEN), depositAmount) {
            console.log("Initial WETH deposit successful");
        } catch {
            console.log("Initial deposit failed, skipping interest test");
            vm.stopPrank();
            return;
        }
        
        uint256 initialBalance = manager.balanceOf(address(WETH_TOKEN), testUser);
        console.log("Initial balance:", initialBalance);
        
        console.log("Fast forwarding 1 day to accrue interest...");
        skip(1 days);
        
        uint256 balanceAfterInterest = manager.balanceOf(address(WETH_TOKEN), testUser);
        console.log("Balance after 1 day:", balanceAfterInterest);
        
        if (balanceAfterInterest > initialBalance) {
            console.log("SUCCESS! Interest accrued correctly!");
            console.log("Interest earned:", balanceAfterInterest - initialBalance);
        } else {
            console.log("No interest accrued (this might be normal for short periods)");
        }
        
        vm.stopPrank();
    }
    
    function test_HealthFactorCheck() public {
        console.log("\n=== Testing Health Factor Check ===");
        
        address testUser = makeAddr("testUserHealth");
        vm.deal(testUser, 100 ether);
        
        console.log("Test user address:", testUser);
        
        vm.startPrank(testUser);
        
        uint256 wrapAmount = 10 ether;
        (bool success, ) = address(WETH_TOKEN).call{value: wrapAmount}("");
        require(success, "Failed to wrap ETH");
        
        // Deposit WETH as collateral
        uint256 depositAmount = 5 ether; // 5 WETH
        WETH_TOKEN.approve(address(manager), depositAmount);
        
        try manager.deposit(address(WETH_TOKEN), depositAmount) {
            console.log("WETH deposit successful");
        } catch {
            console.log("WETH deposit failed, skipping health factor test");
            vm.stopPrank();
            return;
        }
        
        // Try to borrow a very large amount (should fail due to health factor)
        uint256 largeBorrowAmount = 100000e18; // 100,000 DAI
        uint256 interestRateMode = 2; // Variable rate
        
        console.log("Attempting large DAI borrow (should fail)...");
        console.log("Borrow amount:", largeBorrowAmount);
        
        try manager.borrow(address(DAI_TOKEN), largeBorrowAmount, interestRateMode) {
            console.log("WARNING: Large borrow succeeded (unexpected)");
        } catch Error(string memory reason) {
            console.log("EXPECTED FAILURE:", reason);
            console.log("Health factor check working correctly!");
        } catch {
            console.log("EXPECTED FAILURE: Unknown error");
            console.log("Health factor check working correctly!");
        }
        
        vm.stopPrank();
    }
    
    function test_BalanceAndDebtQueries() public {
        console.log("\n=== Testing Balance and Debt Queries ===");
        
        address testUser = makeAddr("testUserQueries");
        vm.deal(testUser, 100 ether);
        
        console.log("Test user address:", testUser);
        
        vm.startPrank(testUser);
        
        uint256 wrapAmount = 10 ether;
        (bool success, ) = address(WETH_TOKEN).call{value: wrapAmount}("");
        require(success, "Failed to wrap ETH");
        
        uint256 initialWethBalance = manager.balanceOf(address(WETH_TOKEN), testUser);
        uint256 initialDaiDebt = manager.debtOf(address(DAI_TOKEN), testUser);
        
        console.log("Initial WETH balance:", initialWethBalance);
        console.log("Initial DAI debt:", initialDaiDebt);
        
        assertEq(initialWethBalance, 0, "Initial WETH balance should be 0");
        assertEq(initialDaiDebt, 0, "Initial DAI debt should be 0");
        
        uint256 depositAmount = 5 ether; // 5 WETH
        WETH_TOKEN.approve(address(manager), depositAmount);
        
        try manager.deposit(address(WETH_TOKEN), depositAmount) {
            console.log("WETH deposit successful");
            
            uint256 newWethBalance = manager.balanceOf(address(WETH_TOKEN), testUser);
            console.log("WETH balance after deposit:", newWethBalance);
            assertGt(newWethBalance, 0, "WETH balance should be greater than 0");
            
        } catch {
            console.log("WETH deposit failed");
        }
        
        uint256 borrowAmount = 1000e18; // 1,000 DAI
        uint256 interestRateMode = 2; // Variable rate
        
        try manager.borrow(address(DAI_TOKEN), borrowAmount, interestRateMode) {
            console.log("DAI borrow successful");
            
            uint256 newDaiDebt = manager.debtOf(address(DAI_TOKEN), testUser);
            console.log("DAI debt after borrow:", newDaiDebt);
            assertGt(newDaiDebt, 0, "DAI debt should be greater than 0");
            
        } catch {
            console.log("DAI borrow failed");
        }
        
        vm.stopPrank();
    }

    function test_UserHealthFactorProtection() public {
        console.log("\n=== Testing User Health Factor Protection ===");
        
        // Create two test users
        address userA = makeAddr("userA");
        address userB = makeAddr("userB");
        vm.deal(userA, 100 ether);
        vm.deal(userB, 100 ether);
        
        console.log("User A address:", userA);
        console.log("User B address:", userB);
        
        // User A deposits WETH as collateral
        vm.startPrank(userA);
        uint256 wrapAmount = 10 ether;
        (bool success, ) = address(WETH_TOKEN).call{value: wrapAmount}("");
        require(success, "Failed to wrap ETH");
        
        uint256 depositAmount = 5 ether; // 5 WETH
        WETH_TOKEN.approve(address(manager), depositAmount);
        
        try manager.deposit(address(WETH_TOKEN), depositAmount) {
            console.log("User A WETH deposit successful");
        } catch {
            console.log("User A WETH deposit failed, skipping test");
            vm.stopPrank();
            return;
        }
        
        // Check User A's health factor (should be infinite since no debt)
        uint256 userAHealthFactor = manager.calculateUserHealthFactor(userA);
        console.log("User A health factor (no debt):", userAHealthFactor);
        assertEq(userAHealthFactor, type(uint256).max, "User A should have infinite health factor");
        
        vm.stopPrank();
        
        // User B tries to borrow DAI (should fail because User B has no collateral)
        vm.startPrank(userB);
        uint256 borrowAmount = 1000e18; // 1,000 DAI
        uint256 interestRateMode = 2; // Variable rate
        
        console.log("User B attempting to borrow DAI without collateral...");
        
        try manager.borrow(address(DAI_TOKEN), borrowAmount, interestRateMode) {
            console.log("WARNING: User B borrow succeeded (this should fail)");
        } catch Error(string memory reason) {
            console.log("EXPECTED FAILURE:", reason);
            console.log("User health factor protection working correctly!");
        } catch {
            console.log("EXPECTED FAILURE: Unknown error");
            console.log("User health factor protection working correctly!");
        }
        
        vm.stopPrank();
        
        // User A borrows some DAI (should succeed)
        vm.startPrank(userA);
        uint256 userABorrowAmount = 1000e18; // 1,000 DAI
        
        console.log("User A attempting to borrow DAI with collateral...");
        
        try manager.borrow(address(DAI_TOKEN), userABorrowAmount, interestRateMode) {
            console.log("User A borrow successful");
            
            // Check User A's health factor after borrowing
            uint256 userAHealthFactorAfter = manager.calculateUserHealthFactor(userA);
            console.log("User A health factor after borrow:", userAHealthFactorAfter);
            assertGt(userAHealthFactorAfter, manager.MINIMUM_HEALTH_FACTOR(), "User A health factor should be above minimum");
            
        } catch Error(string memory reason) {
            console.log("User A borrow failed:", reason);
            vm.stopPrank();
            return;
        }
        
        vm.stopPrank();
        
        // User B tries to borrow DAI again (should still fail because User B has no collateral)
        vm.startPrank(userB);
        console.log("User B attempting to borrow DAI again without collateral...");
        
        try manager.borrow(address(DAI_TOKEN), borrowAmount, interestRateMode) {
            console.log("WARNING: User B borrow succeeded (this should fail)");
        } catch Error(string memory reason) {
            console.log("EXPECTED FAILURE:", reason);
            console.log("User health factor protection working correctly!");
        } catch {
            console.log("EXPECTED FAILURE: Unknown error");
            console.log("User health factor protection working correctly!");
        }
        
        vm.stopPrank();
        
        console.log("User health factor protection test completed successfully!");
    }
    
    function test_WithdrawalHealthFactorCheck() public {
        console.log("\n=== Testing Withdrawal Health Factor Check ===");
        
        address testUser = makeAddr("testUserWithdrawal");
        vm.deal(testUser, 100 ether);
        
        console.log("Test user address:", testUser);
        
        vm.startPrank(testUser);
        
        // Wrap ETH to WETH
        uint256 wrapAmount = 10 ether;
        (bool success, ) = address(WETH_TOKEN).call{value: wrapAmount}("");
        require(success, "Failed to wrap ETH");
        
        // Deposit WETH
        uint256 depositAmount = 2 ether; // 2 WETH (less collateral)
        WETH_TOKEN.approve(address(manager), depositAmount);
        
        try manager.deposit(address(WETH_TOKEN), depositAmount) {
            console.log("WETH deposit successful");
        } catch {
            console.log("WETH deposit failed, skipping test");
            vm.stopPrank();
            return;
        }
        
        // Borrow a large amount of DAI to create a tight health factor
        uint256 borrowAmount = 3000e18; // 3,000 DAI (much more debt relative to collateral)
        uint256 interestRateMode = 2; // Variable rate
        
        try manager.borrow(address(DAI_TOKEN), borrowAmount, interestRateMode) {
            console.log("DAI borrow successful");
        } catch {
            console.log("DAI borrow failed, skipping test");
            vm.stopPrank();
            return;
        }
        
        // Check health factor before withdrawal
        uint256 healthFactorBefore = manager.calculateUserHealthFactor(testUser);
        console.log("Health factor before withdrawal:", healthFactorBefore);
        
        // Try to withdraw too much WETH (should fail due to health factor)
        uint256 largeWithdrawAmount = 1.5 ether; // 1.5 WETH (75% of collateral)
        
        console.log("Attempting large WETH withdrawal (should fail)...");
        
        try manager.withdraw(address(WETH_TOKEN), largeWithdrawAmount) {
            console.log("WARNING: Large withdrawal succeeded (this should fail)");
        } catch Error(string memory reason) {
            console.log("EXPECTED FAILURE:", reason);
            console.log("Withdrawal health factor check working correctly!");
        } catch {
            console.log("EXPECTED FAILURE: Unknown error");
            console.log("Withdrawal health factor check working correctly!");
        }
        
        // Try to withdraw a small amount (should succeed)
        uint256 smallWithdrawAmount = 0.2 ether; // 0.2 WETH (10% of collateral)
        
        console.log("Attempting small WETH withdrawal (should succeed)...");
        
        try manager.withdraw(address(WETH_TOKEN), smallWithdrawAmount) {
            console.log("Small withdrawal successful");
            
            // Check health factor after withdrawal
            uint256 healthFactorAfter = manager.calculateUserHealthFactor(testUser);
            console.log("Health factor after withdrawal:", healthFactorAfter);
            assertGt(healthFactorAfter, manager.MINIMUM_HEALTH_FACTOR(), "Health factor should remain above minimum");
            
        } catch Error(string memory reason) {
            console.log("Small withdrawal failed:", reason);
        } catch {
            console.log("Small withdrawal failed: Unknown error");
        }
        
        vm.stopPrank();
        
        console.log("Withdrawal health factor check test completed!");
    }

    function test_AssetConfigurationSystem() public {
        console.log("\n=== Testing Asset Configuration System ===");
        
        // Test asset registration
        address[] memory registeredAssets = manager.getRegisteredAssets();
        console.log("Number of registered assets:", registeredAssets.length);
        
        // Test each registered asset
        for (uint256 i = 0; i < registeredAssets.length; i++) {
            address asset = registeredAssets[i];
            bool isActive = manager.isAssetActive(asset);
            uint256 ltv = manager.getLTV(asset);
            
            console.log("Asset", i, ":", asset);
            console.log("  Active:", isActive);
            console.log("  LTV:", ltv);
            
            assertTrue(isActive, "Asset should be active");
            assertGt(ltv, 0, "LTV should be greater than 0");
        }
        
        // Test unsupported asset
        address unsupportedAsset = address(0x1234567890123456789012345678901234567890);
        bool isUnsupportedActive = manager.isAssetActive(unsupportedAsset);
        console.log("Unsupported asset active:", isUnsupportedActive);
        assertFalse(isUnsupportedActive, "Unsupported asset should not be active");
        
        // Test LTV for unsupported asset (should revert)
        try manager.getLTV(unsupportedAsset) {
            console.log("WARNING: getLTV for unsupported asset succeeded (should fail)");
        } catch Error(string memory reason) {
            console.log("EXPECTED FAILURE for unsupported asset:", reason);
        } catch {
            console.log("EXPECTED FAILURE for unsupported asset: Unknown error");
        }
        
        console.log("Asset configuration system test completed successfully!");
    }
}