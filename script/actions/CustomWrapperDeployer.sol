// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {CustomRateFeedWrapper} from "@oracles/CustomRateFeedWrapper.sol";
import {Config, console} from "../Config.sol";

/// @title DeployCustomWrapper
contract DeployCustomWrapper is Config {
    function run() public payable {
        uint256 chainId = vm.envUint("CHAIN_ID");
        string memory chain = vm.envString("CHAIN");
        uint256 protocolId = vm.envUint("PROTOCOL_ID");
        string memory version = vm.envString("VERSION");
        bool dryRun = vm.envBool("DRY_RUN");

        address token = vm.envAddress("TOKEN_ADDRESS");
        bytes memory funcData = vm.envBytes("FUNC_DATA"); // full calldata (selector + args)
        uint8 decimals = uint8(vm.envUint("DECIMALS"));

        setUp();
        vm.createSelectFork(vm.envString(rpcs[chainId]));

        string memory baseDir = getBaseDir(dryRun);
        string memory outputPath = string(
            abi.encodePacked(
                baseDir, "/protocol-", vm.toString(protocolId), "/oracleWrappers.json"
            )
        );

        CustomRateFeedWrapper wrapper;

        if (!dryRun) {
            uint256 privateKey = vm.parseUint(vm.envString("PRIVATE_KEY"));
            vm.startBroadcast(privateKey);
            wrapper = new CustomRateFeedWrapper(token, decimals, funcData);
            vm.stopBroadcast();
            console.log("Deployed:", address(wrapper));
        } else {
            wrapper = new CustomRateFeedWrapper(token, decimals, funcData);
            console.log("Dry run:", address(wrapper));
        }

        _writeDeployment(outputPath, token, address(wrapper));
    }

    function _writeDeployment(string memory outputPath, address token, address wrapper)
        internal
    {
        string memory existingJson;
        if (vm.exists(outputPath)) {
            existingJson = vm.readFile(outputPath);
        } else {
            existingJson = "{}";
        }

        string memory obj = "oracleWrappers";
        string[] memory keys = vm.parseJsonKeys(existingJson, ".");
        for (uint256 i = 0; i < keys.length; i++) {
            string memory key = keys[i];
            if (
                keccak256(abi.encodePacked(key))
                    != keccak256(abi.encodePacked(vm.toString(token)))
            ) {
                address addr = vm.parseJsonAddress(
                    existingJson, string(abi.encodePacked(".", key))
                );
                vm.serializeAddress(obj, key, addr);
            }
        }

        string memory updatedJson = vm.serializeAddress(obj, vm.toString(token), wrapper);
        vm.writeFile(outputPath, updatedJson);
        console.log("Saved wrapper address to:", outputPath);
    }
}
