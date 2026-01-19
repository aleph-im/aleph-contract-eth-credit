// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {UniversalRouter} from "@uniswap/universal-router/contracts/UniversalRouter.sol";
import {Commands} from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import {IV4Router} from "@uniswap/v4-periphery/src/interfaces/IV4Router.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IPermit2} from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PathKey} from "@uniswap/v4-periphery/src/libraries/PathKey.sol";

struct SwapConfig {
    uint8 v;
    address t;
    address[] v2;
    bytes v3;
    PathKey[] v4;
}

error InvalidVersion();
error InsufficientOutput();
error InvalidAddress();
error InvalidPath();
error DuplicateTokens();

library AlephSwapLibrary {
    using SafeERC20 for IERC20;
    using SafeCast for uint256;

    function swapV2(
        uint128 _amountIn,
        uint128 _amountOutMinimum,
        uint48 _ttl,
        SwapConfig memory config,
        UniversalRouter router,
        IPermit2 permit2,
        IERC20 aleph
    ) internal returns (uint256 amountOut) {
        if (config.v != 2 || config.v2.length < 2) revert InvalidVersion();

        // Use balance delta instead of return values for robustness:
        // - Captures actual tokens received regardless of execution path
        // - Handles fee-on-transfer tokens correctly
        // - Independent of UniversalRouter return value parsing
        uint256 balanceBefore = aleph.balanceOf(address(this));

        bytes memory commands;
        bytes[] memory inputs;

        if (config.t == address(0)) {
            address[] memory ethPath = config.v2;
            commands = abi.encodePacked(uint8(Commands.WRAP_ETH), uint8(Commands.V2_SWAP_EXACT_IN));
            inputs = new bytes[](2);
            inputs[0] = abi.encode(address(router), uint256(_amountIn));
            inputs[1] = abi.encode(address(this), uint256(_amountIn), uint256(_amountOutMinimum), ethPath, false);
        } else {
            commands = abi.encodePacked(uint8(Commands.PERMIT2_TRANSFER_FROM), uint8(Commands.V2_SWAP_EXACT_IN));
            inputs = new bytes[](2);
            inputs[0] = abi.encode(config.t, address(router), uint256(_amountIn).toUint160());
            inputs[1] = abi.encode(address(this), uint256(_amountIn), uint256(_amountOutMinimum), config.v2, false);
        }

        uint256 deadline = block.timestamp + _ttl;

        if (config.t == address(0)) {
            router.execute{value: _amountIn}(commands, inputs, deadline);
        } else {
            _approve(config.t, _amountIn, _ttl, permit2, router);
            router.execute(commands, inputs, deadline);
        }

        uint256 balanceAfter = aleph.balanceOf(address(this));
        amountOut = balanceAfter - balanceBefore;
        if (amountOut < _amountOutMinimum) revert InsufficientOutput();
        return amountOut;
    }

    function swapV3(
        uint128 _amountIn,
        uint128 _amountOutMinimum,
        uint48 _ttl,
        SwapConfig memory config,
        UniversalRouter router,
        IPermit2 permit2,
        IERC20 aleph
    ) internal returns (uint256 amountOut) {
        if (config.v != 3 || config.v3.length < 43) revert InvalidVersion();

        // Use balance delta instead of return values for robustness:
        // - Captures actual tokens received regardless of execution path
        // - Handles fee-on-transfer tokens correctly
        // - Independent of UniversalRouter return value parsing
        uint256 balanceBefore = aleph.balanceOf(address(this));

        bytes memory commands;
        bytes[] memory inputs;

        if (config.t == address(0)) {
            bytes memory ethV3Path = config.v3;
            commands = abi.encodePacked(uint8(Commands.WRAP_ETH), uint8(Commands.V3_SWAP_EXACT_IN));
            inputs = new bytes[](2);
            inputs[0] = abi.encode(address(router), uint256(_amountIn));
            inputs[1] = abi.encode(address(this), uint256(_amountIn), uint256(_amountOutMinimum), ethV3Path, false);
        } else {
            commands = abi.encodePacked(uint8(Commands.PERMIT2_TRANSFER_FROM), uint8(Commands.V3_SWAP_EXACT_IN));
            inputs = new bytes[](2);
            inputs[0] = abi.encode(config.t, address(router), uint256(_amountIn).toUint160());
            inputs[1] = abi.encode(address(this), uint256(_amountIn), uint256(_amountOutMinimum), config.v3, false);
        }

        uint256 deadline = block.timestamp + _ttl;

        if (config.t == address(0)) {
            router.execute{value: _amountIn}(commands, inputs, deadline);
        } else {
            _approve(config.t, _amountIn, _ttl, permit2, router);
            router.execute(commands, inputs, deadline);
        }

        uint256 balanceAfter = aleph.balanceOf(address(this));
        amountOut = balanceAfter - balanceBefore;
        if (amountOut < _amountOutMinimum) revert InsufficientOutput();
        return amountOut;
    }

    function swapV4(
        uint128 _amountIn,
        uint128 _amountOutMinimum,
        uint48 _ttl,
        SwapConfig memory config,
        UniversalRouter router,
        IPermit2 permit2,
        IERC20 aleph
    ) internal returns (uint256 amountOut) {
        if (config.v != 4) revert InvalidVersion();

        Currency currencyIn = Currency.wrap(config.t);
        PathKey[] memory path = config.v4;

        // Use balance delta instead of return values for robustness:
        // - Captures actual tokens received regardless of execution path
        // - Handles fee-on-transfer tokens correctly
        // - Independent of UniversalRouter return value parsing
        uint256 balanceBefore = aleph.balanceOf(address(this));

        bytes memory commands = abi.encodePacked(uint8(0x10));
        bytes[] memory inputs = new bytes[](1);

        bytes memory actions =
            abi.encodePacked(uint8(Actions.SWAP_EXACT_IN), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));

        bytes[] memory params = new bytes[](3);
        params[0] = abi.encode(
            IV4Router.ExactInputParams({
                currencyIn: currencyIn, path: path, amountIn: _amountIn, amountOutMinimum: _amountOutMinimum
            })
        );

        Currency currency0 = currencyIn;
        Currency currency1 = path[path.length - 1].intermediateCurrency;

        params[1] = abi.encode(currency0, _amountIn);
        params[2] = abi.encode(currency1, _amountOutMinimum);

        inputs[0] = abi.encode(actions, params);

        uint256 deadline = block.timestamp + _ttl;

        if (config.t == address(0)) {
            router.execute{value: _amountIn}(commands, inputs, deadline);
        } else {
            _approve(config.t, _amountIn, _ttl, permit2, router);
            router.execute(commands, inputs, deadline);
        }

        uint256 balanceAfter = aleph.balanceOf(address(this));
        amountOut = balanceAfter - balanceBefore;
        if (amountOut < _amountOutMinimum) revert InsufficientOutput();
        return amountOut;
    }

    /**
     * @dev Validates and creates V2 swap configuration
     * @param _address Token address to configure
     * @param _v2Path Array of addresses defining the swap path
     * @param _alephAddress ALEPH token address
     * @param _wethAddress WETH token address
     * @return processedPath The path with address(0) replaced by WETH
     */
    function validateAndCreateV2Config(
        address _address,
        address[] calldata _v2Path,
        address _alephAddress,
        address _wethAddress
    ) internal pure returns (address[] memory processedPath) {
        if (_address == _alephAddress) revert InvalidAddress();
        if (_v2Path.length < 2 || _v2Path.length > 5) revert InvalidPath();
        if (_v2Path[_v2Path.length - 1] != _alephAddress) revert InvalidPath();
        if (_v2Path[0] != _address && _v2Path[0] != address(0)) {
            revert InvalidPath();
        }

        // Check for any duplicate tokens in the path (not just adjacent)
        for (uint256 i = 1; i < _v2Path.length; i++) {
            for (uint256 j = 0; j < i; j++) {
                if (_v2Path[i] == _v2Path[j]) revert DuplicateTokens();
            }
        }

        // Replace address(0) with WETH in the path during configuration
        processedPath = new address[](_v2Path.length);
        for (uint256 i = 0; i < _v2Path.length; i++) {
            processedPath[i] = _v2Path[i] == address(0) ? _wethAddress : _v2Path[i];
        }
        return processedPath;
    }

    /**
     * @dev Validates and creates V3 swap configuration
     * @param _address Token address to configure
     * @param _v3Path Encoded path with fee tiers for V3 swapping
     * @param _alephAddress ALEPH token address
     * @param _wethAddress WETH token address
     * @return processedPath The path with address(0) replaced by WETH
     */
    function validateAndCreateV3Config(
        address _address,
        bytes calldata _v3Path,
        address _alephAddress,
        address _wethAddress
    ) internal pure returns (bytes memory processedPath) {
        if (_address == _alephAddress) revert InvalidAddress();
        if (_v3Path.length < 43 || _v3Path.length > 200) revert InvalidPath();
        if (_v3Path.length % 23 != 20) revert InvalidPath();

        // Verify path starts with correct token
        address firstToken;
        assembly {
            firstToken := shr(96, calldataload(_v3Path.offset))
        }
        if (firstToken != _address && firstToken != address(0)) revert InvalidPath();

        // Verify path ends with ALEPH token
        address lastToken;
        assembly {
            let pathEnd := add(_v3Path.offset, sub(_v3Path.length, 20))
            lastToken := shr(96, calldataload(pathEnd))
        }
        if (lastToken != _alephAddress) revert InvalidPath();

        // Check for duplicate tokens in path
        _checkV3PathForDuplicates(_v3Path);

        // Replace address(0) with WETH in the path during configuration
        processedPath = _replaceAddressZeroWithWethV3(_v3Path, _wethAddress);
        return processedPath;
    }

    /**
     * @dev Validates V4 swap configuration
     * @param _address Token address to configure
     * @param _v4Path Array of PathKey structs defining the V4 swap path
     * @param _alephAddress ALEPH token address
     */
    function validateV4Config(address _address, PathKey[] calldata _v4Path, address _alephAddress) internal pure {
        if (_address == _alephAddress) revert InvalidAddress();
        if (_v4Path.length < 1 || _v4Path.length > 5) revert InvalidPath();

        // For V4, input token is implicit (not in PathKey array)
        // Validate that input token doesn't appear in any intermediate outputs
        // This prevents circular paths and validates path is meant for this token
        Currency inputCurrency = Currency.wrap(_address);
        for (uint256 i = 0; i < _v4Path.length; i++) {
            Currency intermediateCurrency = _v4Path[i].intermediateCurrency;
            // Input token should not appear as intermediate output (before the last hop)
            // This catches misconfigurations and circular paths
            if (i < _v4Path.length - 1 && Currency.unwrap(intermediateCurrency) == Currency.unwrap(inputCurrency)) {
                revert InvalidPath();
            }
        }

        // Verify path ends with ALEPH token
        if (Currency.unwrap(_v4Path[_v4Path.length - 1].intermediateCurrency) != _alephAddress) {
            revert InvalidPath();
        }

        // Check for any duplicate tokens in path (not just adjacent)
        for (uint256 i = 1; i < _v4Path.length; i++) {
            Currency currentCurrency = _v4Path[i].intermediateCurrency;
            for (uint256 j = 0; j < i; j++) {
                Currency prevCurrency = _v4Path[j].intermediateCurrency;
                if (Currency.unwrap(currentCurrency) == Currency.unwrap(prevCurrency)) {
                    revert DuplicateTokens();
                }
            }
        }
    }

    /**
     * @dev Helper function to check for duplicate tokens in V3 encoded path
     */
    function _checkV3PathForDuplicates(bytes calldata path) private pure {
        if (path.length < 43) return; // Minimum path length for 2 tokens

        // V3 path structure: token(20 bytes) + fee(3 bytes) + ... + token(20 bytes)
        // The +3 accounts for the last token not having a trailing fee section
        // Each hop is 23 bytes (20 bytes token + 3 bytes fee), except the last token
        uint256 numTokens = (path.length + 3) / 23;

        // Check each token against all previous tokens (not just adjacent)
        for (uint256 i = 0; i < numTokens; i++) {
            address tokenI;
            assembly {
                let posI := add(path.offset, mul(i, 23))
                tokenI := shr(96, calldataload(posI))
            }

            for (uint256 j = 0; j < i; j++) {
                address tokenJ;
                assembly {
                    let posJ := add(path.offset, mul(j, 23))
                    tokenJ := shr(96, calldataload(posJ))
                }

                if (tokenI == tokenJ) {
                    revert DuplicateTokens();
                }
            }
        }
    }

    /**
     * @dev Helper function to replace address(0) with WETH address in V3 encoded path
     */
    function _replaceAddressZeroWithWethV3(bytes calldata path, address _wethAddress)
        private
        pure
        returns (bytes memory)
    {
        if (path.length < 20) {
            return path;
        }

        // Check if any token in the path is address(0)
        // V3 path structure: token (20 bytes) + fee (3 bytes) + token (20 bytes) + ...
        // Tokens appear at positions: 0, 23, 46, 69, etc.
        bool hasAddressZero = false;
        // V3 path structure: token(20 bytes) + fee(3 bytes) + ... + token(20 bytes)
        // The +3 accounts for the last token not having a trailing fee section
        // Each hop is 23 bytes (20 bytes token + 3 bytes fee), except the last token
        uint256 numTokens = (path.length + 3) / 23;

        for (uint256 i = 0; i < numTokens; i++) {
            address token;
            assembly {
                let tokenPos := add(path.offset, mul(i, 23))
                token := shr(96, calldataload(tokenPos))
            }
            if (token == address(0)) {
                hasAddressZero = true;
                break;
            }
        }

        // If no address(0) found, return original path
        if (!hasAddressZero) {
            return path;
        }

        // Create new path with WETH replacing all address(0) occurrences
        bytes memory newPath = new bytes(path.length);

        // Replace all address(0) with WETH at each token position
        for (uint256 i = 0; i < numTokens; i++) {
            uint256 tokenPos = i * 23;
            address token;

            assembly {
                let srcPos := add(path.offset, tokenPos)
                token := shr(96, calldataload(srcPos))
            }

            if (token == address(0)) {
                // Replace with WETH
                assembly {
                    let destPos := add(add(newPath, 32), tokenPos)
                    mstore(destPos, shl(96, _wethAddress))
                }
            } else {
                // Copy original token
                for (uint256 j = 0; j < 20; j++) {
                    newPath[tokenPos + j] = path[tokenPos + j];
                }
            }

            // Copy fee bytes (3 bytes after each token, except the last token)
            if (i < numTokens - 1) {
                for (uint256 j = 0; j < 3; j++) {
                    newPath[tokenPos + 20 + j] = path[tokenPos + 20 + j];
                }
            }
        }

        return newPath;
    }

    function _approve(address _token, uint160 _amount, uint48 _ttl, IPermit2 permit2, UniversalRouter router) private {
        uint48 expiration = uint48(block.timestamp) + _ttl;
        IERC20 token = IERC20(_token);

        // Always approve exact amount needed for this swap
        // forceApprove safely handles any existing allowance (no race condition)
        token.forceApprove(address(permit2), _amount);
        permit2.approve(_token, address(router), _amount, expiration);
    }
}
