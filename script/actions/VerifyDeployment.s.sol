// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {IPToken} from "@interfaces/IPToken.sol";
import {IDoubleJumpRateModel} from "@interfaces/IDoubleJumpRateModel.sol";
import {Config} from "../Config.sol";

contract VerifyDeployment is Config {
    struct MarketConfig {
        string name;
        string symbol;
        address baseToken;
        uint8 decimals;
        uint256 initialExchangeRateMantissa;
        uint256 reserveFactorMantissa;
        uint256 protocolSeizeShareMantissa;
        uint256 borrowRateMaxMantissa;
        uint256 collateralFactorMantissa;
        uint256 liquidationThresholdMantissa;
        uint256 liquidationIncentiveMantissa;
        uint256 closeFactor;
        uint256 supplyCap;
        uint256 borrowCap;
        uint256 baseRate;
        uint256 initialMultiplier;
        uint256 firstKinkMultiplier;
        uint256 secondKinkMultiplier;
        uint256 firstKink;
        uint256 secondKink;
        address mainProvider;
        address fallbackProvider;
    }

    function run() public {
        string memory chain = vm.envString("CHAIN");
        uint256 chainId = vm.envUint("CHAIN_ID");
        uint256 protocolId = vm.envUint("PROTOCOL_ID");

        // Load market configurations
        MarketConfig[] memory configs = readMarketConfigs(chain, protocolId);

        // Load deployment data
        string memory deploymentPath = getDeploymentPath(protocolId);
        string memory json = vm.readFile(deploymentPath);
        address riskEngineAddress = vm.parseJsonAddress(json, ".riskEngine");
        IRiskEngine re = IRiskEngine(riskEngineAddress);
        vm.createSelectFork(vm.envString(rpcs[chainId]));

        // Verify each market
        for (uint256 i = 0; i < configs.length; i++) {
            string memory marketKey =
                string(abi.encodePacked("market-", vm.toLowercase(configs[i].symbol)));
            address pTokenAddress =
                vm.parseJsonAddress(json, string(abi.encodePacked(".", marketKey)));
            IPToken pToken = IPToken(pTokenAddress);

            // Basic PToken property checks
            require(
                keccak256(bytes(pToken.name())) == keccak256(bytes(configs[i].name)),
                "Name mismatch"
            );
            require(
                keccak256(bytes(pToken.symbol())) == keccak256(bytes(configs[i].symbol)),
                "Symbol mismatch"
            );
            require(pToken.decimals() == configs[i].decimals, "Decimals mismatch");
            require(pToken.asset() == configs[i].baseToken, "Base token mismatch");
            require(
                pToken.initialExchangeRate() == configs[i].initialExchangeRateMantissa,
                "initial rate mismatch"
            );
            require(
                pToken.reserveFactorMantissa() == configs[i].reserveFactorMantissa,
                "reserve mismatch"
            );
            require(
                pToken.protocolSeizeShareMantissa()
                    == configs[i].protocolSeizeShareMantissa,
                "seize share mismatch"
            );
            require(
                pToken.borrowRateMaxMantissa() == configs[i].borrowRateMaxMantissa,
                "borrow rate max mismatch"
            );
            (uint256 firstKink, uint256 secondKink) =
                IDoubleJumpRateModel(pTokenAddress).kinks();
            require(firstKink == configs[i].firstKink, "firstKink mismatch");
            require(secondKink == configs[i].secondKink, "secondKink mismatch");

            // Risk Engine configuration checks
            require(
                re.closeFactor(pTokenAddress) == configs[i].closeFactor,
                "closeFactor mismatch"
            );
            require(
                re.supplyCap(pTokenAddress) == configs[i].supplyCap, "supplyCap mismatch"
            );
            require(
                re.borrowCap(pTokenAddress) == configs[i].borrowCap, "borrowCap mismatch"
            );
            require(
                re.collateralFactor(0, pToken) == configs[i].collateralFactorMantissa,
                "Collateral factor mismatch"
            );
            require(
                re.liquidationThreshold(0, pToken)
                    == configs[i].liquidationThresholdMantissa,
                "Liquidation threshold mismatch"
            );
            require(
                re.liquidationIncentive(0, pTokenAddress)
                    == configs[i].liquidationIncentiveMantissa,
                "Liquidation threshold mismatch"
            );

            console.log("test passed for market: %s", configs[i].symbol);
        }

        console.log("All markets passed test verification");
    }

    function readMarketConfigs(string memory chain, uint256 protocolId)
        internal
        view
        returns (MarketConfig[] memory)
    {
        string memory root = vm.projectRoot();
        string memory configPath = string(
            abi.encodePacked(
                root,
                "/script/configs/",
                chain,
                "/protocol-",
                vm.toString(protocolId),
                ".json"
            )
        );
        string memory json = vm.readFile(configPath);

        string[] memory allKeys = vm.parseJsonKeys(json, ".");
        uint256 marketCount = 0;
        for (uint256 i = 0; i < allKeys.length; i++) {
            if (startsWith(allKeys[i], "market-")) {
                marketCount++;
            }
        }

        MarketConfig[] memory configs = new MarketConfig[](marketCount);
        uint256 configIndex = 0;

        for (uint256 i = 0; i < allKeys.length; i++) {
            string memory marketKey = allKeys[i];
            if (startsWith(marketKey, "market-")) {
                string memory marketPath = string(abi.encodePacked(".", marketKey));
                configs[configIndex] = MarketConfig({
                    name: vm.parseJsonString(
                        json, string(abi.encodePacked(marketPath, ".name"))
                    ),
                    symbol: vm.parseJsonString(
                        json, string(abi.encodePacked(marketPath, ".symbol"))
                    ),
                    baseToken: vm.parseJsonAddress(
                        json, string(abi.encodePacked(marketPath, ".baseToken"))
                    ),
                    decimals: uint8(
                        vm.parseJsonUint(
                            json, string(abi.encodePacked(marketPath, ".decimals"))
                        )
                    ),
                    initialExchangeRateMantissa: vm.parseJsonUint(
                        json,
                        string(abi.encodePacked(marketPath, ".initialExchangeRateMantissa"))
                    ),
                    reserveFactorMantissa: vm.parseJsonUint(
                        json, string(abi.encodePacked(marketPath, ".reserveFactorMantissa"))
                    ),
                    protocolSeizeShareMantissa: vm.parseJsonUint(
                        json,
                        string(abi.encodePacked(marketPath, ".protocolSeizeShareMantissa"))
                    ),
                    borrowRateMaxMantissa: vm.parseJsonUint(
                        json, string(abi.encodePacked(marketPath, ".borrowRateMaxMantissa"))
                    ),
                    collateralFactorMantissa: vm.parseJsonUint(
                        json,
                        string(abi.encodePacked(marketPath, ".collateralFactorMantissa"))
                    ),
                    liquidationThresholdMantissa: vm.parseJsonUint(
                        json,
                        string(abi.encodePacked(marketPath, ".liquidationThresholdMantissa"))
                    ),
                    liquidationIncentiveMantissa: vm.parseJsonUint(
                        json,
                        string(abi.encodePacked(marketPath, ".liquidationIncentiveMantissa"))
                    ),
                    closeFactor: vm.parseJsonUint(
                        json, string(abi.encodePacked(marketPath, ".closeFactor"))
                    ),
                    supplyCap: vm.parseJsonUint(
                        json, string(abi.encodePacked(marketPath, ".supplyCap"))
                    ),
                    borrowCap: vm.parseJsonUint(
                        json, string(abi.encodePacked(marketPath, ".borrowCap"))
                    ),
                    baseRate: vm.parseJsonUint(
                        json, string(abi.encodePacked(marketPath, ".baseRate"))
                    ),
                    initialMultiplier: vm.parseJsonUint(
                        json, string(abi.encodePacked(marketPath, ".initialMultiplier"))
                    ),
                    firstKinkMultiplier: vm.parseJsonUint(
                        json, string(abi.encodePacked(marketPath, ".firstKinkMultiplier"))
                    ),
                    secondKinkMultiplier: vm.parseJsonUint(
                        json, string(abi.encodePacked(marketPath, ".secondKinkMultiplier"))
                    ),
                    firstKink: vm.parseJsonUint(
                        json, string(abi.encodePacked(marketPath, ".firstKink"))
                    ),
                    secondKink: vm.parseJsonUint(
                        json, string(abi.encodePacked(marketPath, ".secondKink"))
                    ),
                    mainProvider: vm.parseJsonAddress(
                        json, string(abi.encodePacked(marketPath, ".mainProvider"))
                    ),
                    fallbackProvider: vm.parseJsonAddress(
                        json, string(abi.encodePacked(marketPath, ".fallbackProvider"))
                    )
                });
                configIndex++;
            }
        }

        return configs;
    }
}
