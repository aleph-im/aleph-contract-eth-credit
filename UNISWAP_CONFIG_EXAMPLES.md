# Uniswap Token Configuration Examples

This document provides examples of how to configure tokens for different Uniswap versions (V2, V3, V4) in the AlephPaymentProcessor contract.

## Overview

The `TokenConfig` struct supports all three Uniswap versions with automatic address replacement and validation:

```solidity
struct TokenConfig {
    uint8 version;        // 2, 3, or 4
    address token;        // Token address (use address(0) for native ETH)
    PathKey[] v4Path;     // For Uniswap V4 pools
    bytes v3Path;         // For Uniswap V3 encoded paths  
    address[] v2Path;     // For Uniswap V2 address arrays
}
```

## ⚡ Native ETH Support

All configurations support native ETH by using `address(0)` in paths. The contract automatically replaces `address(0)` with WETH during configuration for optimal runtime performance.

## Validation Requirements

- **V2 paths**: Must have at least 2 addresses
- **V3 paths**: Must be at least 43 bytes (address + fee + address)
- **V4 paths**: Must have at least 1 PathKey element

## Uniswap V2 Configuration

V2 uses simple address arrays for swap paths. The contract automatically replaces `address(0)` with WETH during configuration.

### Example 1: Native ETH → ALEPH

```solidity
address alephTokenAddress = 0x27702a26126e0B3702af63Ee09aC4d1A084EF628;

// Configure native ETH swaps using address(0)
address[] memory ethPath = new address[](2);
ethPath[0] = address(0);        // ETH (auto-replaced with WETH)
ethPath[1] = alephTokenAddress; // ALEPH

alephPaymentProcessor.setTokenConfigV2(address(0), ethPath);

// Usage: Process native ETH
alephPaymentProcessor.process(address(0), 1 ether, 0, 300);
```

### Example 2: ERC20 Direct Pair (WETH → ALEPH)

```solidity
address wethTokenAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
address alephTokenAddress = 0x27702a26126e0B3702af63Ee09aC4d1A084EF628;

address[] memory v2Path = new address[](2);
v2Path[0] = wethTokenAddress;   // WETH
v2Path[1] = alephTokenAddress;  // ALEPH

alephPaymentProcessor.setTokenConfigV2(wethTokenAddress, v2Path);
```

### Example 3: Multi-hop (USDC → WETH → ALEPH)

```solidity  
address usdcTokenAddress = 0xA0b86a33E6441986f0b01B4C31e2B46cE6E3D0a0;
address wethTokenAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
address alephTokenAddress = 0x27702a26126e0B3702af63Ee09aC4d1A084EF628;

address[] memory v2Path = new address[](3);
v2Path[0] = usdcTokenAddress;   // USDC
v2Path[1] = wethTokenAddress;   // WETH (intermediate)
v2Path[2] = alephTokenAddress;  // ALEPH

alephPaymentProcessor.setTokenConfigV2(usdcTokenAddress, v2Path);
```

## Uniswap V3 Configuration

V3 uses encoded byte paths that include fee tiers. The contract automatically replaces `address(0)` with WETH during configuration.

### Example 1: Native ETH → ALEPH (1% fee)

```solidity
address alephTokenAddress = 0x27702a26126e0B3702af63Ee09aC4d1A084EF628;

// Configure native ETH swaps using address(0)  
bytes memory ethV3Path = abi.encodePacked(
    address(0),     // ETH (auto-replaced with WETH)
    uint24(10000),  // 1% fee = 10000
    alephTokenAddress
);

alephPaymentProcessor.setTokenConfigV3(address(0), ethV3Path);

// Usage: Process native ETH
alephPaymentProcessor.process(address(0), 0.5 ether, 0, 300);
```

### Example 2: ERC20 Direct Pair (WETH → ALEPH, 1% fee)

```solidity
address wethTokenAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
address alephTokenAddress = 0x27702a26126e0B3702af63Ee09aC4d1A084EF628;

bytes memory v3Path = abi.encodePacked(
    wethTokenAddress,           // WETH
    uint24(10000),             // 1% fee = 10000
    alephTokenAddress          // ALEPH
);

alephPaymentProcessor.setTokenConfigV3(wethTokenAddress, v3Path);
```

### Example 3: Multi-hop (UNI → WETH → ALEPH, 0.3% fees)

