// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "@mocks/MockToken.sol";

/**
 * @notice Deploys MockToken deterministically across chains using CREATE2.
 */
contract DeployMockTokenScript is Script {
    function run() external {
        vm.startBroadcast();

        bytes32 salt = keccak256(abi.encodePacked("MOCK_TOKEN")); 

        string memory name = "Mock Token";
        string memory symbol = "MOCK";
        uint8 decimals = 18;

        bytes memory bytecode = abi.encodePacked(
            type(MockToken).creationCode,
            abi.encode(name, symbol, decimals)
        );

        address deployedAddr;

        assembly {
            let encoded_data := add(bytecode, 0x20)
            let encoded_size := mload(bytecode)
            deployedAddr := create2(0, encoded_data, encoded_size, salt)

            if iszero(extcodesize(deployedAddr)) {
                revert(0, 0)
            }
        }

        vm.stopBroadcast();

        console.log("MockToken deployed at:", deployedAddr);
    }
}