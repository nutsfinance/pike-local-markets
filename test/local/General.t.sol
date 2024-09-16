pragma solidity 0.8.20;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {TestLocal} from "@helpers/TestLocal.sol";

import {MockOracle} from "@mocks/MockOracle.sol";

contract LocalGeneral is TestLocal {
    IPToken pUSDC;
    IPToken pWETH;

    MockOracle mockOracle;

    IRiskEngine re;

    function setUp() public {
        init();

        // eth price = 2000$, usdc price = 1$
        pUSDC = getPToken("pUSDC");
        pWETH = getPToken("pWETH");
        re = getRiskEngine();
        mockOracle = MockOracle(re.oracle());
    }

    function testD() public {
        address user1 = makeAddr("user1");
        setDebug(true);
        doDeposit(user1, user1, address(pUSDC), 100e6);
    }

    function testDBehalf() public {
        address user1 = makeAddr("user1");
        address onBehalf = makeAddr("onBehalf");
        setDebug(true);
        doDeposit(user1, onBehalf, address(pUSDC), 100e6);
    }

    function testDB() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");
        setDebug(true);

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);

        doDepositAndEnter(user1, user1, address(pUSDC), 2000e6);
        doBorrow(user1, user1, address(pWETH), 0.745e18);
    }

    function testDBBehalf() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");
        address onBehalf = makeAddr("onBehalf");
        setDebug(true);

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);

        doDepositAndEnter(onBehalf, onBehalf, address(pUSDC), 2000e6);
        // "DelegateNotAllowed()" selector
        doBorrowRevert(user1, onBehalf, address(pWETH), 0.745e18, 0xf0f402cc);

        doDelegate(onBehalf, user1, pWETH, true);

        doBorrow(user1, onBehalf, address(pWETH), 0.745e18);
    }

    function testDBR() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");
        setDebug(true);

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);

        doDepositAndEnter(user1, user1, address(pUSDC), 2000e6);
        doBorrow(user1, user1, address(pWETH), 0.745e18);
        doRepay(user1, user1, address(pWETH), 0.745e18);
    }

    function testDBRBehalf() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");
        address onBehalf = makeAddr("onBehalf");
        setDebug(true);

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);

        doDepositAndEnter(onBehalf, onBehalf, address(pUSDC), 2000e6);
        doBorrow(onBehalf, onBehalf, address(pWETH), 0.745e18);
        doRepay(user1, onBehalf, address(pWETH), 0.745e18);
    }

    function testDBRW() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");
        setDebug(true);

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);

        doDepositAndEnter(user1, user1, address(pUSDC), 2000e6);
        doBorrow(user1, user1, address(pWETH), 0.745e18);
        doRepay(user1, user1, address(pWETH), 0.745e18);
        doWithdrawUnderlying(user1, user1, address(pUSDC), 2000e6);
    }

    function testDBRWBehalf() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");
        address onBehalf = makeAddr("onBehalf");
        setDebug(true);

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);

        doDepositAndEnter(onBehalf, onBehalf, address(pUSDC), 2000e6);
        doBorrow(onBehalf, onBehalf, address(pWETH), 0.745e18);
        doRepay(onBehalf, onBehalf, address(pWETH), 0.745e18);
        // "DelegateNotAllowed()" selector
        doWithdrawUnderlyingRevert(user1, onBehalf, address(pUSDC), 2000e6, 0xf0f402cc);

        doDelegate(onBehalf, user1, pUSDC, true);

        doWithdrawUnderlying(user1, onBehalf, address(pUSDC), 2000e6);
    }

    function testDBL() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");
        address liquidator = makeAddr("liquidator");
        setDebug(true);

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pUSDC), 2000e6);

        doDepositAndEnter(user1, user1, address(pWETH), 1e18);
        doBorrow(user1, user1, address(pUSDC), 1450e6);

        // 1450 / 0.825(weth liq threshold) = 1757.57 is liquidation threshold price for collateral

        mockOracle.setPrice(address(pWETH), 1757e6, 18);

        LiquidationParams memory lp = LiquidationParams({
            prankAddress: liquidator,
            userToLiquidate: user1,
            collateralPToken: address(pWETH),
            borrowedPToken: address(pUSDC),
            repayAmount: 725e6,
            expectRevert: false,
            error: bytes4(0)
        });

        doLiquidate(lp);
    }
}
