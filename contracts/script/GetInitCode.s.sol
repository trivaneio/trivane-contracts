// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {stdToml} from "forge-std/StdToml.sol";

import {TrivaneCore} from "../src/core/TrivaneCore.sol";

contract GetInitCode is Script {
    using stdToml for string;

    function run() external view {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/foundry.toml");
        string memory config = vm.readFile(path);
        bytes32 salt = vm.parseBytes32(config.readString(".profile.salt.salt"));

        bytes memory trivaneCoreBytecode = type(TrivaneCore).creationCode;
        bytes memory trivaneCoreConstructor = abi.encode(deployer);
        bytes memory trivaneCoreInitCode = abi.encodePacked(trivaneCoreBytecode, trivaneCoreConstructor);

        console.log("\nTrivaneCore Init Code Hash:");
        console.logBytes32(keccak256(trivaneCoreInitCode));
        console.log("\nTrivaneCore Address:");
        console.log(findCreate2Address(salt, trivaneCoreInitCode));
    }

    function findCreate2Address(bytes32 salt, bytes memory initCode) public pure returns (address deploymentAddress) {
        // determine the address where the contract will be deployed.
        deploymentAddress = address(
            uint160( // downcast to match the address type.
                uint256( // convert to uint to truncate upper digits.
                    keccak256( // compute the CREATE2 hash using 4 inputs.
                        abi.encodePacked( // pack all inputs to the hash together.
                            hex"ff", // start with 0xff to distinguish from RLP.
                            address(0x900c87c5455c158622EE3Dde90E825c80085F345), // this contract will be the caller.
                            salt, // pass in the supplied salt value.
                            keccak256(abi.encodePacked(initCode)) // pass in the hash of initialization code.
                        )
                    )
                )
            )
        );
    }
}
