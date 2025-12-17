// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IPool {
    /**
     * @notice Supplies an `amount` of underlying asset into the reserve, receiving in return overlying aTokens.
     * @param asset The address of the underlying asset to supply
     * @param amount The amount to be supplied
     * @param onBehalfOf The address that will receive the aTokens (can be different from msg.sender)
     * @param referralCode Code used to register the integrator (0 if none)
     */
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;

    /**
     * @notice Allows users to borrow a specific `amount` of the reserve underlying asset.
     * @dev When using credit delegation, the `onBehalfOf` user must have delegated credit to msg.sender
     * @param asset The address of the underlying asset to borrow
     * @param amount The amount to be borrowed
     * @param interestRateMode The interest rate mode (1 = Stable, 2 = Variable)
     * @param referralCode Code used to register the integrator (0 if none)
     * @param onBehalfOf The address that will receive the debt. Must have delegated credit if != msg.sender
     */
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf) external;

    /**
     * @notice Repays a borrowed `amount` on a specific reserve, burning the equivalent debt tokens.
     * @param asset The address of the borrowed underlying asset
     * @param amount The amount to repay (use type(uint256).max to repay the whole debt)
     * @param interestRateMode The interest rate mode (1 = Stable, 2 = Variable)
     * @param onBehalfOf The address of the user who will get their debt reduced
     * @return The final amount repaid
     */
    function repay(address asset, uint256 amount, uint256 interestRateMode, address onBehalfOf) external returns (uint256);

    /**
     * @notice Withdraws an `amount` of underlying asset from the reserve, burning the equivalent aTokens.
     * @param asset The address of the underlying asset to withdraw
     * @param amount The amount to withdraw (use type(uint256).max to withdraw all)
     * @param to The address that will receive the underlying asset
     * @return The final amount withdrawn
     */
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);

    /**
     * @notice Returns the user account data across all reserves
     * @param user The address of the user
     * @return totalCollateralBase The total collateral in base currency
     * @return totalDebtBase The total debt in base currency
     * @return availableBorrowsBase The borrowing power in base currency
     * @return currentLiquidationThreshold The liquidation threshold
     * @return ltv The loan to value
     * @return healthFactor The current health factor
     */
    function getUserAccountData(address user) external view returns (
        uint256 totalCollateralBase,
        uint256 totalDebtBase,
        uint256 availableBorrowsBase,
        uint256 currentLiquidationThreshold,
        uint256 ltv,
        uint256 healthFactor
    );
}