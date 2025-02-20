// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test} from "forge-std/Test.sol";
import {TrivaneCore} from "../src/core/TrivaneCore.sol";
import {L2NativeSuperchainERC20} from "../src/tokens/L2NativeSuperchainERC20.sol";
import {Create2} from "../src/libraries/Create2.sol";
import {IL2ToL2CrossDomainMessenger, Identifier} from "../src/interfaces/IL2ToL2CrossDomainMessenger.sol";

// Mock L2ToL2CrossDomainMessenger contract
contract MockMessenger is IL2ToL2CrossDomainMessenger {
    address public crossDomainMessageSender;
    uint256 private _messageNonce;
    mapping(bytes32 => bool) private _successfulMessages;

    function sendMessage(uint256 _targetChainId, address _target, bytes calldata _message) external returns (bytes32) {
        bytes32 messageHash = keccak256(abi.encodePacked(_targetChainId, _target, _message));
        _successfulMessages[messageHash] = true;
        emit SentMessage(_targetChainId, _target, _messageNonce++, msg.sender, _message);
        return messageHash;
    }

    function setCrossDomainMessageSender(address sender) external {
        crossDomainMessageSender = sender;
    }

    function __constructor__() external {}

    function crossDomainMessageContext() external view returns (address sender_, uint256 source_) {
        return (crossDomainMessageSender, 1);
    }

    function crossDomainMessageSource() external view returns (uint256 source_) {
        return 1;
    }

    function messageNonce() external view returns (uint256) {
        return _messageNonce;
    }

    function messageVersion() external view returns (uint16) {
        return 1;
    }

    function relayMessage(Identifier calldata _id, bytes calldata _sentMessage)
        external
        payable
        returns (bytes memory)
    {
        return new bytes(0);
    }

    function successfulMessages(bytes32 msgHash) external view returns (bool) {
        return _successfulMessages[msgHash];
    }

    function version() external pure returns (string memory) {
        return "1.0.0";
    }
}

