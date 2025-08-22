# AlephPaymentProcessor

A smart contract for processing token payments by automatically swapping them to ALEPH tokens through Uniswap and distributing the proceeds according to configured percentages.

## Overview

The AlephPaymentProcessor is an upgradeable smart contract that:

- **Accepts payments** in native ETH or any ERC20 token
- **Automatically swaps** received tokens to ALEPH using Uniswap V2, V3, or V4
- **Distributes proceeds** according to configurable percentages:
  - **Burn percentage**: Tokens sent to address(0) for burning
  - **Developers percentage**: Tokens sent to developers recipient
  - **Distribution percentage**: Remaining tokens sent to distribution recipient
- **Supports stable tokens**: Special handling where developers portion is sent directly without swapping
- **Uses Universal Router v2**: For optimal gas efficiency and routing
- **Role-based access**: Admin roles for processing payments, owner controls for configuration

## Key Features

### Multi-Version Uniswap Support
- **V2**: Direct address array paths
- **V3**: Encoded paths with fee tiers
- **V4**: PathKey arrays with hooks support

### Native ETH Support
- Configure swaps using `address(0)` for ETH
- Automatic WETH wrapping during swaps
- Address replacement optimization during configuration

### Flexible Token Processing
- **Stable tokens**: Developers portion sent directly, rest swapped to ALEPH
- **Regular tokens**: Full amount swapped to ALEPH, then distributed proportionally
- **ALEPH tokens**: Direct distribution without swapping

### Security & Access Control
- **Upgradeable**: Uses OpenZeppelin's upgradeable contracts
- **Role-based**: Separate admin and owner roles
- **Validation**: Comprehensive input validation for all configurations

## Contract Architecture

```solidity
struct TokenConfig {
    uint8 version;        // 2, 3, or 4 (Uniswap version)
    address token;        // Token address
    PathKey[] v4Path;     // V4 swap path
    bytes v3Path;         // V3 encoded path
    address[] v2Path;     // V2 address path
}
```

## Usage Examples

See [UNISWAP_CONFIG_EXAMPLES.md](./UNISWAP_CONFIG_EXAMPLES.md) for detailed configuration examples for all Uniswap versions.

## Development Setup

### Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Install

### foundry

```sh
# Download foundry installer `foundryup`
$ curl -L https://foundry.paradigm.xyz | bash

# Install forge, cast, anvil, chisel
$ foundryup

# Install the latest nightly release
$ foundryup -i nightly
```

### lcov (coverage reports)

```sh
# Linux
$ sudo apt-get update sudo apt-get install lcov

# macOS
$ brew install lcov
```

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

The contract includes comprehensive test coverage with 170 tests covering:
- All Uniswap versions (V2, V3, V4)
- ETH and ERC20 token processing
- Edge cases and error conditions
- Access control and validation
- Universal Router v2 integration

Run all tests with:
```shell
$ sh/test.sh
```

Or run Forge tests directly:
```shell
$ forge test
```

Run specific tests:
```shell
$ forge test --match-test "test_process_swap_V2_ETH_to_ALEPH"
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

## Main Functions

### Core Processing
- `process(token, amountIn, amountOutMinimum, ttl)` - Process token payments
- `withdraw(token, to, amount)` - Withdraw unconfigured tokens

### Configuration Management
- `setTokenConfigV2(token, path)` - Configure V2 swap path
- `setTokenConfigV3(token, path)` - Configure V3 encoded path  
- `setTokenConfigV4(token, path)` - Configure V4 PathKey array
- `removeTokenConfig(token)` - Remove token configuration

### Parameter Management
- `setBurnPercentage(percentage)` - Set burn percentage (0-100)
- `setDevelopersPercentage(percentage)` - Set developers percentage (0-100)
- `setDistributionRecipient(address)` - Set distribution recipient
- `setDevelopersRecipient(address)` - Set developers recipient
- `setStableToken(token, isStable)` - Mark token as stable

### Access Control
- `addAdmin(address)` - Grant admin role
- `removeAdmin(address)` - Revoke admin role

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
