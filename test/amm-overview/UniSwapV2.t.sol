// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../../src/amm-overview/UniSwapV2.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract UniswapV2HelperTest is Test {
    UniswapV2Helper public helper;

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant WETH_WHALE = 0x2fEB1512183545f432736Ee120E4aF093817cca0;

    function setUp() public {
        string memory mainnetUrl = vm.envString("MAINNET_RPC_URL");
        vm.createSelectFork(mainnetUrl);

        helper = new UniswapV2Helper();
    }

    function test_GetPoolAndQuote() public {
        uint256 amountIn = 1 ether; // 1 WETH

        (address pool, uint256 quote) = helper.getPoolAndQuote(WETH, USDC, amountIn);

        assertTrue(pool != address(0), "Pool should exist");
        assertTrue(quote > 0, "Quote should be greater than zero");

        console.log("Pool Address:", pool);
        console.log("Quote:", quote);
        console.log("Quote for 1 WETH in USDC:", quote / 1e6);
    }

    function test_ExecuteSwap() public {
        uint256 amountIn = 1 ether;
        address user = address(0x1337);

        deal(WETH, user, amountIn);

        vm.startPrank(user);

        IERC20(WETH).approve(address(helper), amountIn);

        (, uint256 quote) = helper.getPoolAndQuote(WETH, USDC, amountIn);
        console.log("Quote:", quote);
        uint256 minAmountOut = (quote * 95) / 100;
        console.log("Min Amount Out:", minAmountOut);

        uint256 initialUsdcBalance = IERC20(USDC).balanceOf(user);

        console.log("Initial USDC Balance:", initialUsdcBalance);

        helper.executeSwap(WETH, USDC, amountIn, minAmountOut);

        uint256 finalUsdcBalance = IERC20(USDC).balanceOf(user);

        console.log("Final USDC Balance:", finalUsdcBalance);
        assertTrue(finalUsdcBalance > initialUsdcBalance, "USDC balance should increase");

        console.log("USDC Received:", (finalUsdcBalance - initialUsdcBalance) / 1e6);

        vm.stopPrank();
    }
}
