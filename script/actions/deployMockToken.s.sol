// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "@mocks/MockToken.sol";
import {Config, console} from "../Config.sol";

/**
 * @notice Deploys MockToken deterministically across chains using CREATE2.
 */
contract DeployMockTokenScript is Config {
    function run() external {
        setUp();

        uint256 chainId = vm.envUint("CHAIN_ID");
        bool dryRun = vm.envBool("DRY_RUN");
        string memory baseDir = getBaseDir(dryRun);

        vm.createSelectFork(vm.envString(rpcs[chainId]));

        string memory name = vm.envString("NAME");
        string memory symbol = vm.envString("SYMBOL");
        uint256 decimals = vm.envUint("DECIMALS");
        string memory saltStr = vm.envString("SALT");
        bytes32 salt = keccak256(abi.encodePacked(saltStr));

        vm.startBroadcast(deployerPrivateKey);

        bytes memory bytecode = abi.encodePacked(
            type(MockToken).creationCode, abi.encode(name, symbol, uint8(decimals))
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

        string memory dirPath = string(abi.encodePacked(baseDir, "/mocks/"));
        vm.createDir(dirPath, true);

        string memory filePath = string(abi.encodePacked(dirPath, "/", name, ".json"));

        string memory json = "{";
        json = string(
            abi.encodePacked(
                json,
                '"name":"',
                name,
                '","symbol":"',
                symbol,
                '","decimals":',
                vm.toString(decimals),
                ',"salt":"',
                saltStr,
                '","deployedAddress":"',
                vm.toString(deployedAddr),
                '"}'
            )
        );

        vm.writeJson(json, filePath);

        console.log("Mock token info saved to:", filePath);
    }
}
