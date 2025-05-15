// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {Multiply, IMultiply, IFLHelper} from "@periphery/Multiply.sol";
import {IPToken} from "@interfaces/IPToken.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {IOracleEngine} from "@oracles/interfaces/IOracleEngine.sol";
import {IV3SwapRouter} from "swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
import {IUniswapV3Factory} from "@periphery/interfaces/IProtocols.sol";
import {IZap} from "@periphery/interfaces/IProtocols.sol";
import {ISelfPeggingAsset} from "@periphery/interfaces/IProtocols.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Main test contract
contract MultiplyForkTest is Test {
    address USER = makeAddr("user");
    address OWNER = makeAddr("owner");

    // Pike Protocol addresses on Base mainnet
    address constant RISK_ENGINE = 0x1d2Fd1DDA993dd874577D971062fc46E8a4083C6;
    address constant ORACLE_ENGINE = 0x639a47a7a371d54e0A06c3a0f62772a583447dfc;
    address constant PTOKEN_WETH = 0xaBA720dB10134404a4D4D8Fee4C2e7F2Be043e58;
    address constant PTOKEN_LP = 0x6AF0EEC07cedbD188d930772bd97099cb1c80B7A; // WETH/wstETH LP PToken

    // Protocol addresses on Base mainnet
    address constant UNISWAP_V3_FACTORY = 0x33128a8fC17869897dcE68Ed026d694621f6FDfD;
    address constant UNISWAP_V3_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address constant AAVE_V3_LENDING_POOL = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;
    address constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    address constant MORPHO_BLUE = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address constant ZAP_CONTRACT = 0x30E6B0E3b024E605A8e8bF57CDB765D14AaD21EB;
    address constant SPA_ADDRESS = 0x2407f46cFB35930866E796bBc7F564311daF809b; // WETH/wstETH SPA

    // Tokens
    IERC20 public weth = IERC20(0x4200000000000000000000000000000000000006); // WETH on Base
    IERC20 public wstETH = IERC20(0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452); // wstETH on Base
    IERC20 public usdc = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913); // usdc on Base
    IERC20 public lpToken = IERC20(0x8453AabfF7D2A7b91953b62820806eE7Ab88864a); // WETH/wstETH LP token

    // Multiply contract
    Multiply public multiply;

    function setUp() public {
        // Fork Base mainnet
        vm.createSelectFork("https://mainnet.base.org");

        multiply = new Multiply(
            UNISWAP_V3_ROUTER,
            ZAP_CONTRACT,
            OWNER,
            UNISWAP_V3_FACTORY,
            AAVE_V3_LENDING_POOL,
            BALANCER_VAULT,
            MORPHO_BLUE
        );

        // Fund WETH
        deal(address(weth), USER, 1000 ether);
        deal(address(wstETH), USER, 1000 ether);
        deal(address(weth), OWNER, 1000 ether);
        deal(address(wstETH), OWNER, 1000 ether);

        vm.startPrank(USER);
        weth.approve(address(multiply), type(uint256).max);
        weth.approve(ZAP_CONTRACT, type(uint256).max);
        wstETH.approve(ZAP_CONTRACT, type(uint256).max);
        lpToken.approve(address(PTOKEN_LP), type(uint256).max);
        // Allow Multiply to borrow on behalf of the user
        IRiskEngine(RISK_ENGINE).updateDelegate(address(multiply), true);
        // enter markets
        address[] memory ptokens = new address[](1);
        ptokens[0] = PTOKEN_LP;
        IRiskEngine(RISK_ENGINE).enterMarkets(ptokens);

        // provide liquidity to LP token
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 10 ether;
        amounts[1] = 10 ether;

        IZap(ZAP_CONTRACT).zapIn(SPA_ADDRESS, address(lpToken), USER, 0, amounts);
        vm.stopPrank();

        // provide liquidity
        vm.startPrank(OWNER);
        weth.approve(address(PTOKEN_WETH), type(uint256).max);
        IPToken(PTOKEN_WETH).deposit(100 ether, OWNER);
        vm.stopPrank();
    }

    function testLeverageLP() public {
        address[] memory tokens = new address[](3);
        tokens[0] = address(weth); // Borrow WETH
        tokens[1] = address(wstETH); // wstETH on Base
        tokens[2] = IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(
            address(weth), address(wstETH), 100
        );

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1 ether; // Flash loan of 1 WETH
        amounts[1] = 0;
        amounts[2] = 0;

        IFLHelper.FlashLoanParams memory flParams = IFLHelper.FlashLoanParams({
            source: IFLHelper.FlashLoanSource.UNISWAP_V3,
            tokens: tokens,
            amounts: amounts
        });

        // **Leverage Parameters**
        uint24[2] memory feeTier;
        feeTier[0] = 0; // no needed using tapio for swap
        feeTier[1] = 100; // for fl pool (weth/usdc)

        uint256[2] memory minAmountOut;
        minAmountOut[0] = 0; // Minimum WETH out
        minAmountOut[1] = 0; // Minimum LP out

        IMultiply.LeverageLPParams memory params = IMultiply.LeverageLPParams({
            borrowPToken: PTOKEN_WETH,
            supplyPToken: PTOKEN_LP,
            spa: SPA_ADDRESS,
            collateralAmount: 1 ether,
            safetyFactor: 10_000, // 100%
            proportionToSwap: 5000, // 50%
            swapProtocol: IMultiply.SwapProtocol.TAPIO,
            feeTier: feeTier,
            minAmountOut: minAmountOut
        });

        vm.startPrank(USER);
        uint256 initialWETH = weth.balanceOf(USER);
        multiply.leverageLP(flParams, params);

        uint256 finalWETH = weth.balanceOf(USER);
        uint256 collateral = IPToken(PTOKEN_LP).balanceOf(USER);
        uint256 debt = IPToken(PTOKEN_WETH).borrowBalanceCurrent(USER);

        assertEq(initialWETH - finalWETH, 1 ether, "Collateral not transferred");
        assertGt(collateral, 0, "No WLP tokens supplied");
        assertGt(debt, 1 ether, "Debt not increased");
        vm.stopPrank();
    }

    function testLeverageLPExisting() public {
        // **Setup Initial Position**
        vm.startPrank(USER);
        lpToken.approve(PTOKEN_LP, 1 ether);
        IPToken(PTOKEN_LP).deposit(1 ether, USER);
        vm.stopPrank();

        address[] memory tokens = new address[](3);
        tokens[0] = address(weth); // Borrow WETH
        tokens[1] = address(usdc); // usdc on Base
        tokens[2] = IUniswapV3Factory(UNISWAP_V3_FACTORY).getPool(
            address(weth), address(usdc), 3000
        );

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1 ether; // 1 WETH
        amounts[1] = 0;
        amounts[2] = 0;

        IFLHelper.FlashLoanParams memory flParams = IFLHelper.FlashLoanParams({
            source: IFLHelper.FlashLoanSource.UNISWAP_V3,
            tokens: tokens,
            amounts: amounts
        });

        // **Leverage Parameters**
        uint24[2] memory feeTier;
        feeTier[0] = 100; // for swap pool (weth/wsteth)
        feeTier[1] = 3000; // for fl pool (weth/usdc)

        uint256[2] memory minAmountOut;
        minAmountOut[0] = 0; // Minimum WETH out
        minAmountOut[1] = 0; // Minimum LP out

        IMultiply.LeverageLPParams memory params = IMultiply.LeverageLPParams({
            borrowPToken: PTOKEN_WETH,
            supplyPToken: PTOKEN_LP,
            spa: SPA_ADDRESS,
            collateralAmount: 0, // No new deposit
            safetyFactor: 10_000, // 100%
            proportionToSwap: 5000, // 50%
            swapProtocol: IMultiply.SwapProtocol.UNISWAP_V3,
            feeTier: feeTier,
            minAmountOut: minAmountOut
        });

        vm.startPrank(USER);

        uint256 initialWETH = weth.balanceOf(USER);
        multiply.leverageExisting(flParams, params);

        uint256 finalWETH = weth.balanceOf(USER);
        uint256 collateral = IPToken(PTOKEN_LP).balanceOf(USER);
        uint256 debt = IPToken(PTOKEN_WETH).borrowBalanceCurrent(USER);

        assertEq(initialWETH - finalWETH, 0, "Collateral should not be transferred");
        assertGt(collateral, 0, "No LP tokens supplied");
        assertGt(debt, 1 ether, "Debt not increased");
        vm.stopPrank();
    }

    function testDeleverageLP() public {
        // Setup Initial Position
        vm.startPrank(USER);
        lpToken.approve(PTOKEN_LP, 10 ether);
        IPToken(PTOKEN_LP).deposit(10 ether, USER);

        // allow to redeem collateral on behalf
        IPToken(PTOKEN_LP).approve(address(multiply), type(uint256).max);

        IPToken(PTOKEN_WETH).borrow(5 ether);
        vm.stopPrank();

        // **Flash Loan Parameters**
        address[] memory tokens = new address[](1);
        tokens[0] = address(weth); // Borrow WETH

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 2 ether; // Flash loan to repay 2 WETH

        IFLHelper.FlashLoanParams memory flParams = IFLHelper.FlashLoanParams({
            source: IFLHelper.FlashLoanSource.AAVE_V3,
            tokens: tokens,
            amounts: amounts
        });

        // **Deleverage Parameters**
        uint24[2] memory feeTier;
        feeTier[0] = 100; // for swap pool (weth/wsteth)
        feeTier[1] = 0; // no needed using aave

        uint256[2] memory minAmountOut;
        minAmountOut[0] = 0; // Minimum WETH out
        minAmountOut[1] = 0; // Minimum LP out

        IMultiply.DeleverageLPParams memory params = IMultiply.DeleverageLPParams({
            borrowPToken: PTOKEN_WETH,
            supplyPToken: PTOKEN_LP,
            spa: SPA_ADDRESS,
            collateralToRedeem: 2 ether,
            safetyFactor: 9800, // 98% to cover swap fees (or fees can be covered by collateral redemption)
            swapProtocol: IMultiply.SwapProtocol.UNISWAP_V3,
            redeemType: IMultiply.RedeemType.PROPORTIONAL,
            tokenIndexForSingle: 0,
            feeTier: feeTier,
            minAmountOut: minAmountOut
        });

        vm.startPrank(USER);
        uint256 initialDebt = IPToken(PTOKEN_WETH).borrowBalanceCurrent(USER);
        uint256 initialCollateral = IPToken(PTOKEN_LP).balanceOf(USER);
        uint256 initialWETH = weth.balanceOf(USER);

        multiply.deleverageLP(flParams, params);

        uint256 finalDebt = IPToken(PTOKEN_WETH).borrowBalanceCurrent(USER);
        uint256 finalCollateral = IPToken(PTOKEN_LP).balanceOf(USER);
        uint256 finalWETH = weth.balanceOf(USER);

        assertLt(finalDebt, initialDebt, "Debt not reduced");
        assertLt(finalCollateral, initialCollateral, "Collateral not redeemed");
        assertGt(finalWETH, initialWETH, "No excess tokens returned");
        vm.stopPrank();
    }
}
