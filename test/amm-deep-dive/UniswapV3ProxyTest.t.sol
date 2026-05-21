// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {UniswapV3Proxy} from "../../src/amm-deep-dive/UniswapV3Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV3Proxy} from "../../src/amm-deep-dive/interfaces/IUniswapV3Proxy.sol";

contract UniswapV3ProxyTest is Test {
    UniswapV3Proxy public proxy;

    address constant ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant POS_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address constant FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant QUOTER = 0x61fFE014bA17989E743c5F6cB21bF9697530B21e;

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address user = address(1);

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), 19000000);

        proxy = new UniswapV3Proxy(ROUTER, POS_MANAGER, FACTORY, QUOTER);

        deal(WETH, user, 10 ether);
        deal(USDC, user, 50000 * 1e6);
    }

    function test_SwapExactInput() public {
        vm.startPrank(user);
        IERC20(WETH).approve(address(proxy), 1 ether);

        uint256 amountOut = proxy.swapExactInputSingle(WETH, USDC, 1 ether);

        assertTrue(amountOut > 0);
        vm.stopPrank();
    }

    function test_CustomSlippageRevert() public {
        vm.startPrank(user);

        // Set slippage to 0.01% (extremely low, should fail)
        proxy.setSlippageTolerance(1);

        IERC20(WETH).approve(address(proxy), 1 ether);

        // Expect revert due to slippage
        vm.expectRevert();
        proxy.swapExactInputSingle(WETH, USDC, 1 ether);

        vm.stopPrank();
    }

    function test_AddLiquidity() public {
        vm.startPrank(user);
        
        proxy.setSlippageTolerance(1000); 

        uint256 amountWETH = 1 ether;
        uint256 amountUSDC = 10000 * 1e6;

        IERC20(WETH).approve(address(proxy), amountWETH);
        IERC20(USDC).approve(address(proxy), amountUSDC);

        // Standard 0.3% fee pool
        (uint256 tokenId, , , ) = proxy.addLiquidity(
            WETH, USDC, 3000, -887220, 887220, amountWETH, amountUSDC
        );

        assertTrue(tokenId > 0);
        vm.stopPrank();
    }
}
