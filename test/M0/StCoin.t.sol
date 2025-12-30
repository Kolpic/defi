// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {StableCoin} from "../../src/M0/StableCoin.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MockMToken {
    uint256 public currentIndex = 1e12;
    mapping(address => uint256) public balances;

    function setCurrentIndex(uint256 _index) external {
        currentIndex = _index;
    }

    function getCurrentIndex() external view returns (uint256) {
        return currentIndex;
    }

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balances[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        balances[from] -= amount;
        balances[to] += amount;
        return true;
    }

    function startEarning() external {}
}

contract MockSwapFacility {
    // This satisfies the internal check in MExtension/MEarnerManager
    function msgSender() external view returns (address) {
        return msg.sender;
    }
}

contract StableCoinMockTest is Test {
    StableCoin public stableCoin;
    MockMToken public mockM;
    MockSwapFacility public mockSwap;

    address admin = makeAddr("admin");
    address earnerManager = makeAddr("earnerManager");
    address feeRecipient = makeAddr("feeRecipient");
    address clientA = makeAddr("clientA");
    address clientB = makeAddr("clientB");

    function setUp() public {
        mockM = new MockMToken();
        mockSwap = new MockSwapFacility();

        StableCoin implementation = new StableCoin(address(mockM), address(mockSwap));

        bytes memory initData = abi.encodeWithSelector(
            StableCoin.initialize.selector, "Kolpic coin", "KOL", admin, earnerManager, feeRecipient, makeAddr("pauser")
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        stableCoin = StableCoin(address(proxy));
    }

    function test_DifferentialFeesWithMockedYield() public {
        // Setup Clients AND the Earner contract itself
        vm.startPrank(earnerManager);
        stableCoin.setAccountInfo(address(stableCoin), true, 0);
        stableCoin.setAccountInfo(clientA, true, 500); // 5%
        stableCoin.setAccountInfo(clientB, true, 2000); // 20%
        stableCoin.enableEarning();
        vm.stopPrank();

        // Fund the MockSwapFacility so wrap doesn't underflow
        uint256 amount = 1_000_000 * 1e18;
        mockM.transfer(address(mockSwap), amount * 2); // Give tokens to the facility

        // Wrap tokens for clients
        vm.startPrank(address(mockSwap));
        stableCoin.wrap(clientA, amount);
        stableCoin.wrap(clientB, amount);
        vm.stopPrank();

        // Simulate Yield by increasing the Index
        mockM.setCurrentIndex(1.1e12); // 10% increase

        // Validate yields and differential fees
        (uint256 yieldA, uint256 feeA,) = stableCoin.accruedYieldAndFeeOf(clientA);
        (uint256 yieldB, uint256 feeB,) = stableCoin.accruedYieldAndFeeOf(clientB);

        assertEq(feeA, (yieldA * 500) / 10000, "Client A 5% fee mismatch");
        assertEq(feeB, (yieldB * 2000) / 10000, "Client B 20% fee mismatch");

        console.log("Client A Fee Paid:", feeA);
        console.log("Client B Fee Paid:", feeB);
    }

    function test_UserYieldComparison() public {
        // Setup tiers: Client A (5% fee), Client B (20% fee)
        vm.startPrank(earnerManager);
        stableCoin.setAccountInfo(address(stableCoin), true, 0);
        stableCoin.setAccountInfo(clientA, true, 500);
        stableCoin.setAccountInfo(clientB, true, 2000);
        stableCoin.enableEarning();
        vm.stopPrank();

        // Initial Deposit: 1,000,000 tokens each
        uint256 initialDeposit = 1_000_000 * 1e18;
        mockM.transfer(address(mockSwap), initialDeposit * 2);

        vm.startPrank(address(mockSwap));
        stableCoin.wrap(clientA, initialDeposit);
        stableCoin.wrap(clientB, initialDeposit);
        vm.stopPrank();

        // Simulate 10% Market Growth
        mockM.setCurrentIndex(1.1e12);

        // Observe the "Made" Yield (Net Yield)
        // clientA: 100k Gross - 5% (5k) Fee = 95k Net
        // clientB: 100k Gross - 20% (20k) Fee = 80k Net
        (,, uint256 netA) = stableCoin.accruedYieldAndFeeOf(clientA);
        (,, uint256 netB) = stableCoin.accruedYieldAndFeeOf(clientB);

        // Logs for visibility
        console.log("--- Growth Analysis ---");
        console.log("Initial Deposit:      ", initialDeposit / 1e18);
        console.log("Client A Made (Net):  ", netA / 1e18);
        console.log("Client B Made (Net):  ", netB / 1e18);

        // Assertions for the difference in "made" amounts
        assertEq(netA, 95_000 * 1e18, "Client A net growth mismatch");
        assertEq(netB, 80_000 * 1e18, "Client B net growth mismatch");

        // Verify that Client A made 15,000 more than Client B due to lower fees
        assertEq(netA - netB, 15_000 * 1e18, "Yield differential mismatch");
    }

    function test_VerifyDynamicYieldCalculation() public {
        // Setup users with different fees
        vm.startPrank(earnerManager);
        stableCoin.setAccountInfo(address(stableCoin), true, 0);
        stableCoin.setAccountInfo(clientA, true, 500); // 5% fee [cite: 46]
        stableCoin.setAccountInfo(clientB, true, 2000); // 20% fee [cite: 46]
        stableCoin.enableEarning();
        vm.stopPrank();

        // Wrap tokens (This sets the 'principal' for both)
        uint256 amount = 1_000_000 * 1e18;
        mockM.transfer(address(mockSwap), amount * 2);
        vm.startPrank(address(mockSwap));
        stableCoin.wrap(clientA, amount);
        stableCoin.wrap(clientB, amount);
        vm.stopPrank();

        // Change the Index (Market grows by 10%)
        mockM.setCurrentIndex(1.1e12);

        // Verify calculation without changing state
        // The rewards are calculated now, even though they aren't 'stored' yet
        (uint256 grossA, uint256 feeA, uint256 netA) = stableCoin.accruedYieldAndFeeOf(clientA);
        (uint256 grossB, uint256 feeB, uint256 netB) = stableCoin.accruedYieldAndFeeOf(clientB);

        // Client A: 100k gross - 5k fee = 95k net [cite: 52]
        assertEq(netA, 95_000 * 1e18);
        // Client B: 100k gross - 20k fee = 80k net [cite: 53]
        assertEq(netB, 80_000 * 1e18);

        console.log("Calculated Net Yield A:", netA);
        console.log("Calculated Net Yield B:", netB);

        // --- Verification ---
        // Gross Yield for 1M tokens at 10% growth = 100,000
        assertEq(grossA, 100_000 * 1e18, "Gross yield calculation mismatch");

        // Client A: 100k gross - 5k fee (5%) = 95k net
        assertEq(netA, 95_000 * 1e18, "Client A net yield mismatch");

        // Client B: 100k gross - 20k fee (20%) = 80k net
        assertEq(netB, 80_000 * 1e18, "Client B net yield mismatch");

        console.log("Dynamically Calculated Net Yield A:", netA / 1e18);
        console.log("Dynamically Calculated Net Yield B:", netB / 1e18);
    }

    function test_PrincipalCompoundingLifecycle() public {
        // Setup Client B with 20% fee
        vm.startPrank(earnerManager);
        stableCoin.setAccountInfo(address(stableCoin), true, 0);
        stableCoin.setAccountInfo(clientB, true, 2000); // 20%
        stableCoin.enableEarning();
        vm.stopPrank();

        // FIRST DEPOSIT: 1,000,000 tokens
        uint256 firstDeposit = 1_000_000 * 1e18;
        mockM.transfer(address(mockSwap), firstDeposit * 2);
        vm.startPrank(address(mockSwap));
        stableCoin.wrap(clientB, firstDeposit);

        console.log("--- Step 1: First Deposit ---");
        console.log("KOL Balance (Principal):", stableCoin.balanceOf(clientB) / 1e18);

        // TIME PASSES: Index grows by 10%
        mockM.setCurrentIndex(1.1e12);

        (,, uint256 netYield) = stableCoin.accruedYieldAndFeeOf(clientB);
        console.log("--- Step 2: Yield Accrued ---");
        console.log("Accrued Net Yield (Unrealized):", netYield / 1e18);

        // SECOND DEPOSIT: 100,000 tokens
        uint256 secondDeposit = 100_000 * 1e18;
        stableCoin.wrap(clientB, secondDeposit);
        vm.stopPrank();

        // FINAL STATE ANALYSIS
        uint256 finalBalance = stableCoin.balanceOf(clientB);
        (,, uint256 netAfterSecond) = stableCoin.accruedYieldAndFeeOf(clientB);

        // Total Value = Principal tokens + Accrued yield not yet withdrawn
        uint256 totalValue = finalBalance + netAfterSecond;

        console.log("--- Step 3: After Second Deposit ---");
        console.log("KOL Token Balance:      ", finalBalance / 1e18);
        console.log("Accrued Profit (Net):   ", netAfterSecond / 1e18);
        console.log("Total Account Value:    ", totalValue / 1e18);

        // Assertions
        assertEq(finalBalance, 1_100_000 * 1e18, "Balance tracks Principal only");
        assertEq(totalValue, 1_180_000 * 1e18, "Total Value includes the 80k Profit");
    }

    function test_UnwrapAndRealizeYield() public {
        // Setup tiers: Client B (20% fee)
        vm.startPrank(earnerManager);
        stableCoin.setAccountInfo(address(stableCoin), true, 0);
        stableCoin.setAccountInfo(clientB, true, 2000);
        stableCoin.setAccountInfo(address(mockSwap), true, 0);
        stableCoin.enableEarning();
        vm.stopPrank();

        // Wrap 1,000,000 tokens
        uint256 deposit1 = 1_000_000 * 1e18;
        mockM.transfer(address(mockSwap), 2_000_000 * 1e18);
        vm.prank(address(mockSwap));
        stableCoin.wrap(clientB, deposit1);

        // Market Growth (1.0 -> 1.1)
        mockM.setCurrentIndex(1.1e12);

        // Second Wrap (This triggers settlement of the 80k profit)
        uint256 deposit2 = 100_000 * 1e18;
        vm.prank(address(mockSwap));
        stableCoin.wrap(clientB, deposit2);

        // Provide the Contract with the Physical Yield Tokens
        mockM.transfer(address(stableCoin), 100_000 * 1e18); // 80k for user, 20k for protocol

        // Realized Exit Process
        uint256 amountToUnwrap = stableCoin.balanceOf(clientB); // 1.1M
        vm.prank(clientB);
        stableCoin.transfer(address(mockSwap), amountToUnwrap);

        // THE EXIT
        uint256 facilityMBefore = mockM.balanceOf(address(mockSwap));
        vm.startPrank(address(mockSwap));
        stableCoin.unwrap(clientB, amountToUnwrap);
        vm.stopPrank();

        // FINAL VERIFICATION
        uint256 facilityMAfter = mockM.balanceOf(address(mockSwap));
        uint256 principalReturned = facilityMAfter - facilityMBefore;

        // Check how much "Invisible" Net Yield is still owed to the user after the exit
        (,, uint256 netYieldStillOwed) = stableCoin.accruedYieldAndFeeOf(clientB);

        console.log("--- Realized Exit Summary ---");
        console.log("Principal Realized: ", principalReturned / 1e18);
        console.log("Profit Still in Contract: ", netYieldStillOwed / 1e18);
        console.log("Total User Value:   ", (principalReturned + netYieldStillOwed) / 1e18);

        // 1.1M Principal
        assertEq(principalReturned, 1_100_000 * 1e18, "Principal payout mismatch");
        // 80k Net Profit
        assertEq(netYieldStillOwed, 80_000 * 1e18, "Net profit calculation mismatch");
        // Total = 1.18M
        assertEq(principalReturned + netYieldStillOwed, 1_180_000 * 1e18, "Total value mismatch");
    }
}
