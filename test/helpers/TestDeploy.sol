// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import {TestState} from "@helpers/TestState.sol";
import {DiamondCutFacet} from "@mocks/Diamond/facets/DiamondCutFacet.sol";
import {Diamond} from "@mocks/Diamond/Diamond.sol";
import {DiamondLoupeFacet} from "@mocks/Diamond/facets/DiamondLoupeFacet.sol";
import {strings} from "@mocks/Diamond/libraries/strings.sol";
import {IDiamondCut} from "@mocks/Diamond/IDiamondCut.sol";
import {InitialModuleBundle} from "@modules/InitialModuleBundle.sol";
import {RBACModule} from "@modules/common/RBACModule.sol";
import {RiskEngineModule, IRiskEngine} from "@modules/riskEngine/RiskEngineModule.sol";
import {InterestRateModule} from "@modules/pToken/InterestRateModule.sol";
import {PTokenModule, IPToken} from "@modules/pToken/PTokenModule.sol";
import {MockToken} from "@mocks/MockToken.sol";
import {MockOracle} from "@mocks/MockOracle.sol";

contract TestDeploy is Test, TestState {
    using strings for *;

    bool local = true;

    address admin = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address riskEngine;
    address usdc;
    address weth;
    address usdcMarket;
    address wethMarket;

    uint256 initialExchangeRate = 1e18;
    uint256 reserveFactor = 5e16;
    uint256 protocolSeizeShare = 1e16;
    uint256 borrowRateMax = 5e12;
    uint8 pTokenDecimals = 18;

    uint256 baseRatePerYear = 1.5e16;
    uint256 multiplierPerYear = 8.33e16;
    uint256 jumpMultiplierPerYear = 4.3e18;
    uint256 kink = 80e16;

    address oracle;

    function deployProtocol() public {
        usdc = address(new MockToken("USD Coin", "USDC"));
        weth = address(new MockToken("Wrapped Ether", "WETH"));
        oracle = address(new MockOracle());

        riskEngine = deployRiskEngine();

        usdcMarket = deployPToken(
            usdc,
            "pike-usdc", 
            "pUSDC"
        );

        wethMarket = deployPToken(
            weth,
            "pike-weth",
            "pWETH"
        );

        vm.startPrank(admin);

        RBACModule(riskEngine).grantPermission(admin, 0x434f4e464947555241544f520000000000000000000000000000000000000000);
        RBACModule(riskEngine).grantPermission(admin, 0x535550504c595f4341505f475541524449414e00000000000000000000000000);
        RBACModule(riskEngine).grantPermission(admin, 0x424f52524f575f4341505f475541524449414e00000000000000000000000000);
        RBACModule(riskEngine).grantPermission(admin, 0x50415553455f475541524449414e000000000000000000000000000000000000);

        MockOracle(oracle).setPrice(usdcMarket, 1e6, 6);
        MockOracle(oracle).setPrice(wethMarket, 2000e6, 18);

        RiskEngineModule(riskEngine).setOracle(oracle);
        RiskEngineModule(riskEngine).setCloseFactor(50e16);
        RiskEngineModule(riskEngine).supportMarket(IPToken(usdcMarket));
        RiskEngineModule(riskEngine).supportMarket(IPToken(wethMarket));
        RiskEngineModule(riskEngine).setCollateralFactor(IPToken(usdcMarket), 74.5e16, 84.5e16);
        RiskEngineModule(riskEngine).setCollateralFactor(IPToken(wethMarket), 72.5e16, 82.5e16);
        RiskEngineModule(riskEngine).setLiquidationIncentive(1.08e18);

        IPToken[] memory markets = new IPToken[](2);
        markets[0] = IPToken(usdcMarket);
        markets[1] = IPToken(wethMarket);

        uint256[] memory caps = new uint256[](2);
        caps[0] = type(uint256).max;
        caps[1] = type(uint256).max;

        RiskEngineModule(riskEngine).setMarketBorrowCaps(markets, caps);
        RiskEngineModule(riskEngine).setMarketSupplyCaps(markets, caps);

        vm.stopPrank();
    }

    function deployPToken(
        address underlying_,
        string memory name_,
        string memory symbol_
    ) internal returns (address) {
        string[] memory pTokenFacets = new string[](3);
        pTokenFacets[0] = "InitialModuleBundle";
        pTokenFacets[1] = "InterestRateModule";
        pTokenFacets[2] = "PTokenModule";

        address[] memory pTokenModulesAddresses = new address[](3);
        pTokenModulesAddresses[0] = address(new InitialModuleBundle());
        pTokenModulesAddresses[1] = address(new InterestRateModule());
        pTokenModulesAddresses[2] = address(new PTokenModule());

        address _pToken = deployDiamond(pTokenFacets, pTokenModulesAddresses);

        InitialModuleBundle initialModuleBundle = InitialModuleBundle(_pToken);
        initialModuleBundle.initialize(admin);

        vm.startPrank(admin);
        PTokenModule pToken = PTokenModule(_pToken);
        pToken.initialize(
            underlying_,
            IRiskEngine(riskEngine),
            initialExchangeRate,
            reserveFactor,
            protocolSeizeShare,
            borrowRateMax,
            name_,
            symbol_,
            pTokenDecimals
        );

        InterestRateModule interestRateModule = InterestRateModule(_pToken);
        interestRateModule.initialize(
            baseRatePerYear,
            multiplierPerYear,
            jumpMultiplierPerYear,
            kink
        );
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

        riskEngine = deployDiamond(riskEngineModulesFacets, riskEngineModulesAddresses);

        InitialModuleBundle initialModuleBundle = InitialModuleBundle(riskEngine);
        initialModuleBundle.initialize(admin);

        return riskEngine;
    }

    function deployDiamond(string[] memory facets, address[] memory facetAddresses) internal returns (address) {
        vm.startPrank(admin);
        DiamondCutFacet diamondCutFacet = new DiamondCutFacet();

        DiamondCutFacet diamond = DiamondCutFacet(address(new Diamond(admin, address(diamondCutFacet))));

        DiamondLoupeFacet diamondLoupeFacet = new DiamondLoupeFacet();

        bytes4[] memory diamondLoupeFacetSelectors =
            generateSelectors("DiamondLoupeFacet");

        DiamondCutFacet.FacetCut[] memory diamondLoupeFacetCut = new DiamondCutFacet.FacetCut[](facets.length + 1);
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
            strings.slice memory selectr = s.split(comma).until(dbquote); // advance s to the next comma
        }
        return selectors;
    }
}
