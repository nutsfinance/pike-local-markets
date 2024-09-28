pragma solidity 0.8.20;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {TestFork} from "@helpers/TestFork.sol";

import {MockOracle} from "@mocks/MockOracle.sol";

contract ForkGeneral is TestFork {
    IPToken pUSDC;
    IPToken pWETH;

    MockOracle mockOracle;

    IRiskEngine re;

    function setUp() public {
        init();

        pUSDC = getPToken("pUSDC");
        pWETH = getPToken("pWETH");
        re = getRiskEngine();
        mockOracle = MockOracle(re.oracle());
    }

    function testD() public {
        address user1 = makeAddr("user1");
        setDebug(false);
        doDeposit(user1, user1, address(pUSDC), 100e6);
    }
}
