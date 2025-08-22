// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {UniversalRouter} from "@uniswap/universal-router/contracts/UniversalRouter.sol";
import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PathKey} from "@uniswap/v4-periphery/src/libraries/PathKey.sol";

/**
 * @title AlephPaymentProcessor
 * @dev Processes token payments by swapping them to ALEPH tokens through Uniswap (V2, V3, V4)
 *      and distributing the proceeds according to configured percentages for burning,
 *      developers, and distribution recipients. Supports native ETH and ERC20 tokens.
 *      Uses Universal Router v2 for optimal routing and gas efficiency.
 */
contract AlephPaymentProcessor is Initializable, Ownable2StepUpgradeable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    struct TokenConfig {
        uint8 version; // 2, 3, 4 - pack with address
        address token;
        PathKey[] v4Path; // for v4
        bytes v3Path; // for v3 encoded path
        address[] v2Path; // for v2 address array path
    }

    event TokenPaymentsProcessed(
        address indexed _token,
        address indexed sender,
        uint256 amount,
        uint256 amountBurned,
        uint256 amountToDistribution,
        uint256 amountToDevelopers
    );

    // Events for parameter updates
    event TokenConfigUpdated(address indexed token, uint8 version);
    event TokenConfigRemoved(address indexed token, uint8 version);
    event DistributionRecipientUpdated(address indexed recipient);
    event DevelopersRecipientUpdated(address indexed recipient);
    event BurnPercentageUpdated(uint8 percentage);
    event DevelopersPercentageUpdated(uint8 percentage);

    // Payment settings
    address public distributionRecipient; // Address that receives the distribution portion of payments
    address public developersRecipient; // Address that receives the developers portion of payments
    uint8 public burnPercentage; // Percentage of tokens to burn (0-100)
    uint8 public developersPercentage; // Percentage of tokens to send to developers (0-100)

    // Stable token addresses for detecting when not to swap developers portion
    mapping(address => bool) public isStableToken;

    // @notice Role allowed to process balances
    bytes32 public adminRole;

    // Token contracts
    IERC20 internal aleph;
    address internal wethAddress;

    // Uniswap v4 utils
    UniversalRouter internal router;
    IPermit2 internal permit2;

    // Token configuration for swapping in uniswap
    mapping(address => TokenConfig) internal tokenConfig;

    /**
     * @dev Initializes the contract with required parameters
     * @param _alephTokenAddress Address of the ALEPH token contract
     * @param _distributionRecipientAddress Address to receive distribution portion
     * @param _developersRecipientAddress Address to receive developers portion
     * @param _burnPercentage Percentage to burn (0-100)
     * @param _developersPercentage Percentage for developers (0-100)
     * @param _uniswapRouterAddress Universal Router contract address
     * @param _permit2Address Permit2 contract address
     */
    function initialize(
        address _alephTokenAddress,
        address _distributionRecipientAddress,
        address _developersRecipientAddress,
        uint8 _burnPercentage,
        uint8 _developersPercentage,
        address _uniswapRouterAddress,
        address _permit2Address
    ) public initializer {
        validateNonZeroAddress(_alephTokenAddress, "Invalid token address");
        validateNonZeroAddress(_distributionRecipientAddress, "Invalid distribution recipient address");
        validateNonZeroAddress(_developersRecipientAddress, "Invalid developers recipient address");
        validatePercentages(_burnPercentage, _developersPercentage);

        __Ownable_init(msg.sender);
        __Ownable2Step_init();
        __AccessControl_init();

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
        wethAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    }

    /**
     * @dev Processes token payments by swapping to ALEPH and distributing according to percentages
     * @param _token Token address to process (address(0) for ETH)
     * @param _amountIn Amount to process (0 for all available balance)
     * @param _amountOutMinimum Minimum ALEPH output expected from swap
     * @param _ttl Time to live for the transaction in seconds
     */
    function process(address _token, uint128 _amountIn, uint128 _amountOutMinimum, uint48 _ttl)
        external
        onlyRole(adminRole)
    {
        require(
            _token == address(aleph) || aleph.balanceOf(address(this)) == 0,
            "Pending ALEPH balance must be processed before"
        );

        uint128 amountIn = getAmountIn(_token, _amountIn);

        // Calculate portions from initial amount: 5% developers, 5% burn, 90% distribution
        uint8 cachedDevelopersPercentage = developersPercentage;
        uint8 cachedBurnPercentage = burnPercentage;
        (uint256 developersAmount, uint256 burnAmount, uint256 distributionAmount) =
            calculateProportions(uint256(amountIn), cachedDevelopersPercentage, cachedBurnPercentage);

        if (isStableToken[_token] && _token != address(aleph)) {
            // For stable tokens: send developers portion directly, swap the rest
            transferTokenOrEth(_token, developersRecipient, developersAmount, "Transfer to developers recipient failed");

            // Swap burn + distribution portions to ALEPH
            uint256 swapAmount = burnAmount + distributionAmount;
            uint256 alephReceived = swapToken(_token, uint128(swapAmount), _amountOutMinimum, _ttl);

            // Calculate proportional ALEPH amounts based on original percentages
            uint256 alephBurnAmount = swapAmount > 0 ? (alephReceived * burnAmount) / swapAmount : 0;
            uint256 alephDistributionAmount = alephReceived - alephBurnAmount;

            require(aleph.transfer(address(0), alephBurnAmount), "Burn transfer failed");

            require(
                aleph.transfer(distributionRecipient, alephDistributionAmount),
                "Transfer to distribution recipient failed"
            );

            emit TokenPaymentsProcessed(
                _token, msg.sender, amountIn, alephBurnAmount, alephDistributionAmount, developersAmount
            );
        } else {
            // For non-stable tokens or ALEPH: swap entire amount, then distribute proportionally
            uint256 alephReceived =
                _token != address(aleph) ? swapToken(_token, amountIn, _amountOutMinimum, _ttl) : amountIn;

            // Calculate ALEPH amounts based on original input percentages
            (uint256 alephDevelopersAmount, uint256 alephBurnAmount, uint256 alephDistributionAmount) =
                calculateProportions(alephReceived, cachedDevelopersPercentage, cachedBurnPercentage);

            require(
                aleph.transfer(developersRecipient, alephDevelopersAmount), "Transfer to developers recipient failed"
            );

            require(aleph.transfer(address(0), alephBurnAmount), "Burn transfer failed");

            require(
                aleph.transfer(distributionRecipient, alephDistributionAmount),
                "Transfer to distribution recipient failed"
            );

            emit TokenPaymentsProcessed(
                _token, msg.sender, amountIn, alephBurnAmount, alephDistributionAmount, alephDevelopersAmount
            );
        }
    }

    /**
     * @dev Withdraws tokens that are not configured for automatic processing
     * @param _token Token address to withdraw (address(0) for ETH)
     * @param _to Recipient address
     * @param _amount Amount to withdraw (0 for all available balance)
     */
    function withdraw(address _token, address payable _to, uint128 _amount) external onlyRole(adminRole) {
        require(
            _token != address(aleph) && tokenConfig[_token].version == 0,
            "Cannot withdraw a token configured for automatic distribution"
        );

        validateNonZeroAddress(_to, "Invalid recipient address");

        uint256 amount = getAmountIn(_token, _amount);

        transferTokenOrEth(_token, _to, amount, "Transfer failed");
    }

    /**
     * @dev Gets the actual amount to process, using full balance if _amountIn is 0
     * @param _token Token address to check balance for
     * @param _amountIn Requested amount (0 for full balance)
     * @return amountIn Actual amount to process
     */
    function getAmountIn(address _token, uint128 _amountIn) internal view returns (uint128 amountIn) {
        uint256 balance = _token != address(0) ? IERC20(_token).balanceOf(address(this)) : address(this).balance;

        amountIn = _amountIn != 0 ? _amountIn : uint128(Math.min(balance, type(uint128).max));

        // Check balance (native ETH if _token == 0x0 or ERC20 otherwise)
        require(balance >= amountIn, "Insufficient balance");

        return amountIn;
    }

    /**
     * @dev Safely transfers tokens or ETH to a recipient
     * @param _token Token address (address(0) for ETH)
     * @param _recipient Address to receive the transfer
     * @param _amount Amount to transfer
     * @param _errorMessage Error message to use if transfer fails
     */
    function transferTokenOrEth(address _token, address _recipient, uint256 _amount, string memory _errorMessage)
        internal
    {
        // Transfer native ETH or ERC20 tokens
        // https://diligence.consensys.io/blog/2019/09/stop-using-soliditys-transfer-now/
        if (_token != address(0)) {
            require(IERC20(_token).transfer(_recipient, _amount), _errorMessage);
        } else {
            (bool success,) = _recipient.call{value: _amount}("");
            require(success, _errorMessage);
        }
    }

    /**
     * @dev Validates percentage values and their sum
     * @param _percentage1 First percentage to validate
     * @param _percentage2 Second percentage to validate
     */
    function validatePercentages(uint8 _percentage1, uint8 _percentage2) internal pure {
        require(_percentage1 < 101, "Invalid burn percentage");
        require(_percentage2 < 101, "Invalid developers percentage");
        require(_percentage1 + _percentage2 <= 100, "Total percentages exceed 100%");
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
    function calculateProportions(uint256 _totalAmount, uint8 _developersPercentage, uint8 _burnPercentage)
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
        validatePercentages(_newBurnPercentage, developersPercentage);
        burnPercentage = _newBurnPercentage;
        emit BurnPercentageUpdated(_newBurnPercentage);
    }

    /**
     * @dev Sets the developers percentage for token processing
     * @param _newDevelopersPercentage New developers percentage (0-100)
     */
    function setDevelopersPercentage(uint8 _newDevelopersPercentage) external onlyOwner {
        validatePercentages(burnPercentage, _newDevelopersPercentage);
        developersPercentage = _newDevelopersPercentage;
        emit DevelopersPercentageUpdated(_newDevelopersPercentage);
    }

    /**
     * @dev Validates that an address is not zero
     * @param _address Address to validate
     * @param _errorMessage Error message to use if validation fails
     */
    function validateNonZeroAddress(address _address, string memory _errorMessage) internal pure {
        require(_address != address(0), _errorMessage);
    }

    /**
     * @dev Sets the distribution recipient address
     * @param _newDistributionRecipient New distribution recipient address
     */
    function setDistributionRecipient(address _newDistributionRecipient) external onlyOwner {
        validateNonZeroAddress(_newDistributionRecipient, "Invalid distribution recipient address");
        distributionRecipient = _newDistributionRecipient;
        emit DistributionRecipientUpdated(_newDistributionRecipient);
    }

    /**
     * @dev Sets the developers recipient address
     * @param _newDevelopersRecipient New developers recipient address
     */
    function setDevelopersRecipient(address _newDevelopersRecipient) external onlyOwner {
        validateNonZeroAddress(_newDevelopersRecipient, "Invalid developers recipient address");
        developersRecipient = _newDevelopersRecipient;
        emit DevelopersRecipientUpdated(_newDevelopersRecipient);
    }

    /**
     * @dev Marks a token as stable or non-stable for processing logic
     * @param _token Token address to configure
     * @param _isStable True if token is stable (developers portion not swapped)
     */
    function setStableToken(address _token, bool _isStable) external onlyOwner {
        isStableToken[_token] = _isStable;
    }

    /**
     * @dev Grants admin role to a new address
     * @param _newAdmin Address to grant admin role
     */
    function addAdmin(address _newAdmin) external onlyOwner {
        _grantRole(adminRole, _newAdmin);
    }

    /**
     * @dev Revokes admin role from an address
     * @param _admin Address to revoke admin role
     */
    function removeAdmin(address _admin) external onlyOwner {
        _revokeRole(adminRole, _admin);
    }

    /**
     * @dev Returns the token configuration for swapping
     * @param _address Token address to query
     * @return TokenConfig struct with swap configuration
     */
    function getTokenConfig(address _address) external view returns (TokenConfig memory) {
        return tokenConfig[_address];
    }

    /**
     * @dev Configures a token for Uniswap V2 swapping
     * @param _address Token address to configure
     * @param _v2Path Array of addresses defining the swap path
     */
    function setTokenConfigV2(address _address, address[] calldata _v2Path) external onlyOwner {
        require(_v2Path.length >= 2, "Invalid V2 path");

        // Replace address(0) with WETH in the path during configuration
        address[] memory processedPath = replaceAddressZeroWithWethV2(_v2Path);

        tokenConfig[_address] =
            TokenConfig({version: 2, token: _address, v4Path: new PathKey[](0), v3Path: "", v2Path: processedPath});

        emit TokenConfigUpdated(_address, 2);
    }

    /**
     * @dev Configures a token for Uniswap V3 swapping
     * @param _address Token address to configure
     * @param _v3Path Encoded path with fee tiers for V3 swapping
     */
    function setTokenConfigV3(address _address, bytes calldata _v3Path) external onlyOwner {
        require(_v3Path.length >= 43, "V3 path too short");

        // Replace address(0) with WETH in the path during configuration
        bytes memory processedPath = replaceAddressZeroWithWeth(_v3Path);

        tokenConfig[_address] = TokenConfig({
            version: 3,
            token: _address,
            v4Path: new PathKey[](0),
            v3Path: processedPath,
            v2Path: new address[](0)
        });

        emit TokenConfigUpdated(_address, 3);
    }

    /**
     * @dev Configures a token for Uniswap V4 swapping
     * @param _address Token address to configure
     * @param _v4Path Array of PathKey structs defining the V4 swap path
     */
    function setTokenConfigV4(address _address, PathKey[] calldata _v4Path) external onlyOwner {
        require(_v4Path.length > 0, "Empty V4 path");

        tokenConfig[_address] =
            TokenConfig({version: 4, token: _address, v4Path: _v4Path, v3Path: "", v2Path: new address[](0)});

        emit TokenConfigUpdated(_address, 4);
    }

    /**
     * @dev Removes token configuration to disable automatic processing
     * @param _address Token address to remove configuration for
     */
    function removeTokenConfig(address _address) external onlyOwner {
        TokenConfig memory config = tokenConfig[_address];
        require(config.version > 0, "Invalid token config");

        delete tokenConfig[_address];
        emit TokenConfigRemoved(_address, config.version);
    }

    /**
     * @dev Helper function to replace address(0) with WETH address in V2 path array
     */
    function replaceAddressZeroWithWethV2(address[] memory path) internal view returns (address[] memory) {
        address[] memory newPath = new address[](path.length);
        for (uint256 i = 0; i < path.length; i++) {
            newPath[i] = path[i] == address(0) ? wethAddress : path[i];
        }
        return newPath;
    }

    /**
     * @dev Helper function to replace address(0) with WETH address in V3 encoded path
     */
    function replaceAddressZeroWithWeth(bytes memory path) internal view returns (bytes memory) {
        if (path.length < 20) {
            return path;
        }

        // Check if the first token is address(0)
        address firstToken;
        assembly {
            // Load first 20 bytes starting at offset 32 (after length)
            firstToken := shr(96, mload(add(path, 32)))
        }

        if (firstToken != address(0)) {
            return path;
        }

        // Create new path with WETH replacing address(0)
        bytes memory newPath = new bytes(path.length);

        // Copy WETH address to first 20 bytes
        assembly {
            // Store WETH address in the first 20 bytes (shifted left to align)
            mstore(add(newPath, 32), shl(96, sload(wethAddress.slot)))
        }

        // Copy the rest of the path (starting from byte 20)
        for (uint256 i = 20; i < path.length; i++) {
            newPath[i] = path[i];
        }

        return newPath;
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
    function approve(address _token, uint160 _amount, uint48 _ttl) internal {
        uint48 expiration = uint48(block.timestamp) + _ttl;
        // Only approve if current allowance is insufficient
        if (IERC20(_token).allowance(address(this), address(permit2)) < _amount) {
            IERC20(_token).approve(address(permit2), type(uint256).max);
        }
        permit2.approve(_token, address(router), _amount, expiration);
    }

    // https://docs.uniswap.org/contracts/v4/quickstart/swap
    /**
     * @dev Routes token swapping to appropriate Uniswap version based on configuration
     * @param _token Token address to swap from
     * @param _amountIn Amount of input tokens
     * @param _amountOutMinimum Minimum output amount expected
     * @param _ttl Time to live for the swap
     * @return amountOut Amount of ALEPH tokens received
     */
    function swapToken(address _token, uint128 _amountIn, uint128 _amountOutMinimum, uint48 _ttl)
        internal
        returns (uint256 amountOut)
    {
        TokenConfig memory config = tokenConfig[_token];
        require(config.version >= 2 && config.version <= 4, "Invalid uniswap version");

        if (config.version == 2) {
            return swapV2(_token, _amountIn, _amountOutMinimum, _ttl);
        } else if (config.version == 3) {
            return swapV3(_token, _amountIn, _amountOutMinimum, _ttl);
        } else {
            return swapV4(_token, _amountIn, _amountOutMinimum, _ttl);
        }
    }

    /**
     * @dev Executes Uniswap V2 swap through Universal Router
     * @param _token Token address to swap from
     * @param _amountIn Amount of input tokens
     * @param _amountOutMinimum Minimum output amount expected
     * @param _ttl Time to live for the swap
     * @return amountOut Amount of ALEPH tokens received
     */
    function swapV2(address _token, uint128 _amountIn, uint128 _amountOutMinimum, uint48 _ttl)
        internal
        returns (uint256 amountOut)
    {
        TokenConfig memory config = tokenConfig[_token];
        require(config.version == 2, "Invalid uniswap version");
        require(config.v2Path.length >= 2, "Invalid V2 path");

        uint256 balanceBefore = aleph.balanceOf(address(this));

        bytes memory commands;
        bytes[] memory inputs;

        if (_token == address(0)) {
            // For ETH swaps, first wrap ETH to WETH, then swap
            // Path already has address(0) replaced with WETH during configuration
            address[] memory ethPath = config.v2Path;

            commands = abi.encodePacked(uint8(Commands.WRAP_ETH), uint8(Commands.V2_SWAP_EXACT_IN));
            inputs = new bytes[](2);

            // First wrap ETH to WETH in the router
            inputs[0] = abi.encode(
                address(router), // recipient (router gets the WETH)
                uint256(_amountIn) // amount to wrap
            );

            // Then swap WETH for target token
            inputs[1] = abi.encode(
                address(this), // recipient
                uint256(_amountIn), // amountIn
                uint256(_amountOutMinimum), // amountOutMinimum
                ethPath, // path starting with WETH
                false // payerIsUser - false because router has WETH
            );
        } else {
            // For ERC20 swaps, first transfer then swap
            commands = abi.encodePacked(uint8(Commands.PERMIT2_TRANSFER_FROM), uint8(Commands.V2_SWAP_EXACT_IN));
            inputs = new bytes[](2);

            // Transfer tokens to router first
            inputs[0] = abi.encode(
                _token, // token
                address(router), // recipient (router)
                uint160(_amountIn) // amount
            );

            // Then swap
            inputs[1] = abi.encode(
                address(this), // recipient
                uint256(_amountIn), // amountIn
                uint256(_amountOutMinimum), // amountOutMinimum
                config.v2Path, // address array path
                false // payerIsUser - false means router pays
            );
        }

        uint256 deadline = block.timestamp + _ttl;

        if (_token == address(0)) {
            // For ETH swaps, send the ETH value with the call
            router.execute{value: _amountIn}(commands, inputs, deadline);
        } else {
            // For ERC20 swaps, approve token transfer first
            approve(_token, _amountIn, _ttl);
            router.execute(commands, inputs, deadline);
        }

        // Calculate the output amount received
        uint256 balanceAfter = aleph.balanceOf(address(this));
        amountOut = balanceAfter - balanceBefore;
        require(amountOut >= _amountOutMinimum, "Insufficient output amount");
        return amountOut;
    }

    /**
     * @dev Executes Uniswap V3 swap through Universal Router
     * @param _token Token address to swap from
     * @param _amountIn Amount of input tokens
     * @param _amountOutMinimum Minimum output amount expected
     * @param _ttl Time to live for the swap
     * @return amountOut Amount of ALEPH tokens received
     */
    function swapV3(address _token, uint128 _amountIn, uint128 _amountOutMinimum, uint48 _ttl)
        internal
        returns (uint256 amountOut)
    {
        TokenConfig memory config = tokenConfig[_token];
        require(config.version == 3, "Invalid uniswap version");
        require(config.v3Path.length >= 43, "V3 path too short");

        uint256 balanceBefore = aleph.balanceOf(address(this));

        bytes memory commands;
        bytes[] memory inputs;

        if (_token == address(0)) {
            // For ETH swaps, first wrap ETH to WETH, then swap
            // Path already has address(0) replaced with WETH during configuration
            bytes memory ethV3Path = config.v3Path;

            commands = abi.encodePacked(uint8(Commands.WRAP_ETH), uint8(Commands.V3_SWAP_EXACT_IN));
            inputs = new bytes[](2);

            // First wrap ETH to WETH in the router
            inputs[0] = abi.encode(
                address(router), // recipient (router gets the WETH)
                uint256(_amountIn) // amount to wrap
            );

            // Then swap WETH for target token
            inputs[1] = abi.encode(
                address(this), // recipient
                uint256(_amountIn), // amountIn
                uint256(_amountOutMinimum), // amountOutMinimum
                ethV3Path, // encoded path starting with WETH
                false // payerIsUser - false because router has WETH
            );
        } else {
            // For ERC20 swaps, first transfer then swap
            commands = abi.encodePacked(uint8(Commands.PERMIT2_TRANSFER_FROM), uint8(Commands.V3_SWAP_EXACT_IN));
            inputs = new bytes[](2);

            // Transfer tokens to router first
            inputs[0] = abi.encode(
                _token, // token
                address(router), // recipient (router)
                uint160(_amountIn) // amount
            );

            // Then swap
            inputs[1] = abi.encode(
                address(this), // recipient
                uint256(_amountIn), // amountIn
                uint256(_amountOutMinimum), // amountOutMinimum
                config.v3Path, // encoded path
                false // payerIsUser - false means router pays
            );
        }

        uint256 deadline = block.timestamp + _ttl;

        if (_token == address(0)) {
            // For ETH swaps, send the ETH value with the call
            router.execute{value: _amountIn}(commands, inputs, deadline);
        } else {
            // For ERC20 swaps, approve token transfer first
            approve(_token, _amountIn, _ttl);
            router.execute(commands, inputs, deadline);
        }

        // Calculate the output amount received
        uint256 balanceAfter = aleph.balanceOf(address(this));
        amountOut = balanceAfter - balanceBefore;
        require(amountOut >= _amountOutMinimum, "Insufficient output amount");
        return amountOut;
    }

    /**
     * @dev Executes Uniswap V4 swap through Universal Router
     * @param _token Token address to swap from
     * @param _amountIn Amount of input tokens
     * @param _amountOutMinimum Minimum output amount expected
     * @param _ttl Time to live for the swap
     * @return amountOut Amount of ALEPH tokens received
     */
    function swapV4(address _token, uint128 _amountIn, uint128 _amountOutMinimum, uint48 _ttl)
        internal
        returns (uint256 amountOut)
    {
        TokenConfig memory config = tokenConfig[_token];
        require(config.version == 4, "Invalid uniswap version");

        Currency currencyIn = Currency.wrap(_token);
        PathKey[] memory path = config.v4Path;

        // Encode the Universal Router command
        // https://github.com/Uniswap/universal-router/blob/main/contracts/libraries/Commands.sol#L35
        // uint256 constant V4_SWAP = 0x10;
        // bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes memory commands = abi.encodePacked(uint8(0x10));
        bytes[] memory inputs = new bytes[](1);

        // Encode V4Router actions
        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        // Prepare parameters for each action
        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputParams({
                currencyIn: currencyIn,
                path: path,
                amountIn: _amountIn,
                amountOutMinimum: _amountOutMinimum
            })
        );

        Currency currency0 = currencyIn;
        Currency currency1 = path[path.length - 1].intermediateCurrency;

        params[1] = abi.encode(currency0, _amountIn);
        params[2] = abi.encode(currency1, _amountOutMinimum);

        // Combine actions and params into inputs
        inputs[0] = abi.encode(actions, params);

        // Execute the swap
        uint256 deadline = block.timestamp + _ttl;
        // router.execute(commands, inputs, deadline);

        if (_token == address(0)) {
            // For ETH swaps, send the ETH value with the call
            router.execute{value: _amountIn}(commands, inputs, deadline);
        } else {
            // For ERC20 swaps, no value needed but approve token transferFrom
            approve(_token, _amountIn, _ttl);
            router.execute(commands, inputs, deadline);
        }

        // Verify and return the output amount
        amountOut = currency1.balanceOf(address(this));
        require(amountOut >= _amountOutMinimum, "Insufficient output amount");
        return amountOut;
    }
}
