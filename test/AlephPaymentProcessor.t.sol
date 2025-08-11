// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/StdUtils.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test, console} from "forge-std/Test.sol";
import {AlephPaymentProcessor} from "../src/AlephPaymentProcessor.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PathKey} from "@uniswap/v4-periphery/src/libraries/PathKey.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

contract AlephPaymentProcessorTest is Test {
    address ethTokenAddress = address(0); // 0x0000000000000000000000000000000000000000
    address usdcTokenAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address alephTokenAddress = 0x27702a26126e0B3702af63Ee09aC4d1A084EF628;
    address recipientAddress = address(this); // makeAddr("recipient");
    uint8 burnPercentage = 20;
    address uniswapRouterAddress = 0x66a9893cC07D91D95644AEDD05D03f95e1dBA8Af;
    address permit2Address = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    IERC20 ALEPH = IERC20(alephTokenAddress);
    IERC20 USDC = IERC20(usdcTokenAddress);

    AlephPaymentProcessor alephPaymentProcessor;
    address contractAddress;

    receive() external payable {}

    function setUp() public {
        alephPaymentProcessor = new AlephPaymentProcessor();
        contractAddress = address(alephPaymentProcessor);

        alephPaymentProcessor.initialize(
            alephTokenAddress,
            recipientAddress,
            burnPercentage,
            uniswapRouterAddress,
            permit2Address
        );

        // Set token swap config
        // Init ETH/ALEPH PoolKey for uniswap v4 (0x8e1ff09f103511aca5fa8a007e691ed18a2982b37749e8c8bdf914eacdff3a21)
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
        PathKey[] memory usdcPath = new PathKey[](1);
        usdcPath[0] = PathKey({
            intermediateCurrency: Currency.wrap(alephTokenAddress),
            fee: 10000,
            tickSpacing: 200,
            hooks: IHooks(address(0)),
            hookData: bytes("")
        });
        alephPaymentProcessor.setTokenConfigV4(usdcTokenAddress, usdcPath);
    }

    function testFuzz_set_burn_percentage(uint8 x) public {
        vm.assume(x > 0);
        vm.assume(x <= 100);

        alephPaymentProcessor.setBurnPercentage(x);
        vm.assertEq(alephPaymentProcessor.burnPercentage(), x);
    }

    function testFuzz_set_recipient_address(address x) public {
        vm.assume(x != address(0));

        alephPaymentProcessor.setRecipient(x);
        vm.assertEq(alephPaymentProcessor.recipient(), x);
    }

    function test_pool_ALEPH_USDC() public view {
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(alephTokenAddress),
            currency1: Currency.wrap(usdcTokenAddress),
            fee: 10000,
            tickSpacing: 200,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(poolKey));
        // console.log(vm.toString(poolId));

        vm.assertEq(
            poolId,
            0x8ee28047ee72104999ce30d35f92e1757a7a94a5ac2bc200f4c2da1eabfe6429
        );
    }

    function test_pool_ETH_ALEPH() public view {
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(ethTokenAddress),
            currency1: Currency.wrap(alephTokenAddress),
            fee: 10000,
            tickSpacing: 200,
            hooks: IHooks(address(0))
        });

        bytes32 poolId = keccak256(abi.encode(poolKey));
        // console.log(vm.toString(poolId));

        vm.assertEq(
            poolId,
            0x8e1ff09f103511aca5fa8a007e691ed18a2982b37749e8c8bdf914eacdff3a21
        );
    }

    function test_process_swap_ETH_ALEPH() public {
        vm.deal(contractAddress, 1 ether);

        vm.assertEq(contractAddress.balance, 1 ether);
        vm.assertEq(ALEPH.balanceOf(recipientAddress), 0);
        uint256 burnedBefore = ALEPH.balanceOf(address(0));

        alephPaymentProcessor.process(address(0), 0.2 ether, 0, 60);

        vm.assertEq(contractAddress.balance, 0.8 ether);
        vm.assertGt(ALEPH.balanceOf(recipientAddress), 0);
        uint256 burnedAfter = ALEPH.balanceOf(address(0));
        vm.assertGt(burnedAfter, burnedBefore);
    }

    function test_process_swap_USDC_ALEPH() public {
        deal(address(USDC), contractAddress, 1_000);

        vm.assertEq(USDC.balanceOf(contractAddress), 1_000);
        vm.assertEq(ALEPH.balanceOf(recipientAddress), 0);
        uint256 burnedBefore = ALEPH.balanceOf(address(0));

        alephPaymentProcessor.process(address(USDC), 200, 0, 60);

        vm.assertEq(USDC.balanceOf(contractAddress), 800);
        vm.assertGt(ALEPH.balanceOf(recipientAddress), 0);
        uint256 burnedAfter = ALEPH.balanceOf(address(0));
        vm.assertGt(burnedAfter, burnedBefore);
    }

    function test_process_ALEPH() public {
        deal(address(ALEPH), contractAddress, 1_000);

        vm.assertEq(ALEPH.balanceOf(contractAddress), 1_000);
        vm.assertEq(ALEPH.balanceOf(recipientAddress), 0);
        uint256 burnedBefore = ALEPH.balanceOf(address(0));

        alephPaymentProcessor.process(address(ALEPH), 100, 0, 60);

        vm.assertEq(ALEPH.balanceOf(contractAddress), 900);
        vm.assertEq(ALEPH.balanceOf(recipientAddress), 80);
        uint256 burnedAfter = ALEPH.balanceOf(address(0));
        vm.assertEq(burnedAfter - burnedBefore, 20);
    }

    function test_process_swap_ALL_ETH_ALEPH() public {
        vm.deal(contractAddress, 1 ether);

        vm.assertEq(contractAddress.balance, 1 ether);
        vm.assertEq(ALEPH.balanceOf(recipientAddress), 0);
        uint256 burnedBefore = ALEPH.balanceOf(address(0));

        alephPaymentProcessor.process(address(0), 0, 0, 60);

        vm.assertEq(contractAddress.balance, 0 ether);
        vm.assertGt(ALEPH.balanceOf(recipientAddress), 0);
        uint256 burnedAfter = ALEPH.balanceOf(address(0));
        vm.assertGt(burnedAfter, burnedBefore);
    }

    function test_error_insufficient_out_amount() public {
        vm.deal(contractAddress, 1_000);

        vm.expectRevert();
        // vm.expectRevert("Insufficient output amount");
        alephPaymentProcessor.process(address(0), 0, 1_000 * 10 ** 18, 60);
    }

    function test_error_clean_ALEPH() public {
        deal(address(ALEPH), contractAddress, 1_000);

        vm.deal(contractAddress, 1 ether);
        vm.expectRevert("Pending ALEPH balance must be processed before");
        alephPaymentProcessor.process(address(0), 0.2 ether, 0, 60);
    }

    function test_error_insufficient_ETH_balance() public {
        vm.deal(contractAddress, 1_000);

        vm.expectRevert("Insufficient balance");
        alephPaymentProcessor.process(address(0), 1_001, 0, 60);
    }

    function test_error_insufficient_TOKEN_balance() public {
        deal(address(ALEPH), contractAddress, 1_000);

        vm.expectRevert("Insufficient balance");
        alephPaymentProcessor.process(address(ALEPH), 1_001, 0, 60);
    }

    function test_withdraw_ETH() public {
        vm.deal(contractAddress, 1_000);
        vm.deal(recipientAddress, 0);

        vm.assertEq(contractAddress.balance, 1_000);
        vm.assertEq(recipientAddress.balance, 0);

        alephPaymentProcessor.removeTokenConfig(address(0));

        alephPaymentProcessor.withdraw(
            address(0),
            payable(recipientAddress),
            500
        );

        vm.assertEq(contractAddress.balance, 500);
        vm.assertEq(recipientAddress.balance, 500);
    }

    function test_withdraw_ALL_ETH() public {
        vm.deal(contractAddress, 1_000);
        vm.deal(recipientAddress, 0);

        vm.assertEq(contractAddress.balance, 1_000);
        vm.assertEq(recipientAddress.balance, 0);

        alephPaymentProcessor.removeTokenConfig(address(0));

        alephPaymentProcessor.withdraw(
            address(0),
            payable(recipientAddress),
            0
        );

        vm.assertEq(contractAddress.balance, 0);
        vm.assertEq(recipientAddress.balance, 1_000);
    }

    function test_withdraw_TOKEN() public {
        deal(address(USDC), contractAddress, 1_000);
        deal(address(USDC), recipientAddress, 0);

        vm.assertEq(USDC.balanceOf(contractAddress), 1_000);
        vm.assertEq(USDC.balanceOf(recipientAddress), 0);

        alephPaymentProcessor.removeTokenConfig(address(USDC));

        alephPaymentProcessor.withdraw(
            address(USDC),
            payable(recipientAddress),
            500
        );

        vm.assertEq(USDC.balanceOf(contractAddress), 500);
        vm.assertEq(USDC.balanceOf(recipientAddress), 500);
    }

    function test_withdraw_ALL_TOKEN() public {
        deal(address(USDC), contractAddress, 1_000);
        deal(address(USDC), recipientAddress, 0);

        vm.assertEq(USDC.balanceOf(contractAddress), 1_000);
        vm.assertEq(USDC.balanceOf(recipientAddress), 0);

        alephPaymentProcessor.removeTokenConfig(address(USDC));

        alephPaymentProcessor.withdraw(
            address(USDC),
            payable(recipientAddress),
            0
        );

        vm.assertEq(USDC.balanceOf(contractAddress), 0);
        vm.assertEq(USDC.balanceOf(recipientAddress), 1_000);
    }

    function test_error_withdraw_ALEPH() public {
        deal(address(ALEPH), contractAddress, 1_000);
        deal(address(ALEPH), recipientAddress, 0);

        vm.assertEq(ALEPH.balanceOf(contractAddress), 1_000);
        vm.assertEq(ALEPH.balanceOf(recipientAddress), 0);

        vm.expectRevert(
            "Cannot withdraw a token configured for automatic distribution"
        );
        alephPaymentProcessor.withdraw(
            address(ALEPH),
            payable(recipientAddress),
            1_000
        );
    }

    function test_error_withdraw_TOKEN() public {
        deal(address(USDC), contractAddress, 1_000);
        deal(address(USDC), recipientAddress, 0);

        vm.assertEq(USDC.balanceOf(contractAddress), 1_000);
        vm.assertEq(USDC.balanceOf(recipientAddress), 0);

        vm.expectRevert(
            "Cannot withdraw a token configured for automatic distribution"
        );
        alephPaymentProcessor.withdraw(
            address(USDC),
            payable(recipientAddress),
            1_000
        );
    }
}
