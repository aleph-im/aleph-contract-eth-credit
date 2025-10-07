# AlephPaymentProcessor Contract Documentation

## Overview

The **AlephPaymentProcessor** is a sophisticated smart contract designed to process token payments by automatically swapping them to ALEPH tokens through Uniswap (V2, V3, and V4) and distributing the proceeds according to configurable percentages. The contract supports both native ETH and ERC20 tokens, featuring optimal routing through Uniswap's Universal Router v2 for gas efficiency.

## Core Functionality

The contract serves as a payment processor that:
1. **Receives payments** in various tokens (including ETH)
2. **Swaps tokens** to ALEPH via Uniswap protocols (V2/V3/V4)
3. **Distributes proceeds** across three categories:
   - **Burn**: Tokens sent to address(0) for permanent removal
   - **Developers**: Allocated to development team
   - **Distribution**: Sent to distribution recipient

## Architecture

### Inheritance Chain
```solidity
AlephPaymentProcessor is
    Initializable,           // Upgradeable proxy initialization
    Ownable2StepUpgradeable, // Two-step ownership transfer
    AccessControlUpgradeable, // Role-based access control
    ReentrancyGuardUpgradeable // Protection against reentrancy attacks
```

### Core Dependencies
- **OpenZeppelin Contracts**: Security, access control, and utilities
- **Uniswap Universal Router**: Multi-version DEX routing
- **Uniswap Permit2**: Gas-efficient token approvals
- **AlephSwapLibrary**: Custom swap logic abstraction

## State Variables

### Configuration Parameters
```solidity
address public distributionRecipient;  // Receives distribution portion
address public developersRecipient;    // Receives developers portion
uint8 public burnPercentage;          // Percentage to burn (0-100)
uint8 public developersPercentage;    // Percentage for developers (0-100)
```

### Access Control
```solidity
bytes32 public adminRole;  // Role for processing payments and withdrawals
```

### Token Configuration
```solidity
IERC20 internal aleph;                    // ALEPH token contract
address internal wethAddress;             // Wrapped ETH address
mapping(address => bool) public isStableToken;  // Stable token flags
mapping(address => SwapConfig) internal swapConfig;  // Swap configurations
```

### Uniswap Integration
```solidity
UniversalRouter internal router;  // Universal Router v2
IPermit2 internal permit2;        // Permit2 for approvals
```

## Public Interface

### Core Functions

#### `initialize()`
```solidity
function initialize(
    address _alephTokenAddress,
    address _distributionRecipientAddress,
    address _developersRecipientAddress,
    uint8 _burnPercentage,
    uint8 _developersPercentage,
    address _uniswapRouterAddress,
    address _permit2Address,
    address _wethAddress
) public initializer
```
**Purpose**: Initializes the contract with required parameters
**Access**: One-time only (initializer modifier)
**Validation**:
- All addresses must be non-zero
- Combined percentages cannot exceed 100%

#### `process()`
```solidity
function process(
    address _token,
    uint128 _amountIn,
    uint128 _amountOutMinimum,
    uint48 _ttl
) external onlyRole(adminRole) nonReentrant
```
**Purpose**: Main payment processing function
**Access**: Admin role only
**Parameters**:
- `_token`: Token address to process (address(0) for ETH)
- `_amountIn`: Amount to process (0 for full balance)
- `_amountOutMinimum`: Minimum ALEPH output expected
- `_ttl`: Transaction time-to-live (60-3600 seconds)

**Logic Flow**:
1. **Validation**: Checks TTL range, pending balances, and swap configuration
2. **Balance Calculation**: Determines actual amount to process
3. **Stable Token Handling**:
   - Stable tokens: Send developers portion directly, swap remainder
   - Non-stable tokens: Swap entire amount, then distribute proportionally
4. **Distribution**: Allocates proceeds according to configured percentages

