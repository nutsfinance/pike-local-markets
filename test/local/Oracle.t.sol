pragma solidity 0.8.28;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {TestLocal} from "@helpers/TestLocal.sol";
import {MockOracle} from "@mocks/MockOracle.sol";
import {ChainlinkOracleProvider} from "@oracles/ChainlinkOracleProvider.sol";
import {IChainlinkOracleProvider} from "@oracles/interfaces/IChainlinkOracleProvider.sol";
import {PythOracleProvider} from "@oracles/PythOracleProvider.sol";
import {IPythOracleProvider} from "@oracles/interfaces/IPythOracleProvider.sol";
import {OracleEngine} from "@oracles/OracleEngine.sol";
import {IOracleEngine} from "@oracles/interfaces/IOracleEngine.sol";
import {MockChainlinkAggregator} from "@mocks/MockChainlinkAggregator.sol";
import {MockPyth} from "@mocks/MockPyth.sol";
import "@chainlink/contracts/shared/interfaces/AggregatorV3Interface.sol";

contract LocalOracle is TestLocal {
    IPToken pUSDC;
    IPToken pWETH;
    IRiskEngine re;

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
        setDebug(false);
        setAdmin(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        init();

        // eth price = 2000$, usdc price = 1$
        deployPToken("pike-usdc", "pUSDC", 6, 1e6, 74.5e16, 84.5e16, deployMockToken);
        deployPToken("pike-weth", "pWETH", 18, 2000e6, 72.5e16, 82.5e16, deployMockToken);

        /// eth price = 2000$, usdc price = 1$
        pUSDC = getPToken("pUSDC");
        pWETH = getPToken("pWETH");

        re = getRiskEngine();

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
        data =
            abi.encodeCall(OracleEngine.initialize, (_testState.admin, _testState.admin));
        ERC1967Proxy oracleEngineProxy =
            new ERC1967Proxy(oracleEngineImplementation, data);
        oracleEngine = OracleEngine(address(oracleEngineProxy));

        weth = pWETH.asset();
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
        vm.expectRevert(IChainlinkOracleProvider.GracePeriodNotOver.selector);
        wethPrice = chainlinkOracleProvider.getPrice(weth);

        // sequencer down
        sequencerUptimeFeed.setRoundData(
            1, block.timestamp - gracePeriod - 1, block.timestamp - gracePeriod - 1
        );
        vm.expectRevert(IChainlinkOracleProvider.SequencerDown.selector);
        wethPrice = chainlinkOracleProvider.getPrice(weth);

        // stale price
        sequencerUptimeFeed.setRoundData(
            0, block.timestamp - gracePeriod - 1, block.timestamp - gracePeriod - 1
        );
        wethPriceFeed.setRoundData(
            2000e8, block.timestamp - 2 hours, block.timestamp - 2 hours
        );
        vm.expectRevert(IChainlinkOracleProvider.StalePrice.selector);
        wethPrice = chainlinkOracleProvider.getPrice(weth);

        // invalid asset
        vm.expectRevert(IChainlinkOracleProvider.InvalidAsset.selector);
        chainlinkOracleProvider.setAssetConfig(address(0), wethPriceFeed, 1 hours);

        // invalid feed
        vm.expectRevert(IChainlinkOracleProvider.InvalidFeed.selector);
        chainlinkOracleProvider.setAssetConfig(
            weth, AggregatorV3Interface(address(0)), 1 hours
        );

        // invalid stale period
        vm.expectRevert(IChainlinkOracleProvider.InvalidStalePeriod.selector);
        chainlinkOracleProvider.setAssetConfig(weth, wethPriceFeed, 0);
    }

    function testPythOracleProvider() public {
        vm.startPrank(_testState.admin);

        // configure weth price
        pythOracleProvider.setAssetConfig(weth, "weth", 0, 1 hours);

        pyth.setData(2000e8, 0, -8);

        // get weth price
        uint256 wethPrice = pythOracleProvider.getPrice(weth);
        assertEq(wethPrice, 2000e18);

        // invalid asset
        vm.expectRevert(IPythOracleProvider.InvalidAsset.selector);
        pythOracleProvider.setAssetConfig(address(0), "weth", 0, 1 hours);

        // invalid stale period
        vm.expectRevert(IPythOracleProvider.InvalidMaxStalePeriod.selector);
        pythOracleProvider.setAssetConfig(weth, "weth", 0, 0);
    }

    function testPythOracleProvider_FailIfConfIsLow() public {
        vm.startPrank(_testState.admin);

        // configure weth price
        pythOracleProvider.setAssetConfig(weth, "weth", 2000, 1 hours);

        pyth.setData(2000e8, 10e8, -8);

        // get weth price
        vm.expectRevert(IPythOracleProvider.InvalidMinConfRatio.selector);
        pythOracleProvider.getPrice(weth);
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

        wethPrice = oracleEngine.getUnderlyingPrice(pWETH);
        assertEq(wethPrice, 2002e18);

        // get fallback if main oracle is down
        wethPriceFeed.setRoundData(
            2002e8, block.timestamp - 2 hours, block.timestamp - 2 hours
        );
        pythOracleProvider.setAssetConfig(weth, "weth", 0, 1 hours);
        pyth.setData(2001e8, 0, -8);
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
        pyth.setData(4001e8, 0, -8);
        vm.expectRevert(IOracleEngine.BoundValidationFailed.selector);
        wethPrice = oracleEngine.getPrice(weth);

        // fallback fails
        pyth.setData(0, 0, 0);
        wethPrice = oracleEngine.getPrice(weth);
        assertEq(wethPrice, 2002e18);

        // main and fallback both fails
        wethPriceFeed.setRoundData(
            2002e8, block.timestamp - 2 hours, block.timestamp - 2 hours
        );
        vm.expectRevert(IOracleEngine.InvalidFallbackOraclePrice.selector);
        wethPrice = oracleEngine.getPrice(weth);

        // only main is configured and it fails
        oracleEngine.setAssetConfig(
            weth, address(chainlinkOracleProvider), address(0), 0, 0
        );
        vm.expectRevert(IOracleEngine.InvalidMainOraclePrice.selector);
        wethPrice = oracleEngine.getPrice(weth);

        // invalid bounds
        vm.expectRevert(IOracleEngine.InvalidBounds.selector);
        oracleEngine.setAssetConfig(
            weth, address(chainlinkOracleProvider), address(0), 2, 1
        );

        // invalid main oracle
        vm.expectRevert(IOracleEngine.InvalidMainOracle.selector);
        oracleEngine.setAssetConfig(weth, address(0), address(0), 0, 0);

        // invalid asset
        vm.expectRevert(IOracleEngine.InvalidAsset.selector);
        oracleEngine.setAssetConfig(
            address(0), address(chainlinkOracleProvider), address(0), 0, 0
        );
    }

    function testOracleEngineInAction() public {
        address user1 = makeAddr("user1");
        vm.startPrank(_testState.admin);

        // get fallback oracle only
        oracleEngine.setAssetConfig(
            weth, address(pythOracleProvider), address(pythOracleProvider), 0, 0
        );

        pythOracleProvider.setAssetConfig(weth, "weth", 2000, 1 hours);
        pyth.setData(2000e8, 10e8, -8);

        re.setOracle(address(oracleEngine));

        vm.stopPrank();

        doDeposit(user1, user1, address(pWETH), 1e18);
        // "InvalidFallbackOraclePrice()" selector
        doBorrowRevert(
            user1, user1, address(pWETH), 1e17, abi.encodePacked(bytes4(0x5fe3213c))
        );
    }
}
