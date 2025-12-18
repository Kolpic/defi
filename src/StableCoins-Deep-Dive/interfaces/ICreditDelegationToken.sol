// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title ICreditDelegationToken
/// @notice Interface for Aave's variable/stable debt tokens that support credit delegation
interface ICreditDelegationToken {
    /**
     * @notice Returns the current delegated allowance of a delegatee
     * @param fromUser The user who delegated credit
     * @param toUser The user who received the delegation (can borrow on behalf)
     * @return The amount of credit delegated
     */
    function borrowAllowance(address fromUser, address toUser) external view returns (uint256);

    /**
     * @notice Delegates borrowing power to another user
     * @param delegatee The address receiving the delegation
     * @param amount The amount of credit to delegate
     */
    function approveDelegation(address delegatee, uint256 amount) external;

    /**
     * @notice Returns the balance of a user
     * @param user The user whose balance is being checked
     * @return The balance of the user
     */
    function balanceOf(address user) external view returns (uint256);
}

