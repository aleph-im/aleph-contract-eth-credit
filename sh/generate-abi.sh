forge build --silent && jq '.abi' ./out/AlephPaymentProcessor.sol/AlephPaymentProcessor.json > abi.json
cat abi.json

forge inspect AlephPaymentProcessor methods