pragma solidity 0.8.20;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {
    InterestRateModule,
    IInterestRateModel
} from "@modules/interestRateModel/InterestRateModule.sol";
import {TestLocal} from "@helpers/TestLocal.sol";

import {MockOracle} from "@mocks/MockOracle.sol";

contract LocalIRM is TestLocal {
    IPToken pUSDC;
    IPToken pWETH;
    IInterestRateModel pUSDCIRM;
    IInterestRateModel pWETHIRM;

    MockOracle mockOracle;

    IRiskEngine re;

    function setUp() public {
        setDebug(false);
        setAdmin(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        init();

        // eth price = 2000$, usdc price = 1$
        deployPToken("pike-usdc", "pUSDC", 6, 1e6, 74.5e16, 84.5e16, deployMockToken);
        deployPToken("pike-weth", "pWETH", 18, 2000e6, 72.5e16, 82.5e16, deployMockToken);

        pUSDC = getPToken("pUSDC");
        pUSDCIRM = getIRM("pUSDC");
        pWETH = getPToken("pWETH");
        pWETHIRM = getIRM("pWETH");
        re = getRiskEngine();
        mockOracle = MockOracle(re.oracle());
    }

    function testInitialize_FailIfInitialized() public {
        assertEq(pUSDCIRM.getUtilization(0, 0, 0), 0);
        assertEq(pWETHIRM.getUtilization(0, 0, 0), 0);

        vm.prank(getAdmin());
        // "AlreadyInitialized()" selector
        vm.expectRevert(0x0dc149f0);
        InterestRateModule(address(pUSDCIRM)).initialize(0, 0, 0, 0);
    }
}
