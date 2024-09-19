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
    MockPyth pyth;

    uint256 startTimestamp = 1_726_655_826;
    uint256 gracePeriod = 3600;

    address weth;

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
        sequencerUptimeFeed.setRoundData(
            0, block.timestamp - gracePeriod - 1, block.timestamp - gracePeriod - 1
        );

        // deploy weth price feed
        wethPriceFeed = new MockChainlinkAggregator();
        wethPriceFeed.setRoundData(2000e8, block.timestamp, block.timestamp);

        // deploy chainlink oracle provider
        address chainlinkOracleProviderImplementation = address(
            new ChainlinkOracleProvider(AggregatorV3Interface(sequencerUptimeFeed))
        );
        bytes memory data =
            abi.encodeCall(ChainlinkOracleProvider.initialize, (_testState.admin));
        ERC1967Proxy chainlinkOracleProviderProxy =
            new ERC1967Proxy(chainlinkOracleProviderImplementation, data);

        chainlinkOracleProvider =
            ChainlinkOracleProvider(address(chainlinkOracleProviderProxy));

        // deploy pyth oracle provider
        pyth = new MockPyth();
        address pythOracleProviderImplementation =
            address(new PythOracleProvider(address(pyth)));
        data = abi.encodeCall(PythOracleProvider.initialize, (_testState.admin));
        ERC1967Proxy pythOracleProviderProxy =
            new ERC1967Proxy(pythOracleProviderImplementation, data);
        pythOracleProvider = PythOracleProvider(address(pythOracleProviderProxy));

        // deploy oracle engine
        address oracleEngineImplementation = address(new OracleEngine());
        data = abi.encodeCall(OracleEngine.initialize, (_testState.admin));
        ERC1967Proxy oracleEngineProxy =
            new ERC1967Proxy(oracleEngineImplementation, data);
        oracleEngine = OracleEngine(address(oracleEngineProxy));

        weth = pWETH.underlying();
    }

    function testChainlinkOracleProvider() public {
        vm.startPrank(_testState.admin);

        // configure weth price
        chainlinkOracleProvider.setAssetConfig(weth, wethPriceFeed, 1 hours);

        // get weth price
        uint256 wethPrice = chainlinkOracleProvider.getPrice(weth);
        assertEq(wethPrice, 2000e18);

        // grace period not over
        sequencerUptimeFeed.setRoundData(0, block.timestamp, block.timestamp);
        vm.expectRevert(ChainlinkOracleProvider.GracePeriodNotOver.selector);
        wethPrice = chainlinkOracleProvider.getPrice(weth);

        // sequencer down
        sequencerUptimeFeed.setRoundData(
            1, block.timestamp - gracePeriod - 1, block.timestamp - gracePeriod - 1
        );
        vm.expectRevert(ChainlinkOracleProvider.SequencerDown.selector);
        wethPrice = chainlinkOracleProvider.getPrice(weth);

        // stale price
        sequencerUptimeFeed.setRoundData(
            0, block.timestamp - gracePeriod - 1, block.timestamp - gracePeriod - 1
        );
        wethPriceFeed.setRoundData(
            2000e8, block.timestamp - 2 hours, block.timestamp - 2 hours
        );
        vm.expectRevert(ChainlinkOracleProvider.StalePrice.selector);
        wethPrice = chainlinkOracleProvider.getPrice(weth);
    }

    function testPythOracleProvider() public {
        vm.startPrank(_testState.admin);

        // configure weth price
        pythOracleProvider.setAssetConfig(weth, "weth", 1 hours);

        pyth.setData(2000e8, -8);

        // get weth price
        uint256 wethPrice = pythOracleProvider.getPrice(weth);
        assertEq(wethPrice, 2000e18);
    }

    function testOracleEngine() public {
        vm.startPrank(_testState.admin);

        chainlinkOracleProvider.setAssetConfig(weth, wethPriceFeed, 1 hours);

        // get main oracle only
        oracleEngine.setAssetConfig(
            weth, address(chainlinkOracleProvider), address(0), 0, 0
        );
        wethPriceFeed.setRoundData(2002e8, block.timestamp, block.timestamp);

        uint256 wethPrice = oracleEngine.getPrice(weth);
        assertEq(wethPrice, 2002e18);

        // get fallback if main oracle is down
        wethPriceFeed.setRoundData(
            2002e8, block.timestamp - 2 hours, block.timestamp - 2 hours
        );
        pythOracleProvider.setAssetConfig(weth, "weth", 1 hours);
        pyth.setData(2001e8, -8);
        oracleEngine.setAssetConfig(
            weth, address(chainlinkOracleProvider), address(pythOracleProvider), 0, 0
        );
        wethPrice = oracleEngine.getPrice(weth);
        assertEq(wethPrice, 2001e18);

        // get main oracle if bounds not set
        wethPriceFeed.setRoundData(2002e8, block.timestamp, block.timestamp);
        wethPrice = oracleEngine.getPrice(weth);
        assertEq(wethPrice, 2002e18);

        // verify bounds if set
        oracleEngine.setAssetConfig(
            weth,
            address(chainlinkOracleProvider),
            address(pythOracleProvider),
            0.99e18,
            1.01e18
        );
        wethPrice = oracleEngine.getPrice(weth);
        assertEq(wethPrice, 2002e18);

        // bounds not met
        pyth.setData(4001e8, -8);
        vm.expectRevert(OracleEngine.BoundValidationFailed.selector);
        wethPrice = oracleEngine.getPrice(weth);
    }
}
