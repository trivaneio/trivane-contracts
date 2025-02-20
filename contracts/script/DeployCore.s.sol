// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {TrivaneCore} from "../src/core/TrivaneCore.sol";
import {stdToml} from "forge-std/StdToml.sol";

contract Deploy is Script {
    using stdToml for string;

    address constant CREATE2_FACTORY_IMMUTABLE = 0x900c87c5455c158622EE3Dde90E825c80085F345;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        // Load config
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/foundry.toml");
        string memory config = vm.readFile(path);
        uint256[] memory supportedChains = config.readUintArray(".profile.supported_chains.supported_chains");
        bytes32 salt = vm.parseBytes32(config.readString(".profile.salt.salt"));

        bytes memory trivaneCoreCode = abi.encodePacked(type(TrivaneCore).creationCode, abi.encode(deployer));

        // Deploy to each supported chain
        for (uint256 i = 0; i < supportedChains.length; i++) {
            uint256 chainId = supportedChains[i];

            // Switch to the appropriate RPC
            string memory rpcKey = chainId == 420120000 ? "interop-alpha-0" : "interop-alpha-1";
            vm.createSelectFork(vm.rpcUrl(rpcKey));

            console.log("\nDeploying to chain:", chainId);

            vm.startBroadcast(deployerPrivateKey);

            ImmutableCreate2Factory factory = ImmutableCreate2Factory(CREATE2_FACTORY_IMMUTABLE);
            address trivaneCoreAddress = factory.safeCreate2{value: 0}(salt, trivaneCoreCode);

            console.log("TrivaneCore deployed at:", trivaneCoreAddress);

            TrivaneCore trivaneCore = TrivaneCore(trivaneCoreAddress);
            if (chainId == 420120000) {
                trivaneCore.addSupportedChain(420120001);
            } else {
                trivaneCore.addSupportedChain(420120000);
                trivaneCore.deploySuperchainToken("TestToken-1", "TEST1", 1000000 * 10 ** 18, salt);
            }

            vm.stopBroadcast();
        }
    }
}

interface ImmutableCreate2Factory {
    function safeCreate2(bytes32 salt, bytes calldata initializationCode)
        external
        payable
        returns (address deploymentAddress);
}
