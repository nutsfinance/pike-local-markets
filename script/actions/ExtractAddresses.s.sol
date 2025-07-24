// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Config} from "../Config.sol";

contract ExtractAddresses is Script, Config {
    function extractImplementationAddresses(
        string memory baseDir,
        string memory commonDir
    ) internal {
        string[] memory implFiles = new string[](12);
        implFiles[0] = "Factory.json";
        implFiles[1] = "OracleEngine.json";
        implFiles[2] = "oracleEngineBeacon.json";
        implFiles[3] = "pTokenBeacon.json";
        implFiles[4] = "PTokenRouter.json";
        implFiles[5] = "reBeacon.json";
        implFiles[6] = "RiskEngineRouter.json";
        implFiles[7] = "Timelock.json";
        implFiles[8] = "timelockBeacon.json";
        implFiles[9] = "ChainlinkOracleComposite.json";
        implFiles[10] = "ChainlinkOracleProvider.json";
        implFiles[11] = "PythOracleProvider.json";

        string memory implObj = "implementations";
        string[] memory implKeys = new string[](implFiles.length);
        for (uint256 i = 0; i < implFiles.length; i++) {
            string memory filePath = string.concat(baseDir, "/artifacts/", implFiles[i]);
            string memory key = implFiles[i];
            uint256 dotIndex = findChar(key, bytes1("."));
            if (dotIndex < bytes(key).length) {
                key = substring(key, 0, dotIndex);
            }
            implKeys[i] = key;
            address addr = getAddresses(filePath);
            vm.serializeAddress(implObj, key, addr);
            console.log("Processed %s: %s", filePath, vm.toString(addr));
        }

        string memory implJsonContent = vm.serializeAddress(
            implObj,
            implKeys[implKeys.length - 1],
            getAddresses(
                string.concat(baseDir, "/artifacts/", implFiles[implFiles.length - 1])
            )
        );

        string memory implOutputPath =
            string.concat(commonDir, "/implementationData.json");
        writeJsonFile(implOutputPath, implJsonContent);
    }

    function run() external {
        bool dryRun = vm.envBool("DRY_RUN");
        uint256 protocolId = vm.envUint("PROTOCOL_ID");

        string memory baseDir = getBaseDir(dryRun);
        string memory commonDir = string.concat(baseDir, "/common");
        vm.createDir(commonDir, true);

        string[] memory oracleFiles = new string[](3);
        oracleFiles[0] = "chainlinkCompositeProxy.json";
        oracleFiles[1] = "chainlinkProviderProxy.json";
        oracleFiles[2] = "pythProviderProxy.json";

        string memory oracleObj = "oracle-providers";
        string[] memory oracleKeys = new string[](oracleFiles.length);
        address[] memory oracleAddresses = new address[](oracleFiles.length);
        for (uint256 i = 0; i < oracleFiles.length; i++) {
            string memory filePath = string.concat(baseDir, "/artifacts/", oracleFiles[i]);
            string memory key = oracleFiles[i];
            uint256 dotIndex = findChar(key, bytes1("."));
            if (dotIndex < bytes(key).length) {
                key = substring(key, 0, dotIndex);
            }
            oracleKeys[i] = key;
            address addr = getAddresses(filePath);
            oracleAddresses[i] = addr;
            vm.serializeAddress(oracleObj, key, addr);
            console.log("Processed %s: %s", filePath, vm.toString(addr));
        }

        string memory oracleJsonContent = vm.serializeAddress(
            oracleObj,
            oracleKeys[oracleKeys.length - 1],
            getAddresses(
                string.concat(baseDir, "/artifacts/", oracleFiles[oracleFiles.length - 1])
            )
        );

        string memory oracleOutputPath =
            string.concat(commonDir, "/oracle-providers.json");
        writeJsonFile(oracleOutputPath, oracleJsonContent);

        string memory protocolDir =
            string.concat(baseDir, "/protocol-", vm.toString(protocolId));
        vm.createDir(protocolDir, true);
        string memory deploymentDataPath =
            string.concat(protocolDir, "/deploymentData.json");

        string memory existingJson = vm.readFile(deploymentDataPath);

        string memory deploymentObj = "deploymentData";
        string[] memory keys = vm.parseJsonKeys(existingJson, ".");
        for (uint256 i = 0; i < keys.length; i++) {
            string memory key = keys[i];
            bool isOracleKey;
            for (uint256 j = 0; j < oracleKeys.length; j++) {
                if (
                    keccak256(abi.encodePacked(key))
                        == keccak256(abi.encodePacked(oracleKeys[j]))
                ) {
                    isOracleKey = true;
                    break;
                }
            }
            if (!isOracleKey) {
                bytes memory valueBytes =
                    vm.parseJson(existingJson, string(abi.encodePacked(".", key)));
                if (startsWith(key, "market-")) {
                    address addr = abi.decode(valueBytes, (address));
                    vm.serializeAddress(deploymentObj, key, addr);
                } else if (
                    keccak256(abi.encodePacked(key))
                        == keccak256(abi.encodePacked("protocolId"))
                ) {
                    uint256 val = abi.decode(valueBytes, (uint256));
                    vm.serializeUint(deploymentObj, key, val);
                } else if (
                    keccak256(abi.encodePacked(key))
                        == keccak256(abi.encodePacked("deploymentTimestamp"))
                ) {
                    uint256 val = abi.decode(valueBytes, (uint256));
                    vm.serializeUint(deploymentObj, key, val);
                } else if (
                    keccak256(abi.encodePacked(key))
                        == keccak256(abi.encodePacked("isDryRun"))
                ) {
                    bool val = abi.decode(valueBytes, (bool));
                    vm.serializeBool(deploymentObj, key, val);
                } else {
                    address addr = abi.decode(valueBytes, (address));
                    vm.serializeAddress(deploymentObj, key, addr);
                }
            }
        }

        string memory finalJson = deploymentObj;
        for (uint256 i = 0; i < oracleKeys.length; i++) {
            finalJson =
                vm.serializeAddress(deploymentObj, oracleKeys[i], oracleAddresses[i]);
        }
        vm.writeFile(deploymentDataPath, finalJson);
        console.log("Updated deploymentData.json");

        extractImplementationAddresses(baseDir, commonDir);
    }
}
