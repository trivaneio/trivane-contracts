// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Create2} from "../libraries/Create2.sol";
import {IL2ToL2CrossDomainMessenger} from "../interfaces/IL2ToL2CrossDomainMessenger.sol";
import {L2NativeSuperchainERC20} from "../tokens/L2NativeSuperchainERC20.sol";
import {IERC20} from "../interfaces/IERC20.sol";

/// @notice Thrown when a function is called by an address other than the L2ToL2CrossDomainMessenger.
error CallerNotL2ToL2CrossDomainMessenger();

/// @notice Thrown when the cross-domain sender is not this contract's address on another chain.
error InvalidCrossDomainSender();

/// @notice Thrown when a function restricted to the contract owner is called by another address
error CallerNotOwner();

/// @notice Thrown when attempting to add a chain that is already in the supported chains list
error ChainAlreadySupported();

/// @notice Thrown when attempting to interact with a chain that is not in the supported chains list
error ChainNotSupported();

/// @notice Thrown when attempting to set the contract owner to the zero address
error ZeroAddressOwner();

/// @notice Thrown when attempting to bridge to the same chain
error SameChain();

/// @notice Thrown when token deployment fails
error DeploymentFailed();

/// @notice Thrown when bridge transfer fails
error BridgeTransferFailed();

/// @notice Thrown when cross-chain message sending fails
error MessageSendingFailed();

/**
 * @title TrivaneCore
 * @notice Core contract for managing cross-chain token deployment and chain support
 * @dev Handles the deployment of tokens across multiple chains using Create2 for address consistency
 *
 * This contract enables:
 * - Cross-chain token deployment with consistent addresses using Create2
 * - Management of supported chains in the network
 * - Secure cross-chain message passing for token deployment synchronization
 * - Owner-controlled chain management functionality
 */
