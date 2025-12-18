// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../src/StableCoins-Deep-Dive/CircleAdapter.sol";
import "../../src/StableCoins-Deep-Dive/interfaces/IPool.sol";
import "../../src/StableCoins-Deep-Dive/interfaces/ITokenMessenger.sol";
import "../../src/StableCoins-Deep-Dive/interfaces/ICreditDelegationToken.sol";

// --- Mocks ---

// Mock ERC20 Token
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

// Mock Aave Pool
contract MockPool is IPool {
    mapping(address => uint256) public userCollateral;
    mapping(address => uint256) public userDebt;

    uint256 public mockAvailableBorrowsBase;

    function setMockAvailableBorrowsBase(uint256 amount) external {
        mockAvailableBorrowsBase = amount;
    }

    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 /*referralCode*/
    )
        external
    {
        userCollateral[onBehalfOf] += amount;
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
    }

    function borrow(
        address asset,
        uint256 amount,
        uint256,
        /*mode*/
        uint16,
        /*code*/
        address onBehalfOf
    )
        external
    {
        // In Aave V3, debt is assigned to 'onBehalfOf', but funds go to 'msg.sender'
        userDebt[onBehalfOf] += amount;
        MockERC20(asset).mint(msg.sender, amount);
    }

    function repay(
        address asset,
        uint256 amount,
        uint256,
        /*mode*/
        address onBehalfOf
    )
        external
        returns (uint256)
    {
        uint256 debt = userDebt[onBehalfOf];
        uint256 repayAmount = amount > debt ? debt : amount;

        userDebt[onBehalfOf] -= repayAmount;
        IERC20(asset).transferFrom(msg.sender, address(this), repayAmount);

        return repayAmount;
    }

    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        return amount;
    }

    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        return (
            userCollateral[user],
            userDebt[user], // Return actual debt
            mockAvailableBorrowsBase,
            0,
            0,
            1.5e18
        );
    }
}

// Mock Circle TokenMessenger
contract MockTokenMessenger is ITokenMessenger {
    event MessageSent(uint256 amount);

    function depositForBurn(
        uint256 amount,
        uint32,
        /*destinationDomain*/
        bytes32,
        /*mintRecipient*/
        address burnToken
    )
        external
        returns (uint64 _nonce)
    {
        IERC20(burnToken).transferFrom(msg.sender, address(this), amount);
        emit MessageSent(amount);
        return 1;
    }
}

// Mock Debt Token
contract MockDebtToken is ICreditDelegationToken {
    mapping(address => mapping(address => uint256)) public allowances;
    MockPool pool;

    constructor(address _pool) {
        pool = MockPool(_pool);
    }

    function borrowAllowance(address fromUser, address toUser) external view returns (uint256) {
        return allowances[fromUser][toUser];
    }

    function approveDelegation(address delegatee, uint256 amount) external {
        allowances[msg.sender][delegatee] = amount;
    }

    function balanceOf(address user) external view returns (uint256) {
        return pool.userDebt(user);
    }
}

// --- Main Test Contract ---

