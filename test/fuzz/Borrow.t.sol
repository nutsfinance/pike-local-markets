pragma solidity 0.8.20;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {TestFuzz} from "@helpers/TestFuzz.sol";

import {MockOracle} from "@mocks/MockOracle.sol";

contract FuzzBorrow is TestFuzz {
    IPToken pUSDC;
    IPToken pWETH;
    IRiskEngine re;

    MockOracle mockOracle;

    address borrower;
    address onBehalfOf;
    uint256 usdcPrice;
    uint256 wethPrice;
    uint256 usdcCF;
    uint256 usdcToDeposit;
    uint256 wethToBorrow;
    uint256 pTokenTotalSupply;
    uint256 totalBorrows;
    uint256 cash;
    uint256 usdcTotalSupply;
    uint256 usdcTotalBorrows;
    uint256 usdcCash;
    uint256 wethTotalSupply;
    uint256 wethTotalBorrows;
    uint256 wethCash;

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

    function testFuzz_borrow(address[2] memory addresses, uint256[8] memory amounts)
        public
    {
        borrower = addresses[0];
        onBehalfOf = addresses[1];
        usdcPrice = amounts[0];
        wethPrice = amounts[1];
        usdcCF = amounts[2];
        usdcToDeposit = amounts[3];
        wethToBorrow = amounts[4];
        pTokenTotalSupply = amounts[5];
        totalBorrows = amounts[6];
        cash = amounts[7];

        /// 0.98-1.02$
        usdcPrice = bound(usdcPrice, 0.98e6, 1.02e6);
        /// 1000-4000$
        wethPrice = bound(wethPrice, 1000e6, 4000e6);
        /// 10-90%
        usdcCF = bound(usdcCF, 10e16, 90e16);
        usdcToDeposit = bound(usdcToDeposit, 100e6, 1e15);
        /// ± 0.00001% deviate from CF
        wethToBorrow = bound(
            wethToBorrow,
            1e10,
            usdcToDeposit * usdcPrice * (usdcCF - 0.00001e16) / (wethPrice * 1e6)
        );
        usdcCash = bound(cash, 10e6, 1e15);
        usdcTotalBorrows = bound(totalBorrows, 10e6, 1e15);
        usdcTotalSupply = bound(pTokenTotalSupply, 10e6, (usdcCash + usdcTotalBorrows));
        wethCash = bound(cash, 1e10, 400e21);
        wethCash = Math.max(wethCash, wethToBorrow);
        wethTotalBorrows = bound(totalBorrows, 1e10, 400e21);
        wethTotalSupply = bound(pTokenTotalSupply, 1e10, (wethCash + wethTotalBorrows));

        vm.assume(
            borrower != address(pUSDC) && borrower != address(pWETH)
                && borrower != address(0)
        );
        vm.assume(
            onBehalfOf != address(pUSDC) && onBehalfOf != address(pWETH)
                && onBehalfOf != address(0)
        );
        vm.assume((usdcCash + usdcTotalBorrows) / usdcTotalSupply < 8);
        vm.assume((wethCash + wethTotalBorrows) / wethTotalSupply < 8);

        vm.prank(getAdmin());
        re.setCollateralFactor(pUSDC, usdcCF, usdcCF);
        mockOracle.setPrice(address(pWETH), wethPrice, 18);
        mockOracle.setPrice(address(pUSDC), usdcPrice, 6);

        setPTokenTotalSupply(address(pUSDC), usdcTotalSupply);
        setTotalBorrows(address(pUSDC), usdcTotalBorrows);
        deal(address(pUSDC.underlying()), address(pUSDC), usdcCash);

        setPTokenTotalSupply(address(pWETH), wethTotalSupply);
        setTotalBorrows(address(pWETH), wethTotalBorrows);
        deal(address(pWETH.underlying()), address(pWETH), wethCash);
        if (borrower != onBehalfOf) {
            vm.prank(onBehalfOf);
            re.updateDelegate(borrower, true);
        }

        doDepositAndEnter(borrower, onBehalfOf, address(pUSDC), usdcToDeposit);
        doBorrow(borrower, onBehalfOf, address(pWETH), wethToBorrow);
    }
}
