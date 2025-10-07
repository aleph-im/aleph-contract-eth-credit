# Quick Start Guide - AlephPaymentProcessor

## 🚀 Get Started in 5 Minutes

This guide walks you through setting up and using the AlephPaymentProcessor contract for the first time.

## Prerequisites

- Deployed AlephPaymentProcessor contract
- Owner/Admin wallet access
- ALEPH token address
- Tokens you want to process payments for

## Step 1: Initialize the Contract

```solidity
// Example initialization on Ethereum Mainnet
alephPaymentProcessor.initialize(
    0x27702a26126e0B3702af63Ee09aC4d1A084EF628, // ALEPH token
    0x1234..., // Distribution recipient address
    0x5678..., // Developers recipient address
    20,        // 20% burn percentage
    30,        // 30% developers percentage
    0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD, // Universal Router
    0x000000000022D473030F116dDEE9F6B43aC78BA3, // Permit2
    0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2  // WETH
);
```

**Result**: Contract is ready to accept configurations and process payments.

## Step 2: Configure Your First Token

### Option A: Accept ETH Payments (Simplest)

```solidity
// Configure ETH -> ALEPH swapping via Uniswap V2
address[] memory ethPath = new address[](2);
ethPath[0] = address(0);        // ETH (auto-converted to WETH)
ethPath[1] = alephTokenAddress; // ALEPH

alephPaymentProcessor.setSwapConfigV2(address(0), ethPath);
```

### Option B: Accept USDC Payments

```solidity
// Configure USDC -> WETH -> ALEPH path
address[] memory usdcPath = new address[](3);
usdcPath[0] = 0xA0b86a33E6441986f0b01B4C31e2B46cE6E3D0a0; // USDC
usdcPath[1] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH
usdcPath[2] = alephTokenAddress; // ALEPH

alephPaymentProcessor.setSwapConfigV2(usdcTokenAddress, usdcPath);
```

**Result**: Contract can now process ETH or USDC payments.

## Step 3: Set Up an Admin

```solidity
// Grant admin role to a processing wallet
alephPaymentProcessor.addAdmin(0x9ABC...); // Admin wallet address
```

**Result**: Admin can now process payments without being the contract owner.

## Step 4: Process Your First Payment

### Send tokens to the contract first:
```solidity
// For ETH: Send directly to contract
(bool success,) = address(alephPaymentProcessor).call{value: 1 ether}("");

// For ERC20: Transfer to contract
IERC20(usdcToken).transfer(address(alephPaymentProcessor), 1000 * 1e6); // 1000 USDC
```

### Process the payment:
```solidity
// Process all available ETH with 5% slippage protection
uint128 minAlephOut = calculateMinOutput(1 ether, 0.95); // 95% of expected output
alephPaymentProcessor.process(
    address(0),  // ETH
    0,          // Process all available balance
    minAlephOut, // Minimum ALEPH output
    300         // 5 minute deadline
);
```

**Result**:
- ETH swapped to ALEPH
- 20% of ALEPH burned (sent to address(0))
- 30% of ALEPH sent to developers
- 50% of ALEPH sent to distribution recipient

## Step 5: Verify Results

Check the transaction events:
```solidity
// Listen for TokenPaymentsProcessed event
event TokenPaymentsProcessed(
    address indexed token,      // address(0) for ETH
    address indexed sender,     // Admin who processed
    uint256 amount,            // 1 ether
    uint256 swapAmount,        // 1 ether (same for ETH)
    uint256 alephReceived,     // ALEPH tokens received
    uint256 amountBurned,      // ALEPH burned (20%)
    uint256 amountToDistribution, // ALEPH to distribution (50%)
    uint256 amountToDevelopers,   // ALEPH to developers (30%)
    uint8 swapVersion,         // 2 (Uniswap V2)
    bool isStable             // false
);
```

## Common Usage Patterns

### 1. Regular Payment Processing

```solidity
// Daily processing script
function processDailyPayments() external onlyAdmin {
    // Process ETH
    if (address(this).balance > 0) {
        process(address(0), 0, calculateMinOutput(address(this).balance), 300);
    }

    // Process USDC
    uint256 usdcBalance = IERC20(usdc).balanceOf(address(this));
    if (usdcBalance > 0) {
        process(usdc, 0, calculateMinOutput(usdcBalance), 300);
    }
}
```

### 2. Stable Token Handling

```solidity
// Mark USDC as stable (developers get USDC directly, not ALEPH)
alephPaymentProcessor.setStableToken(usdcAddress, true);

// Now when processing USDC:
// - 30% USDC sent directly to developers
// - 70% USDC swapped to ALEPH, then distributed (20% burn + 50% distribution)
```

### 3. Emergency Withdrawal

```solidity
// Withdraw unconfigured tokens
alephPaymentProcessor.withdraw(
    unknownTokenAddress,
    emergencyWallet,
    0 // Withdraw all
);
```

## Quick Troubleshooting

### ❌ "NotConfigured" error
**Problem**: Token doesn't have swap configuration
**Solution**: Call `setSwapConfigV2()`, `setSwapConfigV3()`, or `setSwapConfigV4()`

### ❌ "PendingBalance" error
**Problem**: ALEPH tokens left in contract from previous processing
**Solution**: Process ALEPH directly: `process(alephAddress, 0, 0, 300)`

### ❌ "InsufficientBalance" error
**Problem**: Not enough tokens in contract
**Solution**: Send tokens to contract first, then process

### ❌ "TtlOutOfRange" error
**Problem**: TTL not between 60-3600 seconds
**Solution**: Use TTL between 1-60 minutes: `process(token, amount, minOut, 300)`

## Next Steps

1. **Read the Full Documentation**: [Complete Contract Documentation](./ALEPH_PAYMENT_PROCESSOR_DOCS.md)
2. **Configure More Tokens**: [Uniswap Configuration Examples](./UNISWAP_CONFIG_EXAMPLES.md)
3. **Set Up Monitoring**: Listen to contract events for payment tracking
4. **Automate Processing**: Create scripts for regular payment processing
5. **Security Setup**: Use multi-sig wallets for owner operations

## Production Checklist

- [ ] Contract deployed behind upgradeable proxy
- [ ] Owner set to multi-signature wallet
- [ ] Admin roles granted to processing wallets
- [ ] All payment tokens configured with optimal swap paths
- [ ] Stable tokens marked appropriately
- [ ] Monitoring and alerting configured
- [ ] Emergency procedures documented
- [ ] Regular processing automation deployed

Ready to dive deeper? Check out the [Complete Documentation](./ALEPH_PAYMENT_PROCESSOR_DOCS.md) for advanced features and security considerations.