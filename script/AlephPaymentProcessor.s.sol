// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {AlephPaymentProcessor} from "../src/AlephPaymentProcessor.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PathKey} from "@uniswap/v4-periphery/src/libraries/PathKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

//
contract AlephPaymentProcessorScript is Script {
    AlephPaymentProcessor public alephPaymentProcessor;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        address alephTokenAddress = 0x27702a26126e0B3702af63Ee09aC4d1A084EF628;
        address distributionRecipientAddress = address(0); // "TODO"
        address developersRecipientAddress = address(0); // "TODO"
        uint8 burnPercentage = 5; // 5% burn
        uint8 developersPercentage = 5; // 5% to developers
        address uniswapRouterAddress = 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af;
        address permit2Address = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

        address proxy = Upgrades.deployUUPSProxy(
            "AlephPaymentProcessor.sol",
            abi.encodeCall(
                AlephPaymentProcessor.initialize,
                (
                    alephTokenAddress,
                    distributionRecipientAddress,
                    developersRecipientAddress,
                    burnPercentage,
                    developersPercentage,
                    uniswapRouterAddress,
                    permit2Address
                )
            )
        );

        alephPaymentProcessor = AlephPaymentProcessor(payable(proxy));

        // Init ETH/ALEPH PoolKey for uniswap v4 (0x8e1ff09f103511aca5fa8a007e691ed18a2982b37749e8c8bdf914eacdff3a21)
        address ethTokenAddress = address(0); // 0x0000000000000000000000000000000000000000
        PathKey[] memory ethPath = new PathKey[](1);
        ethPath[0] = PathKey({
            intermediateCurrency: Currency.wrap(alephTokenAddress),
            fee: 10000,
            tickSpacing: 200,
            hooks: IHooks(address(0)),
            hookData: bytes("")
        });
        alephPaymentProcessor.setTokenConfigV4(ethTokenAddress, ethPath);

        // Init ALEPH/USDC PoolKey for uniswap v4 (0x8ee28047ee72104999ce30d35f92e1757a7a94a5ac2bc200f4c2da1eabfe6429)
        address usdcTokenAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        PathKey[] memory usdcPath = new PathKey[](1);
        usdcPath[0] = PathKey({
            intermediateCurrency: Currency.wrap(alephTokenAddress),
            fee: 10000,
            tickSpacing: 200,
            hooks: IHooks(address(0)),
            hookData: bytes("")
        });
        alephPaymentProcessor.setTokenConfigV4(usdcTokenAddress, usdcPath);

        // Set USDC as stable token
        alephPaymentProcessor.setStableToken(usdcTokenAddress, true);

        console.log(proxy);
        console.log(alephPaymentProcessor.distributionRecipient());
        console.log(alephPaymentProcessor.developersRecipient());
        console.log(alephPaymentProcessor.burnPercentage());
        console.log(alephPaymentProcessor.developersPercentage());
    }
}
