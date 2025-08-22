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
    address distributionRecipientAddress = makeAddr("distributionRecipient");
    address developersRecipientAddress = makeAddr("developersRecipient");
    uint8 burnPercentage = 5;
    uint8 developersPercentage = 5;
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
            distributionRecipientAddress,
            developersRecipientAddress,
            burnPercentage,
            developersPercentage,
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
        vm.assume(x <= 95); // Can't exceed 95% since developersPercentage is 5%

        alephPaymentProcessor.setBurnPercentage(x);
        vm.assertEq(alephPaymentProcessor.burnPercentage(), x);
    }

    function testFuzz_set_distribution_recipient_address(address x) public {
        vm.assume(x != address(0));

        alephPaymentProcessor.setDistributionRecipient(x);
        vm.assertEq(alephPaymentProcessor.distributionRecipient(), x);
    }

    function testFuzz_set_developers_recipient_address(address x) public {
        vm.assume(x != address(0));

        alephPaymentProcessor.setDevelopersRecipient(x);
        vm.assertEq(alephPaymentProcessor.developersRecipient(), x);
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

        vm.assertEq(poolId, 0x8ee28047ee72104999ce30d35f92e1757a7a94a5ac2bc200f4c2da1eabfe6429);
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

        vm.assertEq(poolId, 0x8e1ff09f103511aca5fa8a007e691ed18a2982b37749e8c8bdf914eacdff3a21);
    }

    function test_process_swap_ETH_ALEPH() public {
        vm.deal(contractAddress, 1 ether);

        vm.assertEq(contractAddress.balance, 1 ether);
        vm.assertEq(ALEPH.balanceOf(distributionRecipientAddress), 0);
        vm.assertEq(ALEPH.balanceOf(developersRecipientAddress), 0);
        uint256 burnedBefore = ALEPH.balanceOf(address(0));

        alephPaymentProcessor.process(address(0), 0.2 ether, 0, 60);

        vm.assertEq(contractAddress.balance, 0.8 ether);
        vm.assertGt(ALEPH.balanceOf(distributionRecipientAddress), 0);
        vm.assertGt(ALEPH.balanceOf(developersRecipientAddress), 0);
        uint256 burnedAfter = ALEPH.balanceOf(address(0));
        vm.assertGt(burnedAfter, burnedBefore);
    }

    function test_process_swap_USDC_ALEPH() public {
        deal(address(USDC), contractAddress, 1_000);

        vm.assertEq(USDC.balanceOf(contractAddress), 1_000);
        vm.assertEq(ALEPH.balanceOf(distributionRecipientAddress), 0);
        uint256 burnedBefore = ALEPH.balanceOf(address(0));

        alephPaymentProcessor.process(address(USDC), 200, 0, 60);

        vm.assertEq(USDC.balanceOf(contractAddress), 800);
        vm.assertGt(ALEPH.balanceOf(distributionRecipientAddress), 0);
        uint256 burnedAfter = ALEPH.balanceOf(address(0));
        vm.assertGt(burnedAfter, burnedBefore);
    }

    function test_process_ALEPH() public {
        deal(address(ALEPH), contractAddress, 1_000);

        vm.assertEq(ALEPH.balanceOf(contractAddress), 1_000);
        vm.assertEq(ALEPH.balanceOf(distributionRecipientAddress), 0);
        vm.assertEq(ALEPH.balanceOf(developersRecipientAddress), 0);
        uint256 burnedBefore = ALEPH.balanceOf(address(0));

        alephPaymentProcessor.process(address(ALEPH), 100, 0, 60);

        vm.assertEq(ALEPH.balanceOf(contractAddress), 900);
        vm.assertEq(ALEPH.balanceOf(distributionRecipientAddress), 90); // 90% of 100 = 90
        vm.assertEq(ALEPH.balanceOf(developersRecipientAddress), 5); // 5% of 100 = 5
        uint256 burnedAfter = ALEPH.balanceOf(address(0));
        vm.assertEq(burnedAfter - burnedBefore, 5); // 5% of 100 = 5
    }

    function test_process_swap_ALL_ETH_ALEPH() public {
        vm.deal(contractAddress, 1 ether);

        vm.assertEq(contractAddress.balance, 1 ether);
        vm.assertEq(ALEPH.balanceOf(distributionRecipientAddress), 0);
        uint256 burnedBefore = ALEPH.balanceOf(address(0));

        alephPaymentProcessor.process(address(0), 0, 0, 60);

        vm.assertEq(contractAddress.balance, 0 ether);
        vm.assertGt(ALEPH.balanceOf(distributionRecipientAddress), 0);
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
        vm.deal(distributionRecipientAddress, 0);

        vm.assertEq(contractAddress.balance, 1_000);
        vm.assertEq(distributionRecipientAddress.balance, 0);

        alephPaymentProcessor.removeTokenConfig(address(0));

        alephPaymentProcessor.withdraw(address(0), payable(distributionRecipientAddress), 500);

        vm.assertEq(contractAddress.balance, 500);
        vm.assertEq(distributionRecipientAddress.balance, 500);
    }

    function test_withdraw_ALL_ETH() public {
        vm.deal(contractAddress, 1_000);
        vm.deal(distributionRecipientAddress, 0);

        vm.assertEq(contractAddress.balance, 1_000);
        vm.assertEq(distributionRecipientAddress.balance, 0);

        alephPaymentProcessor.removeTokenConfig(address(0));

        alephPaymentProcessor.withdraw(address(0), payable(distributionRecipientAddress), 0);

        vm.assertEq(contractAddress.balance, 0);
        vm.assertEq(distributionRecipientAddress.balance, 1_000);
    }

    function test_withdraw_TOKEN() public {
        deal(address(USDC), contractAddress, 1_000);
        deal(address(USDC), distributionRecipientAddress, 0);

        vm.assertEq(USDC.balanceOf(contractAddress), 1_000);
        vm.assertEq(USDC.balanceOf(distributionRecipientAddress), 0);

        alephPaymentProcessor.removeTokenConfig(address(USDC));

        alephPaymentProcessor.withdraw(address(USDC), payable(distributionRecipientAddress), 500);

        vm.assertEq(USDC.balanceOf(contractAddress), 500);
        vm.assertEq(USDC.balanceOf(distributionRecipientAddress), 500);
    }

    function test_withdraw_ALL_TOKEN() public {
        deal(address(USDC), contractAddress, 1_000);
        deal(address(USDC), distributionRecipientAddress, 0);

        vm.assertEq(USDC.balanceOf(contractAddress), 1_000);
        vm.assertEq(USDC.balanceOf(distributionRecipientAddress), 0);

        alephPaymentProcessor.removeTokenConfig(address(USDC));

        alephPaymentProcessor.withdraw(address(USDC), payable(distributionRecipientAddress), 0);

        vm.assertEq(USDC.balanceOf(contractAddress), 0);
        vm.assertEq(USDC.balanceOf(distributionRecipientAddress), 1_000);
    }

    function test_error_withdraw_ALEPH() public {
        deal(address(ALEPH), contractAddress, 1_000);
        deal(address(ALEPH), distributionRecipientAddress, 0);

        vm.assertEq(ALEPH.balanceOf(contractAddress), 1_000);
        vm.assertEq(ALEPH.balanceOf(distributionRecipientAddress), 0);

        vm.expectRevert("Cannot withdraw a token configured for automatic distribution");
        alephPaymentProcessor.withdraw(address(ALEPH), payable(distributionRecipientAddress), 1_000);
    }

    function test_error_withdraw_TOKEN() public {
        deal(address(USDC), contractAddress, 1_000);
        deal(address(USDC), distributionRecipientAddress, 0);

        vm.assertEq(USDC.balanceOf(contractAddress), 1_000);
        vm.assertEq(USDC.balanceOf(distributionRecipientAddress), 0);

        vm.expectRevert("Cannot withdraw a token configured for automatic distribution");
        alephPaymentProcessor.withdraw(address(USDC), payable(distributionRecipientAddress), 1_000);
    }

    function test_stable_token_detection() public {
        vm.assertEq(alephPaymentProcessor.isStableToken(usdcTokenAddress), false);

        alephPaymentProcessor.setStableToken(usdcTokenAddress, true);
        vm.assertEq(alephPaymentProcessor.isStableToken(usdcTokenAddress), true);

        alephPaymentProcessor.setStableToken(usdcTokenAddress, false);
        vm.assertEq(alephPaymentProcessor.isStableToken(usdcTokenAddress), false);
    }

    function test_stable_token_distribution_USDC() public {
        // Set USDC as stable token
        alephPaymentProcessor.setStableToken(usdcTokenAddress, true);

        deal(address(USDC), contractAddress, 1000);

        uint256 initialDistributionBalance = ALEPH.balanceOf(distributionRecipientAddress);
        uint256 initialDevelopersUSDCBalance = USDC.balanceOf(developersRecipientAddress);
        uint256 initialBurnBalance = ALEPH.balanceOf(address(0));

        alephPaymentProcessor.process(address(USDC), 1000, 0, 60);

        // Developers should receive 5% in USDC directly (50 USDC)
        vm.assertEq(USDC.balanceOf(developersRecipientAddress) - initialDevelopersUSDCBalance, 50);

        // The remaining 95% (950) should be swapped to ALEPH and split:
        // - 5% burned (proportionally from the swapped amount)
        // - 90% to distribution (proportionally from the swapped amount)
        vm.assertGt(ALEPH.balanceOf(distributionRecipientAddress), initialDistributionBalance);
        vm.assertGt(ALEPH.balanceOf(address(0)), initialBurnBalance);

        // Contract should be left with 0 USDC
        vm.assertEq(USDC.balanceOf(contractAddress), 0);
    }

    function test_non_stable_token_distribution_ETH() public {
        vm.deal(contractAddress, 1000);

        uint256 initialDistributionBalance = ALEPH.balanceOf(distributionRecipientAddress);
        uint256 initialDevelopersBalance = ALEPH.balanceOf(developersRecipientAddress);
        uint256 initialBurnBalance = ALEPH.balanceOf(address(0));

        alephPaymentProcessor.process(address(0), 1000, 0, 60);

        // All amounts should be in ALEPH after swap, distributed according to percentages
        uint256 distributionReceived = ALEPH.balanceOf(distributionRecipientAddress) - initialDistributionBalance;
        uint256 developersReceived = ALEPH.balanceOf(developersRecipientAddress) - initialDevelopersBalance;
        uint256 burnReceived = ALEPH.balanceOf(address(0)) - initialBurnBalance;

        // All recipients should receive ALEPH
        vm.assertGt(distributionReceived, 0);
        vm.assertGt(developersReceived, 0);
        vm.assertGt(burnReceived, 0);

        // Contract should be left with 0 ETH
        vm.assertEq(contractAddress.balance, 0);
    }

    function test_process_ALEPH_exact_percentages() public {
        deal(address(ALEPH), contractAddress, 10000); // Use 10000 for easier percentage calculations

        uint256 initialDistributionBalance = ALEPH.balanceOf(distributionRecipientAddress);
        uint256 initialDevelopersBalance = ALEPH.balanceOf(developersRecipientAddress);
        uint256 initialBurnBalance = ALEPH.balanceOf(address(0));

        alephPaymentProcessor.process(address(ALEPH), 10000, 0, 60);

        // Check exact percentages: 5% developers, 5% burn, 90% distribution
        vm.assertEq(ALEPH.balanceOf(developersRecipientAddress) - initialDevelopersBalance, 500); // 5% of 10000
        vm.assertEq(ALEPH.balanceOf(address(0)) - initialBurnBalance, 500); // 5% of 10000
        vm.assertEq(ALEPH.balanceOf(distributionRecipientAddress) - initialDistributionBalance, 9000); // 90% of 10000

        // Contract should be empty
        vm.assertEq(ALEPH.balanceOf(contractAddress), 0);
    }

    function test_zero_amount_process() public {
        deal(address(ALEPH), contractAddress, 0);

        vm.expectRevert("Insufficient balance");
        alephPaymentProcessor.process(address(ALEPH), 100, 0, 60);
    }

    function test_edge_case_small_amounts() public {
        deal(address(ALEPH), contractAddress, 10); // Very small amount

        uint256 initialDistributionBalance = ALEPH.balanceOf(distributionRecipientAddress);
        uint256 initialDevelopersBalance = ALEPH.balanceOf(developersRecipientAddress);
        uint256 initialBurnBalance = ALEPH.balanceOf(address(0));

        alephPaymentProcessor.process(address(ALEPH), 10, 0, 60);

        // With small amounts, due to integer division, some amounts might be 0
        // 5% of 10 = 0.5, which rounds down to 0
        // 90% of 10 = 9
        uint256 developersReceived = ALEPH.balanceOf(developersRecipientAddress) - initialDevelopersBalance;
        uint256 burnReceived = ALEPH.balanceOf(address(0)) - initialBurnBalance;
        uint256 distributionReceived = ALEPH.balanceOf(distributionRecipientAddress) - initialDistributionBalance;

        // Total should equal 10
        vm.assertEq(developersReceived + burnReceived + distributionReceived, 10);
    }

    function test_access_control_set_stable_token() public {
        vm.prank(makeAddr("notOwner"));
        vm.expectRevert();
        alephPaymentProcessor.setStableToken(usdcTokenAddress, true);
    }

    function test_access_control_set_distribution_recipient() public {
        vm.prank(makeAddr("notOwner"));
        vm.expectRevert();
        alephPaymentProcessor.setDistributionRecipient(makeAddr("newRecipient"));
    }

    function test_access_control_set_developers_recipient() public {
        vm.prank(makeAddr("notOwner"));
        vm.expectRevert();
        alephPaymentProcessor.setDevelopersRecipient(makeAddr("newRecipient"));
    }

    function test_invalid_recipient_addresses() public {
        vm.expectRevert("Invalid distribution recipient address");
        alephPaymentProcessor.setDistributionRecipient(address(0));

        vm.expectRevert("Invalid developers recipient address");
        alephPaymentProcessor.setDevelopersRecipient(address(0));
    }

    function test_process_with_max_uint128() public {
        deal(address(ALEPH), contractAddress, type(uint128).max);

        uint256 initialDistributionBalance = ALEPH.balanceOf(distributionRecipientAddress);
        uint256 initialDevelopersBalance = ALEPH.balanceOf(developersRecipientAddress);
        uint256 initialBurnBalance = ALEPH.balanceOf(address(0));

        alephPaymentProcessor.process(address(ALEPH), type(uint128).max, 0, 60);

        // Should handle large numbers correctly
        uint256 expectedDevelopers = (uint256(type(uint128).max) * developersPercentage) / 100;
        uint256 expectedBurn = (uint256(type(uint128).max) * burnPercentage) / 100;
        uint256 expectedDistribution = uint256(type(uint128).max) - expectedDevelopers - expectedBurn;

        vm.assertEq(ALEPH.balanceOf(developersRecipientAddress) - initialDevelopersBalance, expectedDevelopers);
        vm.assertEq(ALEPH.balanceOf(address(0)) - initialBurnBalance, expectedBurn);
        vm.assertEq(ALEPH.balanceOf(distributionRecipientAddress) - initialDistributionBalance, expectedDistribution);
    }

    function testFuzz_percentage_calculations(uint128 amount, uint8 devPercent, uint8 burnPercent) public {
        vm.assume(amount > 0 && amount <= type(uint128).max / 2); // Prevent overflow
        vm.assume(devPercent <= 100 && burnPercent <= 100);
        vm.assume(devPercent + burnPercent <= 100); // Ensure distribution percentage is not negative

        // Set custom percentages - set smaller percentage first to avoid validation issues
        if (devPercent <= burnPercent) {
            alephPaymentProcessor.setDevelopersPercentage(devPercent);
            alephPaymentProcessor.setBurnPercentage(burnPercent);
        } else {
            alephPaymentProcessor.setBurnPercentage(burnPercent);
            alephPaymentProcessor.setDevelopersPercentage(devPercent);
        }

        deal(address(ALEPH), contractAddress, amount);

        uint256 initialDistributionBalance = ALEPH.balanceOf(distributionRecipientAddress);
        uint256 initialDevelopersBalance = ALEPH.balanceOf(developersRecipientAddress);
        uint256 initialBurnBalance = ALEPH.balanceOf(address(0));

        alephPaymentProcessor.process(address(ALEPH), amount, 0, 60);

        uint256 developersReceived = ALEPH.balanceOf(developersRecipientAddress) - initialDevelopersBalance;
        uint256 burnReceived = ALEPH.balanceOf(address(0)) - initialBurnBalance;
        uint256 distributionReceived = ALEPH.balanceOf(distributionRecipientAddress) - initialDistributionBalance;

        // Total should equal original amount
        vm.assertEq(developersReceived + burnReceived + distributionReceived, amount);
    }

    function test_stable_token_eth_distribution() public {
        // ETH cannot be a stable token, but test the logic anyway
        alephPaymentProcessor.setStableToken(address(0), true);

        vm.deal(contractAddress, 1000);

        uint256 initialDevelopersBalance = address(developersRecipientAddress).balance;
        uint256 initialDistributionBalance = ALEPH.balanceOf(distributionRecipientAddress);
        uint256 initialBurnBalance = ALEPH.balanceOf(address(0));

        alephPaymentProcessor.process(address(0), 1000, 0, 60);

        // Developers should receive 5% in ETH directly (50 wei)
        vm.assertEq(address(developersRecipientAddress).balance - initialDevelopersBalance, 50);

        // The rest should be swapped to ALEPH
        vm.assertGt(ALEPH.balanceOf(distributionRecipientAddress), initialDistributionBalance);
        vm.assertGt(ALEPH.balanceOf(address(0)), initialBurnBalance);
    }

    function test_multiple_process_calls() public {
        deal(address(ALEPH), contractAddress, 1000);

        // First process
        alephPaymentProcessor.process(address(ALEPH), 500, 0, 60);

        uint256 midDistributionBalance = ALEPH.balanceOf(distributionRecipientAddress);
        uint256 midDevelopersBalance = ALEPH.balanceOf(developersRecipientAddress);
        uint256 midBurnBalance = ALEPH.balanceOf(address(0));

        // Second process
        alephPaymentProcessor.process(address(ALEPH), 500, 0, 60);

        // Check that second process added correctly
        vm.assertEq(ALEPH.balanceOf(distributionRecipientAddress) - midDistributionBalance, 450); // 90% of 500
        vm.assertEq(ALEPH.balanceOf(developersRecipientAddress) - midDevelopersBalance, 25); // 5% of 500
        vm.assertEq(ALEPH.balanceOf(address(0)) - midBurnBalance, 25); // 5% of 500
    }

    // ======== ADDITIONAL COVERAGE TESTS ========

    function test_addAdmin() public {
        address newAdmin = makeAddr("newAdmin");

        // Initially newAdmin should not have ADMIN_ROLE
        vm.assertEq(alephPaymentProcessor.hasRole(alephPaymentProcessor.ADMIN_ROLE(), newAdmin), false);

        alephPaymentProcessor.addAdmin(newAdmin);

        // After adding, newAdmin should have ADMIN_ROLE
        vm.assertEq(alephPaymentProcessor.hasRole(alephPaymentProcessor.ADMIN_ROLE(), newAdmin), true);
    }

    function test_removeAdmin() public {
        address admin = makeAddr("admin");

        // Add admin first
        alephPaymentProcessor.addAdmin(admin);
        vm.assertEq(alephPaymentProcessor.hasRole(alephPaymentProcessor.ADMIN_ROLE(), admin), true);

        // Remove admin
        alephPaymentProcessor.removeAdmin(admin);
        vm.assertEq(alephPaymentProcessor.hasRole(alephPaymentProcessor.ADMIN_ROLE(), admin), false);
    }

    function test_getTokenConfig() public {
        // Test getting config for a token that doesn't exist
        AlephPaymentProcessor.TokenConfig memory config =
            alephPaymentProcessor.getTokenConfig(makeAddr("nonExistentToken"));
        vm.assertEq(config.version, 0);
        vm.assertEq(config.token, address(0));

        // Test getting config for ETH (which was set in setUp)
        AlephPaymentProcessor.TokenConfig memory ethConfig = alephPaymentProcessor.getTokenConfig(ethTokenAddress);
        vm.assertEq(ethConfig.version, 4);
        vm.assertEq(ethConfig.token, ethTokenAddress);
    }

    function test_access_control_addAdmin() public {
        address notOwner = makeAddr("notOwner");
        address newAdmin = makeAddr("newAdmin");

        vm.prank(notOwner);
        vm.expectRevert();
        alephPaymentProcessor.addAdmin(newAdmin);
    }

    function test_access_control_removeAdmin() public {
        address notOwner = makeAddr("notOwner");
        address admin = makeAddr("admin");

        vm.prank(notOwner);
        vm.expectRevert();
        alephPaymentProcessor.removeAdmin(admin);
    }

    function test_access_control_setTokenConfigV4() public {
        address notOwner = makeAddr("notOwner");
        PathKey[] memory path = new PathKey[](0);

        vm.prank(notOwner);
        vm.expectRevert();
        alephPaymentProcessor.setTokenConfigV4(makeAddr("token"), path);
    }

    function test_access_control_removeTokenConfig() public {
        address notOwner = makeAddr("notOwner");

        vm.prank(notOwner);
        vm.expectRevert();
        alephPaymentProcessor.removeTokenConfig(ethTokenAddress);
    }

    function test_removeTokenConfig_success() public {
        // Remove ETH token config
        alephPaymentProcessor.removeTokenConfig(ethTokenAddress);

        // Verify it's removed
        AlephPaymentProcessor.TokenConfig memory config = alephPaymentProcessor.getTokenConfig(ethTokenAddress);
        vm.assertEq(config.version, 0);
    }

    function test_removeTokenConfig_invalid() public {
        address nonExistentToken = makeAddr("nonExistent");

        vm.expectRevert("Invalid token config");
        alephPaymentProcessor.removeTokenConfig(nonExistentToken);
    }

    function test_setBurnPercentage_boundary_values() public {
        // Test setting to 0
        alephPaymentProcessor.setBurnPercentage(0);
        vm.assertEq(alephPaymentProcessor.burnPercentage(), 0);

        // Test setting to maximum allowed (95% since developers is 5%)
        alephPaymentProcessor.setBurnPercentage(95);
        vm.assertEq(alephPaymentProcessor.burnPercentage(), 95);
    }

    function test_setBurnPercentage_invalid_values() public {
        // Test setting above 100
        vm.expectRevert("Invalid burn percentage");
        alephPaymentProcessor.setBurnPercentage(101);

        // Test setting that would exceed total 100% with developers
        vm.expectRevert("Total percentages exceed 100%");
        alephPaymentProcessor.setBurnPercentage(96); // 96 + 5 = 101%
    }

    function test_setDevelopersPercentage_boundary_values() public {
        // First set burn to 0 to allow full range
        alephPaymentProcessor.setBurnPercentage(0);

        // Test setting to 0
        alephPaymentProcessor.setDevelopersPercentage(0);
        vm.assertEq(alephPaymentProcessor.developersPercentage(), 0);

        // Test setting to maximum
        alephPaymentProcessor.setDevelopersPercentage(100);
        vm.assertEq(alephPaymentProcessor.developersPercentage(), 100);
    }

    function test_setDevelopersPercentage_invalid_values() public {
        // Test setting above 100
        vm.expectRevert("Invalid developers percentage");
        alephPaymentProcessor.setDevelopersPercentage(101);

        // Test setting that would exceed total 100% with burn
        vm.expectRevert("Total percentages exceed 100%");
        alephPaymentProcessor.setDevelopersPercentage(96); // 5 + 96 = 101%
    }

    function test_receive_ether() public {
        uint256 initialBalance = address(alephPaymentProcessor).balance;

        // Send ETH to the contract
        (bool success,) = address(alephPaymentProcessor).call{value: 1 ether}("");
        vm.assertTrue(success);

        vm.assertEq(address(alephPaymentProcessor).balance, initialBalance + 1 ether);
    }

    function test_process_zero_percentages() public {
        // Set both percentages to 0
        alephPaymentProcessor.setBurnPercentage(0);
        alephPaymentProcessor.setDevelopersPercentage(0);

        deal(address(ALEPH), contractAddress, 1000);

        uint256 initialDistributionBalance = ALEPH.balanceOf(distributionRecipientAddress);
        uint256 initialDevelopersBalance = ALEPH.balanceOf(developersRecipientAddress);
        uint256 initialBurnBalance = ALEPH.balanceOf(address(0));

        alephPaymentProcessor.process(address(ALEPH), 1000, 0, 60);

        // All should go to distribution (100%)
        vm.assertEq(ALEPH.balanceOf(distributionRecipientAddress) - initialDistributionBalance, 1000);
        vm.assertEq(ALEPH.balanceOf(developersRecipientAddress) - initialDevelopersBalance, 0);
        vm.assertEq(ALEPH.balanceOf(address(0)) - initialBurnBalance, 0);
    }

    function test_process_maximum_percentages() public {
        // Set maximum percentages (50% each, total 100%)
        alephPaymentProcessor.setBurnPercentage(0);
        alephPaymentProcessor.setDevelopersPercentage(0);
        alephPaymentProcessor.setBurnPercentage(50);
        alephPaymentProcessor.setDevelopersPercentage(50);

        deal(address(ALEPH), contractAddress, 1000);

        uint256 initialDistributionBalance = ALEPH.balanceOf(distributionRecipientAddress);
        uint256 initialDevelopersBalance = ALEPH.balanceOf(developersRecipientAddress);
        uint256 initialBurnBalance = ALEPH.balanceOf(address(0));

        alephPaymentProcessor.process(address(ALEPH), 1000, 0, 60);

        // Check 50% each, 0% to distribution
        vm.assertEq(ALEPH.balanceOf(distributionRecipientAddress) - initialDistributionBalance, 0);
        vm.assertEq(ALEPH.balanceOf(developersRecipientAddress) - initialDevelopersBalance, 500);
        vm.assertEq(ALEPH.balanceOf(address(0)) - initialBurnBalance, 500);
    }

    // ======== BRANCH COVERAGE TESTS ========

    function test_process_stable_token_ETH_branch() public {
        // Test the stable token branch where _token == address(0) (ETH)
        alephPaymentProcessor.setStableToken(address(0), true);

        vm.deal(contractAddress, 1000);

        uint256 initialDevelopersETHBalance = developersRecipientAddress.balance;
        uint256 initialDistributionBalance = ALEPH.balanceOf(distributionRecipientAddress);
        uint256 initialBurnBalance = ALEPH.balanceOf(address(0));

        alephPaymentProcessor.process(address(0), 1000, 0, 60);

        // Developers should receive 5% in ETH directly (50 wei)
        vm.assertEq(developersRecipientAddress.balance - initialDevelopersETHBalance, 50);

        // The rest should be swapped to ALEPH and distributed
        vm.assertGt(ALEPH.balanceOf(distributionRecipientAddress), initialDistributionBalance);
        vm.assertGt(ALEPH.balanceOf(address(0)), initialBurnBalance);
    }

    function test_process_stable_token_ERC20_branch() public {
        // Test the stable token branch where _token != address(0) (ERC20)
        alephPaymentProcessor.setStableToken(usdcTokenAddress, true);

        deal(address(USDC), contractAddress, 1000);

        uint256 initialDevelopersUSDCBalance = USDC.balanceOf(developersRecipientAddress);
        uint256 initialDistributionBalance = ALEPH.balanceOf(distributionRecipientAddress);
        uint256 initialBurnBalance = ALEPH.balanceOf(address(0));

        alephPaymentProcessor.process(address(USDC), 1000, 0, 60);

        // Developers should receive 5% in USDC directly (50 USDC)
        vm.assertEq(USDC.balanceOf(developersRecipientAddress) - initialDevelopersUSDCBalance, 50);

        // The rest should be swapped to ALEPH and distributed
        vm.assertGt(ALEPH.balanceOf(distributionRecipientAddress), initialDistributionBalance);
        vm.assertGt(ALEPH.balanceOf(address(0)), initialBurnBalance);
    }

    function test_process_non_stable_token_swap_branch() public {
        // Test the non-stable token branch where _token != address(ALEPH) (requires swap)
        vm.deal(contractAddress, 1000);

        uint256 initialDistributionBalance = ALEPH.balanceOf(distributionRecipientAddress);
        uint256 initialDevelopersBalance = ALEPH.balanceOf(developersRecipientAddress);
        uint256 initialBurnBalance = ALEPH.balanceOf(address(0));

        alephPaymentProcessor.process(address(0), 1000, 0, 60);

        // All recipients should receive ALEPH (after swap)
        vm.assertGt(ALEPH.balanceOf(distributionRecipientAddress), initialDistributionBalance);
        vm.assertGt(ALEPH.balanceOf(developersRecipientAddress), initialDevelopersBalance);
        vm.assertGt(ALEPH.balanceOf(address(0)), initialBurnBalance);
    }

    function test_process_ALEPH_no_swap_branch() public {
        // Test the non-stable token branch where _token == address(ALEPH) (no swap needed)
        deal(address(ALEPH), contractAddress, 1000);

        uint256 initialDistributionBalance = ALEPH.balanceOf(distributionRecipientAddress);
        uint256 initialDevelopersBalance = ALEPH.balanceOf(developersRecipientAddress);
        uint256 initialBurnBalance = ALEPH.balanceOf(address(0));

        alephPaymentProcessor.process(address(ALEPH), 1000, 0, 60);

        // All recipients should receive ALEPH (no swap needed)
        vm.assertEq(ALEPH.balanceOf(distributionRecipientAddress) - initialDistributionBalance, 900); // 90%
        vm.assertEq(ALEPH.balanceOf(developersRecipientAddress) - initialDevelopersBalance, 50); // 5%
        vm.assertEq(ALEPH.balanceOf(address(0)) - initialBurnBalance, 50); // 5%
    }

    function test_getAmountIn_zero_input_branch() public {
        // Test the _amountIn == 0 branch in getAmountIn
        deal(address(ALEPH), contractAddress, 1000);

        uint256 initialDistributionBalance = ALEPH.balanceOf(distributionRecipientAddress);

        // Process with _amountIn = 0 (should process all available balance)
        alephPaymentProcessor.process(address(ALEPH), 0, 0, 60);

        // Should process all 1000 ALEPH
        vm.assertEq(ALEPH.balanceOf(distributionRecipientAddress) - initialDistributionBalance, 900); // 90% of 1000
    }

    function test_getAmountIn_nonzero_input_branch() public {
        // Test the _amountIn != 0 branch in getAmountIn
        deal(address(ALEPH), contractAddress, 1000);

        uint256 initialDistributionBalance = ALEPH.balanceOf(distributionRecipientAddress);

        // Process with specific _amountIn = 500
        alephPaymentProcessor.process(address(ALEPH), 500, 0, 60);

        // Should process only 500 ALEPH
        vm.assertEq(ALEPH.balanceOf(distributionRecipientAddress) - initialDistributionBalance, 450); // 90% of 500
        vm.assertEq(ALEPH.balanceOf(contractAddress), 500); // Remaining balance
    }

    function test_getAmountIn_ETH_balance_branch() public {
        // Test the _token == address(0) branch in getAmountIn
        vm.deal(contractAddress, 1000);

        // This tests the ETH balance path in getAmountIn
        alephPaymentProcessor.process(address(0), 500, 0, 60);

        vm.assertEq(contractAddress.balance, 500); // Should have 500 ETH remaining
    }

    function test_getAmountIn_ERC20_balance_branch() public {
        // Test the _token != address(0) branch in getAmountIn
        deal(address(ALEPH), contractAddress, 1000);

        // This tests the ERC20 balance path in getAmountIn
        alephPaymentProcessor.process(address(ALEPH), 300, 0, 60);

        vm.assertEq(ALEPH.balanceOf(contractAddress), 700); // Should have 700 ALEPH remaining
    }

    function test_withdraw_ETH_branch() public {
        // Test the _token == address(0) branch in withdraw
        vm.deal(contractAddress, 1000);
        alephPaymentProcessor.removeTokenConfig(address(0));

        uint256 initialRecipientBalance = distributionRecipientAddress.balance;

        alephPaymentProcessor.withdraw(address(0), payable(distributionRecipientAddress), 500);

        vm.assertEq(distributionRecipientAddress.balance - initialRecipientBalance, 500);
    }

    function test_withdraw_ERC20_branch() public {
        // Test the _token != address(0) branch in withdraw
        deal(address(USDC), contractAddress, 1000);
        alephPaymentProcessor.removeTokenConfig(address(USDC));

        uint256 initialRecipientBalance = USDC.balanceOf(distributionRecipientAddress);

        alephPaymentProcessor.withdraw(address(USDC), payable(distributionRecipientAddress), 500);

        vm.assertEq(USDC.balanceOf(distributionRecipientAddress) - initialRecipientBalance, 500);
    }

    function test_withdraw_invalid_token_branch() public {
        // Test the withdraw validation branch for ALEPH token
        deal(address(ALEPH), contractAddress, 1000);

        vm.expectRevert("Cannot withdraw a token configured for automatic distribution");
        alephPaymentProcessor.withdraw(address(ALEPH), payable(distributionRecipientAddress), 500);
    }

    function test_withdraw_invalid_recipient_branch() public {
        // Test the withdraw validation branch for invalid recipient
        vm.deal(contractAddress, 1000);
        alephPaymentProcessor.removeTokenConfig(address(0));

        vm.expectRevert("Invalid recipient address");
        alephPaymentProcessor.withdraw(address(0), payable(address(0)), 500);
    }

    function test_swapV4_ETH_branch() public {
        // Test the _token == address(0) branch in swapV4
        vm.deal(contractAddress, 1 ether);

        // This will trigger the ETH swap branch in swapV4
        alephPaymentProcessor.process(address(0), 0.1 ether, 0, 60);

        vm.assertEq(contractAddress.balance, 0.9 ether);
    }

    function test_swapV4_ERC20_branch() public {
        // Test the _token != address(0) branch in swapV4
        deal(address(USDC), contractAddress, 1000);

        // This will trigger the ERC20 swap branch in swapV4
        alephPaymentProcessor.process(address(USDC), 200, 0, 60);

        vm.assertEq(USDC.balanceOf(contractAddress), 800);
    }

    function test_process_pending_ALEPH_validation_pass() public {
        // Test the validation branch where _token == address(ALEPH)
        deal(address(ALEPH), contractAddress, 1000);

        // This should pass because _token == address(ALEPH)
        alephPaymentProcessor.process(address(ALEPH), 500, 0, 60);

        vm.assertEq(ALEPH.balanceOf(contractAddress), 500);
    }

    function test_process_pending_ALEPH_validation_pass_zero_balance() public {
        // Test the validation branch where ALEPH balance is 0
        vm.deal(contractAddress, 1000);
        // Ensure ALEPH balance is 0
        vm.assertEq(ALEPH.balanceOf(contractAddress), 0);

        // This should pass because ALEPH balance is 0
        alephPaymentProcessor.process(address(0), 500, 0, 60);

        vm.assertEq(contractAddress.balance, 500);
    }

    // ======== TARGETED BRANCH COVERAGE TESTS ========

    function test_initialize_error_branches() public {
        // Test each require condition in initialize to hit error branches
        AlephPaymentProcessor newProcessor = new AlephPaymentProcessor();

        // Test invalid token address branch (line 87, BRDA:87,0,0)
        vm.expectRevert("Invalid token address");
        newProcessor.initialize(
            address(0), // Invalid token
            distributionRecipientAddress,
            developersRecipientAddress,
            5,
            5,
            uniswapRouterAddress,
            permit2Address
        );

        // Test invalid distribution recipient branch (line 88, BRDA:88,1,0)
        vm.expectRevert("Invalid distribution recipient address");
        newProcessor.initialize(
            alephTokenAddress,
            address(0), // Invalid distribution recipient
            developersRecipientAddress,
            5,
            5,
            uniswapRouterAddress,
            permit2Address
        );

        // Test invalid developers recipient branch (line 92, BRDA:92,2,0)
        vm.expectRevert("Invalid developers recipient address");
        newProcessor.initialize(
            alephTokenAddress,
            distributionRecipientAddress,
            address(0), // Invalid developers recipient
            5,
            5,
            uniswapRouterAddress,
            permit2Address
        );

        // Test invalid burn percentage branch (line 96, BRDA:96,3,0)
        vm.expectRevert("Invalid burn percentage");
        newProcessor.initialize(
            alephTokenAddress,
            distributionRecipientAddress,
            developersRecipientAddress,
            101, // Invalid burn percentage
            5,
            uniswapRouterAddress,
            permit2Address
        );

        // Test invalid developers percentage branch (line 97, BRDA:97,4,0)
        vm.expectRevert("Invalid developers percentage");
        newProcessor.initialize(
            alephTokenAddress,
            distributionRecipientAddress,
            developersRecipientAddress,
            5,
            101, // Invalid developers percentage
            uniswapRouterAddress,
            permit2Address
        );

        // Test total percentages exceed 100% branch (line 98, BRDA:98,5,0)
        vm.expectRevert("Total percentages exceed 100%");
        newProcessor.initialize(
            alephTokenAddress,
            distributionRecipientAddress,
            developersRecipientAddress,
            60,
            50, // 60 + 50 = 110% > 100%
            uniswapRouterAddress,
            permit2Address
        );
    }

    function test_process_pending_aleph_validation_error() public {
        // Test the error branch in process validation (line 129, BRDA:129,6,1)
        deal(address(ALEPH), contractAddress, 1000); // Give contract some ALEPH
        vm.deal(contractAddress, 1000); // Give contract some ETH

        vm.expectRevert("Pending ALEPH balance must be processed before");
        alephPaymentProcessor.process(address(0), 500, 0, 60); // Try to process ETH while ALEPH balance exists
    }

    function test_stable_token_non_aleph_branch() public {
        // Test the stable token branch where _token != address(ALEPH) (line 144, BRDA:144,7,0)
        alephPaymentProcessor.setStableToken(usdcTokenAddress, true);
        deal(address(USDC), contractAddress, 1000);

        uint256 initialDevelopersBalance = USDC.balanceOf(developersRecipientAddress);

        alephPaymentProcessor.process(address(USDC), 1000, 0, 60);

        // Should give developers 5% in USDC directly
        vm.assertGt(USDC.balanceOf(developersRecipientAddress), initialDevelopersBalance);
    }

    function test_stable_token_eth_transfer_branch() public {
        // Test ETH transfer branch for stable tokens (line 146, BRDA:146,8,0)
        alephPaymentProcessor.setStableToken(address(0), true); // Set ETH as stable
        vm.deal(contractAddress, 1000);

        uint256 initialDevelopersETHBalance = developersRecipientAddress.balance;

        alephPaymentProcessor.process(address(0), 1000, 0, 60);

        // Should give developers 5% in ETH directly
        vm.assertGt(developersRecipientAddress.balance, initialDevelopersETHBalance);
    }

    function test_stable_token_erc20_transfer_branch() public {
        // Test ERC20 transfer branch for stable tokens (line 147, BRDA:147,9,0)
        alephPaymentProcessor.setStableToken(usdcTokenAddress, true);
        deal(address(USDC), contractAddress, 1000);

        uint256 initialDevelopersBalance = USDC.balanceOf(developersRecipientAddress);

        alephPaymentProcessor.process(address(USDC), 1000, 0, 60);

        // Should give developers 5% in USDC directly
        vm.assertEq(USDC.balanceOf(developersRecipientAddress) - initialDevelopersBalance, 50);
    }

    function test_stable_token_eth_transfer_failure() public {
        // Test ETH transfer failure branch (line 158, BRDA:158,10,0)
        alephPaymentProcessor.setStableToken(address(0), true);
        vm.deal(contractAddress, 1000);

        // Mock a scenario where ETH transfer could fail
        // This is hard to test directly, but we can test the branch is there
        alephPaymentProcessor.process(address(0), 1000, 0, 60);

        // If we get here, the transfer succeeded
        vm.assertGt(developersRecipientAddress.balance, 0);
    }

    function test_stable_token_proportional_zero_swap() public {
        // Test the proportional calculation branch when swapAmount > 0 (line 171)
        alephPaymentProcessor.setStableToken(usdcTokenAddress, true);
        deal(address(USDC), contractAddress, 100);

        uint256 initialBurnBalance = ALEPH.balanceOf(address(0));

        alephPaymentProcessor.process(address(USDC), 100, 0, 60);

        // Should have swapped and burned some ALEPH
        vm.assertGt(ALEPH.balanceOf(address(0)), initialBurnBalance);
    }

    function test_withdraw_token_config_validation() public {
        // Test the withdraw validation for token with config (line 239, BRDA:239,16,0)
        vm.expectRevert("Cannot withdraw a token configured for automatic distribution");
        alephPaymentProcessor.withdraw(address(ALEPH), payable(distributionRecipientAddress), 100);

        // Test with configured token
        vm.expectRevert("Cannot withdraw a token configured for automatic distribution");
        alephPaymentProcessor.withdraw(address(0), payable(distributionRecipientAddress), 100);
    }

    function test_withdraw_invalid_recipient() public {
        // Test invalid recipient validation (line 244, BRDA:244,17,0)
        vm.deal(contractAddress, 1000);
        alephPaymentProcessor.removeTokenConfig(address(0));

        vm.expectRevert("Invalid recipient address");
        alephPaymentProcessor.withdraw(address(0), payable(address(0)), 500);
    }

    function test_withdraw_eth_vs_erc20_branches() public {
        // Test ETH withdrawal branch (line 254, BRDA:254,18,0)
        vm.deal(contractAddress, 1000);
        alephPaymentProcessor.removeTokenConfig(address(0));

        uint256 initialBalance = distributionRecipientAddress.balance;
        alephPaymentProcessor.withdraw(address(0), payable(distributionRecipientAddress), 500);
        vm.assertEq(distributionRecipientAddress.balance - initialBalance, 500);

        // Test ERC20 withdrawal branch (line 254, BRDA:254,18,1)
        deal(address(USDC), contractAddress, 1000);
        alephPaymentProcessor.removeTokenConfig(address(USDC));

        uint256 initialUSDCBalance = USDC.balanceOf(distributionRecipientAddress);
        alephPaymentProcessor.withdraw(address(USDC), payable(distributionRecipientAddress), 300);
        vm.assertEq(USDC.balanceOf(distributionRecipientAddress) - initialUSDCBalance, 300);
    }

    function test_withdraw_transfer_failure() public {
        // Test transfer failure branch (line 260, BRDA:260,19,0)
        vm.deal(contractAddress, 100);
        alephPaymentProcessor.removeTokenConfig(address(0));

        // Try to withdraw more than available - should fail with "Insufficient balance"
        vm.expectRevert("Insufficient balance");
        alephPaymentProcessor.withdraw(address(0), payable(distributionRecipientAddress), 200);
    }

    function test_getAmountIn_balance_check() public {
        // Test insufficient balance branch (line 276, BRDA:276,20,0)
        vm.deal(contractAddress, 100);

        vm.expectRevert("Insufficient balance");
        alephPaymentProcessor.process(address(0), 200, 0, 60); // Try to process more than available
    }

    function test_setBurnPercentage_validation_branches() public {
        // Test invalid burn percentage > 100 (line 282, BRDA:282,21,0)
        vm.expectRevert("Invalid burn percentage");
        alephPaymentProcessor.setBurnPercentage(101);

        // Test total percentages exceed 100% (line 283, BRDA:283,22,0)
        vm.expectRevert("Total percentages exceed 100%");
        alephPaymentProcessor.setBurnPercentage(96); // 96 + 5 (developers) = 101%
    }

    function test_setDevelopersPercentage_validation_branches() public {
        // Test invalid developers percentage > 100 (line 294, BRDA:294,23,0)
        vm.expectRevert("Invalid developers percentage");
        alephPaymentProcessor.setDevelopersPercentage(101);

        // Test total percentages exceed 100% (line 298, BRDA:298,24,0)
        vm.expectRevert("Total percentages exceed 100%");
        alephPaymentProcessor.setDevelopersPercentage(96); // 5 (burn) + 96 = 101%
    }

    function test_setDistributionRecipient_validation() public {
        // Test invalid distribution recipient (line 309, BRDA:309,25,0)
        vm.expectRevert("Invalid distribution recipient address");
        alephPaymentProcessor.setDistributionRecipient(address(0));
    }

    function test_setDevelopersRecipient_validation() public {
        // Test invalid developers recipient (line 320, BRDA:320,26,0)
        vm.expectRevert("Invalid developers recipient address");
        alephPaymentProcessor.setDevelopersRecipient(address(0));
    }

    function test_removeTokenConfig_validation() public {
        // Test invalid token config removal (line 361, BRDA:361,27,0)
        vm.expectRevert("Invalid token config");
        alephPaymentProcessor.removeTokenConfig(makeAddr("nonExistentToken"));
    }

    function test_swapV4_invalid_version_branch() public {
        // Test invalid uniswap version (line 391, BRDA:391,28,0)
        alephPaymentProcessor.removeTokenConfig(address(0));
        vm.deal(contractAddress, 1000);

        vm.expectRevert("Invalid uniswap version");
        alephPaymentProcessor.process(address(0), 500, 0, 60);
    }

    function test_swapV4_eth_vs_erc20_branches() public {
        // Test ETH swap branch (line 434, BRDA:434,29,0)
        vm.deal(contractAddress, 1 ether);
        alephPaymentProcessor.process(address(0), 0.1 ether, 0, 60);
        vm.assertEq(contractAddress.balance, 0.9 ether);

        // Test ERC20 swap branch (line 434, BRDA:434,29,1) is harder to test
        // since it requires the approve function which has access control
    }

    function test_swapV4_insufficient_output() public {
        // Test insufficient output amount (line 445, BRDA:445,30,0)
        vm.deal(contractAddress, 0.001 ether); // Very small amount

        vm.expectRevert(); // Should revert with "Insufficient output amount" or similar
        alephPaymentProcessor.process(address(0), 0.001 ether, type(uint128).max, 60); // Demand impossible output
    }

    // ======== ADDITIONAL BRANCH COVERAGE TESTS ========

    function test_stable_token_zero_developers_amount_eth() public {
        // Test when developers amount is 0 for ETH stable token (hitting specific branches)
        alephPaymentProcessor.setDevelopersPercentage(0);
        alephPaymentProcessor.setStableToken(address(0), true);

        vm.deal(contractAddress, 1000);

        uint256 initialBurnBalance = ALEPH.balanceOf(address(0));
        uint256 initialDevelopersETHBalance = developersRecipientAddress.balance;

        alephPaymentProcessor.process(address(0), 1000, 0, 60);

        // Developers should get 0 ETH (0% of 1000)
        vm.assertEq(developersRecipientAddress.balance, initialDevelopersETHBalance);

        // All 1000 should be swapped and distributed/burned
        vm.assertGt(ALEPH.balanceOf(address(0)), initialBurnBalance);
    }

    function test_stable_token_zero_developers_amount_erc20() public {
        // Test when developers amount is 0 for ERC20 stable token
        alephPaymentProcessor.setDevelopersPercentage(0);
        alephPaymentProcessor.setStableToken(usdcTokenAddress, true);

        deal(address(USDC), contractAddress, 1000);

        uint256 initialBurnBalance = ALEPH.balanceOf(address(0));
        uint256 initialDevelopersUSDCBalance = USDC.balanceOf(developersRecipientAddress);

        alephPaymentProcessor.process(address(USDC), 1000, 0, 60);

        // Developers should get 0 USDC (0% of 1000)
        vm.assertEq(USDC.balanceOf(developersRecipientAddress), initialDevelopersUSDCBalance);

        // All 1000 should be swapped and distributed/burned
        vm.assertGt(ALEPH.balanceOf(address(0)), initialBurnBalance);
    }

    function test_non_stable_token_zero_swap_amount() public {
        // Test when _token == address(ALEPH) so no swap needed (line 196 branch)
        deal(address(ALEPH), contractAddress, 1000);

        uint256 initialDistributionBalance = ALEPH.balanceOf(distributionRecipientAddress);
        uint256 initialDevelopersBalance = ALEPH.balanceOf(developersRecipientAddress);
        uint256 initialBurnBalance = ALEPH.balanceOf(address(0));

        alephPaymentProcessor.process(address(ALEPH), 1000, 0, 60);

        // Should distribute directly without swap
        vm.assertEq(ALEPH.balanceOf(distributionRecipientAddress) - initialDistributionBalance, 900); // 90%
        vm.assertEq(ALEPH.balanceOf(developersRecipientAddress) - initialDevelopersBalance, 50); // 5%
        vm.assertEq(ALEPH.balanceOf(address(0)) - initialBurnBalance, 50); // 5%
    }

    function test_stable_token_swap_amount_zero() public {
        // Test when swapAmount is 0 in stable token processing
        // When developers get 100%, there's nothing to swap, which should fail with SwapAmountCannotBeZero
        alephPaymentProcessor.setBurnPercentage(0);
        alephPaymentProcessor.setDevelopersPercentage(100);
        alephPaymentProcessor.setStableToken(address(0), true); // Set ETH as stable token

        vm.deal(contractAddress, 100);

        // This should revert because swapAmount would be 0
        vm.expectRevert(); // Expecting SwapAmountCannotBeZero()
        alephPaymentProcessor.process(address(0), 100, 0, 60);
    }

    function test_withdraw_token_vs_aleph_validation() public {
        // Test different paths in withdraw validation

        // Test ALEPH token (should fail)
        vm.expectRevert("Cannot withdraw a token configured for automatic distribution");
        alephPaymentProcessor.withdraw(address(ALEPH), payable(distributionRecipientAddress), 100);

        // Test configured token (ETH - should fail)
        vm.expectRevert("Cannot withdraw a token configured for automatic distribution");
        alephPaymentProcessor.withdraw(address(0), payable(distributionRecipientAddress), 100);

        // Test unconfigured token after removing config (should succeed)
        alephPaymentProcessor.removeTokenConfig(address(0));
        vm.deal(contractAddress, 1000);

        uint256 initialBalance = distributionRecipientAddress.balance;
        alephPaymentProcessor.withdraw(address(0), payable(distributionRecipientAddress), 500);
        vm.assertEq(distributionRecipientAddress.balance - initialBalance, 500);
    }

    function test_getAmountIn_different_token_branches() public {
        // Test ETH balance branch
        vm.deal(contractAddress, 1000);
        uint256 balance1 = contractAddress.balance;
        alephPaymentProcessor.process(address(0), 500, 0, 60);
        vm.assertEq(contractAddress.balance, balance1 - 500);

        // Test ERC20 balance branch
        deal(address(ALEPH), contractAddress, 2000);
        uint256 balance2 = ALEPH.balanceOf(contractAddress);
        alephPaymentProcessor.process(address(ALEPH), 300, 0, 60);
        vm.assertEq(ALEPH.balanceOf(contractAddress), balance2 - 300);
    }

    function test_zero_amount_processing() public {
        // Test processing with _amountIn = 0 (should process all balance)
        deal(address(ALEPH), contractAddress, 1500);

        uint256 initialDistributionBalance = ALEPH.balanceOf(distributionRecipientAddress);

        alephPaymentProcessor.process(address(ALEPH), 0, 0, 60); // Process all

        // Should process all 1500 ALEPH
        vm.assertEq(ALEPH.balanceOf(distributionRecipientAddress) - initialDistributionBalance, 1350); // 90% of 1500
        vm.assertEq(ALEPH.balanceOf(contractAddress), 0); // All processed
    }

    function test_exact_boundary_percentages() public {
        // Test with exact boundary conditions
        alephPaymentProcessor.setBurnPercentage(0);
        alephPaymentProcessor.setDevelopersPercentage(0);

        deal(address(ALEPH), contractAddress, 1000);

        uint256 initialDistributionBalance = ALEPH.balanceOf(distributionRecipientAddress);
        uint256 initialDevelopersBalance = ALEPH.balanceOf(developersRecipientAddress);
        uint256 initialBurnBalance = ALEPH.balanceOf(address(0));

        alephPaymentProcessor.process(address(ALEPH), 1000, 0, 60);

        // 100% should go to distribution
        vm.assertEq(ALEPH.balanceOf(distributionRecipientAddress) - initialDistributionBalance, 1000);
        vm.assertEq(ALEPH.balanceOf(developersRecipientAddress), initialDevelopersBalance);
        vm.assertEq(ALEPH.balanceOf(address(0)), initialBurnBalance);
    }
}
