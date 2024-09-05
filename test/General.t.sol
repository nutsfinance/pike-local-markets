pragma solidity 0.8.20;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {TestHelpers} from "@helpers/TestHelpers.sol";

contract TestContract is TestHelpers {
    IPToken pUSDC;
    IPToken pWETH;

    IRiskEngine re;

    function setUp() public {
        /// eth price = 2000$, usdc price = 1$
        pUSDC = getPToken("pUSDC");
        pWETH = getPToken("pWETH");
        re = getRiskEngine();
    }

    function testD() public {
        address user1 = makeAddr("user1");
        setDebug(true);
        doDeposit(user1, user1, address(pUSDC), 100e6);
    }

    function testDB() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");
        setDebug(true);

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);

        doDepositAndEnter(address(re), user1, user1, address(pUSDC), 2000e6);
        doBorrow(user1, user1, address(pWETH), 0.745e18);
    }

    function testDBR() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");
        setDebug(true);

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);

        doDepositAndEnter(address(re), user1, user1, address(pUSDC), 2000e6);
        doBorrow(user1, user1, address(pWETH), 0.745e18);
        doRepay(user1, user1, address(pWETH), 0.745e18);
    }

    function testDBRW() public {
        address user1 = makeAddr("user1");
        address depositor = makeAddr("depositor");
        setDebug(true);

        ///porivde liquidity
        doDeposit(depositor, depositor, address(pWETH), 1e18);

        doDepositAndEnter(address(re), user1, user1, address(pUSDC), 2000e6);
        doBorrow(user1, user1, address(pWETH), 0.745e18);
        doRepay(user1, user1, address(pWETH), 0.745e18);
        doWithdrawUnderlying(user1, user1, address(pUSDC), 2000e6);
    }
}
