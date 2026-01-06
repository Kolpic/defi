// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console, stdStorage, StdStorage} from "forge-std/Test.sol";
import {StableCoin} from "../../src/M0/StableCoin.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract MockFacility {
    address public activeUser;

    // The test will set this before calling wrap
    function setActiveUser(address _user) external {
        activeUser = _user;
    }

    function msgSender() external view returns (address) {
        // Return the user we are acting for, not the Proxy address
        return activeUser;
    }
}

contract StableCoinForkTest is Test {
    StableCoin public stableCoin;
    using stdStorage for StdStorage;
    MockFacility public mockFacility;

    address constant M_TOKEN = 0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b;
    // address constant SWAP_FACILITY = 0xB6807116b3B1B321a390594e31ECD6e0076f6278;
    address constant SWAP_FACILITY = 0xacA92E438df0B2401fF60dA7E4337B687a2435DA;
    address constant M_REGISTRAR = 0x119FbeeDD4F4f4298Fb59B720d5654442b81ae2c;

    address admin = makeAddr("admin");
    address earnerManager = makeAddr("earnerManager");
    address feeRecipient = makeAddr("feeRecipient");
    address pauser = makeAddr("pauser");
    address client = makeAddr("client");

    address clientA = makeAddr("clientA");
    address clientB = makeAddr("clientB");

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

        mockFacility = new MockFacility();

        StableCoin implementation = new StableCoin(M_TOKEN, address(mockFacility));

        bytes memory initData = abi.encodeWithSelector(
            StableCoin.initialize.selector, "Kolpic coin", "KOL", admin, earnerManager, feeRecipient, pauser
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        stableCoin = StableCoin(address(proxy));

        _approveEarner(address(proxy));
    }

    function testTokenDecimals() public {
        vm.startPrank(earnerManager);
        console.log("-- M_Token decimals -- ", IERC20Metadata(M_TOKEN).decimals());
        assertEq(IERC20Metadata(M_TOKEN).decimals(), 6);
        console.log("-- StableCoin decimals --", stableCoin.decimals());
        assertEq(stableCoin.decimals(), 6);
        vm.stopPrank();
    }

    function testWhitelistingAndFees() public {
        vm.startPrank(earnerManager);

        uint16 feeRateBps = 500; // 5% fee
        stableCoin.setAccountInfo(client, true, feeRateBps);

        assertTrue(stableCoin.isWhitelisted(client), "Client should be whitelisted");
        assertEq(stableCoin.feeRateOf(client), feeRateBps, "Fee rate mismatch");

        vm.stopPrank();
    }

    function test_RevertWhen_UnauthorizedWhitelisting() public {
        vm.expectRevert();
        vm.prank(address(0xdead));
        stableCoin.setAccountInfo(client, true, 500);
    }

    function testYieldFlow() public {
        vm.prank(earnerManager);
        stableCoin.setAccountInfo(client, true, 1000);

        stableCoin.enableEarning();

        vm.warp(block.timestamp + 30 days);
        vm.roll(block.number + (30 days / 12)); // Roll blocks too for accuracy

        (uint256 yieldWithFee, uint256 fee, uint256 netYield) = stableCoin.accruedYieldAndFeeOf(client);

        console.log("Yield with Fee:", yieldWithFee);
        console.log("Fee taken by Protocol:", fee);
        console.log("Net Yield for Client:", netYield);

        if (yieldWithFee > 0) {
            assertEq(fee, (yieldWithFee * 1000) / 10000, "Fee should be 10%");
        }
    }

    function test_UpdateFeeMidWay() public {
        vm.startPrank(earnerManager);
        stableCoin.setAccountInfo(clientA, true, 1000); // Start at 10%

        // Accrue some yield
        vm.warp(block.timestamp + 10 days);

        // Change fee to 50%
        stableCoin.setAccountInfo(clientA, true, 5000);
        vm.stopPrank();

        (, uint256 fee,) = stableCoin.accruedYieldAndFeeOf(clientA);

        // The M0 model usually calculates fee based on the *current* rate
        // stored in the mapping at the time of the check/settlement.
        assertEq(stableCoin.feeRateOf(clientA), 5000);
    }

    function test_DifferentialFeesMultipleUsers() public {
        address facilityAddr = address(mockFacility);

        uint16 feeA = 500; // 5%
        uint16 feeB = 2500; // 25%
        uint16 feeC = 0; // 0%

        vm.startPrank(earnerManager);
        stableCoin.setAccountInfo(clientA, true, feeA);
        stableCoin.setAccountInfo(clientB, true, feeB);
        stableCoin.setAccountInfo(client, true, feeC);
        stableCoin.setAccountInfo(facilityAddr, true, 0);
        stableCoin.enableEarning();
        vm.stopPrank();

        // Use Minter Gateway to Mint Tokens
        // Address found in M0 Docs for Mainnet -> https://docs.m0.org/get-started/resources/addresses/
        address minterGateway = 0xf7f9638cb444D65e5A40bF5ff98ebE4ff319F04E;
        uint256 tokensToMint = 300_000 * 1e6;

        vm.prank(minterGateway);
        (bool success,) = M_TOKEN.call(abi.encodeWithSignature("mint(address,uint256)", facilityAddr, tokensToMint));
        require(success, "M0 Minting failed");

        // Wrap tokens for each client
        uint256 perClientWrap = 100_000 * 1e6;

        vm.startPrank(facilityAddr);
        IERC20(M_TOKEN).approve(address(stableCoin), tokensToMint);

        // Wrap for Client A
        mockFacility.setActiveUser(clientA);
        stableCoin.wrap(clientA, perClientWrap);

        // Wrap for Client B
        mockFacility.setActiveUser(clientB);
        stableCoin.wrap(clientB, perClientWrap);

        // Wrap for Client C
        mockFacility.setActiveUser(client);
        stableCoin.wrap(client, perClientWrap);

        vm.stopPrank();

        vm.warp(block.timestamp + 365 days);
        vm.roll(block.number + 2_600_000);

        _verifyClientYield(clientA, feeA, "Client A");
        _verifyClientYield(clientB, feeB, "Client B");
        _verifyClientYield(client, feeC, "Client C");
    }

    function test_SettleDifferentialFees() public {
        address facilityAddr = address(mockFacility);

        uint16 feeA = 1000; // 10%
        uint16 feeB = 2000; // 20%

        vm.startPrank(earnerManager);
        stableCoin.setAccountInfo(clientA, true, feeA);
        stableCoin.setAccountInfo(clientB, true, feeB);
        stableCoin.setAccountInfo(facilityAddr, true, 0);
        stableCoin.enableEarning();
        vm.stopPrank();

        // Funding: Mint 200,000 M tokens (6 decimals)
        address minterGateway = 0xf7f9638cb444D65e5A40bF5ff98ebE4ff319F04E;
        uint256 tokensToMint = 200_000 * 1e6;

        vm.prank(minterGateway);
        (bool success,) = M_TOKEN.call(abi.encodeWithSignature("mint(address,uint256)", facilityAddr, tokensToMint));
        require(success, "M0 Minting failed");

        // Wrap tokens for each client (100,000 each)
        uint256 perClientWrap = 100_000 * 1e6;
        vm.startPrank(facilityAddr);
        IERC20(M_TOKEN).approve(address(stableCoin), tokensToMint);

        mockFacility.setActiveUser(clientA);
        stableCoin.wrap(clientA, perClientWrap);

        mockFacility.setActiveUser(clientB);
        stableCoin.wrap(clientB, perClientWrap);
        vm.stopPrank();

        // Warp time forward (1 year) to generate yield
        vm.warp(block.timestamp + 365 days);
        vm.roll(block.number + 2_600_000);

        // Pre-settlement check: Calculate expected fees
        (, uint256 expectedFeeA,) = stableCoin.accruedYieldAndFeeOf(clientA);
        (, uint256 expectedFeeB,) = stableCoin.accruedYieldAndFeeOf(clientB);
        uint256 totalExpectedFees = expectedFeeA + expectedFeeB;

        assertGt(totalExpectedFees, 0, "No fees to settle");

        // Settle Yield
        uint256 recipientBalanceBefore = stableCoin.balanceOf(feeRecipient);

        address[] memory accountsToClaim = new address[](2);
        accountsToClaim[0] = clientA;
        accountsToClaim[1] = clientB;

        stableCoin.claimFor(accountsToClaim);

        uint256 recipientBalanceAfter = stableCoin.balanceOf(feeRecipient);

        assertEq(
            recipientBalanceAfter - recipientBalanceBefore,
            totalExpectedFees,
            "Fee recipient did not receive correct amount"
        );

        console.log("Total Fees Settled to Recipient:", totalExpectedFees);
        console.log("Fee from Client A (10%):", expectedFeeA);
        console.log("Fee from Client B (20%):", expectedFeeB);
    }

    function _mintMToFacility(address to, uint256 amount) internal {
        address minterGateway = 0xf7f9638cb444D65e5A40bF5ff98ebE4ff319F04E;
        vm.prank(minterGateway);
        (bool success,) = M_TOKEN.call(abi.encodeWithSignature("mint(address,uint256)", to, amount));
        require(success, "M0 Minting failed");
    }

    function _verifyClientYield(address account, uint16 expectedFeeBps, string memory label) internal view {
        (uint256 yield, uint256 feeTaken, uint256 net) = stableCoin.accruedYieldAndFeeOf(account);

        assertGt(yield, 0, string.concat(label, " No yield accrued"));
        assertEq(feeTaken, (yield * expectedFeeBps) / 10000, string.concat(label, " fee mismatch"));
        assertEq(net, yield - feeTaken, string.concat(label, " net mismatch"));

        console.log(string.concat(label, " Net Yield:"), net);
    }

    function _approveEarner(address earner) internal {
        bytes32 earnersList = 0x6561726e65727300000000000000000000000000000000000000000000000000;

        address registrarOwner = 0xB024aC5a7c6bC92fbACc8C3387E628a07e1Da016; // Standard Governor

        vm.prank(registrarOwner);
        (bool success,) = M_REGISTRAR.call(abi.encodeWithSignature("addToList(bytes32,address)", earnersList, earner));
        require(success, "Mock approval failed");
    }
}
