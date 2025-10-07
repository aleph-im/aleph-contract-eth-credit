#!/bin/bash

# Create Uniswap V4 USDC/ALEPH Pool on Sepolia
# Usage: ./scripts/create-pool.sh [with-liquidity]

echo "🚀 Creating USDC/ALEPH Uniswap V4 pool on Sepolia..."

# Check if .env exists and load it
if [ -f .env ]; then
    export $(cat .env | xargs)
else
    echo "⚠️  .env file not found. Make sure to set PRIVATE_KEY environment variable"
fi

# Verify required environment variables
if [ -z "$PRIVATE_KEY" ]; then
    echo "❌ PRIVATE_KEY environment variable is required"
    exit 1
fi

if [ -z "$ETHERSCAN_API_KEY" ]; then
    echo "⚠️  ETHERSCAN_API_KEY not set (optional for verification)"
fi

# Check if user wants to add liquidity
if [ "$1" = "with-liquidity" ]; then
    export ADD_LIQUIDITY=true
    echo "💧 Liquidity will be added after pool initialization"
else
    export ADD_LIQUIDITY=false
    echo "🔧 Pool will be initialized without liquidity"
fi

echo ""
echo "🔄 Running unified pool creation script..."

forge script script/CreateUniswapV4Pool.s.sol:CreateUniswapV4PoolScript \
    --rpc-url sepolia \
    --private-key $PRIVATE_KEY \
    --broadcast \
    -vvvv

echo ""
echo "ℹ️  Usage examples:"
echo "   ./scripts/create-pool.sh                # Initialize pool only"
echo "   ./scripts/create-pool.sh with-liquidity # Initialize pool + add liquidity"