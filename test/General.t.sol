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
        pUSDC = getPToken("pUSDC");
        pWETH = getPToken("pWETH");
        re = getRiskEngine();
    }

    function testD() public {
        address caller = makeAddr("user1");
        setDebug(true);
        doDeposit(caller, caller, address(pUSDC), 100e6);
    }
}
