pragma solidity 0.8.28;

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

    uint256 firstKink;
    uint256 secondKink;
    uint256 baseMulPerYear;
    uint256 firstJumpMulPerYear;
    uint256 secondJumpMulPerYear;

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

        uint256 secondKinkLocal = 0;

        // "ZeroValue()" selector
        vm.expectRevert(0x7c946ed7);
        pUSDCIRM.configureInterestRateModel(
            baseRatePerYear,
            multiplierPerYear,
            jumpMultiplierPerYear1,
            jumpMultiplierPerYear2,
            kink1,
            secondKinkLocal
        );
    }

    function testConfig_FailIfBaseRateNonZero() public {
        vm.prank(getAdmin());

        // "InvalidMultiplierForNonZeroBaseRate()" selector
        vm.expectRevert(0x435fecd9);
        pUSDCIRM.configureInterestRateModel(
            1,
            multiplierPerYear,
            jumpMultiplierPerYear1,
            jumpMultiplierPerYear2,
            kink1,
            kink2
        );
    }

    function testConfig_FailIfNotInOrder() public {
        vm.startPrank(getAdmin());

        // "InvalidKinkOrMultiplierOrder()" selector
        vm.expectRevert(0x397bc3d5);
        pUSDCIRM.configureInterestRateModel(
            baseRatePerYear, 0, jumpMultiplierPerYear2, multiplierPerYear, 0, kink2
        );

        // "InvalidKinkOrMultiplierOrder()" selector
        vm.expectRevert(0x397bc3d5);
        pUSDCIRM.configureInterestRateModel(
            0, 0, multiplierPerYear, jumpMultiplierPerYear2, kink2, kink2
        );

        vm.stopPrank();
    }

    function testConfig_SetParams(uint256[2] memory amounts) public {
        secondKink = bound(secondKink, 1, 1e18);
        firstKink = bound(firstKink, 0, secondKink - 1);
        baseRatePerYear = bound(baseRatePerYear, 0, amounts[0]);
        baseMulPerYear = amounts[1];
        secondJumpMulPerYear = bound(secondJumpMulPerYear, 1, type(uint256).max);
        vm.assume(firstJumpMulPerYear < secondJumpMulPerYear);

        vm.prank(getAdmin());
        pUSDCIRM.configureInterestRateModel(
            baseRatePerYear,
            baseMulPerYear,
            firstJumpMulPerYear,
            secondJumpMulPerYear,
            firstKink,
            secondKink
        );

        (uint256 set1stKink, uint256 set2ndKink) = pUSDCIRM.kinks();
        uint256 setBaseRate = pUSDCIRM.baseRatePerSecond();
        (uint256 setBaseMultiplier, uint256 set1stJump, uint256 set2ndJump) =
            pUSDCIRM.multipliers();

        assertEq(set1stKink, firstKink);
        assertEq(set2ndKink, secondKink);
        assertEq(setBaseRate, baseRatePerYear / SECONDS_PER_YEAR);
        assertEq(setBaseMultiplier, baseMulPerYear / SECONDS_PER_YEAR);
        assertEq(set1stJump, firstJumpMulPerYear / SECONDS_PER_YEAR);
        assertEq(set2ndJump, secondJumpMulPerYear / SECONDS_PER_YEAR);
    }
}
