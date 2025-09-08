#!/bin/bash

# Unified deployment script
# Usage: ./sh/deploy-unified.sh <local|staging|production>

if [ -z "$1" ]; then
    echo "Usage: $0 <local|staging|production>"
    exit 1
fi

ENVIRONMENT=$1

echo "Deploying to $ENVIRONMENT..."
forge clean

case $ENVIRONMENT in
    "local")
        forge script script/deploy.s.sol:DeployStagingScript --optimize --rpc-url http://localhost:8545 --broadcast -vvvv --interactives 1
        ;;
    "staging")
        forge script script/deploy.s.sol:DeployStagingScript --optimize --slow --broadcast --verify -vvvv --interactives 1 --etherscan-api-key $ETHERSCAN_API_KEY
        ;;
    "production")
        forge script script/deploy.s.sol:DeployProductionScript --optimize --slow --broadcast --verify -vvvv --ledger --etherscan-api-key $ETHERSCAN_API_KEY
        ;;
    *)
        echo "Invalid environment. Use: local, staging, or production"
        exit 1
        ;;
esac