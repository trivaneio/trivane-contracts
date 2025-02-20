// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {SuperchainERC20} from "./SuperchainERC20.sol";

contract L2NativeSuperchainERC20 is SuperchainERC20 {
    string private _name;
    string private _symbol;
    /// @dev Immutable flag to determine if this is the native chain deployment
    /// Prevents repeat minting and enables chain-specific logic
    bool private immutable _isNativeChain;

    constructor(string memory name_, string memory symbol_, uint256 initialSupply_, uint256 nativeChainId) {
        _name = name_;
        _symbol = symbol_;

        _isNativeChain = block.chainid == nativeChainId;

        if (_isNativeChain) {
            _mint(tx.origin, initialSupply_);
        }
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function isNativeChain() public view returns (bool) {
        return _isNativeChain;
    }
}
