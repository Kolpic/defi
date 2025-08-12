# DeFi Smart Contracts Collection

A comprehensive collection of DeFi smart contracts built with Foundry, featuring Uniswap V3 integration, TWAP price providers, and more.

## 📁 Projects

### 🦄 [Uniswap V3 Swapper](./uniswap-v3/)

A smart contract that integrates with Uniswap V3 as a swap provider, supporting both single-hop and multi-hop routes.

**Features:**

- ✅ Swaps based on desired output amount (minimum input)
- ✅ Swaps based on specified input amount (maximum output)
- ✅ Support for both single-hop and multi-hop routes
- ✅ Internal slippage handling
- ✅ Predefined token pairs support

**Key Functions:**

- `swapExactInput()` - Swap with exact input amount
- `swapExactOutput()` - Swap with exact output amount
- Configurable slippage tolerance

### 📊 [TWAP Price Provider](./TWAP-price-provider/)

A smart contract that integrates with Uniswap V3 as a TWAP (Time-Weighted Average Price) provider for price feeds.

**Features:**

- ✅ Fetching prices of assets denominated in other assets (e.g., ETH in USDC, ETH in WBTC)
- ✅ Supporting predefined token pairs only
- ✅ Configurable observation times (30min - 2 hours)
- ✅ Uses Uniswap's official OracleLibrary for accurate TWAP calculations

**Key Functions:**

- `getTWAPPrice()` - Get TWAP price with custom observation time
- `getQuote()` - Get quote for swap
- Pool management (register, activate, deactivate)

### 🏦 [Aave V3 Integration](./aave-v3/)

_Coming soon..._

## 🛠️ Technology Stack

- **Framework**: Foundry
- **Language**: Solidity
- **Testing**: Forge (with mainnet forking)
- **Dependencies**:
  - Uniswap V3 Core & Periphery
  - OpenZeppelin Contracts
  - Forge Standard Library

## 🚀 Getting Started

### Prerequisites

1. **Install Foundry**

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. **Clone the repository**

```bash
git clone <your-repo-url>
cd defi
```

3. **Install dependencies**

```bash
forge install
```

4. **Set up environment variables**

```bash
# Create .env file
cp .env.example .env

# Add your RPC URLs
export MAINNET_RPC_URL=https://mainnet.infura.io/v3/YOUR_KEY
export SEPOLIA_RPC_URL=https://sepolia.infura.io/v3/YOUR_KEY
```

### Running Tests

#### Uniswap V3 Swapper Tests

```bash
cd uniswap-v3
forge test --match-test test_DeployAndCheckSetup -vvv
```

#### TWAP Price Provider Tests

```bash
cd TWAP-price-provider
forge test --match-test testGetTWAPPrice_WETH_to_USDC -vvv
```

#### All Tests

```bash
# From the root directory
forge test --recursive -vvv
```

## 📋 Requirements Met

### Uniswap V3 Swapper ✅

- ✅ **Core Functionality**: Contract integrates with Uniswap V3 as a swap provider
- ✅ **Swap Types**: Supports both exact input and exact output swaps
- ✅ **Predefined Pairs**: Only predefined token pairs supported
- ✅ **Multi-hop Support**: Both single-hop and multi-hop routes
- ✅ **Slippage Handling**: Internal slippage management

### TWAP Price Provider ✅

- ✅ **Core Functionality**: Contract integrates with Uniswap V3 as a TWAP price provider
- ✅ **Price Fetching**: Can fetch prices of assets denominated in other assets
- ✅ **Predefined Pairs**: Only predefined token pairs supported

## 🔗 Integration

The contracts are designed to work together:

```solidity
// Use TWAP for price oracle
(uint256 twapPrice, ) = twapProvider.getTWAPPrice(WETH, USDC, 1e18);

// Use Swapper for actual trades
uint256 amountOut = swapper.swapExactInput(path, fees, amountIn);
```

## 🧪 Testing

All contracts include comprehensive fork tests that run against mainnet:

- **Unit Tests**: Basic functionality and edge cases
- **Fork Tests**: Real mainnet integration tests
- **Integration Tests**: Cross-contract functionality

## 📝 License

MIT License - see individual project directories for specific licenses.

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## 📞 Support

For questions or issues, please open an issue in the repository.
