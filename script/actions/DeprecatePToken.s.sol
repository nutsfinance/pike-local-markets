// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IPToken} from "@interfaces/IPToken.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {Timelock} from "@governance/Timelock.sol";
import {Config} from "../Config.sol";
import {console} from "forge-std/console.sol";

contract DeprecatePToken is Config {
    function run() public payable {
        uint256 chainId = vm.envUint("CHAIN_ID");
        uint256 protocolId = vm.envUint("PROTOCOL_ID");
        string memory pTokenName = vm.envString("PTOKEN_NAME");

        setUp();
        vm.createSelectFork(vm.envString(rpcs[chainId]));

        string memory baseDir = getBaseDir(false);
        string memory deploymentPath = string(
            abi.encodePacked(
                baseDir, "/protocol-", vm.toString(protocolId), "/deployment-data.json"
            )
        );

        string memory dJson = vm.readFile(deploymentPath);

        // pToken (market-pusdc, market-pusdt, etc)
        string memory pTokenKey = string(abi.encodePacked("market-", pTokenName));
        address pTokenAddress =
            vm.parseJsonAddress(dJson, string(abi.encodePacked(".", pTokenKey)));
        require(pTokenAddress != address(0), "PToken not found");

        // risk engine
        address riskEngine = vm.parseJsonAddress(dJson, ".riskEngine");
        require(riskEngine != address(0), "RiskEngine missing");

        // timelock
        address timelock = vm.parseJsonAddress(dJson, ".timelock");
        require(timelock != address(0), "Timelock missing");

        console.log("Deprecating Market:", pTokenName);
        console.log("PToken Address:", pTokenAddress);
        console.log("RiskEngine:", riskEngine);
        console.log("Timelock:", timelock);

        IPToken pToken = IPToken(pTokenAddress);
        IRiskEngine re = IRiskEngine(riskEngine);
        Timelock tl = Timelock(payable(timelock));

        // set reserve factor to 100%
        bytes memory call1 =
            abi.encodeWithSelector(pToken.setReserveFactor.selector, 1e18);

        // set collateral factor to 0
        IRiskEngine.BaseConfiguration memory cfg = IRiskEngine.BaseConfiguration({
            collateralFactorMantissa: 0,
            liquidationThresholdMantissa: 0,
            liquidationIncentiveMantissa: 1e18
        });

        bytes memory call2 =
            abi.encodeWithSelector(re.configureMarket.selector, pToken, cfg);

        // -------------------
        // BATCH EXECUTION
        // -------------------

        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory payloads = new bytes[](2);

        targets[0] = pTokenAddress;
        targets[1] = riskEngine;

        values[0] = 0;
        values[1] = 0;

        payloads[0] = call1;
        payloads[1] = call2;

        vm.startBroadcast(deployerPrivateKey);

        tl.emergencyExecuteBatch(targets, values, payloads);

        // set borrow paused as guardian
        re.setBorrowPaused(pToken, true);

        vm.stopBroadcast();

        console.log("Market deprecated successfully.");
    }
}
