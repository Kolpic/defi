// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IPool} from "./interfaces/IPool.sol";
import {IAaveOracle} from "./interfaces/IOracle.sol";
import {POOL, ORACLE, WETH, DAI, USDC, USDT} from "./Constants.sol";
import {console} from "forge-std/console.sol";

contract AaveV3Manager is ReentrancyGuard {
    IPool public constant pool = IPool(POOL);
    IAaveOracle public constant AAVE_ORACLE = IAaveOracle(ORACLE);

    event Deposited(address indexed user, address indexed asset, uint256 amount, uint256 sharesMinted);
    event Withdrawn(address indexed user, address indexed asset, uint256 amount, uint256 sharesBurned);
    event Borrowed(address indexed user, address indexed asset, uint256 amount);
    event Repaid(address indexed user, address indexed asset, uint256 amount);
    event AssetRegistered(address indexed asset, uint256 ltv, string symbol);

    // Asset configuration struct
    struct AssetConfig {
        uint256 ltv; // Loan-to-Value ratio in basis points (e.g., 8000 = 80%)
        bool isActive;
        string symbol;
    }

    // Internal accounting for user deposits (shares)
    mapping(address => mapping(address => uint256)) public s_userShares;
    mapping(address => uint256) public s_totalShares;

    // Internal accounting for user borrows
    mapping(address => mapping(address => uint256)) public s_userBorrowedPrincipal;
    mapping(address => uint256) public s_totalBorrowedPrincipal;

    // Asset configuration mapping
    mapping(address => AssetConfig) public assetConfigs;

    uint256 public constant MINIMUM_HEALTH_FACTOR = 1.1e18;
    uint256 public constant DEAD_SHARES = 1e3; // 1000 wei
    
    // Operation types for health factor calculation
    uint256 public constant OPERATION_NONE = 0;
    uint256 public constant OPERATION_DEPOSIT = 1;
    uint256 public constant OPERATION_WITHDRAW = 2;
    uint256 public constant OPERATION_BORROW = 3;
    uint256 public constant OPERATION_REPAY = 4;

    constructor() {
        _initializeAssetConfigs();
    }

    /**
     * @notice Initialize default asset configurations
     */
    function _initializeAssetConfigs() private {
        // Register common assets with their LTV ratios
        _registerAsset(WETH, 8000, "WETH"); // 80%
        _registerAsset(DAI, 7500, "DAI");   // 75%
        _registerAsset(USDC, 8000, "USDC"); // 80%
        _registerAsset(USDT, 7500, "USDT"); // 75%
    }

    /**
     * @notice Register a new asset with its configuration
     * @param _asset The asset address
     * @param _ltv The loan-to-value ratio in basis points
     * @param _symbol The asset symbol
     */
    function _registerAsset(address _asset, uint256 _ltv, string memory _symbol) private {
        assetConfigs[_asset] = AssetConfig({
            ltv: _ltv,
            isActive: true,
            symbol: _symbol
        });
        emit AssetRegistered(_asset, _ltv, _symbol);
    }

    /**
     * @notice Get the LTV ratio for an asset
     * @param _asset The asset address
     * @return The LTV ratio in basis points
     */
    function getLTV(address _asset) public view returns (uint256) {
        AssetConfig memory config = assetConfigs[_asset];
        require(config.isActive, "Asset not registered or inactive");
        return config.ltv;
    }

    /**
     * @notice Check if an asset is registered and active
     * @param _asset The asset address
     * @return True if the asset is registered and active
     */
    function isAssetActive(address _asset) public view returns (bool) {
        return assetConfigs[_asset].isActive;
    }

    /**
     * @notice Get all registered assets
     * @return Array of registered asset addresses
     */
    function getRegisteredAssets() public view returns (address[] memory) {
        address[] memory assets = new address[](4);
        assets[0] = WETH;
        assets[1] = DAI;
        assets[2] = USDC;
        assets[3] = USDT;
        return assets;
    }

    /**
     * @notice Deposits an asset into the Aave V3 pool on behalf of the user.
     * @dev Mints internal shares to the user to track their portion of the pooled funds.
     * @param _asset The address of the asset to deposit.
     * @param _amount The amount of the asset to deposit.
     */
    function deposit(address _asset, uint256 _amount) external nonReentrant {
        require(_amount > 0, "Amount must be > 0");
        require(isAssetActive(_asset), "Asset not supported");

        uint256 totalShares = s_totalShares[_asset];
        uint256 totalAssetsInPool = _getTotalAssetsInPool(_asset);
        uint256 sharesToMint;

        if (totalShares == 0) {
            // 1:1 rate
            s_totalShares[_asset] = DEAD_SHARES;
            sharesToMint = _amount;
        } else {
            // Subsequent depositors get shares proportional to their deposit
            sharesToMint = (_amount * totalShares) / totalAssetsInPool;
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
    function withdraw(address _asset, uint256 _amount) external nonReentrant {
        require(_amount > 0, "Amount must be > 0");
        require(isAssetActive(_asset), "Asset not supported");

        uint256 totalShares = s_totalShares[_asset];
        uint256 totalAssetsInPool = _getTotalAssetsInPool(_asset);
        require(totalShares > 0 && totalAssetsInPool > 0, "Nothing to withdraw");

        uint256 sharesToBurn = (_amount * totalShares) / totalAssetsInPool;
        require(sharesToBurn > 0, "Shares to burn must be > 0");

        uint256 userShares = s_userShares[_asset][msg.sender];
        require(userShares >= sharesToBurn, "Insufficient shares");

        // Check health factor before updating state
        uint256 userHealthFactor = calculateHealthFactor(msg.sender, _asset, _amount, OPERATION_WITHDRAW, 0);
        require(userHealthFactor > MINIMUM_HEALTH_FACTOR, "Withdrawal would make health factor too low");

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
    function borrow(address _asset, uint256 _amount, uint256 _interestRateMode) external nonReentrant {
        require(_amount > 0, "Amount must be > 0");
        require(_interestRateMode == 2, "Only variable rate borrowing is supported");
        require(isAssetActive(_asset), "Asset not supported");

        // Check health factor after borrowing (simulate the borrow)
        uint256 userHealthFactor = calculateHealthFactor(msg.sender, _asset, _amount, OPERATION_BORROW, _interestRateMode);
        require(userHealthFactor > MINIMUM_HEALTH_FACTOR, "User health factor too low after borrowing");

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
    function repay(address _asset, uint256 _amount, uint256 _interestRateMode) external nonReentrant {
        require(_amount > 0, "Amount must be > 0");
        require(_interestRateMode == 2, "Only variable rate repay is supported");
        require(isAssetActive(_asset), "Asset not supported");

        uint256 userOwed = debtOf(_asset, msg.sender);
        require(_amount <= userOwed, "Amount to repay exceeds debt");

        // Check health factor after repayment (should improve health factor)
        uint256 userHealthFactor = calculateHealthFactor(msg.sender, _asset, _amount, OPERATION_REPAY, _interestRateMode);
        require(userHealthFactor > MINIMUM_HEALTH_FACTOR, "Repayment would result in health factor too low");

        uint256 userPrincipal = s_userBorrowedPrincipal[_asset][msg.sender];
        uint256 principalToReduce = (userPrincipal * _amount) / userOwed;

        s_userBorrowedPrincipal[_asset][msg.sender] -= principalToReduce;
        s_totalBorrowedPrincipal[_asset] -= principalToReduce;

        // Approve the pool to spend the asset
        IERC20(_asset).approve(address(pool), _amount);
        IERC20(_asset).transferFrom(msg.sender, address(this), _amount);

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
     * @notice Calculates the health factor for a specific user.
     * @param _user The address of the user.
     * @return The user's health factor (in wei, 1e18 = 1.0).
     */
    function calculateUserHealthFactor(address _user) public view returns (uint256) {
        return calculateHealthFactor(_user, address(0), 0, OPERATION_NONE, 0);
    }

    /**
     * @notice Calculates the health factor for a user after a specific operation.
     * @param _user The address of the user.
     * @param _operationAsset The asset involved in the operation (address(0) for no operation).
     * @param _operationAmount The amount involved in the operation.
     * @param _operationType Use constants: OPERATION_NONE, OPERATION_DEPOSIT, OPERATION_WITHDRAW, OPERATION_BORROW, OPERATION_REPAY.
     * @param _interestRateMode The interest rate mode for borrow/repay operations (1 for stable, 2 for variable). Currently not used but kept for future extensibility.
     * @return The user's health factor after the operation.
     */
    function calculateHealthFactor(
        address _user,
        address _operationAsset,
        uint256 _operationAmount,
        uint256 _operationType,
        uint256 _interestRateMode
    ) public view returns (uint256) {
        uint256 totalCollateralValue = 0;
        uint256 totalBorrowedValue = 0;

        address[] memory registeredAssets = getRegisteredAssets();
        
        for (uint256 i = 0; i < registeredAssets.length; i++) {
            address asset = registeredAssets[i];
            
            // Calculate collateral amount (deposits)
            uint256 collateralAmount = balanceOf(asset, _user);
            
            // Adjust collateral based on operation
            if (_operationType == OPERATION_DEPOSIT && asset == _operationAsset) {
                // Deposit operation - add to collateral
                collateralAmount += _operationAmount;
            } else if (_operationType == OPERATION_WITHDRAW && asset == _operationAsset) {
                // Withdraw operation - subtract from collateral
                collateralAmount = collateralAmount > _operationAmount ? collateralAmount - _operationAmount : 0;
            }
            
            if (collateralAmount > 0) {
                uint256 assetPrice = AAVE_ORACLE.getAssetPrice(asset);
                
                // Get liquidation threshold from Aave pool
                IPool.ReserveData memory reserveData = pool.getReserveData(asset);
                uint256 liquidationThreshold = _getLiquidationThreshold(reserveData.configuration);
                
                // liquidationThreshold is in basis points (e.g., 8250 = 82.5%)
                uint256 collateralValue = (collateralAmount * assetPrice * liquidationThreshold) / (1e26 * 10000);
                totalCollateralValue += collateralValue;
            }
            
            // Calculate borrowed amount (debts)
            uint256 borrowedAmount = debtOf(asset, _user);
            
            // Adjust debt based on operation
            if (_operationType == OPERATION_BORROW && asset == _operationAsset) {
                // For borrow operations, add the borrowed amount
                borrowedAmount += _operationAmount;
            } else if (_operationType == OPERATION_REPAY && asset == _operationAsset) {
                // For repay operations, subtract the repaid amount
                if (_operationAmount <= borrowedAmount) {
                    borrowedAmount -= _operationAmount;
                }
            }
            
            if (borrowedAmount > 0) {
                uint256 assetPrice = AAVE_ORACLE.getAssetPrice(asset);
                uint256 borrowedValue = (borrowedAmount * assetPrice) / 1e26;
                totalBorrowedValue += borrowedValue;
            }
        }

        if (totalBorrowedValue == 0) {
            return type(uint256).max; // No debt = infinite health factor
        }

        return (totalCollateralValue * 1e18) / totalBorrowedValue;
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
        uint256 variableDebt = IERC20(reserveData.variableDebtTokenAddress).balanceOf(address(this));
        uint256 stableDebt = IERC20(reserveData.stableDebtTokenAddress).balanceOf(address(this));
        return variableDebt + stableDebt;
    }

    /**
     * @notice Helper function to extract liquidation threshold from ReserveConfigurationMap.
     * @param config The reserve configuration data from Aave.
     * @return The liquidation threshold in basis points.
     */
    function _getLiquidationThreshold(IPool.ReserveConfigurationMap memory config) private pure returns (uint256) {
        /**
         * Liquidation threshold is stored in bits 16-23 of the configuration data
         * Liquidation threshold is stored in bits 16-23 of the configuration data
         * Bits 0-15:   LTV
         * Bits 16-31:  Liquidation Threshold  ← extract this
         * Bits 32-47:  Liquidation Bonus
         * Bits 48-55:  Decimals
         * Bits 56-63:  Reserve Factor
         */
        return (config.data >> 16) & 0xFFFF;
    }
}