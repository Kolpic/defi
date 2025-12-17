// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICircleAdapter {
    // --- Errors ---
    
    error InsufficientDelegation(uint256 delegated, uint256 required);
    error NoBorrowingPower();
    error ZeroAddress();
    error ZeroBorrowAmount();

    // --- Events ---
    
    event CrossChainTransferInitiated(
        address indexed user,
        uint256 amount,
        uint256 healthFactor,
        uint32 destinationDomain
    );

    event LoanRepaid(address indexed payer, address indexed onBehalfOf, uint256 amount);

    // --- Functions ---

    /**
     * @notice Execute cross-chain transfer by borrowing against existing Aave position
     * @dev User must have collateral in Aave and delegated credit to this contract
     */
    function executeFastCrossChainTransfer(
        uint256 borrowAmount,
        uint32 destinationDomain,
        bytes32 mintRecipient
    ) external;

    /**
     * @notice Supply collateral and execute cross-chain transfer in one transaction
     * @dev User must have delegated credit to this contract
     */
    function supplyAndTransfer(
        address collateralAsset,
        uint256 collateralAmount,
        uint32 destinationDomain,
        bytes32 mintRecipient
    ) external;

    /**
     * @notice Bridge USDC directly without borrowing
     */
    function bridgeUsdc(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient
    ) external;

    /**
     * @notice Get the user's current debt in Aave
     */
    function getBorrowBalance(address user) external view returns (uint256);

    /**
     * @notice Get the user's current health factor
     */
    function getHealthFactor(address user) external view returns (uint256);

    /**
     * @notice Get the credit delegation allowance from a user to this contract
     */
    function getDelegatedAmount(address user) external view returns (uint256);

    /**
     * @notice Repay USDC debt on behalf of a user
     */
    function repay(address onBehalfOf, uint256 amount) external;
}
