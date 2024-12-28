pragma solidity 0.8.28;

import {IRBAC} from "@modules/common/RBACModule.sol";
import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IDoubleJumpRateModel} from "@interfaces/IDoubleJumpRateModel.sol";
import {IFactory} from "@factory/interfaces/IFactory.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {IOracleEngine} from "@oracles/interfaces/IOracleEngine.sol";

import {Config, console} from "../Config.sol";

contract Factory is Config {
    string PATH;

    IFactory factory;

    IPToken pUSDC;
    IPToken pWETH;
    IPToken pSTETH;

    IRiskEngine re;
    IOracleEngine oe;

    constructor() Config(1, true) {
        PATH = "/deployments/base-sepolia-demo/";
    }

    function run() public payable {
        setUp();
        vm.createSelectFork(vm.envString(rpcs[0]));
        forks[0] = vm.activeFork();
        address usdc = 0xf10f12A5cB889CA699017898feE16ce82c9557eD;
        address weth = 0x565A622533868FA98d4D0D784712bEBBAba0AA64;
        address chainlinkProvider = 0x274081BbB947B0D24c28A078c48e52a45043F49d;

        factory = IFactory(getAddress(".Factory", "Testnet"));

        uint256 protocolId = factory.protocolCount() + 1;
        IFactory.PTokenSetup memory pUSDCSetup = IFactory.PTokenSetup(
            protocolId, usdc, 1e18, 1e16, 2e16, 1e18, "pike usdc", "pUSDC2", 8
        );
        IFactory.PTokenSetup memory pWETHSetup = IFactory.PTokenSetup(
            protocolId, weth, 1e18, 1e16, 2e16, 1e18, "pike weth", "pWETH2", 8
        );

        IRiskEngine.BaseConfiguration memory config =
            IRiskEngine.BaseConfiguration(72.5e16, 82.5e16, 102e16);

        IPToken[] memory markets = new IPToken[](2);
        markets[0] = pUSDC;
        markets[1] = pWETH;

        uint256[] memory caps = new uint256[](2);
        caps[0] = type(uint256).max;
        caps[1] = type(uint256).max;

        vm.startBroadcast(adminPrivateKey);

        // step 1 deploy protocol
        console.log("deploying protocol: %s", protocolId);
        factory.deployProtocol(ADMIN, 30e16, 20e16);

        oe = IOracleEngine(factory.getProtocolInfo(protocolId).oracleEngine);
        re = IRiskEngine(factory.getProtocolInfo(protocolId).riskEngine);

        console.log("deployed risk engine: %s", address(re));
        console.log("deployed oracle engine: %s", address(oe));

        // step 2 deploy pTokens
        console.log("deploying %s", pUSDCSetup.name);
        factory.deployMarket(pUSDCSetup);
        pUSDC = IPToken(factory.getMarket(protocolId, 0));
        console.log("deployed: %s", address(pUSDC));

        console.log("deploying: %s", pWETHSetup.name);
        factory.deployMarket(pWETHSetup);
        pWETH = IPToken(factory.getMarket(protocolId, 1));
        console.log("deployed: %s", address(pWETH));

        // step 3 set oracle engine data providers
        oe.setAssetConfig(usdc, chainlinkProvider, address(0), 0, 0);
        oe.setAssetConfig(weth, chainlinkProvider, address(0), 0, 0);
        console.log(
            "oracle set for %s with price: %s",
            pUSDCSetup.name,
            oe.getUnderlyingPrice(pUSDC)
        );
        console.log(
            "oracle set for %s with price: %s",
            pWETHSetup.name,
            oe.getUnderlyingPrice(pWETH)
        );

        // step 4 set risk engine config for pTokens
        re.configureMarket(pUSDC, config);
        re.configureMarket(pWETH, config);
        re.setCloseFactor(address(pUSDC), 50e16);
        re.setCloseFactor(address(pWETH), 50e16);
        re.setMarketSupplyCaps(markets, caps);
        re.setMarketBorrowCaps(markets, caps);
        console.log("Risk Engine configured");

        // step 5 set pToken config for IRM
        IDoubleJumpRateModel(address(pUSDC)).configureInterestRateModel(
            0, 0, 6.111111e16, 6e18, 5e16, 95e16
        );
        IDoubleJumpRateModel(address(pWETH)).configureInterestRateModel(
            0, 0, 6.111111e16, 6e18, 5e16, 95e16
        );
        console.log("IRM configured");
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
