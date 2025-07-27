// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Config} from "../Config.sol";

contract MergeDeploymentData is Script, Config {
    function run() external {
        bool dryRun = vm.envBool("DRY_RUN");
        uint256 protocolId = vm.envUint("PROTOCOL_ID");

        string memory baseDir = getBaseDir(dryRun);
        string memory commonDir = string.concat(baseDir, "/common");
        string memory mergedPath = string.concat(commonDir, "/", vm.envString("CHAIN"),".json");

        string memory oraclePath = string.concat(commonDir, "/oracle-providers.json");
        string memory oracleJson = vm.readFile(oraclePath);
        string memory topObject = "merged";
        string memory merged = vm.serializeString(topObject, "oracle-providers", oracleJson);

        for (uint256 id = 1; id <= protocolId; id++) {
            string memory path = string.concat(baseDir, "/protocol-", vm.toString(id), "/deployment-data.json");

            string memory protocolJson = vm.readFile(path);

            string memory key = string.concat("protocol-", vm.toString(id));
            merged = vm.serializeString(topObject, key, protocolJson);
        }

        vm.writeFile(mergedPath, merged);
        console.log("Merged deployment data written to: %s", mergedPath);
    }
}