#### `withdraw()`
```solidity
function withdraw(
    address _token,
    address payable _to,
    uint128 _amount
) external onlyRole(adminRole) nonReentrant
```
**Purpose**: Withdraws tokens not configured for processing
**Access**: Admin role only
**Restrictions**: Cannot withdraw ALEPH or configured tokens

### Configuration Functions (Owner Only)

#### Percentage Management
```solidity
function setBurnPercentage(uint8 _newBurnPercentage) external onlyOwner
function setDevelopersPercentage(uint8 _newDevelopersPercentage) external onlyOwner
```

#### Recipient Management
```solidity
function setDistributionRecipient(address _newDistributionRecipient) external onlyOwner
function setDevelopersRecipient(address _newDevelopersRecipient) external onlyOwner
```

#### Token Configuration
```solidity
function setStableToken(address _token, bool _isStable) external onlyOwner
```

#### Swap Configuration
```solidity
function setSwapConfigV2(address _address, address[] calldata _v2Path) external onlyOwner
function setSwapConfigV3(address _address, bytes calldata _v3Path) external onlyOwner
function setSwapConfigV4(address _address, PathKey[] calldata _v4Path) external onlyOwner
function removeSwapConfig(address _address) external onlyOwner
```

#### Access Management
```solidity
function addAdmin(address _newAdmin) external onlyOwner
function removeAdmin(address _admin) external onlyOwner
```

### View Functions

#### `getSwapConfig()`
```solidity
function getSwapConfig(address _address) external view returns (SwapConfig memory)
```
Returns the swap configuration for a token.

#### `getAmountIn()` (Internal)
```solidity
function getAmountIn(address _token, uint128 _amountIn) internal view returns (uint128)
```
Calculates actual processing amount, using full balance if `_amountIn` is 0.

## Swap Configuration System

### SwapConfig Struct
```solidity
struct SwapConfig {
    uint8 v;          // Uniswap version (2, 3, or 4)
    address t;        // Token address
    address[] v2;     // V2 swap path
    bytes v3;         // V3 encoded path
    PathKey[] v4;     // V4 path keys
}
```

### Version-Specific Configuration

#### Uniswap V2
- **Path Format**: Array of token addresses
- **Requirements**: 2-5 tokens in path, must end with ALEPH
- **Example**: `[TOKEN, WETH, ALEPH]`

#### Uniswap V3
- **Path Format**: Encoded bytes with fee tiers
- **Requirements**: 43-200 bytes, must end with ALEPH
- **Structure**: `token0 + fee + token1 + fee + ... + ALEPH`

#### Uniswap V4
- **Path Format**: Array of PathKey structs
- **Requirements**: 1-5 path keys, must end with ALEPH currency
- **Features**: Advanced routing with hooks and dynamic fees

## Special Token Handling

### Stable Tokens
When `isStableToken[token] == true`:
1. **Developers portion** sent directly in original token
2. **Burn + Distribution portions** swapped to ALEPH
3. **Rationale**: Preserves stable value for developers

### Native ETH
- Uses `address(0)` as identifier
- Automatically wrapped to WETH for Uniswap interactions
- Contract accepts ETH via `receive()` function

## Events

### Payment Processing
```solidity
event TokenPaymentsProcessed(
    address indexed _token,
    address indexed sender,
    uint256 amount,
    uint256 swapAmount,
    uint256 alephReceived,
    uint256 amountBurned,
    uint256 amountToDistribution,
    uint256 amountToDevelopers,
    uint8 swapVersion,
    bool isStable
);
```

### Swap Execution
```solidity
event SwapExecuted(
    address indexed token,
    uint256 amountIn,
    uint256 amountOut,
    uint8 version,
    uint256 timestamp
);
```

### Configuration Updates
- `SwapConfigUpdated`
- `SwapConfigRemoved`
- `DistributionRecipientUpdated`
- `DevelopersRecipientUpdated`
- `BurnPercentageUpdated`
- `DevelopersPercentageUpdated`
- `StableTokenUpdated`

