pragma solidity 0.8.25;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {
    DoubleJumpRateModel,
    IDoubleJumpRateModel
} from "@modules/interestRateModel/DoubleJumpRateModel.sol";
import {TestLocal} from "@helpers/TestLocal.sol";

import {MockOracle} from "@mocks/MockOracle.sol";

contract LocalIRM is TestLocal {
    IPToken pUSDC;
    IPToken pWETH;
    IDoubleJumpRateModel pUSDCIRM;
    IDoubleJumpRateModel pWETHIRM;

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

    function testConfig_FailIfSecondKinkIsZero() public {
        vm.prank(getAdmin());

        uint256 secondKink = 0;

        // "ZeroValue()" selector
        vm.expectRevert(0x7c946ed7);
        pUSDCIRM.configureInterestRateModel(
            baseRatePerYear, 0, multiplierPerYear, jumpMultiplierPerYear, 0, secondKink
        );
    }

    function testConfig_FailIfBaseRateNonZero() public {
        vm.prank(getAdmin());

        // "InvalidMultiplierForNonZeroBaseRate()" selector
        vm.expectRevert(0x435fecd9);
        pUSDCIRM.configureInterestRateModel(
            baseRatePerYear, 0, multiplierPerYear, jumpMultiplierPerYear, kink, kink
        );
    }

    function testConfig_FailIfNotInOrder() public {
        vm.startPrank(getAdmin());

        // "InvalidKinkOrMultiplierOrder()" selector
        vm.expectRevert(0x397bc3d5);
        pUSDCIRM.configureInterestRateModel(
            baseRatePerYear, 0, jumpMultiplierPerYear, multiplierPerYear, 0, kink
        );

        // "InvalidKinkOrMultiplierOrder()" selector
        vm.expectRevert(0x397bc3d5);
        pUSDCIRM.configureInterestRateModel(
            0, 0, multiplierPerYear, jumpMultiplierPerYear, kink, kink
        );

        vm.stopPrank();
    }
}
