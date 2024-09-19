pragma solidity 0.8.20;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {TestLocal} from "@helpers/TestLocal.sol";

import {MockOracle} from "@mocks/MockOracle.sol";

contract LocalRiskEngine is TestLocal {
    IPToken pUSDC;
    IPToken pWETH;

    MockOracle mockOracle;

    IRiskEngine re;

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
        re = getRiskEngine();
        mockOracle = MockOracle(re.oracle());
    }

    function testPauseMint_Success() public {
        address user1 = makeAddr("user1");

        vm.prank(getAdmin());
        re.setMintPaused(pUSDC, true);

        // "MintPaused()" selector
        doDepositRevert(
            user1, user1, address(pUSDC), 2000e6, abi.encodePacked(bytes4(0xd7d248ba))
        );
    }

    function testPauseBorrow_Success() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");

        vm.prank(getAdmin());
        re.setBorrowPaused(pWETH, true);

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);

        doDepositAndEnter(user1, user1, address(pUSDC), 2000e6);
        // "BorrowPaused()" selector
        doBorrowRevert(
            user1, user1, address(pWETH), 0.745e18, abi.encodePacked(bytes4(0x12b0cb46))
        );
    }

    function testPauseTransfer_Success() public {
        address user1 = makeAddr("user1");
        address receiver = makeAddr("receiver");

        vm.prank(getAdmin());
        re.setTransferPaused(true);

        doDeposit(user1, user1, address(pUSDC), 2000e6);
        // "TransferPaused()" selector
        doTransferRevert(
            user1,
            user1,
            receiver,
            address(pUSDC),
            2000e6,
            abi.encodePacked(bytes4(0xcd1fda9f))
        );
    }

    function testPauseSeize_Success() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");
        address liquidator = makeAddr("liquidator");

        vm.prank(getAdmin());
        re.setSeizePaused(true);

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pUSDC), 2000e6);

        doDepositAndEnter(user1, user1, address(pWETH), 1e18);
        doBorrow(user1, user1, address(pUSDC), 1450e6);

        // 1450 / 0.825(weth liq threshold) = 1757.57 is liquidation threshold price for collateral

        mockOracle.setPrice(address(pWETH), 1757e6, 18);
        // "SeizePaused()" selector
        LiquidationParams memory lp = LiquidationParams({
            prankAddress: liquidator,
            userToLiquidate: user1,
            collateralPToken: address(pWETH),
            borrowedPToken: address(pUSDC),
            repayAmount: 725e6,
            expectRevert: true,
            error: abi.encodePacked(bytes4(0x0fe80ef6))
        });

        doLiquidate(lp);
    }

    function testBorrow_FailIfNotEntered() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);

        doDepositAndEnter(user1, user1, address(pUSDC), 2000e6);

        vm.prank(user1);
        re.exitMarket(address(pUSDC));

        assertEq(re.getAssetsIn(user1).length, 0, "assets are not empty");
        assertEq(re.checkMembership(user1, pUSDC), false, "still in market");
        // "BorrowRiskEngineRejection(3)" selector
        doBorrowRevert(
            user1,
            user1,
            address(pWETH),
            0.745e18,
            abi.encodePacked(bytes4(0xcd617e38), uint256(3))
        );
    }

    function testBorrow_FailIfCapReached() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");
        uint256 borrowAmount = 0.745e18;

        IPToken[] memory markets = new IPToken[](1);
        markets[0] = pWETH;

        uint256[] memory caps = new uint256[](1);
        caps[0] = borrowAmount - 1;

        vm.prank(getAdmin());
        re.setMarketBorrowCaps(markets, caps);

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);

        doDepositAndEnter(user1, user1, address(pUSDC), 2000e6);
        // "BorrowRiskEngineRejection(8)" selector
        doBorrowRevert(
            user1,
            user1,
            address(pWETH),
            0.745e18,
            abi.encodePacked(bytes4(0xcd617e38), uint256(8))
        );
    }

    function testMint_FailIfCapReached() public {
        address user1 = makeAddr("user1");
        uint256 mintAmount = 2000e6;

        IPToken[] memory markets = new IPToken[](1);
        markets[0] = pUSDC;

        uint256[] memory caps = new uint256[](1);
        caps[0] = mintAmount - 1;

        vm.prank(getAdmin());
        re.setMarketSupplyCaps(markets, caps);

        // "BorrowRiskEngineRejection(7)" selector
        doDepositRevert(
            user1,
            user1,
            address(pUSDC),
            mintAmount,
            abi.encodePacked(bytes4(0x1d3413fb), uint256(7))
        );
    }

    function testGetMarkets() public view {
        IPToken[] memory markets = re.getAllMarkets();

        assertEq(address(pUSDC), address(markets[0]));
        assertEq(address(pWETH), address(markets[1]));
    }

    function testDeprecateMarket() public {
        vm.startPrank(getAdmin());
        pUSDC.setReserveFactor(1e18);

        re.setCollateralFactor(pUSDC, 0, 0);
        re.setBorrowPaused(pUSDC, true);

        assertEq(re.isDeprecated(pUSDC), true, "not deprecated");
    }
}
