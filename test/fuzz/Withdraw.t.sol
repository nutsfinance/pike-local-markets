pragma solidity 0.8.20;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {TestFuzz} from "@helpers/TestFuzz.sol";

import {MockOracle} from "@mocks/MockOracle.sol";

contract FuzzWithdraw is TestFuzz {
    IPToken pUSDC;
    IPToken pWETH;
    IRiskEngine re;

    MockOracle mockOracle;

    address withdrawer;
    address onBehalfOf;
    uint256 underlyingToDeposit;
    uint256 underlyingToWithdraw;
    uint256 pTokenToWithdraw;
    uint256 pTokenTotalSupply;
    uint256 totalBorrows;
    uint256 cash;

    function setUp() public {
        setDebug(false);
        setAdmin(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
        init();

        // eth price = 2000$, usdc price = 1$
        deployPToken("pike-usdc", "pUSDC", 6, 1e6, 74.5e16, 84.5e16, deployMockToken);
        deployPToken("pike-weth", "pWETH", 18, 2000e6, 72.5e16, 82.5e16, deployMockToken);

        pUSDC = getPToken("pUSDC");
        pWETH = getPToken("pWETH");
        re = getRiskEngine();
        mockOracle = MockOracle(re.oracle());
    }

    function testFuzz_withdrawUnderlying(
        address[2] memory addresses,
        uint256[5] memory amounts
    ) public {
        withdrawer = addresses[0];
        onBehalfOf = addresses[1];
        underlyingToDeposit = amounts[0];
        underlyingToWithdraw = amounts[1];
        pTokenTotalSupply = amounts[2];
        totalBorrows = amounts[3];
        cash = amounts[4];

        underlyingToDeposit = bound(underlyingToDeposit, 10e6, 1e15);
        underlyingToWithdraw = bound(underlyingToWithdraw, 10e6, underlyingToDeposit);
        cash = bound(cash, 10e6, 1e15);
        totalBorrows = bound(totalBorrows, 10e6, 1e15);
        pTokenTotalSupply = bound(pTokenTotalSupply, 10e6, (totalBorrows + cash));

        vm.assume(withdrawer != address(pUSDC) && withdrawer != address(0));
        vm.assume(onBehalfOf != address(pUSDC) && onBehalfOf != address(0));
        vm.assume((cash + totalBorrows) / pTokenTotalSupply < 8);

        setPTokenTotalSupply(address(pUSDC), pTokenTotalSupply);
        setTotalBorrows(address(pUSDC), totalBorrows);
        deal(address(pUSDC.underlying()), address(pUSDC), cash);
        if (withdrawer != onBehalfOf) {
            vm.prank(onBehalfOf);
            re.updateDelegate(withdrawer, true);
        }

        doDepositAndEnter(withdrawer, onBehalfOf, address(pUSDC), underlyingToDeposit);
        doWithdrawUnderlying(withdrawer, onBehalfOf, address(pUSDC), underlyingToWithdraw);
    }

    function testFuzz_withdraw(address[2] memory addresses, uint256[5] memory amounts)
        public
    {
        withdrawer = addresses[0];
        onBehalfOf = addresses[1];
        underlyingToDeposit = amounts[0];
        pTokenToWithdraw = amounts[1];
        pTokenTotalSupply = amounts[2];
        totalBorrows = amounts[3];
        cash = amounts[4];

        underlyingToDeposit = bound(underlyingToDeposit, 10e6, 1e15);
        cash = bound(cash, 10e6, 1e15);
        totalBorrows = bound(totalBorrows, 10e6, 1e15);
        pTokenTotalSupply = bound(pTokenTotalSupply, 10e6, (totalBorrows + cash));

        vm.assume(withdrawer != address(pUSDC) && withdrawer != address(0));
        vm.assume(onBehalfOf != address(pUSDC) && onBehalfOf != address(0));
        vm.assume((cash + totalBorrows) / pTokenTotalSupply < 8);

        setPTokenTotalSupply(address(pUSDC), pTokenTotalSupply);
        setTotalBorrows(address(pUSDC), totalBorrows);
        deal(address(pUSDC.underlying()), address(pUSDC), cash);
        if (withdrawer != onBehalfOf) {
            vm.prank(onBehalfOf);
            re.updateDelegate(withdrawer, true);
        }

        doDepositAndEnter(withdrawer, onBehalfOf, address(pUSDC), underlyingToDeposit);

        pTokenToWithdraw = bound(pTokenToWithdraw, 1, pUSDC.balanceOf(onBehalfOf));
        doWithdraw(withdrawer, onBehalfOf, address(pUSDC), pTokenToWithdraw);
    }
}
