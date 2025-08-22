// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {UniversalRouter} from "@uniswap/universal-router/contracts/UniversalRouter.sol";
// import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PathKey} from "@uniswap/v4-periphery/src/libraries/PathKey.sol";

contract AlephPaymentProcessor is Initializable, Ownable2StepUpgradeable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    struct TokenConfig {
        uint8 version; // 2, 3, 4 - pack with address
        address token;
        PathKey[] path;
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

    // Uniswap v4 utils
    UniversalRouter internal router;
    IPermit2 internal permit2;

    // Token configuration for swapping in uniswap
    mapping(address => TokenConfig) internal tokenConfig;

    function initialize(
        address _alephTokenAddress,
        address _distributionRecipientAddress,
        address _developersRecipientAddress,
        uint8 _burnPercentage,
        uint8 _developersPercentage,
        address _uniswapRouterAddress,
        address _permit2Address
    ) public initializer {
        require(_alephTokenAddress != address(0), "Invalid token address");
        require(_distributionRecipientAddress != address(0), "Invalid distribution recipient address");
        require(_developersRecipientAddress != address(0), "Invalid developers recipient address");
        require(_burnPercentage < 101, "Invalid burn percentage");
        require(_developersPercentage < 101, "Invalid developers percentage");
        require(_burnPercentage + _developersPercentage <= 100, "Total percentages exceed 100%");

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
    }

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
        uint256 developersAmount = (uint256(amountIn) * cachedDevelopersPercentage) / 100;
        uint256 burnAmount = (uint256(amountIn) * cachedBurnPercentage) / 100;
        uint256 distributionAmount = uint256(amountIn) - developersAmount - burnAmount;

        if (isStableToken[_token] && _token != address(aleph)) {
            // For stable tokens: send developers portion directly, swap the rest
            transferTokenOrEth(_token, developersRecipient, developersAmount, "Transfer to developers recipient failed");

            // Swap burn + distribution portions to ALEPH
            uint256 swapAmount = burnAmount + distributionAmount;
            uint256 alephReceived = swapV4(_token, uint128(swapAmount), _amountOutMinimum, _ttl);

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
                _token != address(aleph) ? swapV4(_token, amountIn, _amountOutMinimum, _ttl) : amountIn;

            // Calculate ALEPH amounts based on original input percentages
            uint256 alephDevelopersAmount = (alephReceived * cachedDevelopersPercentage) / 100;
            uint256 alephBurnAmount = (alephReceived * cachedBurnPercentage) / 100;
            uint256 alephDistributionAmount = alephReceived - alephDevelopersAmount - alephBurnAmount;

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

    function withdraw(address _token, address payable _to, uint128 _amount) external onlyRole(adminRole) {
        require(
            _token != address(aleph) && tokenConfig[_token].version == 0,
            "Cannot withdraw a token configured for automatic distribution"
        );

        require(_to != address(0), "Invalid recipient address");

        uint256 amount = getAmountIn(_token, _amount);

        transferTokenOrEth(_token, _to, amount, "Transfer failed");
    }

    function getAmountIn(address _token, uint128 _amountIn) internal view returns (uint128 amountIn) {
        uint256 balance = _token != address(0) ? IERC20(_token).balanceOf(address(this)) : address(this).balance;

        amountIn = _amountIn != 0 ? _amountIn : uint128(Math.min(balance, type(uint128).max));

        // Check balance (native ETH if _token == 0x0 or ERC20 otherwise)
        require(balance >= amountIn, "Insufficient balance");

        return amountIn;
    }

    function transferTokenOrEth(address _token, address _recipient, uint256 _amount, string memory _errorMessage)
        internal
        onlyRole(adminRole)
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

    function setBurnPercentage(uint8 _newBurnPercentage) external onlyOwner {
        require(_newBurnPercentage < 101, "Invalid burn percentage");
        require(_newBurnPercentage + developersPercentage <= 100, "Total percentages exceed 100%");
        burnPercentage = _newBurnPercentage;
        emit BurnPercentageUpdated(_newBurnPercentage);
    }

    function setDevelopersPercentage(uint8 _newDevelopersPercentage) external onlyOwner {
        require(_newDevelopersPercentage < 101, "Invalid developers percentage");
        require(burnPercentage + _newDevelopersPercentage <= 100, "Total percentages exceed 100%");
        developersPercentage = _newDevelopersPercentage;
        emit DevelopersPercentageUpdated(_newDevelopersPercentage);
    }

    function setDistributionRecipient(address _newDistributionRecipient) external onlyOwner {
        require(_newDistributionRecipient != address(0), "Invalid distribution recipient address");
        distributionRecipient = _newDistributionRecipient;
        emit DistributionRecipientUpdated(_newDistributionRecipient);
    }

    function setDevelopersRecipient(address _newDevelopersRecipient) external onlyOwner {
        require(_newDevelopersRecipient != address(0), "Invalid developers recipient address");
        developersRecipient = _newDevelopersRecipient;
        emit DevelopersRecipientUpdated(_newDevelopersRecipient);
    }

    function setStableToken(address _token, bool _isStable) external onlyOwner {
        isStableToken[_token] = _isStable;
    }

    function addAdmin(address _newAdmin) external onlyOwner {
        _grantRole(adminRole, _newAdmin);
    }

    function removeAdmin(address _admin) external onlyOwner {
        _revokeRole(adminRole, _admin);
    }

    function getTokenConfig(address _address) external view returns (TokenConfig memory) {
        return tokenConfig[_address];
    }

    function setTokenConfigV4(address _address, PathKey[] calldata _path) external onlyOwner {
        tokenConfig[_address] = TokenConfig({version: 4, token: _address, path: _path});

        emit TokenConfigUpdated(_address, 4);
    }

    function removeTokenConfig(address _address) external onlyOwner {
        TokenConfig memory config = tokenConfig[_address];
        require(config.version > 0, "Invalid token config");

        delete tokenConfig[_address];
        emit TokenConfigRemoved(_address, config.version);
    }

    /**
     * @dev Fallback function to receive ETH
     * This allows the contract to receive ETH payments directly
     */
    receive() external payable {}

    function approve(address _token, uint160 _amount, uint48 _ttl) internal onlyRole(adminRole) {
        uint48 expiration = uint48(block.timestamp) + _ttl;
        // Only approve if current allowance is insufficient
        if (IERC20(_token).allowance(address(this), address(permit2)) < _amount) {
            IERC20(_token).approve(address(permit2), type(uint256).max);
        }
        permit2.approve(_token, address(router), _amount, expiration);
    }

    // https://docs.uniswap.org/contracts/v4/quickstart/swap
    function swapV4(address _token, uint128 _amountIn, uint128 _amountOutMinimum, uint48 _ttl)
        internal
        onlyRole(adminRole)
        returns (uint256 amountOut)
    {
        TokenConfig memory config = tokenConfig[_token];
        require(config.version == 4, "Invalid uniswap version");

        Currency currencyIn = Currency.wrap(_token);
        PathKey[] memory path = config.path;

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
