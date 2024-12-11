pragma solidity 0.8.28;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";
import {IRBAC} from "@modules/common/RBACModule.sol";
import {PTokenModule} from "@modules/pToken/PTokenModule.sol";
import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {TestLocal} from "@helpers/TestLocal.sol";
import {MockOracle} from "@mocks/MockOracle.sol";

contract LocalEMode is TestLocal {
    IPToken pUSDC;
    IPToken pWETH;
    IPToken pSTETH;

    MockOracle mockOracle;

    IRiskEngine re;

    uint8 categoryId = 1;

    address[] pToken = new address[](2);
    bool[] collateralPermissions = new bool[](2);
    bool[] borrowPermissions = new bool[](2);

    function setUp() public {
        setDebug(false);
        setAdmin(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        init();

        // eth price = 2000$, usdc price = 1$
        deployPToken("pike-usdc", "pUSDC", 6, 1e6, 74.5e16, 84.5e16, deployMockToken);
        deployPToken("pike-weth", "pWETH", 18, 2000e6, 72.5e16, 82.5e16, deployMockToken);
        deployPToken(
            "pike-steth", "pSTETH", 18, 2000e6, 72.5e16, 82.5e16, deployMockToken
        );

        /// eth price = 2000$, usdc price = 1$
        pUSDC = getPToken("pUSDC");
        pWETH = getPToken("pWETH");
        pSTETH = getPToken("pSTETH");
        re = getRiskEngine();
        mockOracle = MockOracle(re.oracle());

        pToken[0] = address(pWETH);
        pToken[1] = address(pSTETH);

        collateralPermissions[0] = false;
        collateralPermissions[1] = true;
        borrowPermissions[0] = true;
        borrowPermissions[1] = false;

        IRiskEngine.BaseConfiguration memory baseConfig =
            IRiskEngine.BaseConfiguration(90e16, 93e16, 102e16);

        vm.startPrank(getAdmin());

        re.supportEMode(
            categoryId, true, pToken, collateralPermissions, borrowPermissions
        );
        re.configureEMode(categoryId, baseConfig);

        vm.stopPrank();

        address depositor = makeAddr("depositor");
        doDeposit(depositor, depositor, address(pWETH), 10e18);
        doDeposit(depositor, depositor, address(pSTETH), 10e18);
        doDeposit(depositor, depositor, address(pWETH), 10e18);
    }

    function testSwitchEMode_Success() public {
        address user1 = makeAddr("user1");
        // deposit and unsupported asset and switch to emode
        doDeposit(user1, user1, address(pUSDC), 2000e6);

        vm.prank(user1);
        re.switchEMode(1);

        assertEq(re.accountCategory(user1), 1);

        // should not enter if asset not supported only supply
        doDepositAndEnter(user1, user1, address(pUSDC), 2000e6);
        assertEq(re.checkCollateralMembership(user1, pUSDC), false);

        doDepositAndEnter(user1, user1, address(pSTETH), 1e18);
        // with e-mode should be able to borrow up to 90% CF
        doBorrow(user1, user1, address(pWETH), 90e16);
        // decrease debt to 70e16 to met default mode 70% CF
        doRepay(user1, user1, address(pWETH), 20e16);

        // switch to default mode with 72.5% CF
        vm.prank(user1);
        re.switchEMode(0);
    }

    function testSwitchEMode_FailIfNotSupported() public {
        address user1 = makeAddr("user1");
        // deposit an unsupported asset and enable as collateral
        doDepositAndEnter(user1, user1, address(pUSDC), 2000e6);

        // fail for unsupported USDC in e-mode as collateral
        // "InvalidCollateralStatus(address)" selector
        vm.startPrank(user1);
        vm.expectRevert(abi.encodePacked(bytes4(0x0f3b8268), abi.encode(address(pUSDC))));
        re.switchEMode(1);

        // should able to switch after disable collateral
        re.exitMarket(address(pUSDC));
        re.switchEMode(1);
        vm.stopPrank();

        address[] memory ptokens = new address[](1);
        ptokens[0] = address(pWETH);
        // should fail to enable collateral for unsupported asset in e-mode (weth)
        doDeposit(user1, user1, address(pWETH), 1e18);
        vm.prank(user1);
        re.enterMarkets(ptokens);
        assertEq(re.checkCollateralMembership(user1, pWETH), false);
        // "BorrowRiskEngineRejection(uint256)" selector
        doDepositAndEnter(user1, user1, address(pSTETH), 1e18);
        // should fail to borrow unsupported asset in e-mode
        doBorrowRevert(
            user1,
            user1,
            address(pSTETH),
            5e17,
            abi.encodePacked(bytes4(0xcd617e38), abi.encode(10))
        );

        // switch to default
        vm.prank(user1);
        re.switchEMode(0);

        doBorrow(user1, user1, address(pSTETH), 5e17);
        // fail for unsupported USDC in e-mode as borrow
        // "InvalidBorrowStatus(address)" selector
        vm.prank(user1);
        vm.expectRevert(abi.encodePacked(bytes4(0xde3a9c2d), abi.encode(address(pSTETH))));
        re.switchEMode(1);
    }

    function testSwitchEMode_FailIfNotAllowed() public {
        address user1 = makeAddr("user1");

        // fail if e-mode is not supported
        // "InvalidCategory()" selector
        vm.startPrank(user1);
        vm.expectRevert(abi.encodePacked(bytes4(0xd67592f6)));
        re.switchEMode(2);

        // fail if e-mode is already activated
        // "AlreadyInEMode()" selector
        vm.startPrank(user1);
        vm.expectRevert(abi.encodePacked(bytes4(0x99f962a0)));
        re.switchEMode(0);
    }
}
