// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import {UniversalRouter} from "@uniswap/universal-router/contracts/UniversalRouter.sol";
import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PathKey} from "@uniswap/v4-periphery/src/libraries/PathKey.sol";

import {UniversalRouter} from "../lib/universal-router/contracts/UniversalRouter.sol";
import {Commands} from "../lib/universal-router/contracts/libraries/Commands.sol";
import {IV4Router} from "../lib/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "../lib/v4-periphery/src/libraries/Actions.sol";
import {IPermit2} from "../lib/permit2/src/interfaces/IPermit2.sol";
import {Currency} from "../lib/v4-core/src/types/Currency.sol";
import {PathKey} from "../lib/v4-periphery/src/libraries/PathKey.sol";

contract AlephPaymentProcessor is
    Initializable,
    Ownable2StepUpgradeable,
    AccessControlUpgradeable
{
    using SafeERC20 for IERC20;

    struct TokenConfig {
        address token;
        uint8 version; // 2, 3, 4
        PathKey[] path;
    }

    event TokenPaymentsProcessed(
        address indexed _token,
        address indexed sender,
        uint256 amount,
        uint256 amountBurned,
        uint256 amountSent
    );

    // Events for parameter updates
    event TokenConfigUpdated(address indexed token, uint8 version);
    event TokenConfigRemoved(address indexed token, uint8 version);
    event RecipientUpdated(address indexed recipient);
    event BurnPercentageUpdated(uint8 percentage);

    // Payment settings
    address public recipient; // Address that receives the non-burned portion of payments
    uint8 public burnPercentage; // Percentage of tokens to burn (0-100)

    // @notice Role allowed to process balances
    bytes32 public ADMIN_ROLE;

    // Token contracts
    IERC20 internal ALEPH;

    // Uniswap v4 utils
    UniversalRouter internal router;
    IPermit2 internal permit2;

    // Token configuration for swapping in uniswap
    mapping(address => TokenConfig) internal tokenConfig;

    function initialize(
        address _alephTokenAddress,
        address _recipientAddress,
        uint8 _burnPercentage,
        address _uniswapRouterAddress,
        address _permit2Address
    ) public initializer {
        require(_alephTokenAddress != address(0), "Invalid token address");
        require(_recipientAddress != address(0), "Invalid recipient address");
        require(_burnPercentage < 101, "Invalid burn percentage");

        __Ownable_init(msg.sender);
        __Ownable2Step_init();
        __AccessControl_init();

        ADMIN_ROLE = keccak256("ADMIN_ROLE");

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        ALEPH = IERC20(_alephTokenAddress);

        recipient = _recipientAddress;
        burnPercentage = _burnPercentage;

        router = UniversalRouter(payable(_uniswapRouterAddress));
        permit2 = IPermit2(_permit2Address);
    }

    function process(
        address _token,
        uint128 _amountIn,
        uint128 _amountOutMinimum,
        uint48 _ttl
    ) external onlyRole(ADMIN_ROLE) {
        require(
            _token == address(ALEPH) || ALEPH.balanceOf(address(this)) == 0,
            "Pending ALEPH balance must be processed before"
        );

        uint128 amountIn = getAmountIn(_token, _amountIn);

        uint256 alephReceived = _token != address(ALEPH)
            ? swapV4(_token, amountIn, _amountOutMinimum, _ttl)
            : amountIn;

        // Calculate burn and send amounts based on the burn percentage
        uint256 amountToBurn = (alephReceived * burnPercentage) / 100;
        uint256 amountToSend = alephReceived - amountToBurn;

        // Transfer tokens to burn address (0x0) as burn functionality
        require(
            ALEPH.transfer(address(0), amountToBurn),
            "Burn transfer failed"
        );

        require(
            ALEPH.transfer(recipient, amountToSend),
            "Transfer to recipient failed"
        );

        emit TokenPaymentsProcessed(
            _token,
            msg.sender,
            amountIn,
            amountToBurn,
            amountToSend
        );
    }

    function withdraw(
        address _token,
        address payable _to,
        uint128 _amount
    ) external onlyRole(ADMIN_ROLE) {
        require(
            _token != address(ALEPH) && tokenConfig[_token].version == 0,
            "Cannot withdraw a token configured for automatic distribution"
        );

        require(_to != address(0), "Invalid recipient address");

        uint256 amount = getAmountIn(_token, _amount);

        // Transfer native ETH or ERC20 tokens
        // https://diligence.consensys.io/blog/2019/09/stop-using-soliditys-transfer-now/
        // _to.send(_amount) => (bool success, ) = _to.call{value: _amount}("");

        bool success;

        if (_token != address(0)) {
            success = IERC20(_token).transfer(_to, amount);
        } else {
            (success, ) = _to.call{value: amount}("");
        }

        require(success, "Transfer failed");
    }

    function getAmountIn(
        address _token,
        uint128 _amountIn
    ) internal view returns (uint128 amountIn) {
        uint256 balance = _token != address(0)
            ? IERC20(_token).balanceOf(address(this))
            : address(this).balance;

        amountIn = _amountIn != 0
            ? _amountIn
            : uint128(Math.min(balance, type(uint128).max));

        // Check balance (native ETH if _token == 0x0 or ERC20 otherwise)
        require(balance >= amountIn, "Insufficient balance");

        return amountIn;
    }

    function setBurnPercentage(uint8 _newBurnPercentage) external onlyOwner {
        require(_newBurnPercentage < 101, "Invalid burn percentage");
        burnPercentage = _newBurnPercentage;
        emit BurnPercentageUpdated(_newBurnPercentage);
    }

    function setRecipient(address _newRecipient) external onlyOwner {
        require(_newRecipient != address(0), "Invalid recipient address");
        recipient = _newRecipient;
        emit RecipientUpdated(_newRecipient);
    }

    function addAdmin(address _newAdmin) external onlyOwner {
        _grantRole(ADMIN_ROLE, _newAdmin);
    }

    function removeAdmin(address _admin) external onlyOwner {
        _revokeRole(ADMIN_ROLE, _admin);
    }

    function getTokenConfig(
        address _address
    ) external view returns (TokenConfig memory) {
        return tokenConfig[_address];
    }

    function setTokenConfigV4(
        address _address,
        PathKey[] calldata _path
    ) external onlyOwner {
        tokenConfig[_address] = TokenConfig({
            token: _address,
            version: 4,
            path: _path
        });

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

    function approve(
        address _token,
        uint160 _amount,
        uint48 _ttl
    ) internal onlyRole(ADMIN_ROLE) {
        uint48 expiration = uint48(block.timestamp) + _ttl;
        IERC20(_token).approve(address(permit2), type(uint256).max);
        permit2.approve(_token, address(router), _amount, expiration);
    }

    // https://docs.uniswap.org/contracts/v4/quickstart/swap
    function swapV4(
        address _token,
        uint128 _amountIn,
        uint128 _amountOutMinimum,
        uint48 _ttl
    ) internal onlyRole(ADMIN_ROLE) returns (uint256 amountOut) {
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
        bytes memory actions = abi.encodePacked(
            uint8(Actions.SWAP_EXACT_IN),
            uint8(Actions.SETTLE_ALL),
            uint8(Actions.TAKE_ALL)
        );

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
