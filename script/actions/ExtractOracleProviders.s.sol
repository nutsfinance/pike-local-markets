// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Config} from "../Config.sol";

contract ExtractOracleProviders is Script, Config {
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
}