## Security Features

### Access Control
- **Two-Step Ownership**: Prevents accidental ownership transfers
- **Role-Based Access**: Separates administrative and operational roles
- **Admin Role**: Can process payments and withdraw unconfigured tokens
- **Owner Role**: Can modify all configurations and manage roles

### Reentrancy Protection
- All state-changing functions use `nonReentrant` modifier
- Prevents attacks during external calls

### Input Validation
- Address zero checks for all addresses
- Percentage validation (0-100% range, sum ≤ 100%)
- Path validation for all Uniswap versions
- TTL bounds checking (60-3600 seconds)

### Balance Protection
- Prevents processing when ALEPH balance exists (ensures clean state)
- Cannot withdraw configured or ALEPH tokens
- Balance checks before transfers

## Gas Optimization

### Storage Caching
```solidity
// Cache storage variables in memory for multiple reads
uint8 cachedDevelopersPercentage = developersPercentage;
uint8 cachedBurnPercentage = burnPercentage;
address cachedDevelopersRecipient = developersRecipient;
```

### Permit2 Integration
- Reduces gas costs for token approvals
- Batched approval and transfer operations

### Universal Router
- Optimal routing across Uniswap versions
- Minimized intermediate token transfers

## Error Handling

### Custom Errors
```solidity
error InvalidAddress();      // Zero address provided
error InvalidPercentage();   // Percentage > 100%
error ExceedsTotal();       // Combined percentages > 100%
error TtlOutOfRange();      // TTL not in 60-3600 range
error PendingBalance();     // ALEPH balance exists during processing
error NotConfigured();      // Token lacks swap configuration
error InsufficientBalance(); // Insufficient token balance
error CannotWithdraw();     // Attempting to withdraw configured token
error InvalidSwapConfig();  // Invalid swap configuration
error InsufficientOutput(); // Swap output below minimum
```

## Usage Patterns

### Payment Processing Workflow

#### Step-by-Step Process
1. **Token Receipt**: Tokens sent to contract (ETH or ERC20)
   ```solidity
   // ETH: Send directly to contract
   (bool success,) = contractAddress.call{value: 1 ether}("");

   // ERC20: Transfer to contract
   IERC20(token).transfer(contractAddress, amount);
   ```

2. **Configuration**: Owner sets swap configuration for token
   ```solidity
   // Configure ETH -> ALEPH via Uniswap V2
   address[] memory path = new address[](2);
   path[0] = address(0);  // ETH
   path[1] = alephAddress; // ALEPH
   contract.setSwapConfigV2(address(0), path);
   ```

3. **Processing**: Admin calls `process()` with parameters
   ```solidity
   // Process all ETH with 5% slippage protection
   contract.process(
       address(0),          // Token (ETH)
       0,                  // Amount (0 = all balance)
       minOutputAmount,    // Slippage protection
       300                // 5 minute deadline
   );
   ```

4. **Distribution**: Contract automatically distributes proceeds
   - Swaps tokens to ALEPH via Uniswap
   - Burns configured percentage
   - Sends developers percentage
   - Sends remainder to distribution recipient

#### Processing Flow Diagram
```
Token Input → Swap Config Check → Amount Calculation
     ↓
Stable Token? → [Yes] → Direct Transfer (Dev) + Swap (Burn+Dist)
     ↓          [No]  → Swap All → Proportional Distribution
Distribution:
├── Burn Address (X%)
├── Developers (Y%)
└── Distribution (100-X-Y%)
```

### Configuration Workflow

