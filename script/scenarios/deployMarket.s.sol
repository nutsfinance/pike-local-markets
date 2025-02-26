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
    string PATH;

    IFactory factory;

    IPToken pUSDC;
    IPToken pWETH;
    IPToken pSTETH;

    IRiskEngine re;
    IOracleEngine oe;
    Timelock tm;
    MockProvider mp;

    constructor() Config(6, true) {
        PATH = "";
    }

    function run() public payable {
        setUp();
        uint256 selectedFork = 5;
        vm.createSelectFork(vm.envString(rpcs[selectedFork]));
        forks[selectedFork] = vm.activeFork();

        vm.startBroadcast(adminPrivateKey);

        address usdc = address(new MockTestToken("mockUSDC", "USDC", 6, 10_000e6));
        address weth = address(new MockTestToken("mockWETH", "WETH", 18, 10e18));
        address steth = address(new MockTestToken("mockSTETH", "STETH", 18, 10e18));
        mp = MockProvider(0xeB25de08215e107ec96de7d58b20A932089E0E5e);
        mp.setPrice(usdc, 1e6, 6);
        mp.setPrice(weth, 2000e6, 18);
        mp.setPrice(steth, 2000e6, 18);
        address chainlinkProvider = 0x7322C1FaeBa862bE83D404f20397B397a32B79EF;

        factory = IFactory(0xe9A6F322D8aB0722c9B2047612168BB85F184Ae4);

        uint256 protocolId = factory.protocolCount();
        IFactory.PTokenSetup memory pUSDCSetup = IFactory.PTokenSetup(
            protocolId, usdc, 1e18, 1e16, 2e16, 1e18, "pike usdc", "pUSDC", 8
        );
        IFactory.PTokenSetup memory pWETHSetup = IFactory.PTokenSetup(
            protocolId, weth, 1e18, 1e16, 2e16, 1e18, "pike weth", "pWETH", 8
        );
        IFactory.PTokenSetup memory pSTETHSetup = IFactory.PTokenSetup(
            protocolId, steth, 1e18, 1e16, 2e16, 1e18, "pike steth", "pSTETH", 8
        );

        IRiskEngine.BaseConfiguration memory config =
            IRiskEngine.BaseConfiguration(72.5e16, 82.5e16, 102e16);

        // step 1 get protocol info
        console.log("deployed protocol: %s", protocolId);

        oe = IOracleEngine(factory.getProtocolInfo(protocolId).oracleEngine);
        re = IRiskEngine(factory.getProtocolInfo(protocolId).riskEngine);
        tm = Timelock(payable(factory.getProtocolInfo(protocolId).timelock));

        console.log("deployed risk engine: %s", address(re));
        console.log("deployed oracle engine: %s", address(oe));
        console.log("deployed timelock: %s", address(tm));

        // step 2 deploy pTokens
        console.log("deploying %s", pUSDCSetup.name);
        tm.emergencyExecute(
            address(factory),
            0,
            abi.encodeWithSelector(factory.deployMarket.selector, pUSDCSetup)
        );
        pUSDC = IPToken(factory.getMarket(protocolId, 0));
        console.log("deployed: %s", address(pUSDC));

        console.log("deploying: %s", pWETHSetup.name);
        tm.emergencyExecute(
            address(factory),
            0,
            abi.encodeWithSelector(factory.deployMarket.selector, pWETHSetup)
        );
        pWETH = IPToken(factory.getMarket(protocolId, 1));
        console.log("deployed: %s", address(pWETH));

        console.log("deploying: %s", pSTETHSetup.name);
        tm.emergencyExecute(
            address(factory),
            0,
            abi.encodeWithSelector(factory.deployMarket.selector, pSTETHSetup)
        );
        pSTETH = IPToken(factory.getMarket(protocolId, 2));
        console.log("deployed: %s", address(pSTETH));

        // step 3 set oracle engine data providers
        IPToken[] memory markets = new IPToken[](3);
        markets[0] = pUSDC;
        markets[1] = pWETH;
        markets[2] = pSTETH;

        uint256[] memory caps = new uint256[](3);
        caps[0] = type(uint256).max;
        caps[1] = type(uint256).max;
        caps[2] = type(uint256).max;

        tm.emergencyExecute(
            address(oe),
            0,
            abi.encodeWithSelector(
                oe.setAssetConfig.selector, pUSDC.asset(), address(mp), address(0), 0, 0
            )
        );
        tm.emergencyExecute(
            address(oe),
            0,
            abi.encodeWithSelector(
                oe.setAssetConfig.selector, pWETH.asset(), address(mp), address(0), 0, 0
            )
        );
        tm.emergencyExecute(
            address(oe),
            0,
            abi.encodeWithSelector(
                oe.setAssetConfig.selector, pSTETH.asset(), address(mp), address(0), 0, 0
            )
        );
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
        console.log(
            "oracle set for %s with price: %s",
            pSTETHSetup.name,
            oe.getUnderlyingPrice(pSTETH)
        );

        // step 4 set risk engine config for pTokens
        tm.emergencyExecute(
            address(re),
            0,
            abi.encodeWithSelector(re.configureMarket.selector, pUSDC, config)
        );
        tm.emergencyExecute(
            address(re),
            0,
            abi.encodeWithSelector(re.configureMarket.selector, pWETH, config)
        );
        tm.emergencyExecute(
            address(re),
            0,
            abi.encodeWithSelector(re.configureMarket.selector, pSTETH, config)
        );
        tm.emergencyExecute(
            address(re),
            0,
            abi.encodeWithSelector(re.setCloseFactor.selector, address(pUSDC), 50e16)
        );
        tm.emergencyExecute(
            address(re),
            0,
            abi.encodeWithSelector(re.setCloseFactor.selector, address(pWETH), 50e16)
        );
        tm.emergencyExecute(
            address(re),
            0,
            abi.encodeWithSelector(re.setCloseFactor.selector, address(pSTETH), 50e16)
        );
        tm.emergencyExecute(
            address(re),
            0,
            abi.encodeWithSelector(re.setMarketSupplyCaps.selector, markets, caps)
        );
        tm.emergencyExecute(
            address(re),
            0,
            abi.encodeWithSelector(re.setMarketBorrowCaps.selector, markets, caps)
        );
        console.log("Risk Engine configured");

        // step 5 set pToken config for IRM
        tm.emergencyExecute(
            address(pUSDC),
            0,
            abi.encodeWithSelector(
                IDoubleJumpRateModel.configureInterestRateModel.selector,
                0,
                0,
                6.111111e16,
                6e18,
                5e16,
                95e16
            )
        );
        tm.emergencyExecute(
            address(pWETH),
            0,
            abi.encodeWithSelector(
                IDoubleJumpRateModel.configureInterestRateModel.selector,
                0,
                0,
                6.111111e16,
                6e18,
                5e16,
                95e16
            )
        );
        tm.emergencyExecute(
            address(pSTETH),
            0,
            abi.encodeWithSelector(
                IDoubleJumpRateModel.configureInterestRateModel.selector,
                0,
                0,
                6.111111e16,
                6e18,
                5e16,
                95e16
            )
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
