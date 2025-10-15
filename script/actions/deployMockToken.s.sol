// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "@mocks/MockToken.sol";
import {Config, console} from "../Config.sol";

interface ICreateX {
    function deployCreate2(bytes32 salt, bytes memory initCode)
        external
        payable
        returns (address newContract);

    function computeCreate2Address(bytes32 salt, bytes32 initCodeHash)
        external
        view
        returns (address computedAddress);
}

/**
 * @notice Deploys MockToken deterministically across chains using CREATE2.
 */
contract DeployMockTokenScript is Config {
    function run() external {
        address CREATE_X = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;
        ICreateX createx = ICreateX(CREATE_X);

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

        bytes memory bytecode = abi.encodePacked(
            type(MockToken).creationCode, abi.encode(name, symbol, uint8(decimals))
        );

        vm.startBroadcast(deployerPrivateKey);

        address deployedAddr = createx.deployCreate2(salt, bytecode);

        vm.stopBroadcast();

        // verify it matches expected
        console.log("MockToken deployed at:", deployedAddr);
        // require(deployedAddr == expectedAddr, "Deployed address mismatch");

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
