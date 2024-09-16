// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {TestSetters} from "@helpers/TestSetters.sol";
import {DiamondCutFacet} from "@mocks/Diamond/facets/DiamondCutFacet.sol";
import {Diamond} from "@mocks/Diamond/Diamond.sol";
import {DiamondLoupeFacet} from "@mocks/Diamond/facets/DiamondLoupeFacet.sol";
import {strings} from "@mocks/Diamond/libraries/Strings.sol";
import {IDiamondCut} from "@mocks/Diamond/IDiamondCut.sol";
import {InitialModuleBundle} from "@modules/InitialModuleBundle.sol";
import {RBACModule, IRBAC} from "@modules/common/RBACModule.sol";
import {RiskEngineModule, IRiskEngine} from "@modules/riskEngine/RiskEngineModule.sol";
import {InterestRateModule} from "@modules/pToken/InterestRateModule.sol";
import {PTokenModule, IPToken} from "@modules/pToken/PTokenModule.sol";
import {MockToken} from "@mocks/MockToken.sol";
import {MockOracle} from "@mocks/MockOracle.sol";

contract TestDeploy is TestSetters {
    using strings for *;

    uint256 initialExchangeRate = 1e18;
    uint256 reserveFactor = 5e16;
    uint256 protocolSeizeShare = 1e16;
    uint256 borrowRateMax = 5e12;
    uint8 pTokenDecimals = 18;

    uint256 baseRatePerYear = 1.5e16;
    uint256 multiplierPerYear = 8.33e16;
    uint256 jumpMultiplierPerYear = 4.3e18;
    uint256 kink = 80e16;

    function deployProtocol() public {
        address oracle = address(new MockOracle());
        setOracle(oracle);

        address riskEngine = deployRiskEngine();

        vm.startPrank(getAdmin());

        IRBAC(riskEngine).grantPermission(
            getAdmin(), 0x434f4e464947555241544f520000000000000000000000000000000000000000
        );
        IRBAC(riskEngine).grantPermission(
            getAdmin(), 0x535550504c595f4341505f475541524449414e00000000000000000000000000
        );
        IRBAC(riskEngine).grantPermission(
            getAdmin(), 0x424f52524f575f4341505f475541524449414e00000000000000000000000000
        );
        IRBAC(riskEngine).grantPermission(
            getAdmin(), 0x50415553455f475541524449414e000000000000000000000000000000000000
        );

        IRiskEngine(riskEngine).setOracle(oracle);
        IRiskEngine(riskEngine).setCloseFactor(50e16);
        IRiskEngine(riskEngine).setLiquidationIncentive(1.08e18);

        vm.stopPrank();
    }

    function deployPToken(
        string memory name_,
        string memory symbol_,
        uint8 underlyingDecimals,
        uint256 price,
        uint256 colFactor,
        uint256 liqThreshold
    ) internal returns (address) {
        address underlying = address(new MockToken(name_, symbol_, underlyingDecimals));

        IRiskEngine re = IRiskEngine(getRiskEngine());

        PTokenInitialization memory initData = PTokenInitialization({
            underlying: underlying,
            riskEngine: re,
            initialExchangeRate: initialExchangeRate,
            reserveFactor: reserveFactor,
            protocolSeizeShare: protocolSeizeShare,
            borrowRateMax: borrowRateMax,
            name: name_,
            symbol: symbol_,
            pTokenDecimals: pTokenDecimals
        });

        string[] memory pTokenFacets = new string[](3);
        pTokenFacets[0] = "InitialModuleBundle";
        pTokenFacets[1] = "InterestRateModule";
        pTokenFacets[2] = "PTokenModule";

        address[] memory pTokenModulesAddresses = new address[](3);
        pTokenModulesAddresses[0] = address(new InitialModuleBundle());
        pTokenModulesAddresses[1] = address(new InterestRateModule());
        pTokenModulesAddresses[2] = address(new PTokenModule());

        address _pToken = deployDiamond(pTokenFacets, pTokenModulesAddresses);
        setPToken(symbol_, _pToken);

        MockOracle(getOracle()).setPrice(_pToken, price, MockToken(underlying).decimals());

        InitialModuleBundle initialModuleBundle = InitialModuleBundle(_pToken);
        initialModuleBundle.initialize(getAdmin());

        vm.startPrank(getAdmin());
        PTokenModule pToken = PTokenModule(_pToken);
        pToken.initialize(
            initData.underlying,
            initData.riskEngine,
            initData.initialExchangeRate,
            initData.reserveFactor,
            initData.protocolSeizeShare,
            initData.borrowRateMax,
            initData.name,
            initData.symbol,
            initData.pTokenDecimals
        );

        InterestRateModule interestRateModule = InterestRateModule(_pToken);
        interestRateModule.initialize(
            baseRatePerYear, multiplierPerYear, jumpMultiplierPerYear, kink
        );

        re.supportMarket(IPToken(_pToken));
        re.setCollateralFactor(IPToken(_pToken), colFactor, liqThreshold);

        IPToken[] memory markets = new IPToken[](1);
        markets[0] = IPToken(_pToken);

        uint256[] memory caps = new uint256[](1);
        caps[0] = type(uint256).max;

        re.setMarketBorrowCaps(markets, caps);
        re.setMarketSupplyCaps(markets, caps);

        vm.stopPrank();

        return _pToken;
    }

    function deployRiskEngine() internal returns (address) {
        string[] memory riskEngineModulesFacets = new string[](3);
        riskEngineModulesFacets[0] = "InitialModuleBundle";
        riskEngineModulesFacets[1] = "RBACModule";
        riskEngineModulesFacets[2] = "RiskEngineModule";

        address[] memory riskEngineModulesAddresses = new address[](3);
        riskEngineModulesAddresses[0] = address(new InitialModuleBundle());
        riskEngineModulesAddresses[1] = address(new RBACModule());
        riskEngineModulesAddresses[2] = address(new RiskEngineModule());

        address riskEngine =
            deployDiamond(riskEngineModulesFacets, riskEngineModulesAddresses);
        setRiskEngine(riskEngine);

        InitialModuleBundle initialModuleBundle = InitialModuleBundle(riskEngine);
        initialModuleBundle.initialize(getAdmin());

        return riskEngine;
    }

    function deployDiamond(string[] memory facets, address[] memory facetAddresses)
        internal
        returns (address)
    {
        vm.startPrank(getAdmin());
        DiamondCutFacet diamondCutFacet = new DiamondCutFacet();

        DiamondCutFacet diamond =
            DiamondCutFacet(address(new Diamond(getAdmin(), address(diamondCutFacet))));

        DiamondLoupeFacet diamondLoupeFacet = new DiamondLoupeFacet();

        bytes4[] memory diamondLoupeFacetSelectors =
            generateSelectors("DiamondLoupeFacet");

        DiamondCutFacet.FacetCut[] memory diamondLoupeFacetCut =
            new DiamondCutFacet.FacetCut[](facets.length + 1);
        diamondLoupeFacetCut[0] = IDiamondCut.FacetCut({
            facetAddress: address(diamondLoupeFacet),
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: diamondLoupeFacetSelectors
        });

        for (uint256 i = 0; i < facets.length; i++) {
            bytes4[] memory selectors = generateSelectors(facets[i]);
            diamondLoupeFacetCut[i + 1] = IDiamondCut.FacetCut({
                facetAddress: facetAddresses[i],
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: selectors
            });
        }

        diamond.diamondCut(diamondLoupeFacetCut, address(0), "");
        vm.stopPrank();

        return address(diamond);
    }

    function generateSelectors(string memory _facetName)
        internal
        returns (bytes4[] memory selectors)
    {
        //get string of contract methods
        string[] memory cmd = new string[](4);
        cmd[0] = "forge";
        cmd[1] = "inspect";
        cmd[2] = _facetName;
        cmd[3] = "methods";
        bytes memory res = vm.ffi(cmd);
        string memory st = string(res);

        // extract function signatures and take first 4 bytes of keccak
        strings.slice memory s = st.toSlice();

        // Skip TRACE lines if any
        strings.slice memory nl = "\n".toSlice();
        strings.slice memory trace = "TRACE".toSlice();
        while (s.contains(trace)) {
            s.split(nl);
        }

        strings.slice memory colon = ":".toSlice();
        strings.slice memory comma = ",".toSlice();
        strings.slice memory dbquote = '"'.toSlice();
        selectors = new bytes4[]((s.count(colon)));

        for (uint256 i = 0; i < selectors.length; i++) {
            s.split(dbquote); // advance to next doublequote
            // split at colon, extract string up to next doublequote for methodname
            strings.slice memory method = s.split(colon).until(dbquote);
            selectors[i] = bytes4(method.keccak());
            s.split(comma).until(dbquote); // advance s to the next comma
        }
        return selectors;
    }
}
