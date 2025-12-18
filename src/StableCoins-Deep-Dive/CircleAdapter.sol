// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {TransferHelper} from "./libs/TransferHelper.sol";
import {ICircleAdapter} from "./interfaces/ICircleAdapter.sol";
import {ITokenMessenger} from "./interfaces/ITokenMessenger.sol";
import {IPool} from "./interfaces/IPool.sol";
import {ICreditDelegationToken} from "./interfaces/ICreditDelegationToken.sol";

/**
 * @title CircleAdapter
 * @notice Enables fast cross-chain transfers using Aave V3 and Circle CCTP
 * @dev Uses Credit Delegation so each user maintains their own isolated Aave position
 * 
 * Flow:
 * 1. User supplies collateral directly to Aave (their own position)
 * 2. User delegates USDC borrowing power to this contract via `approveDelegation`
 * 3. User calls `executeFastCrossChainTransfer` - contract borrows USDC on user's behalf
 * 4. Contract bridges USDC via Circle CCTP
 * 5. User repays debt and withdraws collateral directly from Aave
 */
contract CircleAdapter is ICircleAdapter, ReentrancyGuard {
    // --- State Variables ---
    IPool public immutable aavePool;
    ITokenMessenger public immutable tokenMessenger;
    IERC20 public immutable usdc;
    ICreditDelegationToken public immutable variableDebtUsdc;
    
    uint256 constant INTEREST_RATE_MODE = 2; // Variable rate
    uint16 constant REFERRAL_CODE = 0;

    // --- Constructor ---
    constructor(
        address _aavePool, 
        address _tokenMessenger, 
        address _usdc,
        address _variableDebtUsdc
    ) {
        if (_aavePool == address(0) || _tokenMessenger == address(0) || _usdc == address(0) || _variableDebtUsdc == address(0)) {
            revert ZeroAddress();
        }
        aavePool = IPool(_aavePool);
        tokenMessenger = ITokenMessenger(_tokenMessenger);
        usdc = IERC20(_usdc);
        variableDebtUsdc = ICreditDelegationToken(_variableDebtUsdc);
    }

    /**
     * @notice Execute a fast cross-chain transfer by borrowing against user's Aave position
     * @dev User must have:
     *      1. Supplied collateral to Aave directly (to their own position)
     *      2. Called `approveDelegation(thisContract, amount)` on the variable debt USDC token
     * @param borrowAmount The amount of USDC to borrow and bridge
     * @param destinationDomain Circle's domain ID for the target chain (0=Eth, 1=Avax, 2=OP, 3=Arb, 6=Base, 7=Polygon)
     * @param mintRecipient The recipient address on destination chain (bytes32 format)
     */
    function executeFastCrossChainTransfer(
        uint256 borrowAmount,
        uint32 destinationDomain,
        bytes32 mintRecipient
    ) external override nonReentrant {
        if (borrowAmount == 0) {
            revert ZeroBorrowAmount();
        }

        uint256 delegatedAmount = variableDebtUsdc.borrowAllowance(msg.sender, address(this));
        if (delegatedAmount < borrowAmount) {
            revert InsufficientDelegation(delegatedAmount, borrowAmount);
        }

        (,, uint256 availableBorrowsBase,,,) = aavePool.getUserAccountData(msg.sender);
        uint256 maxUSDCBorrow = availableBorrowsBase / 100; // Base (8 decimals) -> USDC (6 decimals)
        
        if (maxUSDCBorrow < borrowAmount) {
            revert NoBorrowingPower();
        }

        aavePool.borrow(address(usdc), borrowAmount, INTEREST_RATE_MODE, REFERRAL_CODE, msg.sender);

        (,,,,, uint256 currentHealthFactor) = aavePool.getUserAccountData(msg.sender);

        TransferHelper.safeApprove(address(usdc), address(tokenMessenger), borrowAmount);
        
        tokenMessenger.depositForBurn(
            borrowAmount,
            destinationDomain,
            mintRecipient,
            address(usdc)
        );

        emit CrossChainTransferInitiated(msg.sender, borrowAmount, currentHealthFactor, destinationDomain);
    }

    /**
     * @notice Execute a fast cross-chain transfer by supplying collateral first, then borrowing
     * @dev For users who want to supply and borrow in one transaction
     *      User must have called `approveDelegation(thisContract, amount)` on variable debt USDC
     * @param collateralAsset The address of the collateral asset to supply
     * @param collateralAmount The amount of collateral to supply
     * @param destinationDomain Circle's domain ID for the target chain
     * @param mintRecipient The recipient address on destination chain (bytes32 format)
     */
    function supplyAndTransfer(
        address collateralAsset,
        uint256 collateralAmount,
        uint32 destinationDomain,
        bytes32 mintRecipient
    ) external override nonReentrant {
        uint256 amountToBridge = collateralAmount;
        uint256 currentHealthFactor = type(uint256).max; // Default for USDC (no borrow)

        TransferHelper.safeTransferFrom(address(usdc), msg.sender, address(this), collateralAmount);

        if (collateralAsset != address(usdc)) {
            TransferHelper.safeTransferFrom(collateralAsset, msg.sender, address(this), collateralAmount);
            TransferHelper.safeApprove(collateralAsset, address(aavePool), collateralAmount);

            // Supply to Aave on behalf of the USER (they own the position)
            aavePool.supply(collateralAsset, collateralAmount, msg.sender, REFERRAL_CODE);

            (,, uint256 availableBorrowsBase,,,) = aavePool.getUserAccountData(msg.sender);
            uint256 maxUSDCBorrow = availableBorrowsBase / 100;
            
            if (maxUSDCBorrow == 0) {
                revert NoBorrowingPower();
            }

            uint256 delegatedAmount = variableDebtUsdc.borrowAllowance(msg.sender, address(this));
            if (delegatedAmount < maxUSDCBorrow) {
                revert InsufficientDelegation(delegatedAmount, maxUSDCBorrow);
            }

            // Borrow USDC on behalf of user
            aavePool.borrow(address(usdc), maxUSDCBorrow, INTEREST_RATE_MODE, REFERRAL_CODE, msg.sender);

            (,,,,, currentHealthFactor) = aavePool.getUserAccountData(msg.sender);

            amountToBridge = maxUSDCBorrow;
        }

        TransferHelper.safeApprove(address(usdc), address(tokenMessenger), amountToBridge);

        tokenMessenger.depositForBurn(
            amountToBridge,
            destinationDomain,
            mintRecipient,
            address(usdc)
        );

        emit CrossChainTransferInitiated(msg.sender, amountToBridge, currentHealthFactor, destinationDomain);
    }

    /**
     * @notice Bridge USDC directly without borrowing (for users who already have USDC)
     * @param amount The amount of USDC to bridge
     * @param destinationDomain Circle's domain ID for the target chain
     * @param mintRecipient The recipient address on destination chain (bytes32 format)
     */
    function bridgeUsdc(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient
    ) external override nonReentrant {
        TransferHelper.safeTransferFrom(address(usdc), msg.sender, address(this), amount);
        TransferHelper.safeApprove(address(usdc), address(tokenMessenger), amount);
        
        tokenMessenger.depositForBurn(
            amount,
            destinationDomain,
            mintRecipient,
            address(usdc)
        );

        emit CrossChainTransferInitiated(msg.sender, amount, type(uint256).max, destinationDomain);
    }

    /**
     * @notice Get the user's current debt in Aave
     * @param user The user address
     * @return totalDebtBase The user's total debt in base currency (8 decimals)
     */
    function getBorrowBalance(address user) external view override returns (uint256 totalDebtBase) {
        (, totalDebtBase,,,,) = aavePool.getUserAccountData(user);
    }

    /**
     * @notice Get the user's current health factor
     * @param user The user address
     * @return healthFactor The user's health factor (1e18 = 1.0)
     */
    function getHealthFactor(address user) external view override returns (uint256 healthFactor) {
        (,,,,, healthFactor) = aavePool.getUserAccountData(user);
    }

    /**
     * @notice Get the credit delegation allowance from a user to this contract
     * @param user The user who delegated credit
     * @return The amount of USDC borrowing power delegated
     */
    function getDelegatedAmount(address user) external view override returns (uint256) {
        return variableDebtUsdc.borrowAllowance(user, address(this));
    }

    /**
     * @notice Repay USDC debt on behalf of a user
     * @dev Anyone can repay on behalf of a user
     * @param onBehalfOf The user whose debt will be repaid
     * @param amount The amount to repay (use type(uint256).max for full repayment)
     */
    function repay(address onBehalfOf, uint256 amount) external override nonReentrant {
        uint256 amountToRepay = amount;

        if (amount == type(uint256).max) {
            amountToRepay = variableDebtUsdc.balanceOf(onBehalfOf);
        }

        TransferHelper.safeTransferFrom(address(usdc), msg.sender, address(this), amountToRepay);
        TransferHelper.safeApprove(address(usdc), address(aavePool), amountToRepay);

        uint256 repaid = aavePool.repay(address(usdc), amountToRepay, INTEREST_RATE_MODE, onBehalfOf);

        emit LoanRepaid(msg.sender, onBehalfOf, repaid);
    }
}