```solidity
address uniTokenAddress = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
address wethTokenAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; 
address alephTokenAddress = 0x27702a26126e0B3702af63Ee09aC4d1A084EF628;

bytes memory v3Path = abi.encodePacked(
    uniTokenAddress,           // UNI
    uint24(3000),             // 0.3% fee = 3000
    wethTokenAddress,         // WETH (intermediate)
    uint24(3000),             // 0.3% fee = 3000
    alephTokenAddress         // ALEPH
);

alephPaymentProcessor.setTokenConfigV3(uniTokenAddress, v3Path);
```

### V3 Fee Tiers

Common Uniswap V3 fee tiers:
- `500` = 0.05%
- `3000` = 0.3% 
- `10000` = 1%

## Uniswap V4 Configuration

V4 uses PathKey arrays with hooks and tick spacing. V4 paths define hops through intermediate currencies.

### Example 1: Native ETH → ALEPH (V4)

```solidity
import {PathKey} from "@uniswap/v4-periphery/src/libraries/PathKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

address alephTokenAddress = 0x27702a26126e0B3702af63Ee09aC4d1A084EF628;

// Configure native ETH → ALEPH swap
PathKey[] memory ethV4Path = new PathKey[](1);
ethV4Path[0] = PathKey({
    intermediateCurrency: Currency.wrap(alephTokenAddress),  // Target: ALEPH
    fee: 10000,                    // 1% fee
    tickSpacing: 200,              // Tick spacing for 1% fee
    hooks: IHooks(address(0)),     // No hooks
    hookData: bytes("")            // No hook data
});

alephPaymentProcessor.setTokenConfigV4(address(0), ethV4Path);

// Usage: Process native ETH
alephPaymentProcessor.process(address(0), 0.1 ether, 0, 300);
```

### Example 2: ERC20 Token → ALEPH (V4)

```solidity
address usdcTokenAddress = 0xA0b86a33E6441986f0b01B4C31e2B46cE6E3D0a0;
address alephTokenAddress = 0x27702a26126e0B3702af63Ee09aC4d1A084EF628;

PathKey[] memory v4Path = new PathKey[](1);
v4Path[0] = PathKey({
    intermediateCurrency: Currency.wrap(alephTokenAddress),  // Target: ALEPH
    fee: 3000,                     // 0.3% fee  
    tickSpacing: 60,               // Tick spacing for 0.3% fee
    hooks: IHooks(address(0)),     // No hooks
    hookData: bytes("")            // No hook data  
});

alephPaymentProcessor.setTokenConfigV4(usdcTokenAddress, v4Path);
```

### Example 3: Multi-hop with Intermediate Currency (V4)

```solidity
address uniTokenAddress = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
address wethTokenAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
address alephTokenAddress = 0x27702a26126e0B3702af63Ee09aC4d1A084EF628;

// Configure UNI → WETH → ALEPH
PathKey[] memory v4Path = new PathKey[](2);

// First hop: UNI → WETH
v4Path[0] = PathKey({
    intermediateCurrency: Currency.wrap(wethTokenAddress),   // Intermediate: WETH
    fee: 3000,                     // 0.3% fee
    tickSpacing: 60,               // Tick spacing for 0.3% fee
    hooks: IHooks(address(0)),     // No hooks
    hookData: bytes("")            // No hook data
});

// Second hop: WETH → ALEPH  
v4Path[1] = PathKey({
    intermediateCurrency: Currency.wrap(alephTokenAddress),  // Target: ALEPH
    fee: 10000,                    // 1% fee
    tickSpacing: 200,              // Tick spacing for 1% fee
    hooks: IHooks(address(0)),     // No hooks
    hookData: bytes("")            // No hook data
});

alephPaymentProcessor.setTokenConfigV4(uniTokenAddress, v4Path);
```

### V4 Fee Tiers and Tick Spacing

Common Uniswap V4 fee tiers and their corresponding tick spacing:
- Fee `500` (0.05%) = Tick spacing `10`
- Fee `3000` (0.3%) = Tick spacing `60`
- Fee `10000` (1%) = Tick spacing `200`

## 🔧 Address Replacement & ETH Handling

### Automatic WETH Replacement

The contract automatically replaces `address(0)` with WETH during configuration for optimal runtime performance:

```solidity
// Input path (what you configure)
address[] memory inputPath = [address(0), alephTokenAddress];

// Stored path (after replacement during setTokenConfigV2)
address[] memory storedPath = [0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, alephTokenAddress];

// Runtime: Direct path usage (no processing needed)
```

### ETH Processing Flow

When processing `address(0)` (native ETH):