contract CircleAdapterTest is Test {
    CircleAdapter adapter;
    MockPool pool;
    MockTokenMessenger messenger;
    MockERC20 usdc;
    MockERC20 weth;
    MockDebtToken debtToken;

    address user = address(0x1);
    uint32 destinationDomain = 6;
    bytes32 mintRecipient = bytes32(uint256(uint160(user)));

    event CrossChainTransferInitiated(
        address indexed user, uint256 amount, uint256 healthFactor, uint32 destinationDomain
    );
    event LoanRepaid(address indexed payer, address indexed onBehalfOf, uint256 amount);

    function setUp() public {
        pool = new MockPool();
        messenger = new MockTokenMessenger();
        usdc = new MockERC20("USDC", "USDC");
        weth = new MockERC20("WETH", "WETH");
        debtToken = new MockDebtToken(address(pool));

        adapter = new CircleAdapter(address(pool), address(messenger), address(usdc), address(debtToken));

        vm.label(user, "User");
        usdc.mint(user, 10_000e6);
        weth.mint(user, 10e18);
        usdc.mint(address(pool), 1_000_000e6);
    }

    function test_SupplyAndTransfer_USDC() public {
        uint256 bridgeAmount = 100e6;
        vm.startPrank(user);
        usdc.approve(address(adapter), bridgeAmount);

        vm.expectEmit(true, false, false, true);
        emit CrossChainTransferInitiated(user, bridgeAmount, type(uint256).max, destinationDomain);

        adapter.supplyAndTransfer(address(usdc), bridgeAmount, destinationDomain, mintRecipient);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(messenger)), bridgeAmount);
    }

    function test_SupplyAndTransfer_WETH_Success() public {
        uint256 collateralAmount = 1e18;
        // Logic: 2000e8 / 100 = 20e6 USDC
        pool.setMockAvailableBorrowsBase(2000e6);

        vm.startPrank(user);
        weth.approve(address(adapter), collateralAmount);
        debtToken.approveDelegation(address(adapter), 1_000_000e6);

        vm.expectEmit(true, false, false, true);
        emit CrossChainTransferInitiated(user, 20e6, 1.5e18, destinationDomain);

        adapter.supplyAndTransfer(address(weth), collateralAmount, destinationDomain, mintRecipient);
        vm.stopPrank();

        assertEq(pool.userCollateral(user), collateralAmount, "User should have supplied collateral");
        assertEq(pool.userDebt(user), 20e6, "User should have debt");
        assertEq(usdc.balanceOf(address(messenger)), 20e6, "Messenger should have received USDC");
    }

    function test_Fail_InsufficientDelegation() public {
        uint256 borrowAmount = 100e6;
        pool.setMockAvailableBorrowsBase(1_000_000e8);

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(ICircleAdapter.InsufficientDelegation.selector, 0, borrowAmount));

        adapter.executeFastCrossChainTransfer(borrowAmount, destinationDomain, mintRecipient);
        vm.stopPrank();
    }

    function test_Fail_NoBorrowingPower() public {
        uint256 borrowAmount = 100e6;

        vm.startPrank(user);
        debtToken.approveDelegation(address(adapter), borrowAmount);
        pool.setMockAvailableBorrowsBase(0);

        vm.expectRevert(ICircleAdapter.NoBorrowingPower.selector);
        adapter.executeFastCrossChainTransfer(borrowAmount, destinationDomain, mintRecipient);
        vm.stopPrank();
    }

    function test_Repay_MaxAmount() public {
        uint256 debtAmount = 500e6;

        // Ensure pool.userDebt(user) will reflect this borrow
        vm.prank(address(adapter));
        pool.borrow(address(usdc), debtAmount, 2, 0, user);

        usdc.mint(user, debtAmount);
        vm.startPrank(user);
        usdc.approve(address(adapter), debtAmount);

        vm.expectEmit(true, true, false, true);
        emit LoanRepaid(user, user, debtAmount);

        adapter.repay(user, type(uint256).max);

        vm.stopPrank();

        assertEq(pool.userDebt(user), 0, "Debt should be fully repaid");
    }

    function test_Constructor_RevertZeroAddress() public {
        vm.expectRevert(ICircleAdapter.ZeroAddress.selector);
        new CircleAdapter(address(0), address(messenger), address(usdc), address(debtToken));
    }

    function test_ExecuteFastCrossChainTransfer_Success() public {
        uint256 borrowAmount = 50e6;
        pool.setMockAvailableBorrowsBase(5000e8);

        vm.startPrank(user);
        debtToken.approveDelegation(address(adapter), borrowAmount);

        vm.expectEmit(true, false, false, true);
        emit CrossChainTransferInitiated(user, borrowAmount, 1.5e18, destinationDomain);

        adapter.executeFastCrossChainTransfer(borrowAmount, destinationDomain, mintRecipient);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(messenger)), borrowAmount, "Messenger should receive tokens");
    }

    function test_ExecuteFastCrossChainTransfer_RevertZeroAmount() public {
        vm.expectRevert(ICircleAdapter.ZeroBorrowAmount.selector);
        adapter.executeFastCrossChainTransfer(0, destinationDomain, mintRecipient);
    }

    function test_SupplyAndTransfer_RevertNoBorrowingPower() public {
        pool.setMockAvailableBorrowsBase(0);
        vm.startPrank(user);
        weth.approve(address(adapter), 1e18);

        vm.expectRevert(ICircleAdapter.NoBorrowingPower.selector);

        adapter.supplyAndTransfer(address(weth), 1e18, destinationDomain, mintRecipient);
        vm.stopPrank();
    }

    function test_SupplyAndTransfer_RevertInsufficientDelegation() public {
        // We want to verify error is thrown for 50 USDC (50e6)
        // So we set borrow power to exactly match 50 USDC.
        // Formula: 50e8 (Base) / 100 = 50e6 (USDC)
        uint256 borrowPowerBase = 50e8;
        uint256 maxUSDC = 50e6;

        pool.setMockAvailableBorrowsBase(borrowPowerBase);

        vm.startPrank(user);
        weth.approve(address(adapter), 1e18);

        vm.expectRevert(abi.encodeWithSelector(ICircleAdapter.InsufficientDelegation.selector, 0, maxUSDC));

        adapter.supplyAndTransfer(address(weth), 1e18, destinationDomain, mintRecipient);
        vm.stopPrank();
    }

    function test_BridgeUsdc() public {
        uint256 amount = 75e6;
        vm.startPrank(user);
        usdc.approve(address(adapter), amount);

        vm.expectEmit(true, false, false, true);
        emit CrossChainTransferInitiated(user, amount, type(uint256).max, destinationDomain);

        adapter.bridgeUsdc(amount, destinationDomain, mintRecipient);
        vm.stopPrank();

        assertEq(usdc.balanceOf(address(messenger)), amount);
    }

    function test_ViewFunctions() public {
        address testUser = address(0x99);

        // Setup Debt
        uint256 debtAmount = 123e6;
        vm.prank(address(adapter));
        pool.borrow(address(usdc), debtAmount, 2, 0, testUser);

        // This should now pass because MockPool returns real debt
        assertEq(adapter.getBorrowBalance(testUser), debtAmount);

        // Setup Health Factor
        assertEq(adapter.getHealthFactor(testUser), 1.5e18);

        // Setup Delegation
        uint256 delegation = 1000e6;
        vm.prank(testUser);
        debtToken.approveDelegation(address(adapter), delegation);

        assertEq(adapter.getDelegatedAmount(testUser), delegation);
    }
}
