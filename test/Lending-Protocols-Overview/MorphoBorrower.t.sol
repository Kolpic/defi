// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../../src/Lending-Protocols-Overview/MorphoBorrower.sol";

import {IMorpho, Position} from "@morpho-blue/interfaces/IMorpho.sol";
import {MorphoLib} from "@morpho-blue/libraries/periphery/MorphoLib.sol";
import {Id, MarketParamsLib} from "@morpho-blue/libraries/MarketParamsLib.sol";
import {ErrorsLib} from "@morpho-blue/libraries/ErrorsLib.sol";

contract MorphoBorrowerTest is Test {
    using MorphoLib for IMorpho; // Allows morpho.id(marketParams) if library is linked

    MorphoBorrower borrower;
    // https://docs.morpho.org/get-started/resources/addresses/
    IMorpho morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    // https://etherscan.io/token/0x7f39c581f595b53c5cb19bd0b3f8da6c935e2ca0
    address constant wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;

    MarketParams marketParams;

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));
        borrower = new MorphoBorrower(address(morpho));

        marketParams = MarketParams({
            loanToken: WETH,
            collateralToken: wstETH,
            // oracle: 0x48F7e36EB6b8267fF75661FEf7E163288523fcc0,
            // oracle: 0x3A7bB36Ee3f3eE32A60e9f2b33c1e5f2E83ad766,
            // https://docs.morpho.org/get-started/resources/addresses/
            oracle: 0xbD60A6770b27E084E8617335ddE769241B0e71D8,
            irm: 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC,
            lltv: 945000000000000000
        });

        // morpho.createMarket(marketParams);
    }

    function testSupplyAndBorrow() public {
        uint256 collatAmount = 10 ether;
        uint256 borrowAmount = 5 ether;

        console.log("borrowAmount", borrowAmount);
        console.log("collatAmount", collatAmount);

        deal(wstETH, address(this), collatAmount);

        console.log("wstETH balance", IERC20(wstETH).balanceOf(address(this)));

        IERC20(wstETH).approve(address(borrower), collatAmount);

        uint256 balanceBefore = IERC20(WETH).balanceOf(address(this));

        console.log("balanceBefore", balanceBefore);

        borrower.supplyAndBorrow(marketParams, collatAmount, borrowAmount);

        uint256 balanceAfter = IERC20(WETH).balanceOf(address(this));

        console.log("balanceAfter", balanceAfter);

        Id marketId = MarketParamsLib.id(marketParams);

        Position memory pos = morpho.position(marketId, address(borrower));

        // The total amount of collateral tokens deposited.
        console.log("pos.collateral", pos.collateral);
        // Shares representing the assets borrowed from the market.
        console.log("pos.borrowShares", pos.borrowShares);
        // Shares representing the assets supplied to the market.
        console.log("pos.supplyShares", pos.supplyShares);

        assertEq(pos.collateral, collatAmount);
        assertEq(balanceAfter - balanceBefore, borrowAmount);
    }

    function testRevertIfBorrowAmountTooHigh() public {
        uint256 collatAmount = 1 ether; // 1 wstETH
        // 1 wstETH is roughly 1.1 WETH.
        // Trying to borrow 10 WETH is impossible.
        uint256 wayTooMuchBorrow = 2 ether;

        deal(wstETH, address(this), collatAmount);
        IERC20(wstETH).approve(address(borrower), collatAmount);

        vm.expectRevert(bytes(ErrorsLib.INSUFFICIENT_COLLATERAL));
        borrower.supplyAndBorrow(marketParams, collatAmount, wayTooMuchBorrow);
    }
}
