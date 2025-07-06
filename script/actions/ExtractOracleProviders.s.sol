// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Config} from "../Config.sol";

contract ExtractOracleProviders is Script, Config {
    function getAddresses(string memory path) internal view returns (address) {
        try vm.readFile(path) returns (string memory json) {
            return vm.parseJsonAddress(json, ".address");
        } catch {
            console.log("Warning: Failed to read address from %s", path);
            return address(0);
        }
    }

    function run() external {
        string memory chain = vm.envString("CHAIN");
        bool dryRun = vm.envBool("DRY_RUN");

        // Define the JSON files to process
        string[] memory jsonFiles = new string[](3);
        jsonFiles[0] = "chainlinkComposite.Proxy.json";
        jsonFiles[1] = "chainlinkProvider.Proxy.json";
        jsonFiles[2] = "pythProvider.Proxy.json";

        string memory baseDir = getBaseDir(chain, dryRun);

        // Create the common dir
        string memory commonDir = string.concat(baseDir, "/common");
        vm.createDir(commonDir, true);

        string memory obj = "oracle-providers";
        string[] memory keys = new string[](jsonFiles.length);
        for (uint256 i = 0; i < jsonFiles.length; i++) {
            string memory filePath = string.concat(baseDir, "/", jsonFiles[i]);
            // removing .Proxy.json
            string memory key = jsonFiles[i];
            uint256 dotIndex = findChar(key, bytes1("."));
            if (dotIndex < bytes(key).length) {
                key = substring(key, 0, dotIndex);
            }
            keys[i] = key;

            address addr = getAddresses(filePath);
            vm.serializeAddress(obj, key, addr);
            console.log("Processed %s: %s", filePath, vm.toString(addr));
        }

        string memory jsonContent = vm.serializeAddress(
            obj,
            keys[keys.length - 1],
            getAddresses(string.concat(baseDir, "/", jsonFiles[jsonFiles.length - 1]))
        );

        // Write to oracle-providers.json
        string memory outputPath = string.concat(commonDir, "/oracle-providers.json");
        writeJsonFile(outputPath, jsonContent);
    }

    // Helper to extract substring
    function substring(string memory str, uint256 start, uint256 length)
        private
        pure
        returns (string memory)
    {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = strBytes[start + i];
        }
        return string(result);
    }

    // Helper to find the first occurrence of a character
    function findChar(string memory str, bytes1 char) private pure returns (uint256) {
        bytes memory strBytes = bytes(str);
        for (uint256 i = 0; i < strBytes.length; i++) {
            if (strBytes[i] == char) {
                return i;
            }
        }
        return strBytes.length;
    }
}
