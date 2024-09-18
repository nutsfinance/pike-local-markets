pragma solidity 0.8.20;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {TestLocal} from "@helpers/TestLocal.sol";

import {MockOracle} from "@mocks/MockOracle.sol";
import {ChainlinkOracleProvider} from "@oracles/ChainlinkOracleProvider.sol";
import {PythOracleProvider} from "@oracles/PythOracleProvider.sol";
import {OracleEngine} from "@oracles/OracleEngine.sol";
import {MockChainlinkAggregator} from "@mocks/MockChainlinkAggregator.sol";
import {MockPyth} from "@mocks/MockPyth.sol";
import "@chainlink/contracts/shared/interfaces/AggregatorV3Interface.sol";

contract LocalOracle is TestLocal {
    IPToken pUSDC;
    IPToken pWETH;

    ChainlinkOracleProvider chainlinkOracleProvider;
    PythOracleProvider pythOracleProvider;
    OracleEngine oracleEngine;
    MockChainlinkAggregator sequencerUptimeFeed;
    MockChainlinkAggregator wethPriceFeed;

    uint256 startTimestamp = 1726655826;
    uint256 gracePeriod = 3600;

    function setUp() public {
        setDebug(true);
        setAdmin(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        init();

        // eth price = 2000$, usdc price = 1$
        deployPToken("pike-usdc", "pUSDC", 6, 1e6, 74.5e16, 84.5e16);
        deployPToken("pike-weth", "pWETH", 18, 2000e6, 72.5e16, 82.5e16);

        /// eth price = 2000$, usdc price = 1$
        pUSDC = getPToken("pUSDC");
        pWETH = getPToken("pWETH");
       
        vm.warp(startTimestamp);

        // deploy sequencer uptime feed
        sequencerUptimeFeed = new MockChainlinkAggregator();
        sequencerUptimeFeed.setRoundData(0, block.timestamp - gracePeriod - 1, block.timestamp - gracePeriod -1);

        // deploy weth price feed
        wethPriceFeed = new MockChainlinkAggregator();
        wethPriceFeed.setRoundData(2000e8, block.timestamp, block.timestamp);

        // deploy chainlink oracle provider
        address chainlinkOracleProviderImplementation =
            address(new ChainlinkOracleProvider(AggregatorV3Interface(sequencerUptimeFeed)));
        bytes memory data =
            abi.encodeCall(ChainlinkOracleProvider.initialize,(_testState.admin));
        ERC1967Proxy chainlinkOracleProviderProxy =
            new ERC1967Proxy(chainlinkOracleProviderImplementation, data);

        chainlinkOracleProvider = ChainlinkOracleProvider(address(chainlinkOracleProviderProxy));

        // deploy pyth oracle provider
        MockPyth pyth = new MockPyth();
        address pythOracleProviderImplementation = address(new PythOracleProvider(address(pyth)));
        data = abi.encodeCall(PythOracleProvider.initialize,(_testState.admin));
        ERC1967Proxy pythOracleProviderProxy =
            new ERC1967Proxy(pythOracleProviderImplementation, data);
        pythOracleProvider = PythOracleProvider(address(pythOracleProviderProxy));

        // deploy oracle engine
        address oracleEngineImplementation = address(new OracleEngine());
        data = abi.encodeCall(OracleEngine.initialize,(_testState.admin));
        ERC1967Proxy oracleEngineProxy =
            new ERC1967Proxy(oracleEngineImplementation, data);
        oracleEngine = OracleEngine(address(oracleEngineProxy));
    }

    function testChainlinkOracleProvider() public {
        vm.startPrank(_testState.admin);

        // configure weth price
        chainlinkOracleProvider.setAssetConfig(
            pWETH.underlying(),
            wethPriceFeed,
            1 hours
        );

        // get weth price
        uint256 wethPrice = chainlinkOracleProvider.getPrice(pWETH.underlying());
        assertEq(wethPrice, 2000e18);

        // grace period not over
        sequencerUptimeFeed.setRoundData(0, block.timestamp, block.timestamp);
        vm.stopPrank(); 

        vm.expectRevert();
        wethPrice = chainlinkOracleProvider.getPrice(pWETH.underlying());
    }
}
