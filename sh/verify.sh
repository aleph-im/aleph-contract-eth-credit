#!/bin/bash

# Script to verify an existing contract on Etherscan
# Usage: ETHERSCAN_API_KEY=<your_api_key> ./sh/verify.sh <contract_address> [network]
# Example: ETHERSCAN_API_KEY=ABC123 ./sh/verify.sh 0x1234567890123456789012345678901234567890 mainnet

# Check if contract address is provided
if [ -z "$1" ]; then
    echo "Error: Contract address is required"
    echo "Usage: ETHERSCAN_API_KEY=<your_api_key> ./sh/verify.sh <contract_address> [network]"
    echo "Example: ETHERSCAN_API_KEY=ABC123 ./sh/verify.sh 0x1234567890123456789012345678901234567890 mainnet"
    echo ""
    echo "Or set the API key as environment variable:"
    echo "export ETHERSCAN_API_KEY=your_api_key"
    echo "./sh/verify.sh 0x1234567890123456789012345678901234567890 mainnet"
    exit 1
fi

CONTRACT_ADDRESS=$1
NETWORK=${2:-mainnet}  # Default to mainnet if not specified

# Check if ETHERSCAN_API_KEY is provided
if [ -z "$ETHERSCAN_API_KEY" ]; then
    echo "Error: ETHERSCAN_API_KEY is not set"
    echo "Please set your Etherscan API key:"
    echo "  ETHERSCAN_API_KEY=your_api_key ./sh/verify.sh $CONTRACT_ADDRESS $NETWORK"
    echo "Or export it as environment variable:"
    echo "  export ETHERSCAN_API_KEY=your_api_key"
    exit 1
fi

echo "Verifying contract at address: $CONTRACT_ADDRESS"
echo "Network: $NETWORK"
echo "Contract: AlephPaymentProcessor"

# Build the project first to ensure bytecode is up to date
echo "Building project..."
forge clean && forge build --optimize

# Verify the contract
echo "Starting verification..."
forge verify-contract \
    --chain $NETWORK \
    --watch \
    $CONTRACT_ADDRESS \
    src/AlephPaymentProcessor.sol:AlephPaymentProcessor \
    --verifier etherscan \
    --etherscan-api-key $ETHERSCAN_API_KEY \

echo "Verification completed!"
