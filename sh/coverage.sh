#!/bin/bash

# Script to run forge coverage and output results
echo "Running Forge coverage analysis..."

# Try coverage with IR minimum to avoid stack too deep errors
# forge coverage --ir-minimum --fork-url https://reth-ethereum.ithaca.xyz/rpc

forge coverage  \
    --fork-url https://reth-ethereum.ithaca.xyz/rpc \
    --report lcov \
    --report summary \
    --no-match-coverage "(script|lib)" \
    --ir-minimum

# If that fails, try with via-ir
if [ $? -ne 0 ]; then
    echo "Retrying with via-ir flag..."
    forge coverage  \
        --fork-url https://reth-ethereum.ithaca.xyz/rpc \
        --report lcov \
        --report summary \
        --no-match-coverage "(script|lib)" \
        --via-ir
fi

echo "Coverage analysis complete."

# genhtml lcov.info --branch-coverage --output-dir coverage --ignore-errors inconsistent || true
# echo "Coverage html report generated"