contract TrivaneCore {
    /// @notice Array of supported chain IDs in the network
    /// @dev Maintains a list of all chains where tokens can be deployed
    uint256[] public supportedChains;

    /// @notice Mapping to quickly check if a chain ID is supported
    /// @dev True if the chain is supported, false otherwise
    mapping(uint256 => bool) public isSupportedChain;

    /// @notice Address of the contract owner who can manage supported chains
    /// @dev Has exclusive rights to add/remove chains and transfer ownership
    address public owner;

    /// @notice Address of the SuperchainTokenBridge predeploy for cross-chain messaging
    /// @dev This is a constant address across all OP Stack chains
    address internal constant L2_TO_L2_CROSS_DOMAIN_MESSENGER = 0x4200000000000000000000000000000000000023;

    /// @dev Interface instance for cross-chain message passing
    IL2ToL2CrossDomainMessenger internal constant MESSENGER =
        IL2ToL2CrossDomainMessenger(L2_TO_L2_CROSS_DOMAIN_MESSENGER);

    /// @notice Emitted when a new token is deployed
    /// @param tokenAddress The address where the token was deployed
    /// @param name The name of the deployed token
    /// @param symbol The symbol of the deployed token
    /// @param initialSupply The initial supply of the token
    event TokenDeployed(address indexed tokenAddress, string name, string symbol, uint256 initialSupply);

    /// @notice Emitted when a new chain is added to supported chains
    /// @param chainId The ID of the chain that was added
    event ChainAdded(uint256 indexed chainId);

    /// @notice Emitted when a chain is removed from supported chains
    /// @param chainId The ID of the chain that was removed
    event ChainRemoved(uint256 indexed chainId);

    /// @notice Emitted when ownership is transferred
    /// @param previousOwner The address of the previous owner
    /// @param newOwner The address of the new owner
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice Constructor to set the initial owner
    constructor(address _owner) {
        if (_owner == address(0)) revert ZeroAddressOwner();
        owner = _owner;
    }

    /// @notice Modifier to restrict access to the owner
    modifier onlyOwner() {
        if (msg.sender != owner) revert CallerNotOwner();
        _;
    }

    /// @dev Modifier to restrict a function to only be a cross-domain callback into this contract
    modifier onlyCrossDomainCallback() {
        if (msg.sender != address(MESSENGER)) {
            revert CallerNotL2ToL2CrossDomainMessenger();
        }
        if (MESSENGER.crossDomainMessageSender() != address(this)) {
            revert InvalidCrossDomainSender();
        }
        _;
    }

    /**
     * @notice Deploys a new Superchain token across all supported chains
     * @dev Uses Create2 for deterministic addresses across chains
     * @param name The name of the token
     * @param symbol The symbol of the token
     * @param initialSupply The initial supply to mint
     * @param salt Unique value to ensure unique deployment addresses
     * @return address The address where the token was deployed
     */
    function deploySuperchainToken(string memory name, string memory symbol, uint256 initialSupply, bytes32 salt)
        public
        returns (address)
    {
        uint256 nativeChainId = block.chainid;
        bytes memory bytecode = getBytecode(name, symbol, initialSupply, nativeChainId);
        address deployedAddress = Create2.deploy(0, salt, bytecode);

        _syncDeploymentAcrossChains(name, symbol, initialSupply, nativeChainId, salt);

        return deployedAddress;
    }

    /**
     * @notice Deploys a token on a remote chain as part of cross-chain deployment
     * @dev Can only be called via cross-chain message from this contract on another chain
     * @param name Token name
     * @param symbol Token symbol
     * @param initialSupply Initial token supply
     * @param nativeChainId The chain ID where the token was originally deployed
     * @param salt Deployment salt for Create2
     */
    function deployOnRemoteChain(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        uint256 nativeChainId,
        bytes32 salt
    ) external onlyCrossDomainCallback {
        bytes memory bytecode = getBytecode(name, symbol, initialSupply, nativeChainId);
        address deployedAddress = Create2.deploy(0, salt, bytecode);

        emit TokenDeployed(deployedAddress, name, symbol, initialSupply);
    }

    /**
     * @notice Generates the bytecode for token deployment
     * @dev Combines the contract creation code with constructor arguments
     * @param name Token name
     * @param symbol Token symbol
     * @param initialSupply Initial token supply
     * @param nativeChainId The chain ID where the token originates
     * @return bytes The complete bytecode for deployment
     */
    function getBytecode(string memory name, string memory symbol, uint256 initialSupply, uint256 nativeChainId)
        public
        pure
        returns (bytes memory)
    {
        bytes memory initCode = type(L2NativeSuperchainERC20).creationCode;
        bytes memory constructorArgs = abi.encode(name, symbol, initialSupply, nativeChainId);
        return abi.encodePacked(initCode, constructorArgs);
    }

    function _syncDeploymentAcrossChains(
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        uint256 nativeChainId,
        bytes32 salt
    ) internal {
        uint256 length = supportedChains.length;
        for (uint256 i; i < length;) {
            if (supportedChains[i] != nativeChainId) {
                bytes32 msgHash = MESSENGER.sendMessage(
                    supportedChains[i],
                    address(this),
                    abi.encodeCall(this.deployOnRemoteChain, (name, symbol, initialSupply, nativeChainId, salt))
                );
                if (msgHash == bytes32(0)) revert MessageSendingFailed();
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Adds a new chain to the list of supported chains
     * @dev Only callable by the contract owner
     * @param chainId The ID of the chain to add
     */
    function addSupportedChain(uint256 chainId) public onlyOwner {
        if (isSupportedChain[chainId]) revert ChainAlreadySupported();
        isSupportedChain[chainId] = true;
        supportedChains.push(chainId);

        emit ChainAdded(chainId);
    }

    /**
     * @notice Removes a chain from the list of supported chains
     * @dev Only callable by the contract owner
     * @param chainId The ID of the chain to remove
     */
    function removeSupportedChain(uint256 chainId) public onlyOwner {
        if (!isSupportedChain[chainId]) revert ChainNotSupported();
        isSupportedChain[chainId] = false;

        uint256 length = supportedChains.length;
        uint256 indexToRemove = length;

        for (uint256 i = 0; i < length;) {
            if (supportedChains[i] == chainId) {
                indexToRemove = i;
                break;
            }
            unchecked {
                ++i;
            }
        }

        if (indexToRemove < length) {
            supportedChains[indexToRemove] = supportedChains[length - 1];
            supportedChains.pop();
        }

        emit ChainRemoved(chainId);
    }

    /**
     * @notice Transfers ownership of the contract to a new address
     * @dev Only callable by the current owner
     * @param newOwner The address to transfer ownership to
     */
    function setOwner(address newOwner) public onlyOwner {
        if (newOwner == address(0)) revert ZeroAddressOwner();
        address oldOwner = owner;
        owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}