1. **WRAP_ETH**: Native ETH → WETH in Universal Router
2. **SWAP**: WETH → ALEPH using pre-processed path  
3. **TRANSFER**: ALEPH distributed according to percentages

```solidity
// This triggers: ETH → WETH → ALEPH
alephPaymentProcessor.process(address(0), 1 ether, minOutput, ttl);
```

## 📋 Configuration Management

### Check Current Configuration

```solidity
TokenConfig memory config = alephPaymentProcessor.getTokenConfig(tokenAddress);

if (config.version == 2) {
    // V2 configuration
    address[] memory path = config.v2Path;
} else if (config.version == 3) {
    // V3 configuration  
    bytes memory path = config.v3Path;
} else if (config.version == 4) {
    // V4 configuration
    PathKey[] memory path = config.v4Path;
}
```

### Update Configuration Version

Configurations can be updated by calling the appropriate setter function. The new configuration will completely replace the previous one.

```solidity
// Start with V2
alephPaymentProcessor.setTokenConfigV2(tokenAddress, v2Path);

// Update to V3 (overwrites V2 config)
alephPaymentProcessor.setTokenConfigV3(tokenAddress, v3Path);

// Update to V4 (overwrites V3 config)  
alephPaymentProcessor.setTokenConfigV4(tokenAddress, v4Path);
```

### Remove Configuration

```solidity
alephPaymentProcessor.removeTokenConfig(tokenAddress);
```

## Access Control

All configuration functions require owner privileges:

```solidity
modifier onlyOwner() {
    // Only contract owner can configure tokens
}
```

## Usage in Processing

The contract automatically routes swaps to the appropriate Uniswap version based on the token configuration:

```solidity
function process(address _token, uint128 _amountIn, uint128 _amountOutMinimum, uint48 _ttl) external {
    TokenConfig memory config = tokenConfig[_token];
    
    if (config.version == 2) {
        swapV2(_token, _amountIn, _amountOutMinimum, _ttl);
    } else if (config.version == 3) {
        swapV3(_token, _amountIn, _amountOutMinimum, _ttl);
    } else if (config.version == 4) {
        swapV4(_token, _amountIn, _amountOutMinimum, _ttl);
    }
}
```

This allows the contract to seamlessly support tokens across all Uniswap versions while using the existing Universal Router infrastructure.

## ✅ Validation & Best Practices

### Validation Rules

The contract enforces validation during configuration:

```solidity
// V2: Minimum 2 addresses
require(_v2Path.length >= 2, "Invalid V2 path");

// V3: Minimum 43 bytes (20 + 3 + 20)  
require(_v3Path.length >= 43, "V3 path too short");

// V4: Minimum 1 PathKey
require(_v4Path.length > 0, "Empty V4 path");
```

### Best Practices

1. **Use Native ETH**: Configure with `address(0)` for cleaner code
   ```solidity
   // ✅ Good
   path[0] = address(0);  // Auto-replaced with WETH
   
   // ❌ Avoid  
   path[0] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
   ```

2. **Test Pool Liquidity**: Ensure sufficient liquidity exists for your paths
   ```solidity
   // Check pool exists before configuring
   IUniswapV2Pair pair = IUniswapV2Pair(factory.getPair(tokenA, tokenB));
   require(address(pair) != address(0), "Pool doesn't exist");
   ```

3. **Choose Appropriate Fees**: Use common fee tiers for better liquidity
   - V2: No fees (automatic 0.3%)
   - V3: `500` (0.05%), `3000` (0.3%), `10000` (1%)
   - V4: Match tick spacing to fee tier

4. **Minimize Hops**: Shorter paths = lower gas + slippage
   ```solidity
   // ✅ Preferred: Direct pair
   [tokenA, ALEPH]
   
   // ❌ Only if needed: Multi-hop
   [tokenA, WETH, ALEPH]
   ```

5. **Set Reasonable TTL**: Balance between execution time and deadline risk
   ```solidity
   alephPaymentProcessor.process(token, amount, minOutput, 300); // 5 minutes
   ```

## 🔗 Related Functions

- `setTokenConfigV2(address, address[])` - Configure V2 paths
- `setTokenConfigV3(address, bytes)` - Configure V3 paths  
- `setTokenConfigV4(address, PathKey[])` - Configure V4 paths
- `getTokenConfig(address)` - View current configuration
- `removeTokenConfig(address)` - Remove configuration
- `process(address, uint128, uint128, uint48)` - Execute swap and distribute