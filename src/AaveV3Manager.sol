// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPool} from "./interfaces/IPool.sol";
import {POOL} from "./Constants.sol";
// You'll also need interfaces for aTokens and debtTokens to get total supply

contract AaveV3Manager {
    IPool public constant pool = IPool(POOL);

    event Deposited(address indexed user, address indexed asset, uint256 amount, uint256 sharesMinted);
    event Withdrawn(address indexed user, address indexed asset, uint256 amount, uint256 sharesBurned);
    event Borrowed(address indexed user, address indexed asset, uint256 amount);
    event Repaid(address indexed user, address indexed asset, uint256 amount);

    // Internal accounting for user deposits (shares)
    mapping(address => mapping(address => uint256)) private s_userShares;
    mapping(address => uint256) private s_totalShares;

    // Internal accounting for user borrows
    mapping(address => mapping(address => uint256)) private s_userBorrowedPrincipal;
    mapping(address => uint256) private s_totalBorrowedPrincipal;

    uint256 public constant MINIMUM_HEALTH_FACTOR = 1.1e18;

    /**
     * @notice Deposits an asset into the Aave V3 pool on behalf of the user.
     * @dev Mints internal shares to the user to track their portion of the pooled funds.
     * @param _asset The address of the asset to deposit.
     * @param _amount The amount of the asset to deposit.
     */
    function deposit(address _asset, uint256 _amount) external {
        require(_amount > 0, "Amount must be > 0");

        uint256 totalShares = s_totalShares[_asset];
        uint256 totalAssetsInPool = _getTotalAssetsInPool(_asset);
        
        uint256 sharesToMint;
        if (totalShares == 0 || totalAssetsInPool == 0) {
            // 1:1 rate
            sharesToMint = _amount;
        } else {
            // Subsequent depositors get shares proportional to their deposit
            // sharesToMint = (_amount * totalShares) / totalAssetsInPool;
            sharesToMint = (_amount * totalShares + (totalAssetsInPool / 2)) / totalAssetsInPool;
        }
        require(sharesToMint > 0, "Shares to mint must be > 0");

        // Transfer asset from user to this contract
        IERC20(_asset).transferFrom(msg.sender, address(this), _amount);

        // Approve the Aave pool to spend the asset
        IERC20(_asset).approve(address(pool), _amount);
        
        // Supply the asset to Aave
        pool.supply(_asset, _amount, address(this), 0);

        // Update internal accounting
        s_userShares[_asset][msg.sender] += sharesToMint;
        s_totalShares[_asset] += sharesToMint;

        emit Deposited(msg.sender, _asset, _amount, sharesToMint);
    }

    /**
     * @notice Withdraws an asset from the Aave V3 pool.
     * @dev Burns the user's internal shares in proportion to the amount withdrawn.
     * @param _asset The address of the asset to withdraw.
     * @param _amount The amount of the asset to withdraw.
     */
    function withdraw(address _asset, uint256 _amount) external {
        require(_amount > 0, "Amount must be > 0");

        uint256 totalShares = s_totalShares[_asset];
        uint256 totalAssetsInPool = _getTotalAssetsInPool(_asset);
        require(totalShares > 0 && totalAssetsInPool > 0, "Nothing to withdraw");

        uint256 sharesToBurn = (_amount * totalShares + (totalAssetsInPool / 2)) / totalAssetsInPool;
        require(sharesToBurn > 0, "Shares to burn must be > 0");

        uint256 userShares = s_userShares[_asset][msg.sender];
        require(userShares >= sharesToBurn, "Insufficient shares");

        s_userShares[_asset][msg.sender] -= sharesToBurn;
        s_totalShares[_asset] -= sharesToBurn;

        uint256 amountWithdrawn = pool.withdraw(_asset, _amount, address(this));

        IERC20(_asset).transfer(msg.sender, amountWithdrawn);

        emit Withdrawn(msg.sender, _asset, amountWithdrawn, sharesToBurn);
    }

    /**
     * @notice Borrows an asset from Aave on behalf of the user.
     * @dev The contract takes on the debt, and internally assigns responsibility to the user.
     * @param _asset The address of the asset to borrow.
     * @param _amount The amount to borrow.
     * @param _interestRateMode 1 for Stable, 2 for Variable.
     */
    function borrow(address _asset, uint256 _amount, uint256 _interestRateMode) external {
        require(_amount > 0, "Amount must be > 0");

        (, , , , , uint256 healthFactor) = pool.getUserAccountData(address(this));
        require(healthFactor > MINIMUM_HEALTH_FACTOR, "Health factor too low");

        pool.borrow(_asset, _amount, _interestRateMode, 0, address(this));

        s_userBorrowedPrincipal[_asset][msg.sender] += _amount;
        s_totalBorrowedPrincipal[_asset] += _amount;

        IERC20(_asset).transfer(msg.sender, _amount);

        emit Borrowed(msg.sender, _asset, _amount);
    }

    /**
     * @notice Repays a debt to Aave on behalf of the user.
     * @param _asset The address of the asset to repay.
     * @param _amount The amount of principal + interest to repay.
     * @param _interestRateMode The interest rate mode of the debt.
     */
    function repay(address _asset, uint256 _amount, uint256 _interestRateMode) external {
        require(_amount > 0, "Amount must be > 0");

        uint256 userOwed = debtOf(_asset, msg.sender);
        require(_amount <= userOwed, "Amount to repay exceeds debt");

        // Transfer asset from user to this contract
        IERC20(_asset).transferFrom(msg.sender, address(this), _amount);

        uint256 totalPrincipal = s_totalBorrowedPrincipal[_asset];
        uint256 userPrincipal = s_userBorrowedPrincipal[_asset][msg.sender];

        uint256 principalToReduce = (userPrincipal * _amount) / userOwed;

        s_userBorrowedPrincipal[_asset][msg.sender] -= principalToReduce;
        s_totalBorrowedPrincipal[_asset] -= principalToReduce;

        // Approve the pool to spend the asset
        IERC20(_asset).approve(address(pool), _amount);
        pool.repay(_asset, _amount, _interestRateMode, address(this));

        emit Repaid(msg.sender, _asset, _amount);
    }

    /**
     * @notice Calculates the underlying asset balance for a given user.
     * @return The amount of the underlying asset the user can withdraw.
     */
    function balanceOf(address _asset, address _user) public view returns (uint256) {
        uint256 totalShares = s_totalShares[_asset];
        if (totalShares == 0) {
            return 0;
        }
        
        uint256 userShares = s_userShares[_asset][_user];
        uint256 totalAssets = _getTotalAssetsInPool(_asset);
        return (userShares * totalAssets) / totalShares;
    }

    /**
     * @notice Calculates the total current debt of a user for a specific asset.
     * @return The user's total debt, including accrued interest.
     */
    function debtOf(address _asset, address _user) public view returns (uint256) {
        uint256 userPrincipal = s_userBorrowedPrincipal[_asset][_user];
        if (userPrincipal == 0) {
            return 0;
        }

        uint256 totalPrincipal = s_totalBorrowedPrincipal[_asset];
        uint256 totalContractDebt = _getTotalDebtInPool(_asset);

        return (userPrincipal * totalContractDebt) / totalPrincipal;
    }

    /**
     * @notice Gets the total underlying asset balance this contract holds in Aave.
     * @dev This value includes principal + interest, as it's the balance of the aToken.
     * @param _asset The address of the underlying asset (e.g., DAI).
     * @return The total amount of the asset held in the pool.
     */
    function _getTotalAssetsInPool(address _asset) private view returns (uint256) {
        IPool.ReserveData memory reserveData = pool.getReserveData(_asset);
        return IERC20(reserveData.aTokenAddress).balanceOf(address(this));
    }

    function _getTotalDebtInPool(address _asset) private view returns (uint256) {
        IPool.ReserveData memory reserveData = pool.getReserveData(_asset);
        return IERC20(reserveData.variableDebtTokenAddress).balanceOf(address(this));
    }
}