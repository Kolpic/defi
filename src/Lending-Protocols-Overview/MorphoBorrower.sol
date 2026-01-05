// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IMorpho, MarketParams} from "@morpho-blue/interfaces/IMorpho.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MorphoBorrower {
    IMorpho public immutable morpho;

    constructor(address _morpho) {
        morpho = IMorpho(_morpho);
    }

    function supplyAndBorrow(
        MarketParams memory marketParams,
        uint256 collateralAmount,
        uint256 borrowAmount
    ) external {
        IERC20(marketParams.collateralToken).transferFrom(msg.sender, address(this), collateralAmount);
        IERC20(marketParams.collateralToken).approve(address(morpho), collateralAmount);
        // onBehalf: who gets the credit (this contract)
        morpho.supplyCollateral(marketParams, collateralAmount, address(this), "");
        // assets: amount to borrow, shares: 0 (if borrowing specific asset amount)
        // onBehalf: who owes the debt, receiver: who gets the tokens
        morpho.borrow(marketParams, borrowAmount, 0, address(this), msg.sender);
    }
}