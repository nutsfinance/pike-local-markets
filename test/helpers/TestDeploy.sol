// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {TestSetters} from "@helpers/TestSetters.sol";
import {DiamondCutFacet} from "@mocks/Diamond/facets/DiamondCutFacet.sol";
import {Diamond} from "@mocks/Diamond/Diamond.sol";
import {DiamondLoupeFacet} from "@mocks/Diamond/facets/DiamondLoupeFacet.sol";
import {strings} from "@mocks/Diamond/libraries/Strings.sol";
import {IDiamondCut} from "@mocks/Diamond/IDiamondCut.sol";
import {InitialModuleBundle} from "@modules/InitialModuleBundle.sol";
import {RBACModule, IRBAC} from "@modules/common/RBACModule.sol";
import {RiskEngineModule, IRiskEngine} from "@modules/riskEngine/RiskEngineModule.sol";
import {DoubleJumpRateModel} from "@modules/interestRateModel/DoubleJumpRateModel.sol";
import {PTokenModule, IPToken} from "@modules/pToken/PTokenModule.sol";
import {MockToken, MockReentrantToken} from "@mocks/MockToken.sol";
import {MockOracle} from "@mocks/MockOracle.sol";

contract TestDeploy is TestSetters {
    using strings for *;

    bytes32 constant configurator_permission =
        0x434f4e464947555241544f520000000000000000000000000000000000000000;

    bytes32 constant supply_guard_permission =
        0x535550504c595f4341505f475541524449414e00000000000000000000000000;

    bytes32 constant borrow_guard_permission =
        0x424f52524f575f4341505f475541524449414e00000000000000000000000000;

    bytes32 constant pause_guard_permission =
        0x50415553455f475541524449414e000000000000000000000000000000000000;

    bytes32 constant reserve_manager_permission =
        0x524553455256455f4d414e414745520000000000000000000000000000000000;

    bytes32 constant reserve_withdrawer_permission =
        0x524553455256455f574954484452415745520000000000000000000000000000;

    uint256 initialExchangeRate = 1e18;
    uint256 reserveFactor = 5e16;
    uint256 protocolSeizeShare = 1e16;
    uint256 borrowRateMax = 5e12;
    uint8 pTokenDecimals = 18;

    uint256 baseRatePerYear = 1.5e16;
    uint256 multiplierPerYear = 8.33e16;
    uint256 jumpMultiplierPerYear = 4.3e18;
    uint256 kink = 80e16;

    uint256 closeFactor = 50e16;
    uint256 liquidationIncentive = 1.08e18;

    function deployProtocol() public virtual {
        address oracle = address(new MockOracle());
        setOracle(oracle);

        deployRiskEngine(closeFactor, liquidationIncentive);
    }

    function deployPToken(
        string memory name_,
        string memory symbol_,
        uint8 underlyingDecimals,
        uint256 price,
        uint256 colFactor,
        uint256 liqThreshold,
        function (string memory, string memory, uint8) internal returns (address)
            deployUnderlying
    ) internal virtual returns (address) {
        address underlying = deployUnderlying(name_, symbol_, underlyingDecimals);

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

        string[] memory pTokenFacets = new string[](4);
        pTokenFacets[0] = "InitialModuleBundle";
        pTokenFacets[1] = "DoubleJumpRateModel";
        pTokenFacets[2] = "PTokenModule";
        pTokenFacets[3] = "RBACModule";

        address[] memory pTokenModulesAddresses = new address[](4);
        pTokenModulesAddresses[0] = address(new InitialModuleBundle());
        pTokenModulesAddresses[1] = address(new DoubleJumpRateModel());
        pTokenModulesAddresses[2] = address(new PTokenModule());
        pTokenModulesAddresses[3] = address(new RBACModule());

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

        IRBAC(_pToken).grantPermission(reserve_manager_permission, getAdmin());
        IRBAC(_pToken).grantPermission(reserve_withdrawer_permission, getAdmin());
        IRBAC(_pToken).grantPermission(configurator_permission, getAdmin());
        IRBAC(address(re)).grantNestedPermission(
            configurator_permission, _pToken, getAdmin()
        );
        IRBAC(address(re)).grantNestedPermission(
            supply_guard_permission, _pToken, getAdmin()
        );
        IRBAC(address(re)).grantNestedPermission(
            borrow_guard_permission, _pToken, getAdmin()
        );

        DoubleJumpRateModel interestRateModule = DoubleJumpRateModel(_pToken);
        interestRateModule.configureInterestRateModel(
            baseRatePerYear, 0, multiplierPerYear, jumpMultiplierPerYear, 0, kink
        );

        re.supportMarket(IPToken(_pToken));
        re.setCollateralFactor(IPToken(_pToken), colFactor, liqThreshold);

        assertEq(re.collateralFactor(IPToken(_pToken)), colFactor);
        assertEq(re.liquidationThreshold(IPToken(_pToken)), liqThreshold);

        IPToken[] memory markets = new IPToken[](1);
        markets[0] = IPToken(_pToken);

        uint256[] memory caps = new uint256[](1);
        caps[0] = type(uint256).max;

        re.setMarketBorrowCaps(markets, caps);
        re.setMarketSupplyCaps(markets, caps);

        vm.stopPrank();

        assertEq(IPToken(_pToken).decimals(), pTokenDecimals);
        assertEq(
            keccak256(abi.encodePacked(IPToken(_pToken).symbol())),
            keccak256(abi.encodePacked(initData.symbol))
        );
        assertEq(IPToken(_pToken).borrowIndex(), initData.initialExchangeRate);

        return _pToken;
    }

    function deployRiskEngine(uint256 _closeFactor, uint256 _liquidationIncentive)
        internal
        virtual
        returns (address)
    {
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

        vm.startPrank(getAdmin());

        IRBAC(riskEngine).grantPermission(configurator_permission, getAdmin());
        IRBAC(riskEngine).grantPermission(pause_guard_permission, getAdmin());

        IRiskEngine(riskEngine).setOracle(getOracle());
        IRiskEngine(riskEngine).setCloseFactor(_closeFactor);
        IRiskEngine(riskEngine).setLiquidationIncentive(_liquidationIncentive);

        vm.stopPrank();

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

        // retry if no selectors found
        if (selectors.length == 0) {
            return generateSelectors(_facetName);
        }

        return selectors;
    }

    function deployMockToken(string memory name_, string memory symbol_, uint8 decimals_)
        internal
        returns (address)
    {
        return address(new MockToken(name_, symbol_, decimals_));
    }

    function deployMockReentrantToken(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) internal returns (address) {
        return address(new MockReentrantToken(name_, symbol_, decimals_));
    }
}
