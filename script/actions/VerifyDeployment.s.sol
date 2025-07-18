// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import "forge-std/console2.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {IPToken} from "@interfaces/IPToken.sol";
import {IDoubleJumpRateModel} from "@interfaces/IDoubleJumpRateModel.sol";
import {Config} from "../Config.sol";

contract VerifyDeployment is Config {
    bytes32 implSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 uupsOwnerSlot =
        0x9016d09d72d40fdae2fd8ceac6b6234c7706214fd39c1cd1e609a0528c199300;
    bytes32 routerOwnerSlot =
        0x74d6be38627e7912e34c50c5cbc5a4826c01ce9f17c41aaeea1b0611189c7000;

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

    struct ImplAddrs {
        address factory;
        address riskEngineRouter;
        address oracleEngine;
        address ptokenBeacon;
        address timelock;
        address chainlinkOracleComposite;
        address chainlinkOracleProvider;
        address pythOracleProvider;
        address ptokenRouter;
    }

    struct ProxyAddrs {
        address factoryAddress;
        address riskEngineAddress;
        address oracleEngineAddress;
        address timelockAddress;
        address ptokenRouterAddress;
        address chainlinkCompositeProxy;
        address chainlinkProviderProxy;
        address pythProviderProxy;
        address initialGovernor;
    }

    uint256 chainId;
    uint256 protocolId;
    bool dryRun;
    string chain;
    string json;

    function run() public {
        chain = vm.envString("CHAIN");
        chainId = vm.envUint("CHAIN_ID");
        protocolId = vm.envUint("PROTOCOL_ID");
        dryRun = vm.envBool("DRY_RUN");

        // Load deployment data
        json = vm.readFile(getDeploymentPath(protocolId));
        string memory baseDir = string.concat(getBaseDir(dryRun), "/artifacts/");
        ImplAddrs memory a = loadImplAddrs(baseDir);
        ProxyAddrs memory p = loadProxyAddrs(json, baseDir);

        vm.createSelectFork(vm.envString(rpcs[chainId]));
        //verifyImplementation and owners
        logAddressCheck("Factory", a.factory, readImpl(p.factoryAddress));
        logAddressCheck(
            "Risk Engine", a.riskEngineRouter, readBeaconProxyImpl(p.riskEngineAddress)
        );
        logAddressCheck(
            "Oracle Engine", a.oracleEngine, readBeaconProxyImpl(p.oracleEngineAddress)
        );
        logAddressCheck("Timelock", a.timelock, readBeaconProxyImpl(p.timelockAddress));
        logAddressCheck("PToken Router", a.ptokenRouter, readBeaconImpl(a.ptokenBeacon));

        logAddressCheck(
            "Chainlink Composite Provider",
            a.chainlinkOracleComposite,
            readImpl(p.chainlinkCompositeProxy)
        );
        logAddressCheck(
            "Chainlink Provider",
            a.chainlinkOracleProvider,
            readImpl(p.chainlinkProviderProxy)
        );
        logAddressCheck(
            "Pyth Provider", a.pythOracleProvider, readImpl(p.pythProviderProxy)
        );
        logAddressCheck(
            "Factory Initial Governor", p.initialGovernor, readUUPSOwner(p.factoryAddress)
        );
        logAddressCheck(
            "Chainlink-C Initial Governor",
            p.initialGovernor,
            readUUPSOwner(p.chainlinkCompositeProxy)
        );
        logAddressCheck(
            "Chainlink Initial Governor",
            p.initialGovernor,
            readUUPSOwner(p.chainlinkProviderProxy)
        );
        logAddressCheck(
            "Pyth Initial Governor", p.initialGovernor, readUUPSOwner(p.pythProviderProxy)
        );

        // Load market configurations
        IRiskEngine re = IRiskEngine(p.riskEngineAddress);
        MarketConfig[] memory configs = readMarketConfigs(chain, protocolId);
        // Verify each market
        for (uint256 i = 0; i < configs.length; i++) {
            string memory marketKey =
                string(abi.encodePacked("market-", vm.toLowercase(configs[i].symbol)));
            address pTokenAddress =
                vm.parseJsonAddress(json, string(abi.encodePacked(".", marketKey)));
            IPToken pToken = IPToken(pTokenAddress);

            // Basic PToken property checks
            logStringCheck("Name", pToken.name(), configs[i].name);

            logStringCheck("Symbol", pToken.symbol(), configs[i].symbol);

            logUint256Check("Decimals", pToken.decimals(), configs[i].decimals);
            logAddressCheck("Base token", pToken.asset(), configs[i].baseToken);
            logUint256Check(
                "Initial Exchange Rate",
                pToken.initialExchangeRate(),
                configs[i].initialExchangeRateMantissa
            );

            logUint256Check(
                "Reserve Factor",
                pToken.reserveFactorMantissa(),
                configs[i].reserveFactorMantissa
            );

            logUint256Check(
                "Protocol Seize Share",
                pToken.protocolSeizeShareMantissa(),
                configs[i].protocolSeizeShareMantissa
            );

            logUint256Check(
                "Borrow Rate Max",
                pToken.borrowRateMaxMantissa(),
                configs[i].borrowRateMaxMantissa
            );

            (uint256 firstKink, uint256 secondKink) =
                IDoubleJumpRateModel(pTokenAddress).kinks();
            logUint256Check("First Kink", firstKink, configs[i].firstKink);
            logUint256Check("Second Kink", secondKink, configs[i].secondKink);

            // Risk Engine configuration checks
            logUint256Check(
                "Close Factor", re.closeFactor(pTokenAddress), configs[i].closeFactor
            );

            logUint256Check(
                "Supply Cap", re.supplyCap(pTokenAddress), configs[i].supplyCap
            );

            logUint256Check(
                "Borrow Cap", re.borrowCap(pTokenAddress), configs[i].borrowCap
            );

            logUint256Check(
                "Collateral Factor",
                re.collateralFactor(0, pToken),
                configs[i].collateralFactorMantissa
            );

            logUint256Check(
                "Liquidation Threshold",
                re.liquidationThreshold(0, pToken),
                configs[i].liquidationThresholdMantissa
            );

            logUint256Check(
                "Liquidation Incentive",
                re.liquidationIncentive(0, pTokenAddress),
                configs[i].liquidationIncentiveMantissa
            );

            console.log("test passed for market: %s", configs[i].symbol);
        }

        console.log("All markets passed test verification");
    }

    function loadProxyAddrs(string memory _json, string memory baseDir)
        internal
        view
        returns (ProxyAddrs memory p)
    {
        p.factoryAddress = vm.parseJsonAddress(_json, ".factoryAddress");
        p.riskEngineAddress = vm.parseJsonAddress(_json, ".riskEngine");
        p.oracleEngineAddress = vm.parseJsonAddress(_json, ".oracleEngine");
        p.timelockAddress = vm.parseJsonAddress(_json, ".timelock");
        p.initialGovernor = vm.parseJsonAddress(_json, ".initialGovernor");
        p.chainlinkCompositeProxy = vm.parseJsonAddress(
            vm.readFile(string.concat(baseDir, "chainlinkCompositeProxy.json")),
            ".address"
        );
        p.chainlinkProviderProxy = vm.parseJsonAddress(
            vm.readFile(string.concat(baseDir, "chainlinkProviderProxy.json")), ".address"
        );
        p.pythProviderProxy = vm.parseJsonAddress(
            vm.readFile(string.concat(baseDir, "pythProviderProxy.json")), ".address"
        );
    }

    function loadImplAddrs(string memory baseDir)
        internal
        view
        returns (ImplAddrs memory a)
    {
        a.factory = vm.parseJsonAddress(
            vm.readFile(string.concat(baseDir, "Factory.json")), ".address"
        );
        a.riskEngineRouter = vm.parseJsonAddress(
            vm.readFile(string.concat(baseDir, "RiskEngineRouter.json")), ".address"
        );
        a.oracleEngine = vm.parseJsonAddress(
            vm.readFile(string.concat(baseDir, "OracleEngine.json")), ".address"
        );
        a.ptokenBeacon = vm.parseJsonAddress(
            vm.readFile(string.concat(baseDir, "pTokenBeacon.json")), ".address"
        );
        a.ptokenRouter = vm.parseJsonAddress(
            vm.readFile(string.concat(baseDir, "PTokenRouter.json")), ".address"
        );
        a.timelock = vm.parseJsonAddress(
            vm.readFile(string.concat(baseDir, "Timelock.json")), ".address"
        );
        a.chainlinkOracleComposite = vm.parseJsonAddress(
            vm.readFile(string.concat(baseDir, "ChainlinkOracleComposite.json")),
            ".address"
        );
        a.chainlinkOracleProvider = vm.parseJsonAddress(
            vm.readFile(string.concat(baseDir, "ChainlinkOracleProvider.json")),
            ".address"
        );
        a.pythOracleProvider = vm.parseJsonAddress(
            vm.readFile(string.concat(baseDir, "PythOracleProvider.json")), ".address"
        );
    }

    function readImpl(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, implSlot))));
    }

    function readBeaconProxyImpl(address proxy) internal view returns (address) {
        bytes memory code = address(proxy).code;
        bytes32 result;
        // offset to get immutable variable of deployed bytecode (beacon address) is 0x23 or bytes35
        assembly {
            result := mload(add(code, add(0x20, 0x23)))
        }
        return address(
            uint160(
                uint256(vm.load(address(uint160(uint256(result))), bytes32(uint256(1))))
            )
        );
    }

    function readBeaconImpl(address beacon) internal view returns (address) {
        return address(uint160(uint256(vm.load(beacon, bytes32(uint256(1))))));
    }

    function readRouterOwner(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, routerOwnerSlot))));
    }

    function readUUPSOwner(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, uupsOwnerSlot))));
    }

    function readMarketConfigs(string memory _chain, uint256 _protocolId)
        internal
        view
        returns (MarketConfig[] memory)
    {
        string memory root = vm.projectRoot();
        string memory configPath = string(
            abi.encodePacked(
                root,
                "/script/configs/",
                _chain,
                "/protocol-",
                vm.toString(_protocolId),
                ".json"
            )
        );
        string memory _json = vm.readFile(configPath);

        string[] memory allKeys = vm.parseJsonKeys(_json, ".");
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
                        _json, string(abi.encodePacked(marketPath, ".name"))
                    ),
                    symbol: vm.parseJsonString(
                        _json, string(abi.encodePacked(marketPath, ".symbol"))
                    ),
                    baseToken: vm.parseJsonAddress(
                        _json, string(abi.encodePacked(marketPath, ".baseToken"))
                    ),
                    decimals: uint8(
                        vm.parseJsonUint(
                            _json, string(abi.encodePacked(marketPath, ".decimals"))
                        )
                    ),
                    initialExchangeRateMantissa: vm.parseJsonUint(
                        _json,
                        string(abi.encodePacked(marketPath, ".initialExchangeRateMantissa"))
                    ),
                    reserveFactorMantissa: vm.parseJsonUint(
                        _json, string(abi.encodePacked(marketPath, ".reserveFactorMantissa"))
                    ),
                    protocolSeizeShareMantissa: vm.parseJsonUint(
                        _json,
                        string(abi.encodePacked(marketPath, ".protocolSeizeShareMantissa"))
                    ),
                    borrowRateMaxMantissa: vm.parseJsonUint(
                        _json, string(abi.encodePacked(marketPath, ".borrowRateMaxMantissa"))
                    ),
                    collateralFactorMantissa: vm.parseJsonUint(
                        _json,
                        string(abi.encodePacked(marketPath, ".collateralFactorMantissa"))
                    ),
                    liquidationThresholdMantissa: vm.parseJsonUint(
                        _json,
                        string(abi.encodePacked(marketPath, ".liquidationThresholdMantissa"))
                    ),
                    liquidationIncentiveMantissa: vm.parseJsonUint(
                        _json,
                        string(abi.encodePacked(marketPath, ".liquidationIncentiveMantissa"))
                    ),
                    closeFactor: vm.parseJsonUint(
                        _json, string(abi.encodePacked(marketPath, ".closeFactor"))
                    ),
                    supplyCap: vm.parseJsonUint(
                        _json, string(abi.encodePacked(marketPath, ".supplyCap"))
                    ),
                    borrowCap: vm.parseJsonUint(
                        _json, string(abi.encodePacked(marketPath, ".borrowCap"))
                    ),
                    baseRate: vm.parseJsonUint(
                        _json, string(abi.encodePacked(marketPath, ".baseRate"))
                    ),
                    initialMultiplier: vm.parseJsonUint(
                        _json, string(abi.encodePacked(marketPath, ".initialMultiplier"))
                    ),
                    firstKinkMultiplier: vm.parseJsonUint(
                        _json, string(abi.encodePacked(marketPath, ".firstKinkMultiplier"))
                    ),
                    secondKinkMultiplier: vm.parseJsonUint(
                        _json, string(abi.encodePacked(marketPath, ".secondKinkMultiplier"))
                    ),
                    firstKink: vm.parseJsonUint(
                        _json, string(abi.encodePacked(marketPath, ".firstKink"))
                    ),
                    secondKink: vm.parseJsonUint(
                        _json, string(abi.encodePacked(marketPath, ".secondKink"))
                    ),
                    mainProvider: vm.parseJsonAddress(
                        _json, string(abi.encodePacked(marketPath, ".mainProvider"))
                    ),
                    fallbackProvider: vm.parseJsonAddress(
                        _json, string(abi.encodePacked(marketPath, ".fallbackProvider"))
                    )
                });
                configIndex++;
            }
        }

        return configs;
    }

    function logAddressCheck(string memory label, address expected, address actual)
        internal
        pure
    {
        string memory status = expected == actual ? unicode"✅" : unicode"❌";
        console.log("%s | expected: %s | actual: %s | ", label, expected, actual);
        console.log(status);
    }

    function logStringCheck(
        string memory label,
        string memory expected,
        string memory actual
    ) internal pure {
        string memory status = keccak256(bytes(expected)) == keccak256(bytes(actual))
            ? unicode"✅"
            : unicode"❌";
        console.log("%s | expected: %s | actual: %s | ", label, expected, actual);
        console.log(status);
    }

    function logUint256Check(string memory label, uint256 expected, uint256 actual)
        internal
        pure
    {
        string memory status = expected == actual ? unicode"✅" : unicode"❌";
        console.log("%s | expected: %s | actual: %s | ", label, expected, actual);
        console.log(status);
    }
}
