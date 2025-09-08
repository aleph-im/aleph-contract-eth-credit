// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {AlephPaymentProcessor} from "../src/AlephPaymentProcessor.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PathKey} from "@uniswap/v4-periphery/src/libraries/PathKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

contract BaseDeployScript is Script {
    function deploy(
        address alephTokenAddress,
        address distributionRecipientAddress,
        address developersRecipientAddress,
        address uniswapRouterAddress,
        address permit2Address,
        address wethAddress,
        uint8 burnPercentage,
        uint8 developersPercentage
    ) internal returns (address) {
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
                    permit2Address,
                    wethAddress
                )
            )
        );

        AlephPaymentProcessor alephPaymentProcessor = AlephPaymentProcessor(
            payable(proxy)
        );

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
        alephPaymentProcessor.setSwapConfigV4(ethTokenAddress, ethPath);

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
        alephPaymentProcessor.setSwapConfigV4(usdcTokenAddress, usdcPath);

        // Set USDC as stable token
        alephPaymentProcessor.setStableToken(usdcTokenAddress, true);

        console.log(proxy);
        return proxy;
    }
}

contract DeployStagingScript is BaseDeployScript {
    function setUp() public {}

    function run() public {
        // ---

        vm.createSelectFork(vm.rpcUrl("sepolia"));
        vm.startBroadcast();

        address c1 = deploy(
            0x4b3f52fFF693D898578f132f0222877848E09A8C,
            0xC07192fcC38E8e14e7322596DbDa30Eab998150C,
            0xeCCdEA12eAAAfF747471F968Dc65D1E37ecb4B31,
            0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD,
            0x000000000022D473030F116dDEE9F6B43aC78BA3,
            0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14,
            5,
            5
        );

        console.log(c1);
        vm.stopBroadcast();
    }
}

contract DeployProductionScript is BaseDeployScript {
    function setUp() public {}

    function run() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"));
        vm.startBroadcast();

        address c2 = deploy(
            0x27702a26126e0B3702af63Ee09aC4d1A084EF628,
            address(0),
            address(0),
            0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af,
            0x000000000022D473030F116dDEE9F6B43aC78BA3,
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            5,
            5
        );

        console.log(c2);
        vm.stopBroadcast();
    }
}
