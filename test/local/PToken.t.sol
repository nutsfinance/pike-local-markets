pragma solidity 0.8.28;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {PTokenModule} from "@modules/pToken/PTokenModule.sol";
import {RiskEngineModule} from "@modules/riskEngine/RiskEngineModule.sol";
import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {TestLocal} from "@helpers/TestLocal.sol";

import {MockOracle} from "@mocks/MockOracle.sol";

contract LocalPToken is TestLocal {
    using stdStorage for StdStorage;

    IPToken pUSDC;
    IPToken pWETH;

    MockOracle mockOracle;

    IRiskEngine re;

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
        mockOracle = MockOracle(re.oracle());
    }

    function testInitialize_FailIfAlreadyInitializedOrZeroAddress() public {
        vm.prank(getAdmin());

        // "AlreadyInitialized()" selector
        vm.expectRevert(0x0dc149f0);
        PTokenModule(address(pUSDC)).initialize(
            address(0), IRiskEngine(address(0)), 0, 0, 0, 0, "", "", 0
        );
    }

    function testInitialize_FailIWithZeroValues() public {
        address pToken = address(new PTokenModule());
        // owner slot
        bytes32 slot = 0x74d6be38627e7912e34c50c5cbc5a4826c01ce9f17c41aaeea1b0611189c7000;
        vm.store(pToken, slot, bytes32(abi.encode(getAdmin())));

        vm.startPrank(getAdmin());
        // "ZeroValue()" selector
        vm.expectRevert(0x7c946ed7);
        PTokenModule(pToken).initialize(
            address(0), IRiskEngine(address(0)), 0, 0, 0, 0, "", "", 0
        );

        // "ZeroAddress()" selector
        vm.expectRevert(0xd92e233d);
        PTokenModule(pToken).initialize(
            address(0), IRiskEngine(address(0)), 1, 1, 1, 1, "", "", 0
        );

        // "ZeroAddress()" selector
        vm.expectRevert(0xd92e233d);
        PTokenModule(pToken).initialize(
            address(1), IRiskEngine(address(0)), 1, 1, 1, 1, "", "", 0
        );

        vm.stopPrank();
    }

    function testSetRE_Success() public {
        IRiskEngine newRE = IRiskEngine(new RiskEngineModule());

        vm.prank(getAdmin());
        pUSDC.setRiskEngine(newRE);

        assertEq(address(newRE), address(pUSDC.riskEngine()));
    }

    function testSweep_FailIfUnderlying() public {
        IERC20 underlying = IERC20(pUSDC.underlying());
        vm.prank(getAdmin());
        // "SweepNotAllowed()" selector
        vm.expectRevert(0x00b5509b);
        pUSDC.sweepToken(underlying);
    }

    function testMintBehalfOf_FailIfAddressIsZero() public {
        // "ZeroAddress()" selector
        vm.expectRevert(0xd92e233d);
        pUSDC.mintOnBehalfOf(address(0), 0);
    }

    function testLiquidateBorrow_FailIfPTokenCollateralIsInvalid() public {
        address pToken = address(new PTokenModule());

        // "LiquidateAccrueCollateralInterestFailed()" selector
        vm.expectRevert(0x181b94c8);
        pUSDC.liquidateBorrow(address(0), 0, IPToken(pToken));
    }

    function testApprove_FailIfAddressZero() public {
        // "ZeroAddress()" selector
        vm.expectRevert(0xd92e233d);
        pUSDC.approve(address(0), 0);
    }

    function testAccrueInterest_ReturnIfBorrowRateMaxMantissaReached() public {
        address user1 = makeAddr("user1");
        doDepositAndEnter(user1, user1, address(pUSDC), 2000e6);
        doBorrow(user1, user1, address(pUSDC), 1000e6);

        // borrowRateMaxMantissa slot
        bytes32 slot = 0x0be5863c0c782626615eed72fc4c521bcfabebe439cbc2683e49afadb49a0d08;
        vm.store(address(pUSDC), slot, bytes32(0));

        //skip time
        skip(1);

        uint256 prevIndex = pUSDC.borrowIndex();
        pUSDC.accrueInterest();
        assertEq(prevIndex, pUSDC.borrowIndex());
    }

    function testRedeem_FailIfNotAllowed() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);

        doDepositAndEnter(user1, user1, address(pUSDC), 2000e6);

        doBorrow(user1, user1, address(pWETH), 0.745e18);

        vm.prank(user1);
        // "RedeemRiskEngineRejection(uint256)" selector
        vm.expectRevert(abi.encodePacked(bytes4(0x9759ead5), uint256(3)));
        pUSDC.redeemUnderlying(1000e6);

        vm.prank(depositor);
        // "RedeemTransferOutNotPossible()" selector
        vm.expectRevert(0x91240a1b);
        pWETH.redeemUnderlying(1e18);
    }

    function testBorrow_FailIfNotEnoughCash() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);

        doDepositAndEnter(user1, user1, address(pUSDC), 2000e6);

        deal(address(pWETH.underlying()), address(pWETH), 0);
        //"BorrowCashNotAvailable()" selector
        doBorrowRevert(
            user1, user1, address(pWETH), 0.745e18, abi.encodePacked(bytes4(0x48c25881))
        );
    }

    function testBorrow_FailIfNotListed() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);
        doDepositAndEnter(user1, user1, address(pUSDC), 2000e6);
        doBorrow(user1, user1, address(pWETH), 0.745e18);

        changeList(address(pWETH), false);

        //"RepayBorrowRiskEngineRejection(uint256)" selector
        doRepayRevert(
            user1,
            user1,
            address(pWETH),
            0.745e18,
            abi.encodePacked(bytes4(0xbb0619b7), uint256(4))
        );
    }

    function testLiquidate_FailIfNotListed() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");
        address liquidator = makeAddr("liquidator");

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pUSDC), 2000e6);

        doDepositAndEnter(user1, user1, address(pWETH), 1e18);
        doBorrow(user1, user1, address(pUSDC), 1450e6);

        // 1450 / 0.825(weth liq threshold) = 1757.57 is liquidation threshold price for collateral

        mockOracle.setPrice(address(pWETH), 1757e6, 18);

        changeList(address(pWETH), false);

        //"LiquidateRiskEngineRejection(uint256)" selector
        LiquidationParams memory lp = LiquidationParams({
            prankAddress: liquidator,
            userToLiquidate: user1,
            collateralPToken: address(pWETH),
            borrowedPToken: address(pUSDC),
            repayAmount: 725e6,
            expectRevert: true,
            error: abi.encodePacked(bytes4(0xd1192049), uint256(4))
        });

        doLiquidate(lp);
    }

    function testLiquidate_FailIfBorrowerIsLiquidator() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pUSDC), 2000e6);

        doDepositAndEnter(user1, user1, address(pWETH), 1e18);
        doBorrow(user1, user1, address(pUSDC), 1450e6);

        // 1450 / 0.825(weth liq threshold) = 1757.57 is liquidation threshold price for collateral

        mockOracle.setPrice(address(pWETH), 1757e6, 18);

        //"LiquidateLiquidatorIsBorrower()" selector
        LiquidationParams memory lp = LiquidationParams({
            prankAddress: user1,
            userToLiquidate: user1,
            collateralPToken: address(pWETH),
            borrowedPToken: address(pUSDC),
            repayAmount: 725e6,
            expectRevert: true,
            error: abi.encodePacked(bytes4(0x6f469884))
        });

        doLiquidate(lp);
    }

    function testLiquidate_FailIfRepayIsZero() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");
        address liquidator = makeAddr("liquidator");

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pUSDC), 2000e6);

        doDepositAndEnter(user1, user1, address(pWETH), 1e18);
        doBorrow(user1, user1, address(pUSDC), 1450e6);

        // 1450 / 0.825(weth liq threshold) = 1757.57 is liquidation threshold price for collateral

        mockOracle.setPrice(address(pWETH), 1757e6, 18);

        //"LiquidateCloseAmountIsZero()" selector
        LiquidationParams memory lp = LiquidationParams({
            prankAddress: liquidator,
            userToLiquidate: user1,
            collateralPToken: address(pWETH),
            borrowedPToken: address(pUSDC),
            repayAmount: 0,
            expectRevert: true,
            error: abi.encodePacked(bytes4(0xd29da7ef))
        });

        doLiquidate(lp);
    }

    function testLiquidate_FailIfPriceIsZero() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");
        address liquidator = makeAddr("liquidator");

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pUSDC), 2000e6);

        doDepositAndEnter(user1, user1, address(pWETH), 1e18);
        doBorrow(user1, user1, address(pUSDC), 1450e6);

        // 1450 / 0.825(weth liq threshold) = 1757.57 is liquidation threshold price for collateral

        mockOracle.setPrice(address(pWETH), 1757e6, 18);
        mockOracle.setPrice(address(pUSDC), 0, 18);

        //"LiquidateRiskEngineRejection(uint256)" selector
        LiquidationParams memory lp = LiquidationParams({
            prankAddress: liquidator,
            userToLiquidate: user1,
            collateralPToken: address(pWETH),
            borrowedPToken: address(pUSDC),
            repayAmount: 725e6,
            expectRevert: true,
            error: abi.encodePacked(bytes4(0xd1192049), uint256(5))
        });

        doLiquidate(lp);
    }

    function testDeposit_FailIfReenter() public {
        address depositor = makeAddr("depositor");

        address pReenter = deployPToken(
            "pike-usdc", "pUSDC", 6, 1e6, 74.5e16, 84.5e16, deployMockReentrantToken
        );
        // "ReentrancyGuardReentrantCall()" selector
        doDepositRevert(
            depositor, depositor, pReenter, 2000e6, abi.encodePacked(bytes4(0x3ee5aeb5))
        );
    }
}
