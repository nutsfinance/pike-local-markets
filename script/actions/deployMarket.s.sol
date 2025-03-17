// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IRBAC} from "@modules/common/RBACModule.sol";
import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IDoubleJumpRateModel} from "@interfaces/IDoubleJumpRateModel.sol";
import {IFactory} from "@factory/interfaces/IFactory.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {IOracleEngine} from "@oracles/interfaces/IOracleEngine.sol";
import {Timelock} from "@governance/Timelock.sol";
import {MockTestToken} from "test/mocks/MockToken.sol";
import {MockProvider} from "test/mocks/MockOracle.sol";

import {Config, console} from "../Config.sol";

contract Market is Config {
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
        uint256 baseRatePerYear;
        uint256 multiplierPerYear;
        uint256 firstJumpMultiplierPerYear;
        uint256 secondJumpMultiplierPerYear;
        uint256 firstKink;
        uint256 secondKink;
        address mainProvider;
        address fallbackProvider;
    }

    string PATH;
    IFactory factory;
    IRiskEngine re;
    IOracleEngine oe;
    Timelock tm;
    MockProvider mp;

    constructor() Config() {
        PATH = "";
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
                    baseRatePerYear: vm.parseJsonUint(
                        json, string(abi.encodePacked(marketPath, ".baseRatePerYear"))
                    ),
                    multiplierPerYear: vm.parseJsonUint(
                        json, string(abi.encodePacked(marketPath, ".multiplierPerYear"))
                    ),
                    firstJumpMultiplierPerYear: vm.parseJsonUint(
                        json,
                        string(abi.encodePacked(marketPath, ".firstJumpMultiplierPerYear"))
                    ),
                    secondJumpMultiplierPerYear: vm.parseJsonUint(
                        json,
                        string(abi.encodePacked(marketPath, ".secondJumpMultiplierPerYear"))
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

    function isMarketDeployed(
        string memory chain,
        uint256 protocolId,
        string memory marketKey
    ) internal returns (bool) {
        bool isDryRun = vm.envBool("DRY_RUN");
        string memory root = vm.projectRoot();
        string memory baseDir = isDryRun
            ? string(
                abi.encodePacked(
                    root, "/deployments/", vm.envString("VERSION"), "/", chain, "/dry-run"
                )
            )
            : string(
                abi.encodePacked(root, "/deployments/", vm.envString("VERSION"), "/", chain)
            );

        string memory deploymentPath = string(
            abi.encodePacked(
                baseDir, "/protocol-", vm.toString(protocolId), "/deploymentData.json"
            )
        );
        if (!vm.exists(deploymentPath)) {
            return false;
        }

        string memory json = vm.readFile(deploymentPath);
        try vm.parseJsonAddress(json, string(abi.encodePacked(".", marketKey))) returns (
            address
        ) {
            return true;
        } catch {
            return false;
        }
    }

    function updateDeploymentData(
        string memory chain,
        uint256 protocolId,
        string memory marketKey,
        address marketAddress
    ) internal {
        bool isDryRun = vm.envBool("DRY_RUN");
        string memory root = vm.projectRoot();
        string memory baseDir = isDryRun
            ? string(
                abi.encodePacked(
                    root, "/deployments/", vm.envString("VERSION"), "/", chain, "/dry-run"
                )
            )
            : string(
                abi.encodePacked(root, "/deployments/", vm.envString("VERSION"), "/", chain)
            );

        string memory deploymentPath = string(
            abi.encodePacked(
                baseDir, "/protocol-", vm.toString(protocolId), "/deploymentData.json"
            )
        );

        console.log("Updating deployment data at: %s", deploymentPath);

        // Read existing JSON if it exists, otherwise start with an empty object
        string memory existingJson;
        if (vm.exists(deploymentPath)) {
            existingJson = vm.readFile(deploymentPath);
        } else {
            existingJson = "{}"; // Start with empty object if file doesn't exist
        }

        // Use Foundry's vm.serialize* to build the updated JSON
        string memory obj = "deploymentData"; // Temporary object name for serialization

        // Parse existing keys and re-add them to the new JSON
        string[] memory keys = vm.parseJsonKeys(existingJson, ".");
        for (uint256 i = 0; i < keys.length; i++) {
            string memory key = keys[i];
            if (
                keccak256(abi.encodePacked(key)) != keccak256(abi.encodePacked(marketKey))
            ) {
                // Skip if key matches the new marketKey
                bytes memory valueBytes =
                    vm.parseJson(existingJson, string(abi.encodePacked(".", key)));
                // Determine type and serialize accordingly
                if (startsWith(key, "market-")) {
                    address addr = abi.decode(valueBytes, (address));
                    vm.serializeAddress(obj, key, addr);
                } else if (
                    keccak256(abi.encodePacked(key))
                        == keccak256(abi.encodePacked("protocolId"))
                ) {
                    uint256 val = abi.decode(valueBytes, (uint256));
                    vm.serializeUint(obj, key, val);
                } else if (
                    keccak256(abi.encodePacked(key))
                        == keccak256(abi.encodePacked("deploymentTimestamp"))
                ) {
                    uint256 val = abi.decode(valueBytes, (uint256));
                    vm.serializeUint(obj, key, val);
                } else if (
                    keccak256(abi.encodePacked(key))
                        == keccak256(abi.encodePacked("isDryRun"))
                ) {
                    bool val = abi.decode(valueBytes, (bool));
                    vm.serializeBool(obj, key, val);
                } else {
                    address addr = abi.decode(valueBytes, (address));
                    vm.serializeAddress(obj, key, addr);
                }
            }
        }

        // Add or update the new market key-value pair
        string memory updatedJson = vm.serializeAddress(obj, marketKey, marketAddress);

        console.log("Updated JSON: %s", updatedJson);

        // Write the updated JSON back to the file
        vm.writeFile(deploymentPath, updatedJson);
        console.log(
            "Updated deployment data with %s at %s", marketKey, vm.toString(marketAddress)
        );
    }

    function run() public payable {
        string memory chain = vm.envString("CHAIN");
        uint256 chainId = vm.envUint("CHAIN_ID");
        uint256 protocolId = vm.envUint("PROTOCOL_ID");

        (
            address factoryAddress,
            address riskEngineAddress,
            address oracleEngineAddress,
            address timelockAddress
        ) = readDeploymentData(chain, protocolId);

        setUp();
        vm.createSelectFork(vm.envString(rpcs[chainId]));

        factory = IFactory(factoryAddress);
        re = IRiskEngine(riskEngineAddress);
        oe = IOracleEngine(oracleEngineAddress);
        tm = Timelock(payable(timelockAddress));

        MarketConfig[] memory marketConfigs = readMarketConfigs(chain, protocolId);

        vm.startBroadcast(adminPrivateKey);
        deployAllMarkets(chain, protocolId, marketConfigs);
        vm.stopBroadcast();
    }

    function deployAllMarkets(
        string memory chain,
        uint256 protocolId,
        MarketConfig[] memory marketConfigs
    ) internal {
        for (uint256 i = 0; i < marketConfigs.length; i++) {
            MarketConfig memory config = marketConfigs[i];
            string memory marketKey =
                string(abi.encodePacked("market-", vm.toLowercase(config.symbol)));

            if (isMarketDeployed(chain, protocolId, marketKey)) {
                console.log("Market %s already deployed, skipping", marketKey);
                continue;
            }

            IPToken pToken = deployMarket(protocolId, config);
            configureMarket(pToken, config);
            setMarketCaps(pToken, config);
            configureInterestRateModel(pToken, config);
            updateDeploymentData(chain, protocolId, marketKey, address(pToken));
        }
    }

    function deployMarket(uint256 protocolId, MarketConfig memory config)
        internal
        returns (IPToken)
    {
        IFactory.PTokenSetup memory pTokenSetup = IFactory.PTokenSetup(
            protocolId,
            config.baseToken,
            config.initialExchangeRateMantissa,
            config.reserveFactorMantissa,
            config.protocolSeizeShareMantissa,
            config.borrowRateMaxMantissa,
            config.name,
            config.symbol,
            config.decimals
        );

        console.log("Deploying market: %s", config.name);
        tm.emergencyExecute(
            address(factory),
            0,
            abi.encodeWithSelector(factory.deployMarket.selector, pTokenSetup)
        );

        IPToken pToken = IPToken(
            factory.getMarket(
                protocolId, factory.getProtocolInfo(protocolId).numOfMarkets - 1
            )
        );
        console.log("Deployed: %s at %s", config.name, address(pToken));

        return pToken;
    }

    function configureMarket(IPToken pToken, MarketConfig memory config) internal {
        tm.emergencyExecute(
            address(oe),
            0,
            abi.encodeWithSelector(
                oe.setAssetConfig.selector,
                pToken.asset(),
                config.mainProvider,
                config.fallbackProvider,
                0,
                0
            )
        );

        IRiskEngine.BaseConfiguration memory riskConfig = IRiskEngine.BaseConfiguration(
            config.collateralFactorMantissa,
            config.liquidationThresholdMantissa,
            config.liquidationIncentiveMantissa
        );

        tm.emergencyExecute(
            address(re),
            0,
            abi.encodeWithSelector(re.configureMarket.selector, pToken, riskConfig)
        );
        tm.emergencyExecute(
            address(re),
            0,
            abi.encodeWithSelector(
                re.setCloseFactor.selector, address(pToken), config.closeFactor
            )
        );
    }

    function setMarketCaps(IPToken pToken, MarketConfig memory config) internal {
        IPToken[] memory markets = new IPToken[](1);
        markets[0] = pToken;
        uint256[] memory caps = new uint256[](1);

        caps[0] = config.supplyCap;
        tm.emergencyExecute(
            address(re),
            0,
            abi.encodeWithSelector(re.setMarketSupplyCaps.selector, markets, caps)
        );

        caps[0] = config.borrowCap;
        tm.emergencyExecute(
            address(re),
            0,
            abi.encodeWithSelector(re.setMarketBorrowCaps.selector, markets, caps)
        );
    }

    function configureInterestRateModel(IPToken pToken, MarketConfig memory config)
        internal
    {
        tm.emergencyExecute(
            address(pToken),
            0,
            abi.encodeWithSelector(
                IDoubleJumpRateModel.configureInterestRateModel.selector,
                config.baseRatePerYear,
                config.multiplierPerYear,
                config.firstJumpMultiplierPerYear,
                config.secondJumpMultiplierPerYear,
                config.firstKink,
                config.secondKink
            )
        );
    }
}
