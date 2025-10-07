// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CreateUniswapV4PoolScript is Script {
    
    IPoolManager constant POOL_MANAGER = IPoolManager(0x3fC91A3afd70395Cd496C647d5a6CC9D4B2b7FAD);
    PoolModifyLiquidityTest constant LIQUIDITY_ROUTER = PoolModifyLiquidityTest(0x83feDBeD11B3667f40263a88e8435fca51A03F8C);
    
    address constant USDC_ADDRESS = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;
    address constant ALEPH_ADDRESS = 0x4b3f52fFF693D898578f132f0222877848E09A8C;
    
    uint24 constant FEE = 10000;
    int24 constant TICK_SPACING = 200;
    
    int24 constant MIN_TICK = -887200;
    int24 constant MAX_TICK = 887200;
    
    bool public addLiquidity;
    
    function setUp() public {
        string memory addLiquidityStr = vm.envOr("ADD_LIQUIDITY", string("false"));
        addLiquidity = keccak256(abi.encodePacked(addLiquidityStr)) == keccak256(abi.encodePacked("true"));
    }

    function run() public {
        vm.createSelectFork(vm.rpcUrl("sepolia"));
        vm.startBroadcast();

        PoolKey memory poolKey = createPoolKey();
        
        logPoolConfiguration();
        
        uint160 sqrtPriceX96 = TickMath.getSqrtPriceAtTick(0);
        console.log("Initial sqrt price X96:", sqrtPriceX96);
        
        bool poolExists = initializePool(poolKey, sqrtPriceX96);
        
        if (addLiquidity && poolExists) {
            addInitialLiquidity(poolKey);
        } else if (addLiquidity) {
            console.log("Skipping liquidity addition due to pool initialization failure");
        }

        vm.stopBroadcast();
        
        logSummary();
    }
    
    function createPoolKey() internal pure returns (PoolKey memory) {
        Currency currency0;
        Currency currency1;
        
        if (USDC_ADDRESS < ALEPH_ADDRESS) {
            currency0 = Currency.wrap(USDC_ADDRESS);
            currency1 = Currency.wrap(ALEPH_ADDRESS);
        } else {
            currency0 = Currency.wrap(ALEPH_ADDRESS);
            currency1 = Currency.wrap(USDC_ADDRESS);
        }
        
        return PoolKey({
            currency0: currency0,
            currency1: currency1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(0))
        });
    }
    
    function initializePool(PoolKey memory poolKey, uint160 sqrtPriceX96) internal returns (bool success) {
        console.log("\n=== INITIALIZING POOL ===");
        
        try POOL_MANAGER.initialize(poolKey, sqrtPriceX96) returns (int24 tick) {
            console.log("Pool initialized successfully!");
            console.log("Initial tick:", uint256(int256(tick)));
            
            PoolId poolId = PoolId.wrap(keccak256(abi.encode(poolKey)));
            console.log("Pool ID:");
            console.logBytes32(PoolId.unwrap(poolId));
            
            return true;
            
        } catch Error(string memory reason) {
            console.log("Pool initialization result:", reason);
            
            if (keccak256(abi.encodePacked(reason)) == keccak256("PoolAlreadyInitialized()")) {
                console.log("Pool already exists!");
                PoolId poolId = PoolId.wrap(keccak256(abi.encode(poolKey)));
                console.log("Pool ID:");
                console.logBytes32(PoolId.unwrap(poolId));
                return true;
            } else {
                console.log("Pool initialization failed:", reason);
                return false;
            }
        } catch {
            console.log("Pool initialization failed with unknown error");
            return false;
        }
    }
    
    function addInitialLiquidity(PoolKey memory poolKey) internal {
        console.log("\n=== ADDING LIQUIDITY ===");
        
        address token0 = Currency.unwrap(poolKey.currency0);
        address token1 = Currency.unwrap(poolKey.currency1);
        
        uint256 balance0 = IERC20(token0).balanceOf(msg.sender);
        uint256 balance1 = IERC20(token1).balanceOf(msg.sender);
        
        console.log("Token0 balance:", balance0);
        console.log("Token1 balance:", balance1);
        
        if (balance0 == 0 || balance1 == 0) {
            console.log("Insufficient token balances for liquidity provision");
            console.log("Make sure you have both tokens in your wallet before adding liquidity");
            return;
        }
        
        uint256 liquidity0 = balance0 / 10;
        uint256 liquidity1 = balance1 / 10;
        
        console.log("Adding liquidity - Token0:", liquidity0);
        console.log("Adding liquidity - Token1:", liquidity1);
        
        IERC20(token0).approve(address(LIQUIDITY_ROUTER), liquidity0);
        IERC20(token1).approve(address(LIQUIDITY_ROUTER), liquidity1);
        
        IPoolManager.ModifyLiquidityParams memory params = IPoolManager.ModifyLiquidityParams({
            tickLower: MIN_TICK,
            tickUpper: MAX_TICK,
            liquidityDelta: int256(liquidity0 + liquidity1),
            salt: bytes32(0)
        });
        
        try LIQUIDITY_ROUTER.modifyLiquidity(poolKey, params, new bytes(0)) {
            console.log("Liquidity added successfully!");
        } catch Error(string memory reason) {
            console.log("Failed to add liquidity:", reason);
        } catch {
            console.log("Failed to add liquidity with unknown error");
        }
    }
    
    function logPoolConfiguration() internal view {
        console.log("=== POOL CONFIGURATION ===");
        console.log("Network: Sepolia");
        console.log("USDC:", USDC_ADDRESS);
        console.log("ALEPH:", ALEPH_ADDRESS);
        console.log("Pool Manager:", address(POOL_MANAGER));
        console.log("Fee Tier: 1% (10000 basis points)");
        console.log("Tick Spacing:", uint256(int256(TICK_SPACING)));
        console.log("Add Liquidity:", addLiquidity ? "Yes" : "No");
        
        if (addLiquidity) {
            console.log("Liquidity Router:", address(LIQUIDITY_ROUTER));
        }
    }
    
    function logSummary() internal view {
        console.log("\n=== SUMMARY ===");
        console.log("Script execution complete!");
        console.log("\nNext steps:");
        console.log("1. Verify the pool on Sepolia Etherscan");
        
        if (!addLiquidity) {
            console.log("2. Add liquidity by running: ADD_LIQUIDITY=true forge script ...");
        }
        
        console.log("3. Test swaps to ensure the pool is functioning");
        console.log("4. Update your frontend/contracts to use the new pool");
    }
}