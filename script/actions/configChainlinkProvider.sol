// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {
    IChainlinkOracleProvider,
    AggregatorV3Interface
} from "@oracles/interfaces/IChainlinkOracleProvider.sol";
import {Config} from "../Config.sol";

contract ConfigureChainlinkProvider is Config {
    function run() public payable {
        uint256 chainId = vm.envUint("CHAIN_ID");
        string memory configPath = vm.envString("CONFIG_PATH");
        bool dryRun = vm.envBool("DRY_RUN");

        setUp();
        vm.createSelectFork(vm.envString(rpcs[chainId]));

        string memory json = vm.readFile(configPath);
        string[] memory marketKeys = getMarketKeys(json);

        string memory baseDir = getBaseDir(dryRun);
        string memory providerPath =
            string(abi.encodePacked(baseDir, "/artifacts/chainlinkProviderProxy.json"));
        address providerAddress = getAddresses(providerPath);
        IChainlinkOracleProvider provider = IChainlinkOracleProvider(providerAddress);

        if (!dryRun) {
            vm.startBroadcast();
            for (uint256 i = 0; i < marketKeys.length; i++) {
                string memory marketKey = marketKeys[i];
                address asset = vm.parseJsonAddress(
                    json, string(abi.encodePacked(".", marketKey, ".baseToken"))
                );
                address feed = vm.parseJsonAddress(
                    json, string(abi.encodePacked(".", marketKey, ".chainlinkFeed"))
                );
                uint256 maxStalePeriod = 3600;

                provider.setAssetConfig(
                    asset, AggregatorV3Interface(feed), maxStalePeriod
                );
            }
            vm.stopBroadcast();
        }
    }

    function getMarketKeys(string memory json) internal pure returns (string[] memory) {
        string[] memory allKeys = vm.parseJsonKeys(json, ".");
        uint256 count = 0;
        for (uint256 i = 0; i < allKeys.length; i++) {
            if (startsWith(allKeys[i], "market-")) count++;
        }
        string[] memory marketKeys = new string[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < allKeys.length; i++) {
            if (startsWith(allKeys[i], "market-")) {
                marketKeys[index] = allKeys[i];
                index++;
            }
        }
        return marketKeys;
    }
}
