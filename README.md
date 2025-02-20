# Trivane Contracts

A sophisticated cross-chain token deployment and management system built for OP Stack chains, enabling seamless token operations across multiple Superchain networks.

## Overview

Trivane Contracts provides a robust infrastructure for deploying and managing Superchain ERC20 tokens across OP Stack chains. The system leverages CREATE2 for deterministic deployments, ensuring consistent token addresses across all supported chains while maintaining secure cross-chain communication.

## Core Components

### TrivaneCore.sol
The central contract orchestrating the entire system:
- Manages cross-chain token deployments using CREATE2 for address consistency
- Handles chain support through dynamic addition/removal functionality
- Implements secure cross-chain messaging via L2ToL2CrossDomainMessenger
- Provides owner-controlled administrative functions
- Emits detailed events for deployment tracking and chain management

Key functions:
- `deploySuperchainToken`: Deploys tokens across all supported chains
- `deployOnRemoteChain`: Handles remote chain token deployment
- `addSupportedChain`/`removeSupportedChain`: Manages supported chains
- `setOwner`: Transfers contract ownership

### Supporting Contracts

#### L2NativeSuperchainERC20.sol
The token implementation deployed across chains:
- Implements standard ERC20 functionality
- Stores chain-specific metadata
- Handles initial token supply minting
- Maintains awareness of native chain ID

#### IL2ToL2CrossDomainMessenger
Interface for cross-chain communication:
- Enables secure message passing between chains
- Verifies cross-domain message authenticity
- Manages message nonces and versions

## Technical Features

- **Deterministic Deployment**: CREATE2 ensures consistent token addresses
- **Cross-Chain Communication**: Secure message passing between chains
- **Chain Management**: Dynamic addition/removal of supported chains
- **Access Control**: Owner-restricted administrative functions
- **Event System**: Comprehensive event logging for all operations
- **Error Handling**: Custom errors for precise failure reporting

## Security Measures

The system implements multiple security layers:
- Strict ownership controls for administrative functions
- Cross-chain message sender verification
- Deterministic address validation
- Zero-address checks
- Protected deployment synchronization
- Comprehensive error handling with custom error types

## Events and Monitoring

Key events for system tracking:
- `TokenDeployed`: Records new token deployments
- `ChainAdded`/`ChainRemoved`: Tracks chain support changes
- `OwnershipTransferred`: Monitors ownership changes

## Error Types

Custom errors for precise failure handling:
- `CallerNotL2ToL2CrossDomainMessenger`
- `InvalidCrossDomainSender`
- `CallerNotOwner`
- `ChainAlreadySupported`/`ChainNotSupported`
- `ZeroAddressOwner`
- `DeploymentFailed`
- `MessageSendingFailed`
