// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IRBAC} from "@modules/common/RBACModule.sol";
import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IDoubleJumpRateModel} from "@interfaces/IDoubleJumpRateModel.sol";
import {IFactory} from "@factory/interfaces/IFactory.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {Timelock} from "@governance/Timelock.sol";

import {Config, console} from "../Config.sol";

contract EMode is Config {
    struct EModeConfig {
        uint8 categoryId;
        address[] ptokens;
        bool[] collateralPermissions;
        bool[] borrowPermissions;
        IRiskEngine.BaseConfiguration riskConfig;
    }

    IFactory factory;
    IRiskEngine re;
    Timelock tm;

    constructor() Config() {}

    function readEModeConfigs() internal returns (EModeConfig[] memory) {
        string memory configPath = vm.envString("CONFIG_PATH");
        if (!vm.exists(configPath)) {
            console.log(
                "No config file found at %s, skipping EMode configuration", configPath
            );
            return new EModeConfig[](0);
        }

        string memory json = vm.readFile(configPath);
        string[] memory allKeys = vm.parseJsonKeys(json, ".");

        uint256 emodeCount = 0;
        for (uint256 i = 0; i < allKeys.length; i++) {
            if (startsWith(allKeys[i], "emode-")) {
                emodeCount++;
            }
        }

        if (emodeCount == 0) {
            console.log("No emode-* keys found in config, skipping EMode configuration");
            return new EModeConfig[](0);
        }

        EModeConfig[] memory configs = new EModeConfig[](emodeCount);
        uint256 configIndex = 0;

        for (uint256 i = 0; i < allKeys.length; i++) {
            string memory emodeKey = allKeys[i];
            if (startsWith(emodeKey, "emode-")) {
                string memory emodePath = string(abi.encodePacked(".", emodeKey));
                configs[configIndex] = parseEModeConfig(json, emodePath);
                configIndex++;
            }
        }

        return configs;
    }

    function parseEModeConfig(string memory json, string memory emodePath)
        internal
        pure
        returns (EModeConfig memory config)
    {
        bytes memory ptokenData =
            vm.parseJson(json, string(abi.encodePacked(emodePath, ".ptokens")));
        address[] memory ptokens = abi.decode(ptokenData, (address[]));
        uint256 ptokenCount = ptokens.length;

        bool[] memory collateralPermissions = new bool[](ptokenCount);
        bool[] memory borrowPermissions = new bool[](ptokenCount);

        for (uint256 j = 0; j < ptokenCount; j++) {
            collateralPermissions[j] = vm.parseJsonBool(
                json,
                string(
                    abi.encodePacked(
                        emodePath, ".collateralPermissions[", vm.toString(j), "]"
                    )
                )
            );
            borrowPermissions[j] = vm.parseJsonBool(
                json,
                string(
                    abi.encodePacked(
                        emodePath, ".borrowPermissions[", vm.toString(j), "]"
                    )
                )
            );
        }

        config = EModeConfig({
            categoryId: uint8(
                vm.parseJsonUint(json, string(abi.encodePacked(emodePath, ".categoryId")))
            ),
            ptokens: ptokens,
            collateralPermissions: collateralPermissions,
            borrowPermissions: borrowPermissions,
            riskConfig: IRiskEngine.BaseConfiguration({
                collateralFactorMantissa: vm.parseJsonUint(
                    json,
                    string(abi.encodePacked(emodePath, ".riskConfig.collateralFactorMantissa"))
                ),
                liquidationThresholdMantissa: vm.parseJsonUint(
                    json,
                    string(
                        abi.encodePacked(emodePath, ".riskConfig.liquidationThresholdMantissa")
                    )
                ),
                liquidationIncentiveMantissa: vm.parseJsonUint(
                    json,
                    string(
                        abi.encodePacked(emodePath, ".riskConfig.liquidationIncentiveMantissa")
                    )
                )
            })
        });
    }

    function isEModeConfigured(string memory chain, uint256 protocolId, uint8 categoryId)
        internal
        returns (bool)
    {
        string memory emodePath = getEModeFilePath(chain, protocolId, categoryId);
        return vm.exists(emodePath);
    }

    function getEModeFilePath(string memory chain, uint256 protocolId, uint8 categoryId)
        internal
        view
        returns (string memory)
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
        return string(
            abi.encodePacked(
                baseDir,
                "/protocol-",
                vm.toString(protocolId),
                "/emode-",
                vm.toString(categoryId),
                ".json"
            )
        );
    }

    function writeEModeData(
        string memory chain,
        uint256 protocolId,
        uint8 categoryId,
        address[] memory ptokens,
        bool[] memory collateralPermissions,
        bool[] memory borrowPermissions,
        IRiskEngine.BaseConfiguration memory riskConfig
    ) internal {
        string memory emodePath = getEModeFilePath(chain, protocolId, categoryId);
        string memory obj = "emodeData";
        vm.serializeUint(obj, "categoryId", categoryId);

        uint256 collateralCount = 0;
        for (uint256 i = 0; i < ptokens.length; i++) {
            if (collateralPermissions[i]) {
                string memory key = string(
                    abi.encodePacked("collateralToken", vm.toString(collateralCount))
                );
                vm.serializeAddress(obj, key, ptokens[i]);
                collateralCount++;
            }
        }

        uint256 borrowCount = 0;
        for (uint256 i = 0; i < ptokens.length; i++) {
            if (borrowPermissions[i]) {
                string memory key =
                    string(abi.encodePacked("borrowableToken", vm.toString(borrowCount)));
                vm.serializeAddress(obj, key, ptokens[i]);
                borrowCount++;
            }
        }

        vm.serializeUint(
            obj, "collateralFactorMantissa", riskConfig.collateralFactorMantissa
        );
        vm.serializeUint(
            obj, "liquidationThresholdMantissa", riskConfig.liquidationThresholdMantissa
        );
        string memory finalJson = vm.serializeUint(
            obj, "liquidationIncentiveMantissa", riskConfig.liquidationIncentiveMantissa
        );

        writeJsonFile(emodePath, obj, finalJson);
    }

    function run() public payable {
        string memory chain = vm.envString("CHAIN");
        uint256 chainId = vm.envUint("CHAIN_ID");
        uint256 protocolId = vm.envUint("PROTOCOL_ID");

        (address factoryAddress, address riskEngineAddress,, address timelockAddress) =
            readDeploymentData(chain, protocolId);

        setUp();
        vm.createSelectFork(vm.envString(rpcs[chainId]));

        factory = IFactory(factoryAddress);
        re = IRiskEngine(riskEngineAddress);
        tm = Timelock(payable(timelockAddress));

        EModeConfig[] memory emodeConfigs = readEModeConfigs();
        if (emodeConfigs.length == 0) {
            console.log("No EMode configurations to process, exiting");
            return;
        }

        vm.startBroadcast(adminPrivateKey);
        configureAllEModes(emodeConfigs, chain, protocolId);
        vm.stopBroadcast();
    }

    function configureAllEModes(
        EModeConfig[] memory emodeConfigs,
        string memory chain,
        uint256 protocolId
    ) internal {
        for (uint256 i = 0; i < emodeConfigs.length; i++) {
            if (isEModeConfigured(chain, protocolId, emodeConfigs[i].categoryId)) {
                console.log(
                    "EMode %s already configured, skipping", emodeConfigs[i].categoryId
                );
                continue;
            }

            configureEMode(
                emodeConfigs[i].categoryId,
                emodeConfigs[i].ptokens,
                emodeConfigs[i].collateralPermissions,
                emodeConfigs[i].borrowPermissions,
                emodeConfigs[i].riskConfig
            );
            writeEModeData(
                chain,
                protocolId,
                emodeConfigs[i].categoryId,
                emodeConfigs[i].ptokens,
                emodeConfigs[i].collateralPermissions,
                emodeConfigs[i].borrowPermissions,
                emodeConfigs[i].riskConfig
            );
        }
    }

    function configureEMode(
        uint8 categoryId,
        address[] memory ptokens,
        bool[] memory collateralPermissions,
        bool[] memory borrowPermissions,
        IRiskEngine.BaseConfiguration memory config
    ) internal {
        console.log("=== Adding new EMode with ID %s ===", categoryId);
        for (uint256 i = 0; i < ptokens.length; i++) {
            console.log(
                "Token %s: Collateral=%s Borrow=%s",
                IPToken(ptokens[i]).symbol(),
                collateralPermissions[i],
                borrowPermissions[i]
            );
        }

        tm.emergencyExecute(
            address(re),
            0,
            abi.encodeWithSelector(
                re.supportEMode.selector,
                categoryId,
                true,
                ptokens,
                collateralPermissions,
                borrowPermissions
            )
        );

        tm.emergencyExecute(
            address(re),
            0,
            abi.encodeWithSelector(re.configureEMode.selector, categoryId, config)
        );
    }
}