#### Initial Setup
```solidity
// 1. Deploy & Initialize
contract.initialize(
    alephAddress,        // ALEPH token
    distributionAddr,    // Distribution recipient
    developersAddr,      // Developers recipient
    20,                 // 20% burn
    30,                 // 30% developers
    routerAddress,      // Universal Router
    permit2Address,     // Permit2
    wethAddress        // WETH
);

// 2. Configure supported tokens
contract.setSwapConfigV2(ethAddress, ethPath);
contract.setSwapConfigV3(usdcAddress, usdcPath);

// 3. Grant admin role for processing
contract.addAdmin(processingWallet);

// 4. Mark stable tokens (optional)
contract.setStableToken(usdcAddress, true);
```

#### Ongoing Configuration Management
```solidity
// Update percentages
contract.setBurnPercentage(25);          // Change burn to 25%
contract.setDevelopersPercentage(35);    // Change dev to 35%

// Update recipients
contract.setDistributionRecipient(newAddr);
contract.setDevelopersRecipient(newDevAddr);

// Modify token configurations
contract.setSwapConfigV3(token, newV3Path);  // Upgrade to V3
contract.removeSwapConfig(token);            // Disable processing
```

### Emergency Procedures

#### Immediate Response
1. **Pause Processing**: Remove admin roles temporarily
   ```solidity
   contract.removeAdmin(compromisedAdmin);
   ```

2. **Secure Funds**: Withdraw unconfigured tokens
   ```solidity
   contract.withdraw(tokenAddress, emergencyWallet, 0);
   ```

3. **Investigate**: Check transaction history and identify issues

#### Recovery Actions
1. **Fix Configuration**: Update paths, percentages, or recipients
   ```solidity
   contract.setSwapConfigV2(token, correctedPath);
   contract.setDistributionRecipient(secureWallet);
   ```

2. **Resume Operations**: Re-grant admin roles after verification
   ```solidity
   contract.addAdmin(verifiedAdmin);
   ```

3. **Monitor**: Enhanced monitoring for suspicious activity

## Integration Guidelines

### For Frontend Applications
```typescript
// Check if token is configured
const config = await contract.getSwapConfig(tokenAddress);
const isConfigured = config.v > 0;

// Process payment with slippage protection
const amountOutMin = calculateMinOutput(amountIn, slippageTolerance);
await contract.process(tokenAddress, amountIn, amountOutMin, 300); // 5 min TTL
```

### For Backend Services
```javascript
// Monitor payment events
contract.on('TokenPaymentsProcessed', (
    token, sender, amount, swapAmount, alephReceived,
    amountBurned, amountToDistribution, amountToDevelopers,
    swapVersion, isStable
) => {
    // Process payment data
    logPayment(token, amount, alephReceived);
});
```

## Deployment Considerations

### Network Requirements
- Uniswap Universal Router deployment
- Permit2 contract availability
- WETH contract address
- ALEPH token deployment

### Initial Configuration
```solidity
// Example initialization
initialize(
    "0x...", // ALEPH token
    "0x...", // Distribution recipient
    "0x...", // Developers recipient
    20,      // 20% burn
    30,      // 30% developers
    "0x...", // Universal Router
    "0x...", // Permit2
    "0x..."  // WETH
);
```

### Production Setup
1. Deploy behind upgradeable proxy
2. Set up multi-signature wallet as owner
3. Configure monitoring and alerting
4. Implement automated processing scripts
5. Set up emergency response procedures

## Best Practices

### For Administrators
- Use hardware wallets for owner operations
- Test swap configurations on small amounts first
- Monitor gas prices for optimal processing timing
- Keep TTL values reasonable (300-600 seconds typical)

### For Developers
- Always validate swap configurations before deployment
- Implement proper error handling for failed swaps
- Use events for monitoring and analytics
- Consider MEV protection for large swaps

### For Integration
- Check token approval requirements
- Handle failed transactions gracefully
- Implement retry mechanisms with exponential backoff
- Monitor contract events for payment confirmation

This comprehensive documentation covers the AlephPaymentProcessor contract's functionality, security features, and integration patterns, providing a complete guide for users, administrators, and developers working with the system.