// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {UniswapV3Swapper} from "../src/UniswapV3Swapper.sol";
import {TWAPPriceProvider} from "../src/TWAPPriceProvider.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract UniswapV3SwapperTest is Test {
    // --- Mainnet Addresses ---
    IERC20Metadata constant WETH = IERC20Metadata(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20Metadata constant USDC = IERC20Metadata(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address constant UNISWAP_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    // WETH/USDC 0.05% Pool
    address constant WETH_USDC_POOL = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

    UniswapV3Swapper swapper;
    TWAPPriceProvider twapProvider;
    address user = makeAddr("user");

    function setUp() public {
        // Fork Mainnet
        string memory mainnetRpc = vm.envString("MAINNET_RPC_URL");
        vm.createSelectFork(mainnetRpc);

        // Deploy our contracts
        twapProvider = new TWAPPriceProvider(address(this));
        swapper = new UniswapV3Swapper(UNISWAP_ROUTER, address(twapProvider));

        // Register the WETH/USDC pool in our TWAP provider
        twapProvider.registerPool(address(WETH), address(USDC), WETH_USDC_POOL, 500);
    }

    function test_Fails_SwapWithNormalSlippage() public {
        uint256 amountIn = 1 ether;

        // Give the user some WETH
        deal(address(WETH), user, amountIn);

        // Path for the swap
        address[] memory path = new address[](2);
        path[0] = address(WETH);
        path[1] = address(USDC);
        uint24[] memory fees = new uint24[](1);
        fees[0] = 500;

        vm.startPrank(user);
        WETH.approve(address(swapper), amountIn);

        // We EXPECT this transaction to revert because the TWAP-based quote
        // will not match the live spot price required by the Uniswap Router.
        // The router will see that it cannot provide the amountOutMinimum.
        vm.expectRevert();
        swapper.swapExactInput(path, fees, amountIn);

        vm.stopPrank();
    }
}