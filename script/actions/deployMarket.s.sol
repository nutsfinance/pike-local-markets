// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IRBAC} from "@modules/common/RBACModule.sol";
import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IDoubleJumpRateModel} from "@interfaces/IDoubleJumpRateModel.sol";
import {IFactory} from "@factory/interfaces/IFactory.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {IOracleEngine} from "@oracles/interfaces/IOracleEngine.sol";
import {Timelock} from "@governance/Timelock.sol";
import {CustomRateFeedWrapper} from "@oracles/CustomRateFeedWrapper.sol";
import {MockTestToken} from "test/mocks/MockToken.sol";
import {MockProvider} from "test/mocks/MockOracle.sol";
import {Config, console} from "../Config.sol";

contract DeployMarket is Config {
    struct InterestRateModel {
        uint256 baseRate;
        uint256 initialMultiplier;
        uint256 firstKinkMultiplier;
        uint256 secondKinkMultiplier;
        uint256 firstKink;
        uint256 secondKink;
        uint256 borrowRateMaxMantissa;
    }

    struct MarketConfig {
        string name;
        string symbol;
        address baseToken;
        uint8 decimals;
        uint256 initialExchangeRateMantissa;
        uint256 reserveFactorMantissa;
        uint256 protocolSeizeShareMantissa;
        uint256 collateralFactorMantissa;
        uint256 liquidationThresholdMantissa;
        uint256 liquidationIncentiveMantissa;
        uint256 closeFactor;
        uint256 supplyCap;
        uint256 borrowCap;
        InterestRateModel irm;
        // oracle addresses resolved later
        address mainProvider;
        address fallbackProvider;
    }

    // provider address file format
    struct ProviderAddresses {
        address chainlinkCompositeProxy;
        address chainlinkProviderProxy;
        address pythProviderProxy;
    }

    // parsed oracle result
    struct OracleParsed {
        address provider;
        address[] feeds;
        bool[] invertRates;
        uint256[] maxStalePeriods;
    }

    string PATH;
    IFactory factory;
    IRiskEngine re;
    IOracleEngine oe;
    Timelock tm;
    MockProvider mp;

    uint256 protocolId;
    string chain;
    bool useSafe;
    bool dryRun;

    constructor() {
        PATH = "";
    }

    /* -------------------------------------------------------------------------
       Read markets from script/configs/{chain}.json
       base JSON path:
         .versions."<VERSION>".protocol-ids."<PROTOCOL_ID>"
       markets are keys that startWith "market-"
       ---------------------------------------------------------------------- */

    function readMarketConfigs()
        internal
        view
        returns (MarketConfig[] memory, string memory json, string[] memory marketKeys)
    {
        string memory root = vm.projectRoot();
        string memory configPath =
            string(abi.encodePacked(root, "/script/configs/", chain, ".json"));
        json = vm.readFile(configPath);

        string memory version = vm.envString("VERSION");

        // pointer to protocol object
        string memory base = string(
            abi.encodePacked(
                ".versions.\"",
                version,
                "\".protocol-ids.\"",
                vm.toString(protocolId),
                "\""
            )
        );

        // list keys under protocol-id
        string[] memory allKeys = vm.parseJsonKeys(json, base);

        // count market-* keys
        uint256 count = 0;
        for (uint256 i = 0; i < allKeys.length; i++) {
            if (startsWith(allKeys[i], "market-")) count++;
        }

        marketKeys = new string[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < allKeys.length; i++) {
            if (startsWith(allKeys[i], "market-")) {
                marketKeys[idx++] = allKeys[i];
            }
        }

        MarketConfig[] memory configs = new MarketConfig[](marketKeys.length);

        for (uint256 i = 0; i < marketKeys.length; i++) {
            string memory marketPath = string(abi.encodePacked(base, ".", marketKeys[i]));

            // read basic fields
            configs[i].name =
                vm.parseJsonString(json, string(abi.encodePacked(marketPath, ".name")));
            configs[i].symbol =
                vm.parseJsonString(json, string(abi.encodePacked(marketPath, ".symbol")));
            configs[i].baseToken = vm.parseJsonAddress(
                json, string(abi.encodePacked(marketPath, ".baseToken"))
            );
            configs[i].decimals = uint8(
                vm.parseJsonUint(json, string(abi.encodePacked(marketPath, ".decimals")))
            );
            configs[i].initialExchangeRateMantissa = vm.parseJsonUint(
                json, string(abi.encodePacked(marketPath, ".initialExchangeRateMantissa"))
            );
            configs[i].reserveFactorMantissa = vm.parseJsonUint(
                json, string(abi.encodePacked(marketPath, ".reserveFactorMantissa"))
            );
            configs[i].protocolSeizeShareMantissa = vm.parseJsonUint(
                json, string(abi.encodePacked(marketPath, ".protocolSeizeShareMantissa"))
            );
            configs[i].collateralFactorMantissa = vm.parseJsonUint(
                json, string(abi.encodePacked(marketPath, ".collateralFactorMantissa"))
            );
            configs[i].liquidationThresholdMantissa = vm.parseJsonUint(
                json,
                string(abi.encodePacked(marketPath, ".liquidationThresholdMantissa"))
            );
            configs[i].liquidationIncentiveMantissa = vm.parseJsonUint(
                json,
                string(abi.encodePacked(marketPath, ".liquidationIncentiveMantissa"))
            );
            configs[i].closeFactor = vm.parseJsonUint(
                json, string(abi.encodePacked(marketPath, ".closeFactor"))
            );
            configs[i].supplyCap =
                vm.parseJsonUint(json, string(abi.encodePacked(marketPath, ".supplyCap")));
            configs[i].borrowCap =
                vm.parseJsonUint(json, string(abi.encodePacked(marketPath, ".borrowCap")));

            // interest rate model nested
            configs[i].irm.baseRate = vm.parseJsonUint(
                json, string(abi.encodePacked(marketPath, ".interestRateModel.baseRate"))
            );
            configs[i].irm.initialMultiplier = vm.parseJsonUint(
                json,
                string(
                    abi.encodePacked(marketPath, ".interestRateModel.initialMultiplier")
                )
            );
            configs[i].irm.firstKinkMultiplier = vm.parseJsonUint(
                json,
                string(
                    abi.encodePacked(marketPath, ".interestRateModel.firstKinkMultiplier")
                )
            );
            configs[i].irm.secondKinkMultiplier = vm.parseJsonUint(
                json,
                string(
                    abi.encodePacked(
                        marketPath, ".interestRateModel.secondKinkMultiplier"
                    )
                )
            );
            configs[i].irm.firstKink = vm.parseJsonUint(
                json, string(abi.encodePacked(marketPath, ".interestRateModel.firstKink"))
            );
            configs[i].irm.secondKink = vm.parseJsonUint(
                json,
                string(abi.encodePacked(marketPath, ".interestRateModel.secondKink"))
            );
            configs[i].irm.borrowRateMaxMantissa = vm.parseJsonUint(
                json,
                string(
                    abi.encodePacked(
                        marketPath, ".interestRateModel.borrowRateMaxMantissa"
                    )
                )
            );

            // Note: mainProvider/fallbackProvider will be resolved later in buildOracleForMarket
            // keep zero here
            configs[i].mainProvider = address(0);
            configs[i].fallbackProvider = address(0);
        }

        return (configs, json, marketKeys);
    }

    /* -------------------------------------------------------------------------
       Helpers: load provider list from deployments/<version>/<chain>/oracle-providers.json
       ---------------------------------------------------------------------- */

    function loadProviderAddresses() internal view returns (ProviderAddresses memory p) {
        string memory baseDir = dryRun
            ? string(
                abi.encodePacked(
                    vm.projectRoot(),
                    "/deployments/",
                    vm.envString("VERSION"),
                    "/",
                    chain,
                    "/dry-run"
                )
            )
            : string(
                abi.encodePacked(
                    vm.projectRoot(), "/deployments/", vm.envString("VERSION"), "/", chain
                )
            );
        string memory path = string(abi.encodePacked(baseDir, "/oracle-providers.json"));
        if (!vm.exists(path)) return p;
        string memory json = vm.readFile(path);

        // try parse, ignore missing
        try vm.parseJsonAddress(json, ".chainlinkCompositeProxy") returns (address a) {
            p.chainlinkCompositeProxy = a;
        } catch {}
        try vm.parseJsonAddress(json, ".chainlinkProviderProxy") returns (address a) {
            p.chainlinkProviderProxy = a;
        } catch {}
        try vm.parseJsonAddress(json, ".pythProviderProxy") returns (address a) {
            p.pythProviderProxy = a;
        } catch {}
    }

    function _resolveProviderName(
        string memory providerName,
        address explicit,
        ProviderAddresses memory p
    ) internal pure returns (address) {
        if (explicit != address(0)) return explicit;
        bytes32 h = keccak256(bytes(providerName));
        if (h == keccak256(bytes("ChainlinkOracleComposite"))) {
            return p.chainlinkCompositeProxy;
        }
        if (h == keccak256(bytes("ChainlinkOracle"))) return p.chainlinkProviderProxy;
        if (h == keccak256(bytes("PythOracleProvider"))) return p.pythProviderProxy;
        return address(0);
    }

    /* -------------------------------------------------------------------------
       Feed handling: for a feed at path feedsPathPrefix.<index>:
         - try parsing as address => use directly
         - else parse as object with { type, target, decimals, callData } and deploy wrapper
       Save deployed wrappers to oracleWrappers.json (protocol folder)
       ---------------------------------------------------------------------- */

    function _processFeedsAndMaybeDeploy(
        string memory json,
        string memory feedsPathPrefix,
        string memory chain,
        string memory marketSymbol
    ) internal returns (address[] memory processed) {
        string[] memory feedKeys = vm.parseJsonKeys(json, feedsPathPrefix);
        uint256 n = feedKeys.length;
        processed = new address[](n);

        string memory wrappersPath = string(
            abi.encodePacked(
                getBaseDir(dryRun),
                "/protocol-",
                vm.toString(protocolId),
                "/oracleWrappers.json"
            )
        );

        for (uint256 i = 0; i < n; i++) {
            processed[i] =
                _processSingleFeed(json, feedsPathPrefix, i, marketSymbol, wrappersPath);
        }
    }

    function _processSingleFeed(
        string memory json,
        string memory feedsPathPrefix,
        uint256 index,
        string memory marketSymbol,
        string memory wrappersPath
    ) internal returns (address) {
        string memory thisFeedPath =
            string(abi.encodePacked(feedsPathPrefix, ".", vm.toString(index)));

        // try as address
        try vm.parseJsonAddress(json, thisFeedPath) returns (address addr) {
            return addr;
        } catch {}

        // parse as object
        string memory typ =
            vm.parseJsonString(json, string(abi.encodePacked(thisFeedPath, ".type")));
        require(
            keccak256(bytes(typ)) == keccak256(bytes("CustomRateFeedWrapper")),
            "unsupported feed object"
        );

        address target =
            vm.parseJsonAddress(json, string(abi.encodePacked(thisFeedPath, ".target")));
        uint8 decimals = uint8(
            vm.parseJsonUint(json, string(abi.encodePacked(thisFeedPath, ".decimals")))
        );
        bytes memory callData =
            vm.parseJsonBytes(json, string(abi.encodePacked(thisFeedPath, ".callData")));

        // try to reuse existing wrapper
        address existing = _readExistingWrapper(wrappersPath, marketSymbol);
        if (existing != address(0)) {
            console.log("Re-using existing wrapper for %s -> %s", marketSymbol, existing);
            return existing;
        }

        // deploy wrapper
        address wrapperAddr = dryRun
            ? address(new CustomRateFeedWrapper(target, decimals, callData))
            : _deployWrapper(target, decimals, callData);

        console.log(dryRun ? "dry-run wrapper:" : "deployed wrapper:", wrapperAddr);

        _saveWrapper(wrappersPath, vm.toLowercase(marketSymbol), wrapperAddr);

        return wrapperAddr;
    }

    function _readExistingWrapper(string memory wrappersPath, string memory marketSymbol)
        internal
        view
        returns (address)
    {
        if (!vm.exists(wrappersPath)) return address(0);
        string memory wjson = vm.readFile(wrappersPath);
        try vm.parseJsonAddress(
            wjson, string(abi.encodePacked(".", vm.toLowercase(marketSymbol)))
        ) returns (address a) {
            return a;
        } catch {
            return address(0);
        }
    }

    function _deployWrapper(address target, uint8 decimals, bytes memory callData)
        internal
        returns (address)
    {
        uint256 pk = vm.parseUint(vm.envString("PRIVATE_KEY"));
        vm.startBroadcast(pk);
        CustomRateFeedWrapper w = new CustomRateFeedWrapper(target, decimals, callData);
        vm.stopBroadcast();
        return address(w);
    }

    function _saveWrapper(string memory outputPath, string memory symbol, address wrapper)
        internal
    {
        string memory existingJson =
            vm.exists(outputPath) ? vm.readFile(outputPath) : "{}";
        string memory obj = "oracleWrappers";
        string[] memory keys = vm.parseJsonKeys(existingJson, ".");
        for (uint256 i = 0; i < keys.length; i++) {
            string memory key = keys[i];
            if (keccak256(bytes(key)) != keccak256(bytes(symbol))) {
                address a =
                    vm.parseJsonAddress(existingJson, string(abi.encodePacked(".", key)));
                vm.serializeAddress(obj, key, a);
            }
        }
        string memory updated = vm.serializeAddress(obj, symbol, wrapper);
        vm.writeFile(outputPath, updated);
        console.log("saved wrapper:", outputPath);
    }

    // small helpers for parsing arrays (no convenience VM arrays assumed)
    function _parseBoolArray(string memory json, string memory path)
        internal
        view
        returns (bool[] memory out)
    {
        string[] memory keys = vm.parseJsonKeys(json, path);
        out = new bool[](keys.length);
        for (uint256 i = 0; i < keys.length; i++) {
            out[i] = vm.parseJsonBool(
                json, string(abi.encodePacked(path, ".", vm.toString(i)))
            );
        }
    }

    function _parseUintArray(string memory json, string memory path)
        internal
        view
        returns (uint256[] memory out)
    {
        string[] memory keys = vm.parseJsonKeys(json, path);
        out = new uint256[](keys.length);
        for (uint256 i = 0; i < keys.length; i++) {
            out[i] = vm.parseJsonUint(
                json, string(abi.encodePacked(path, ".", vm.toString(i)))
            );
        }
    }

    function buildOracleForMarket(
        string memory json,
        string memory marketPath,
        bool useSafe,
        bool dryRun,
        ProviderAddresses memory providers
    ) internal returns (OracleParsed memory mainOut, OracleParsed memory fbOut) {
        mainOut = _buildSingleOracle(
            json, marketPath, ".oracleConfiguration.mainOracle", providers
        );

        // fallback
        if (_hasFallback(json, marketPath)) {
            fbOut = _buildSingleOracle(
                json, marketPath, ".oracleConfiguration.fallbackOracle", providers
            );
        } else {
            fbOut.provider = address(0);
        }
    }

    function _buildSingleOracle(
        string memory json,
        string memory marketPath,
        string memory prefix,
        ProviderAddresses memory providers
    ) internal returns (OracleParsed memory o) {
        string memory fullPrefix = string(abi.encodePacked(marketPath, prefix));

        // provider
        string memory provName =
            vm.parseJsonString(json, string(abi.encodePacked(fullPrefix, ".provider")));
        address explicitProv = address(0);
        try vm.parseJsonAddress(
            json, string(abi.encodePacked(fullPrefix, ".providerAddress"))
        ) returns (address a) {
            explicitProv = a;
        } catch {}
        o.provider = _resolveProviderName(provName, explicitProv, providers);

        // feeds
        string memory feedsPrefix = string(abi.encodePacked(fullPrefix, ".feeds"));
        o.feeds = _processFeedsAndMaybeDeploy(
            json,
            feedsPrefix,
            chain,
            vm.parseJsonString(json, string(abi.encodePacked(marketPath, ".symbol")))
        );

        // invert & stale arrays
        o.invertRates =
            _parseBoolArray(json, string(abi.encodePacked(fullPrefix, ".invertRates")));
        o.maxStalePeriods = _parseUintArray(
            json, string(abi.encodePacked(fullPrefix, ".maxStalePeriods"))
        );
    }

    function _hasFallback(string memory json, string memory marketPath)
        internal
        view
        returns (bool)
    {
        bool hasFallback = false;
        try vm.parseJson(
            json,
            string(abi.encodePacked(marketPath, ".oracleConfiguration.fallbackOracle"))
        ) returns (bytes memory b) {
            if (b.length > 2) hasFallback = true;
        } catch {}
        return hasFallback;
    }

    /* -------------------------------------------------------------------------
       Main entry point (run) — wire everything together and call existing functions
       ---------------------------------------------------------------------- */

    function run() public payable {
        chain = vm.envString("CHAIN");
        uint256 chainId = vm.envUint("CHAIN_ID");
        protocolId = vm.envUint("PROTOCOL_ID");
        dryRun = vm.envBool("DRY_RUN");
        address safeAddress = vm.envOr("SAFE_ADDRESS", address(0));
        useSafe = safeAddress != address(0);

        console.log("safeAddress: %s, useSafe: %s", safeAddress, useSafe);

        (
            address factoryAddress,
            address riskEngineAddress,
            address oracleEngineAddress,
            address timelockAddress
        ) = readDeploymentData(protocolId);

        setUp();
        vm.createSelectFork(vm.envString(rpcs[chainId]));

        factory = IFactory(factoryAddress);
        re = IRiskEngine(riskEngineAddress);
        oe = IOracleEngine(oracleEngineAddress);
        tm = Timelock(payable(timelockAddress));

        (MarketConfig[] memory markets, string memory json, string[] memory marketKeys) =
            readMarketConfigs();

        ProviderAddresses memory providers = loadProviderAddresses();

        for (uint256 i = 0; i < markets.length; i++) {
            MarketConfig memory cfg = markets[i];
            string memory marketKey = marketKeys[i];
            string memory marketPath =
                _buildMarketPath(vm.envString("VERSION"), marketKey);

            string memory marketSymbol = cfg.symbol;
            string memory mkLower = vm.toLowercase(marketSymbol);

            string memory mkKey = string(abi.encodePacked("market-", mkLower));

            if (isMarketDeployed(mkKey)) {
                console.log("Market %s already deployed, skipping", mkKey);
                continue;
            }

            // deploy market
            IPToken pToken = deployMarket(cfg);

            // build oracle config (deploy wrappers if needed)
            (OracleParsed memory mainO, OracleParsed memory fbO) =
                buildOracleForMarket(json, marketPath, useSafe, dryRun, providers);

            // set asset config - adapt to IOracleEngine.setAssetConfig signature
            // Here assuming setAssetConfig(asset, providerAddr, fallbackAddr, someUintA, someUintB)
            // If your setAssetConfig expects arrays, change encoding accordingly.
            bytes memory oracleCalldata = abi.encodeWithSelector(
                oe.setAssetConfig.selector,
                pToken.asset(),
                mainO.provider,
                fbO.provider == address(0) ? address(0) : fbO.provider,
                0,
                0
            );

            // Configure risk and oracle via timelock (same pattern as before)
            IRiskEngine.BaseConfiguration memory riskConfig = IRiskEngine
                .BaseConfiguration(
                cfg.collateralFactorMantissa,
                cfg.liquidationThresholdMantissa,
                cfg.liquidationIncentiveMantissa
            );

            bytes memory riskConfigCalldata =
                abi.encodeWithSelector(re.configureMarket.selector, pToken, riskConfig);
            bytes memory closeFactorCalldata = abi.encodeWithSelector(
                re.setCloseFactor.selector, address(pToken), cfg.closeFactor
            );

            if (useSafe) {
                // schedule via timelock/executeSingle (existing code path)
                executeSingle(
                    address(tm),
                    0,
                    abi.encodeWithSelector(
                        tm.emergencyExecute.selector, address(oe), 0, oracleCalldata
                    ),
                    true
                );
                executeSingle(
                    address(tm),
                    0,
                    abi.encodeWithSelector(
                        tm.emergencyExecute.selector, address(re), 0, riskConfigCalldata
                    ),
                    true
                );
                executeSingle(
                    address(tm),
                    0,
                    abi.encodeWithSelector(
                        tm.emergencyExecute.selector, address(re), 0, closeFactorCalldata
                    ),
                    true
                );
            } else {
                uint256 pk = vm.parseUint(vm.envString("PRIVATE_KEY"));
                vm.startBroadcast(pk);
                tm.emergencyExecute(address(oe), 0, oracleCalldata);
                tm.emergencyExecute(address(re), 0, riskConfigCalldata);
                tm.emergencyExecute(address(re), 0, closeFactorCalldata);
                vm.stopBroadcast();
            }

            // set caps
            setMarketCaps(pToken, cfg);

            // configure IRM
            configureInterestRateModel(pToken, cfg);

            // Persist deployed market
            updateDeploymentData(mkKey, address(pToken));
        }
    }

    function isMarketDeployed(string memory marketKey) internal view returns (bool) {
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
                baseDir, "/protocol-", vm.toString(protocolId), "/deployment-data.json"
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

    function updateDeploymentData(string memory marketKey, address marketAddress)
        internal
    {
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
                baseDir, "/protocol-", vm.toString(protocolId), "/deployment-data.json"
            )
        );

        string memory existingJson = "{}";
        if (vm.exists(deploymentPath)) {
            existingJson = vm.readFile(deploymentPath);
        }

        string memory obj = "deploymentData";
        string[] memory keys = vm.parseJsonKeys(existingJson, ".");
        for (uint256 i = 0; i < keys.length; i++) {
            string memory key = keys[i];
            if (
                keccak256(abi.encodePacked(key)) != keccak256(abi.encodePacked(marketKey))
            ) {
                bytes memory valueBytes =
                    vm.parseJson(existingJson, string(abi.encodePacked(".", key)));
                if (startsWith(key, "market-")) {
                    address addr = abi.decode(valueBytes, (address));
                    vm.serializeAddress(obj, key, addr);
                }
            }
        }

        string memory updatedJson = vm.serializeAddress(obj, marketKey, marketAddress);
        vm.writeFile(deploymentPath, updatedJson);
    }

    function deployMarket(MarketConfig memory config) internal returns (IPToken) {
        IFactory.PTokenSetup memory pTokenSetup = IFactory.PTokenSetup(
            protocolId,
            config.baseToken,
            config.initialExchangeRateMantissa,
            config.reserveFactorMantissa,
            config.protocolSeizeShareMantissa,
            config.irm.borrowRateMaxMantissa,
            config.name,
            config.symbol,
            config.decimals
        );

        console.log("Deploying market: %s", config.name);
        bytes memory deployCalldata =
            abi.encodeWithSelector(factory.deployMarket.selector, pTokenSetup);

        address pTokenAddress;
        if (useSafe) {
            vm.prank(address(tm));
            (bool success, bytes memory returnData) =
                address(factory).call(deployCalldata);
            require(success, "Simulation failed: deployMarket reverted");
            pTokenAddress = abi.decode(returnData, (address));
        } else {
            vm.startBroadcast(adminPrivateKey);
            tm.emergencyExecute(address(factory), 0, deployCalldata);
            vm.stopBroadcast();
            pTokenAddress = factory.getMarket(
                protocolId, factory.getProtocolInfo(protocolId).numOfMarkets - 1
            );
        }

        return IPToken(pTokenAddress);
    }

    function setMarketCaps(IPToken pToken, MarketConfig memory config) internal {
        IPToken[] memory markets = new IPToken[](1);
        markets[0] = pToken;
        uint256[] memory caps = new uint256[](1);

        caps[0] = config.supplyCap;
        bytes memory supplyCapCalldata =
            abi.encodeWithSelector(re.setMarketSupplyCaps.selector, markets, caps);

        caps[0] = config.borrowCap;
        bytes memory borrowCapCalldata =
            abi.encodeWithSelector(re.setMarketBorrowCaps.selector, markets, caps);

        if (useSafe) {
            executeSingle(
                address(tm),
                0,
                abi.encodeWithSelector(
                    tm.emergencyExecute.selector, address(re), 0, supplyCapCalldata
                ),
                true
            );
            executeSingle(
                address(tm),
                0,
                abi.encodeWithSelector(
                    tm.emergencyExecute.selector, address(re), 0, borrowCapCalldata
                ),
                true
            );
        } else {
            vm.startBroadcast(adminPrivateKey);
            tm.emergencyExecute(address(re), 0, supplyCapCalldata);
            tm.emergencyExecute(address(re), 0, borrowCapCalldata);
            vm.stopBroadcast();
        }
    }

    function configureInterestRateModel(IPToken pToken, MarketConfig memory config)
        internal
    {
        bytes memory irmCalldata = abi.encodeWithSelector(
            IDoubleJumpRateModel.configureInterestRateModel.selector,
            config.irm.baseRate,
            config.irm.initialMultiplier,
            config.irm.firstKinkMultiplier,
            config.irm.secondKinkMultiplier,
            config.irm.firstKink,
            config.irm.secondKink
        );

        if (useSafe) {
            executeSingle(
                address(tm),
                0,
                abi.encodeWithSelector(
                    tm.emergencyExecute.selector, address(pToken), 0, irmCalldata
                ),
                true
            );
        } else {
            vm.startBroadcast(adminPrivateKey);
            tm.emergencyExecute(address(pToken), 0, irmCalldata);
            vm.stopBroadcast();
        }
    }

    function _buildMarketPath(string memory version, string memory marketKey)
        internal
        view
        returns (string memory)
    {
        return string(
            abi.encodePacked(
                ".versions.\"",
                version,
                "\".protocol-ids.\"",
                vm.toString(protocolId),
                "\".",
                marketKey
            )
        );
    }
}