contract TrivaneCoreTest is Test {
    TrivaneCore public trivaneCore;
    MockMessenger public mockMessenger;
    address public owner;
    address public user;
    address constant MESSENGER_ADDRESS = 0x4200000000000000000000000000000000000023;

    string public constant NAME = "Test Token";
    string public constant SYMBOL = "TEST";
    uint256 public constant INITIAL_SUPPLY = 1000000;
    bytes32 public constant SALT_CHAIN_1 = bytes32(uint256(1));
    bytes32 public constant SALT_CHAIN_2 = bytes32(uint256(2));

    uint256 public constant CHAIN_1 = 1;
    uint256 public constant CHAIN_2 = 2;
    uint256 public constant CHAIN_3 = 3;

    function setUp() public {
        owner = address(this);
        user = makeAddr("user");

        mockMessenger = new MockMessenger();
        vm.etch(MESSENGER_ADDRESS, address(mockMessenger).code);

        trivaneCore = new TrivaneCore(owner);
    }

    /// @notice Test constructor with zero address
    function testConstructorZeroAddress() public {
        vm.expectRevert(abi.encodeWithSignature("ZeroAddressOwner()"));
        new TrivaneCore(address(0));
    }

    /// @notice Test adding supported chains
    function testAddSupportedChain() public {
        trivaneCore.addSupportedChain(CHAIN_1);
        assertTrue(trivaneCore.isSupportedChain(CHAIN_1));
        assertEq(trivaneCore.supportedChains(0), CHAIN_1);
    }

    /// @notice Test adding already supported chain
    function testAddAlreadySupportedChain() public {
        trivaneCore.addSupportedChain(CHAIN_1);
        vm.expectRevert(abi.encodeWithSignature("ChainAlreadySupported()"));
        trivaneCore.addSupportedChain(CHAIN_1);
    }

    /// @notice Test removing supported chain
    function testRemoveSupportedChain() public {
        trivaneCore.addSupportedChain(CHAIN_1);
        trivaneCore.removeSupportedChain(CHAIN_1);
        assertFalse(trivaneCore.isSupportedChain(CHAIN_1));
    }

    /// @notice Test removing non-supported chain
    function testRemoveNonSupportedChain() public {
        vm.expectRevert(abi.encodeWithSignature("ChainNotSupported()"));
        trivaneCore.removeSupportedChain(CHAIN_1);
    }

    /// @notice Test chain management permissions
    function testOnlyOwnerCanManageChains() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("CallerNotOwner()"));
        trivaneCore.addSupportedChain(CHAIN_1);

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("CallerNotOwner()"));
        trivaneCore.removeSupportedChain(CHAIN_1);
    }

    /// @notice Test ownership transfer
    function testOwnershipTransfer() public {
        trivaneCore.setOwner(user);
        assertEq(trivaneCore.owner(), user);
    }

    /// @notice Test ownership transfer to zero address
    function testOwnershipTransferToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSignature("ZeroAddressOwner()"));
        trivaneCore.setOwner(address(0));
    }

    /// @notice Test token deployment bytecode generation
    function testGetBytecode() public {
        bytes memory bytecode = trivaneCore.getBytecode(NAME, SYMBOL, INITIAL_SUPPLY, CHAIN_1);
        assertTrue(bytecode.length > 0);
    }

    /// @notice Test token deployment with mocked cross-chain messaging
    function testDeploySuperchainToken() public {
        trivaneCore.addSupportedChain(CHAIN_1);

        vm.chainId(CHAIN_1);

        address deployedToken = trivaneCore.deploySuperchainToken(NAME, SYMBOL, INITIAL_SUPPLY, SALT_CHAIN_1);

        assertTrue(deployedToken != address(0));

        L2NativeSuperchainERC20 token = L2NativeSuperchainERC20(deployedToken);
        assertEq(token.name(), NAME);
        assertEq(token.symbol(), SYMBOL);
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
    }

    /// @notice Test deterministic deployment addresses
    function testDeterministicDeployment() public {
        trivaneCore.addSupportedChain(CHAIN_1);
        vm.chainId(CHAIN_1);

        // First, deploy the token and get its address
        vm.startPrank(MESSENGER_ADDRESS);
        MockMessenger(MESSENGER_ADDRESS).setCrossDomainMessageSender(address(trivaneCore));

        address deployedAddress = trivaneCore.deploySuperchainToken(NAME, SYMBOL, INITIAL_SUPPLY, SALT_CHAIN_1);
        vm.stopPrank();

        // Now calculate what the address should have been
        bytes memory bytecode = trivaneCore.getBytecode(NAME, SYMBOL, INITIAL_SUPPLY, CHAIN_1);
        bytes32 bytecodeHash = keccak256(bytecode);
        address expectedAddress = Create2.computeAddress(SALT_CHAIN_1, bytecodeHash, address(trivaneCore));

        // Verify addresses match
        assertEq(deployedAddress, expectedAddress);

        // Verify token was actually deployed and has correct properties
        L2NativeSuperchainERC20 token = L2NativeSuperchainERC20(deployedAddress);
        assertEq(token.name(), NAME);
        assertEq(token.symbol(), SYMBOL);
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
    }

    /// @notice Test cross-chain deployment functionality
    function testCrossChainDeployment() public {
        // Add supported chains
        trivaneCore.addSupportedChain(CHAIN_1);
        trivaneCore.addSupportedChain(CHAIN_2);

        // Chain 1 Deployment
        {
            vm.chainId(CHAIN_1);
            vm.startPrank(MESSENGER_ADDRESS);
            MockMessenger(MESSENGER_ADDRESS).setCrossDomainMessageSender(address(trivaneCore));

            bytes memory bytecode1 = trivaneCore.getBytecode(NAME, SYMBOL, INITIAL_SUPPLY, CHAIN_1);
            bytes32 bytecodeHash1 = keccak256(bytecode1);
            address expectedAddress1 = Create2.computeAddress(SALT_CHAIN_1, bytecodeHash1, address(trivaneCore));

            address deployedToken1 = trivaneCore.deploySuperchainToken(NAME, SYMBOL, INITIAL_SUPPLY, SALT_CHAIN_1);

            assertEq(deployedToken1, expectedAddress1);
            vm.stopPrank();
        }

        // Chain 2 Deployment
        {
            vm.chainId(CHAIN_2);
            vm.startPrank(MESSENGER_ADDRESS);
            MockMessenger(MESSENGER_ADDRESS).setCrossDomainMessageSender(address(trivaneCore));

            bytes memory bytecode2 = trivaneCore.getBytecode(NAME, SYMBOL, INITIAL_SUPPLY, CHAIN_2);
            bytes32 bytecodeHash2 = keccak256(bytecode2);
            address expectedAddress2 = Create2.computeAddress(SALT_CHAIN_2, bytecodeHash2, address(trivaneCore));

            address deployedToken2 = trivaneCore.deploySuperchainToken(NAME, SYMBOL, INITIAL_SUPPLY, SALT_CHAIN_2);

            assertEq(deployedToken2, expectedAddress2);

            // Verify token properties
            L2NativeSuperchainERC20 token = L2NativeSuperchainERC20(deployedToken2);
            assertEq(token.name(), NAME);
            assertEq(token.symbol(), SYMBOL);
            assertEq(token.totalSupply(), INITIAL_SUPPLY);

            vm.stopPrank();
        }
    }

    /// @notice Test multiple chain support
    function testMultipleChainSupport() public {
        // Add multiple chains
        trivaneCore.addSupportedChain(CHAIN_1);
        trivaneCore.addSupportedChain(CHAIN_2);
        trivaneCore.addSupportedChain(CHAIN_3);

        // Verify all chains are supported
        assertTrue(trivaneCore.isSupportedChain(CHAIN_1));
        assertTrue(trivaneCore.isSupportedChain(CHAIN_2));
        assertTrue(trivaneCore.isSupportedChain(CHAIN_3));

        // Remove middle chain
        trivaneCore.removeSupportedChain(CHAIN_2);

        // Verify chain removal
        assertTrue(trivaneCore.isSupportedChain(CHAIN_1));
        assertFalse(trivaneCore.isSupportedChain(CHAIN_2));
        assertTrue(trivaneCore.isSupportedChain(CHAIN_3));
    }
}
