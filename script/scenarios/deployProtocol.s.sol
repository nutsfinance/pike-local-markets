pragma solidity 0.8.28;

import {IRBAC} from "@modules/common/RBACModule.sol";
import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IDoubleJumpRateModel} from "@interfaces/IDoubleJumpRateModel.sol";
import {IFactory} from "@factory/interfaces/IFactory.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {IOracleEngine} from "@oracles/interfaces/IOracleEngine.sol";
import {Timelock} from "@governance/Timelock.sol";

import {Config, console} from "../Config.sol";

contract Factory is Config {
    string PATH;

    IFactory factory;

    IPToken pUSDC;
    IPToken pWETH;
    IPToken pSTETH;

    IRiskEngine re;
    IOracleEngine oe;
    Timelock tm;

    constructor() Config(6, true) {
        PATH = "";
    }

    function run() public payable {
        uint256 selectedFork = 1;
        setUp();
        vm.createSelectFork(vm.envString(rpcs[selectedFork]));
        forks[selectedFork] = vm.activeFork();

        factory = IFactory(0x82072C90aacbb62dbD7A0EbAAe3b3e5D7d8cEEEA);
        uint256 protocolId = factory.protocolCount() + 1;

        vm.startBroadcast(adminPrivateKey);

        console.log("deploying protocol: %s", protocolId);
        factory.deployProtocol(ADMIN, 0, 0);

        oe = IOracleEngine(factory.getProtocolInfo(protocolId).oracleEngine);
        re = IRiskEngine(factory.getProtocolInfo(protocolId).riskEngine);
        tm = Timelock(payable(factory.getProtocolInfo(protocolId).timelock));

        console.log("deployed risk engine: %s", address(re));
        console.log("deployed oracle engine: %s", address(oe));
        console.log("deployed timelock: %s", address(tm));
    }

    function getAddress(string memory key, string memory name)
        internal
        view
        returns (address)
    {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, PATH, name, ".json");
        bytes memory addr = vm.parseJson(vm.readFile(path), key);
        return abi.decode(addr, (address));
    }
}
