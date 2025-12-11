// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {UniversalRouter} from "@uniswap/universal-router/contracts/UniversalRouter.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {PathKey} from "@uniswap/v4-periphery/src/libraries/PathKey.sol";
import {AlephSwapLibrary, SwapConfig} from "./AlephSwapLibrary.sol";

error InvalidAddress();
error InvalidPercentage();
error ExceedsTotal();
error TtlOutOfRange();
error PendingBalance();
error NotConfigured();
error ExceedsMax();
error InsufficientBalance();
error TransferFailed();
error InvalidPath();
error DuplicateTokens();
error PathTooLong();
error InvalidVersion();
error InsufficientOutput();
error CannotWithdraw();
error InvalidSwapConfig();
error PathTooShort();
error BurnFailed();
error ZeroAmount();
error ZeroMinimumOutput();

interface IBurnable {
    function burn(uint256 amount) external;
}

/**
 * @title AlephPaymentProcessor
 * @dev Processes token payments by swapping them to ALEPH tokens through Uniswap (V2, V3, V4)
 *      and distributing the proceeds according to configured percentages for burning,
 *      developers, and distribution recipients. Supports native ETH and ERC20 tokens.
 *      Uses Universal Router v2 for optimal routing and gas efficiency.
 */
contract AlephPaymentProcessor is
    Initializable,
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    event TokenPaymentsProcessed(
        address indexed _token,
        address indexed sender,
        uint256 amount,
        uint256 swapAmount,
        uint256 alephReceived,
        uint256 amountBurned,
        uint256 amountToDistribution,
        uint256 amountToDevelopers,
        uint8 swapVersion,
        bool isStable
    );

    event SwapExecuted(address indexed token, uint256 amountIn, uint256 amountOut, uint8 version, uint256 timestamp);

    // Events for parameter updates
    event SwapConfigUpdated(
        address indexed token, uint8 version, address indexed oldToken, uint8 oldVersion, uint256 timestamp
    );
    event SwapConfigRemoved(address indexed token, uint8 version, uint256 timestamp);
    event DistributionRecipientUpdated(address indexed oldRecipient, address indexed newRecipient, uint256 timestamp);
    event DevelopersRecipientUpdated(address indexed oldRecipient, address indexed newRecipient, uint256 timestamp);
    event BurnPercentageUpdated(uint8 oldPercentage, uint8 newPercentage, uint256 timestamp);
    event DevelopersPercentageUpdated(uint8 oldPercentage, uint8 newPercentage, uint256 timestamp);
    event StableTokenUpdated(address indexed token, bool isStable, uint256 timestamp);
    event TokenWithdrawn(address indexed token, address indexed to, uint256 amount, uint256 timestamp);
    event AdminAdded(address indexed admin, uint256 timestamp);
    event AdminRemoved(address indexed admin, uint256 timestamp);
    event TokensBurned(uint256 amount, string method, uint256 timestamp);

    // Payment settings
    address public distributionRecipient; // Address that receives the distribution portion of payments
    address public developersRecipient; // Address that receives the developers portion of payments
    uint8 public burnPercentage; // Percentage of tokens to burn (0-100)
    uint8 public developersPercentage; // Percentage of tokens to send to developers (0-100)

    // Stable token addresses for detecting when not to swap developers portion
    mapping(address => bool) public isStableToken;

    /// @notice Role allowed to process balances and withdraw tokens
    /// @dev Admin role can call process() and withdraw() functions
    /// @dev Owner role can manage configurations, percentages, and grant/revoke admin roles
    bytes32 public adminRole;

    // Token contracts
    IERC20 internal aleph;
    address internal wethAddress;

    // Uniswap v4 utils
    UniversalRouter internal router;
    IPermit2 internal permit2;

    // Swap configuration for swapping in uniswap
    mapping(address => SwapConfig) internal swapConfig;

    /**
     * @dev Constructor disables initializers on the implementation contract
     * This prevents front-running attacks where an attacker could initialize
     * the implementation contract before the proxy is deployed
     *
     * @notice In production, this contract should only be initialized through a proxy.
     * Direct initialization of the implementation contract is disabled for security.
     */
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with required parameters
     * @param _alephTokenAddress Address of the ALEPH token contract
     * @param _distributionRecipientAddress Address to receive distribution portion
     * @param _developersRecipientAddress Address to receive developers portion
     * @param _burnPercentage Percentage to burn (0-100)
     * @param _developersPercentage Percentage for developers (0-100)
     * @param _uniswapRouterAddress Universal Router contract address
     * @param _permit2Address Permit2 contract address
     * @param _wethAddress WETH token address for the current network
     */
    function initialize(
        address _alephTokenAddress,
        address _distributionRecipientAddress,
        address _developersRecipientAddress,
        uint8 _burnPercentage,
        uint8 _developersPercentage,
        address _uniswapRouterAddress,
        address _permit2Address,
        address _wethAddress
    ) public initializer {
        _validAddr(_alephTokenAddress);
        _validAddr(_distributionRecipientAddress);
        _validAddr(_developersRecipientAddress);
        _validAddr(_uniswapRouterAddress);
        _validAddr(_permit2Address);
        _validAddr(_wethAddress);
        _validPerc(_burnPercentage, _developersPercentage);

        __Ownable_init(msg.sender);
        __Ownable2Step_init();
        __AccessControl_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        adminRole = keccak256("ADMIN_ROLE");

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(adminRole, msg.sender);

        aleph = IERC20(_alephTokenAddress);

        distributionRecipient = _distributionRecipientAddress;
        developersRecipient = _developersRecipientAddress;
        burnPercentage = _burnPercentage;
        developersPercentage = _developersPercentage;

        router = UniversalRouter(payable(_uniswapRouterAddress));
        permit2 = IPermit2(_permit2Address);
        wethAddress = _wethAddress;
    }

    /**
     * @dev Processes token payments by swapping to ALEPH and distributing according to percentages
     * @param _token Token address to process (address(0) for ETH)
     * @param _amountIn Amount to process (0 for all available balance)
     * @param _amountOutMinimum Minimum ALEPH output expected from swap
     * @param _ttl Time to live for the transaction in seconds (60-3600 seconds)
     */
    function process(address _token, uint128 _amountIn, uint128 _amountOutMinimum, uint48 _ttl)
        external
        onlyRole(adminRole)
        nonReentrant
    {
        if (_ttl < 60 || _ttl > 3600) revert TtlOutOfRange();

        // Cache swap config to avoid multiple SLOAD operations
        SwapConfig memory cachedSwapConfig = swapConfig[_token];

        if (_token != address(aleph) && cachedSwapConfig.v == 0) {
            revert NotConfigured();
        }

        uint128 amountIn = _getAmountIn(_token, _amountIn);

        // Prevent unnecessary processing of zero amounts
        if (amountIn == 0) revert ZeroAmount();

        // Prevent 100% slippage by requiring minimum output for non-ALEPH swaps
        if (_token != address(aleph) && _amountOutMinimum == 0) {
            revert ZeroMinimumOutput();
        }

        // Cache storage variables for gas optimization
        uint8 cachedDevelopersPercentage = developersPercentage;
        uint8 cachedBurnPercentage = burnPercentage;
        address cachedDevelopersRecipient = developersRecipient;
        address cachedDistributionRecipient = distributionRecipient;
        bool isStable = isStableToken[_token];
        address alephAddress = address(aleph);

        // Calculate portions from initial amount
        (uint256 developersAmount, uint256 burnAmount, uint256 distributionAmount) =
            _calculateProportions(uint256(amountIn), cachedDevelopersPercentage, cachedBurnPercentage);

        if (isStable && _token != alephAddress) {
            // For stable tokens: send developers portion directly, swap the rest
            _transferTokenOrEth(
                _token, cachedDevelopersRecipient, developersAmount, "Transfer to developers recipient failed"
            );

            // Swap burn + distribution portions to ALEPH
            uint256 swapAmount = burnAmount + distributionAmount;
            uint256 alephReceived = _swapToken(_token, uint128(swapAmount), _amountOutMinimum, _ttl);

            // Calculate proportional ALEPH amounts based on original percentages
            uint256 alephBurnAmount = swapAmount > 0 ? (alephReceived * burnAmount) / swapAmount : 0;
            uint256 alephDistributionAmount = alephReceived - alephBurnAmount;

            _burnTokens(alephBurnAmount);

            aleph.safeTransfer(cachedDistributionRecipient, alephDistributionAmount);

            emit TokenPaymentsProcessed(
                _token,
                msg.sender,
                amountIn,
                swapAmount,
                alephReceived,
                alephBurnAmount,
                alephDistributionAmount,
                developersAmount,
                cachedSwapConfig.v,
                isStable
            );
        } else {
            // For non-stable tokens or ALEPH: swap entire amount, then distribute proportionally
            uint256 alephReceived =
                _token != alephAddress ? _swapToken(_token, amountIn, _amountOutMinimum, _ttl) : amountIn;

            // Calculate ALEPH amounts based on original input percentages
            (uint256 alephDevelopersAmount, uint256 alephBurnAmount, uint256 alephDistributionAmount) =
                _calculateProportions(alephReceived, cachedDevelopersPercentage, cachedBurnPercentage);

            aleph.safeTransfer(cachedDevelopersRecipient, alephDevelopersAmount);

            _burnTokens(alephBurnAmount);

            aleph.safeTransfer(cachedDistributionRecipient, alephDistributionAmount);

            emit TokenPaymentsProcessed(
                _token,
                msg.sender,
                amountIn,
                _token != alephAddress ? amountIn : 0,
                alephReceived,
                alephBurnAmount,
                alephDistributionAmount,
                alephDevelopersAmount,
                _token != alephAddress ? cachedSwapConfig.v : 0,
                isStable
            );
        }
    }

    /**
     * @dev Withdraws tokens that are not configured for automatic processing
     * @param _token Token address to withdraw (address(0) for ETH)
     * @param _to Recipient address
     * @param _amount Amount to withdraw (0 for all available balance)
     */
    function withdraw(address _token, address payable _to, uint128 _amount) external onlyRole(adminRole) nonReentrant {
        // Check if token is configured for swapping
        bool isConfigured = swapConfig[_token].v > 0;

        // For WETH, also check if ETH (address(0)) is configured, since WETH
        // is used internally for ETH swaps but config is stored under address(0)
        if (_token == wethAddress && swapConfig[address(0)].v > 0) {
            isConfigured = true;
        }

        if (_token == address(aleph) || isConfigured) {
            revert CannotWithdraw();
        }
        _validAddr(_to);
        if (_to == address(this)) revert InvalidAddress();

        uint256 amount = _getAmountIn(_token, _amount);
        if (amount == 0) revert InsufficientBalance();

        _transferTokenOrEth(_token, _to, amount, "Transfer failed");

        emit TokenWithdrawn(_token, _to, amount, block.timestamp);
    }

    /**
     * @dev Gets the actual amount to process, using full balance if _amountIn is 0
     * @param _token Token address to check balance for
     * @param _amountIn Requested amount (0 for full balance)
     * @return amountIn Actual amount to process
     */
    function _getAmountIn(address _token, uint128 _amountIn) internal view returns (uint128 amountIn) {
        uint256 balance = _token != address(0) ? IERC20(_token).balanceOf(address(this)) : address(this).balance;

        amountIn = _amountIn != 0 ? _amountIn : Math.min(balance, type(uint128).max).toUint128();

        // Check balance (native ETH if _token == 0x0 or ERC20 otherwise)
        if (balance < amountIn) revert InsufficientBalance();

        return amountIn;
    }

    /**
     * @dev Safely transfers tokens or ETH to a recipient
     * @param _token Token address (address(0) for ETH)
     * @param _recipient Address to receive the transfer
     * @param _amount Amount to transfer
     */
    function _transferTokenOrEth(address _token, address _recipient, uint256 _amount, string memory) internal {
        if (_token != address(0)) {
            IERC20(_token).safeTransfer(_recipient, _amount);
        } else {
            (bool success,) = _recipient.call{value: _amount}("");
            if (!success) revert TransferFailed();
        }
    }

    /**
     * @dev Validates percentage values and their sum
     * @param p1 First percentage to validate
     * @param p2 Second percentage to validate
     */
    function _validPerc(uint8 p1, uint8 p2) private pure {
        if (p1 > 100 || p2 > 100) revert InvalidPercentage();
        if (p1 + p2 > 100) revert ExceedsTotal();
    }

    /**
     * @dev Calculates proportional amounts based on percentages
     * @param _totalAmount Total amount to split
     * @param _developersPercentage Developers percentage
     * @param _burnPercentage Burn percentage
     * @return developersAmount Amount for developers
     * @return burnAmount Amount to burn
     * @return distributionAmount Remaining amount for distribution
     */
    function _calculateProportions(uint256 _totalAmount, uint8 _developersPercentage, uint8 _burnPercentage)
        internal
        pure
        returns (uint256 developersAmount, uint256 burnAmount, uint256 distributionAmount)
    {
        developersAmount = (_totalAmount * _developersPercentage) / 100;
        burnAmount = (_totalAmount * _burnPercentage) / 100;
        distributionAmount = _totalAmount - developersAmount - burnAmount;
    }

    /**
     * @dev Sets the burn percentage for token processing
     * @param _newBurnPercentage New burn percentage (0-100)
     */
    function setBurnPercentage(uint8 _newBurnPercentage) external onlyOwner {
        _validPerc(_newBurnPercentage, developersPercentage);
        uint8 oldPercentage = burnPercentage;
        burnPercentage = _newBurnPercentage;
        emit BurnPercentageUpdated(oldPercentage, _newBurnPercentage, block.timestamp);
    }

    /**
     * @dev Sets the developers percentage for token processing
     * @param _newDevelopersPercentage New developers percentage (0-100)
     */
    function setDevelopersPercentage(uint8 _newDevelopersPercentage) external onlyOwner {
        _validPerc(burnPercentage, _newDevelopersPercentage);
        uint8 oldPercentage = developersPercentage;
        developersPercentage = _newDevelopersPercentage;
        emit DevelopersPercentageUpdated(oldPercentage, _newDevelopersPercentage, block.timestamp);
    }

    /**
     * @dev Validates that an address is not zero
     * @param a Address to validate
     */
    function _validAddr(address a) private pure {
        if (a == address(0)) revert InvalidAddress();
    }

    /**
     * @dev Sets the distribution recipient address
     * @param _newDistributionRecipient New distribution recipient address
     */
    function setDistributionRecipient(address _newDistributionRecipient) external onlyOwner {
        _validAddr(_newDistributionRecipient);
        address oldRecipient = distributionRecipient;
        distributionRecipient = _newDistributionRecipient;
        emit DistributionRecipientUpdated(oldRecipient, _newDistributionRecipient, block.timestamp);
    }

    /**
     * @dev Sets the developers recipient address
     * @param _newDevelopersRecipient New developers recipient address
     */
    function setDevelopersRecipient(address _newDevelopersRecipient) external onlyOwner {
        _validAddr(_newDevelopersRecipient);
        address oldRecipient = developersRecipient;
        developersRecipient = _newDevelopersRecipient;
        emit DevelopersRecipientUpdated(oldRecipient, _newDevelopersRecipient, block.timestamp);
    }

    /**
     * @dev Marks a token as stable or non-stable for processing logic
     * @param _token Token address to configure
     * @param _isStable True if token is stable (developers portion not swapped)
     */
    function setStableToken(address _token, bool _isStable) external onlyOwner {
        isStableToken[_token] = _isStable;
        emit StableTokenUpdated(_token, _isStable, block.timestamp);
    }

    /**
     * @dev Grants admin role to a new address
     * @param _newAdmin Address to grant admin role
     * @notice Only owner can grant admin roles. Admins can process payments and withdraw tokens.
     * @notice Consider using multi-signature wallet for owner role in production
     */
    function addAdmin(address _newAdmin) external onlyOwner {
        _validAddr(_newAdmin);
        _grantRole(adminRole, _newAdmin);

        emit AdminAdded(_newAdmin, block.timestamp);
    }

    /**
     * @dev Revokes admin role from an address
     * @param _admin Address to revoke admin role
     * @notice Only owner can revoke admin roles
     */
    function removeAdmin(address _admin) external onlyOwner {
        _validAddr(_admin);
        _revokeRole(adminRole, _admin);

        emit AdminRemoved(_admin, block.timestamp);
    }

    /**
     * @dev Returns the swap configuration for a token
     * @param _address Token address to query
     * @return SwapConfig struct with swap configuration
     */
    function getSwapConfig(address _address) external view returns (SwapConfig memory) {
        return swapConfig[_address];
    }

    /**
     * @dev Configures a token for Uniswap V2 swapping
     * @param _address Token address to configure
     * @param _v2Path Array of addresses defining the swap path
     */
    function setSwapConfigV2(address _address, address[] calldata _v2Path) external onlyOwner {
        address[] memory processedPath =
            AlephSwapLibrary.validateAndCreateV2Config(_address, _v2Path, address(aleph), wethAddress);

        SwapConfig memory oldConfig = swapConfig[_address];
        swapConfig[_address] = SwapConfig({v: 2, t: _address, v4: new PathKey[](0), v3: "", v2: processedPath});
        emit SwapConfigUpdated(_address, 2, oldConfig.t, oldConfig.v, block.timestamp);
    }

    /**
     * @dev Configures a token for Uniswap V3 swapping
     * @param _address Token address to configure
     * @param _v3Path Encoded path with fee tiers for V3 swapping
     */
    function setSwapConfigV3(address _address, bytes calldata _v3Path) external onlyOwner {
        bytes memory processedPath =
            AlephSwapLibrary.validateAndCreateV3Config(_address, _v3Path, address(aleph), wethAddress);

        SwapConfig memory oldConfig = swapConfig[_address];
        swapConfig[_address] =
            SwapConfig({v: 3, t: _address, v4: new PathKey[](0), v3: processedPath, v2: new address[](0)});
        emit SwapConfigUpdated(_address, 3, oldConfig.t, oldConfig.v, block.timestamp);
    }

    /**
     * @dev Configures a token for Uniswap V4 swapping
     * @param _address Token address to configure
     * @param _v4Path Array of PathKey structs defining the V4 swap path
     */
    function setSwapConfigV4(address _address, PathKey[] calldata _v4Path) external onlyOwner {
        AlephSwapLibrary.validateV4Config(_address, _v4Path, address(aleph));

        SwapConfig memory oldConfig = swapConfig[_address];
        swapConfig[_address] = SwapConfig({v: 4, t: _address, v4: _v4Path, v3: "", v2: new address[](0)});
        emit SwapConfigUpdated(_address, 4, oldConfig.t, oldConfig.v, block.timestamp);
    }

    /**
     * @dev Removes swap configuration to disable automatic processing
     * @param _address Token address to remove configuration for
     */
    function removeSwapConfig(address _address) external onlyOwner {
        SwapConfig memory config = swapConfig[_address];
        if (config.v == 0) revert InvalidSwapConfig();
        delete swapConfig[_address];
        emit SwapConfigRemoved(_address, config.v, block.timestamp);
    }

    /**
     * @dev Fallback function to receive ETH
     * This allows the contract to receive ETH payments directly
     */
    /**
     * @dev Fallback function to receive ETH payments directly
     * This allows the contract to receive ETH payments
     */
    receive() external payable {}

    /**
     * @dev Approves token spending through Permit2 for Universal Router
     * @param _token Token address to approve
     * @param _amount Amount to approve
     * @param _ttl Time to live for the approval
     */

    // https://docs.uniswap.org/contracts/v4/quickstart/swap
    /**
     * @dev Routes token swapping to appropriate Uniswap version based on configuration
     * @param _token Token address to swap from
     * @param _amountIn Amount of input tokens
     * @param _amountOutMinimum Minimum output amount expected
     * @param _ttl Time to live for the swap
     * @return amountOut Amount of ALEPH tokens received
     */
    function _swapToken(address _token, uint128 _amountIn, uint128 _amountOutMinimum, uint48 _ttl)
        internal
        returns (uint256 amountOut)
    {
        SwapConfig memory config = swapConfig[_token];
        uint8 v = config.v;
        if (v < 2 || v > 4) revert InvalidVersion();

        if (v == 2) {
            amountOut = AlephSwapLibrary.swapV2(_token, _amountIn, _amountOutMinimum, _ttl, config, router, permit2, aleph);
        } else if (v == 3) {
            amountOut = AlephSwapLibrary.swapV3(_token, _amountIn, _amountOutMinimum, _ttl, config, router, permit2, aleph);
        } else {
            amountOut = AlephSwapLibrary.swapV4(_token, _amountIn, _amountOutMinimum, _ttl, config, router, permit2, aleph);
        }

        emit SwapExecuted(_token, _amountIn, amountOut, v, block.timestamp);
        return amountOut;
    }


    /**
     * @dev Safely burns ALEPH tokens using the most appropriate method
     * @param _amount Amount of ALEPH tokens to burn
     */
    function _burnTokens(uint256 _amount) internal {
        if (_amount == 0) return;

        // Method 1: Try burn() function if the token supports it
        try IBurnable(address(aleph)).burn(_amount) {
            emit TokensBurned(_amount, "burn_function", block.timestamp);
            return;
        } catch {
            // Method 2: Try transfer to address(0)
            try aleph.transfer(address(0), _amount) {
                emit TokensBurned(_amount, "transfer_to_zero", block.timestamp);
                return;
            } catch {
                // Method 3: Transfer to dead address as last resort
                try aleph.transfer(0x000000000000000000000000000000000000dEaD, _amount) {
                    emit TokensBurned(_amount, "transfer_to_dead", block.timestamp);
                    return;
                } catch {
                    // If all methods fail, revert
                    revert BurnFailed();
                }
            }
        }
    }

    /**
     * @dev Function to authorize contract upgrades
     * @param newImplementation Address of the new implementation contract
     * @notice Only the contract owner can authorize upgrades
     * @notice This function is required for UUPS upgradeability pattern
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        // Additional upgrade validation logic can be added here if needed
        // For now, we only require owner authorization
    }
}
