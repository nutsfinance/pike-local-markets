pragma solidity 0.8.28;

import {IMultiply, Multiply, IFLHelper} from "@periphery/Multiply.sol";
import {MockToken, MockPToken} from "@mocks/MockToken.sol";
import {
    MockUniswapV3Pool,
    MockZapContract,
    MockSPA,
    MockRiskEngine
} from "@mocks/MockMultiplyHelpers.sol";
import "forge-std/Test.sol";

contract MultiplyTest is Test {
    MockToken public token0;
    MockToken public token1;
    MockToken public wlpToken;
    MockPToken public pTokenLP;
    MockPToken public pToken0;
    MockPToken public pToken1;
    MockSPA public spa;
    MockZapContract public zapContract;
    MockUniswapV3Pool public uniswapPool;
    Multiply public multiply;

    address public user = makeAddr("user");

    function setUp() public {
        token0 = new MockToken("Token0", "TKN0", 18);
        token1 = new MockToken("Token1", "TKN1", 18);
        wlpToken = new MockToken("LPT", "LPT", 18);

        pTokenLP = new MockPToken(address(wlpToken));
        pToken0 = new MockPToken(address(token0));
        pToken1 = new MockPToken(address(token1));

        address[] memory tokens = new address[](2);
        tokens[0] = address(token0);
        tokens[1] = address(token1);
        spa = new MockSPA(tokens);

        zapContract = new MockZapContract();
        uniswapPool = new MockUniswapV3Pool(address(token0), address(token1));

        multiply = new Multiply(
            address(uniswapPool),
            address(zapContract),
            address(this),
            address(new MockRiskEngine()),
            address(this),
            address(uniswapPool),
            address(0),
            address(0),
            address(0),
            address(0)
        );

        token0.mint(user, 1000 ether);
        wlpToken.mint(user, 1000 ether);
        vm.startPrank(user);
        token0.approve(address(multiply), type(uint256).max);
        vm.stopPrank();
    }

    function testLeverageLP() public {
        // Flash loan params
        address[] memory tokens = new address[](3);
        tokens[0] = address(token0);
        tokens[1] = address(token1);
        tokens[2] = address(uniswapPool);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1 ether; // Flash loan of token0
        amounts[1] = 0;
        amounts[2] = 0;

        IFLHelper.FlashLoanParams memory flParams = IFLHelper.FlashLoanParams({
            source: IFLHelper.FlashLoanSource.UNISWAP_V3,
            tokens: tokens,
            amounts: amounts
        });

        // Leverage params
        uint24 feeTier = 3000;
        uint256[2] memory minAmountOut;
        minAmountOut[0] = 0;
        minAmountOut[1] = 0;

        IMultiply.LeverageLPParams memory params = IMultiply.LeverageLPParams({
            borrowPToken: address(pToken0),
            supplyPToken: address(pTokenLP),
            spa: address(spa),
            collateralAmount: 1 ether,
            safetyFactor: 10_000, // 100%
            proportionToSwap: 5000, // 50%
            swapProtocol: IMultiply.SwapProtocol.UNISWAP_V3,
            feeTier: feeTier,
            minAmountOut: minAmountOut
        });

        vm.startPrank(user);
        uint256 initialToken0 = token0.balanceOf(user);
        token0.approve(address(multiply), type(uint256).max);
        multiply.leverageLP(flParams, params);

        uint256 finalToken0 = token0.balanceOf(user);
        uint256 collateral = pTokenLP.collateralBalances(user);
        uint256 debt = pToken0.borrowBalances(user);

        assertEq(initialToken0 - finalToken0, 1 ether, "Collateral not transferred");
        assertGt(collateral, 0, "No LP tokens supplied");
        assertGt(debt, 1 ether, "Debt not increased");
        vm.stopPrank();
    }

    function testLeverageLPExisting() public {
        // Flash loan params
        address[] memory tokens = new address[](3);
        tokens[0] = address(token0);
        tokens[1] = address(token1);
        tokens[2] = address(uniswapPool);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1 ether; // Flash loan of token0
        amounts[1] = 0;
        amounts[2] = 0;

        IFLHelper.FlashLoanParams memory flParams = IFLHelper.FlashLoanParams({
            source: IFLHelper.FlashLoanSource.UNISWAP_V3,
            tokens: tokens,
            amounts: amounts
        });

        // Leverage params
        uint24 feeTier = 3000;
        uint256[2] memory minAmountOut;
        minAmountOut[0] = 0;
        minAmountOut[1] = 0;

        IMultiply.LeverageLPParams memory params = IMultiply.LeverageLPParams({
            borrowPToken: address(pToken0),
            supplyPToken: address(pTokenLP),
            spa: address(spa),
            collateralAmount: 0,
            safetyFactor: 10_000, // 100%
            proportionToSwap: 5000, // 50%
            swapProtocol: IMultiply.SwapProtocol.UNISWAP_V3,
            feeTier: feeTier,
            minAmountOut: minAmountOut
        });

        vm.startPrank(user);
        uint256 initialToken0 = token0.balanceOf(user);
        token0.approve(address(multiply), type(uint256).max);
        multiply.leverageExisting(flParams, params);

        uint256 finalToken0 = token0.balanceOf(user);
        uint256 collateral = pTokenLP.collateralBalances(user);
        uint256 debt = pToken0.borrowBalances(user);

        assertEq(initialToken0 - finalToken0, 0, "Collateral should not transferred");
        assertGt(collateral, 0, "No LP tokens supplied");
        assertGt(debt, 1 ether, "Debt not increased");
        vm.stopPrank();
    }

    function testDeleverageLP() public {
        // Setup initial position
        vm.startPrank(user);
        token0.mint(address(pToken0), 10 ether);
        pToken0.borrowOnBehalfOf(user, 5 ether);
        wlpToken.mint(address(pTokenLP), 10 ether);
        wlpToken.approve(address(pTokenLP), type(uint256).max);
        pTokenLP.deposit(10 ether, user);
        vm.stopPrank();

        // Flash loan params
        address[] memory tokens = new address[](3);
        tokens[0] = address(token0);
        tokens[1] = address(token1);
        tokens[2] = address(uniswapPool);

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 2 ether; // Flash loan to repay debt
        amounts[1] = 0;
        amounts[2] = 0;

        IFLHelper.FlashLoanParams memory flParams = IFLHelper.FlashLoanParams({
            source: IFLHelper.FlashLoanSource.UNISWAP_V3,
            tokens: tokens,
            amounts: amounts
        });

        // Deleverage params
        uint24 feeTier = 3000;
        uint256[2] memory minAmountOut;
        minAmountOut[0] = 0;
        minAmountOut[1] = 0;

        IMultiply.DeleverageLPParams memory params = IMultiply.DeleverageLPParams({
            borrowPToken: address(pToken0),
            supplyPToken: address(pTokenLP),
            spa: address(spa),
            collateralToRedeem: 2 ether,
            safetyFactor: 9800, //98% to cover the swap fees of collateral
            //(this means less amount of loan will be used so that collateral to redeem would be enough cover the debt)
            swapProtocol: IMultiply.SwapProtocol.UNISWAP_V3,
            redeemType: IMultiply.RedeemType.PROPORTIONAL,
            tokenIndexForSingle: 0,
            feeTier: feeTier,
            minAmountOut: minAmountOut
        });

        vm.startPrank(user);
        uint256 initialDebt = pToken0.borrowBalances(user);
        uint256 initialCollateral = pTokenLP.collateralBalances(user);
        uint256 initialToken0 = token0.balanceOf(user);

        multiply.deleverageLP(flParams, params);

        uint256 finalDebt = pToken0.borrowBalances(user);
        uint256 finalCollateral = pTokenLP.collateralBalances(user);
        uint256 finalToken0 = token0.balanceOf(user);

        assertLt(finalDebt, initialDebt, "Debt not reduced");
        assertLt(finalCollateral, initialCollateral, "Collateral not redeemed");
        assertGt(finalToken0, initialToken0, "No excess tokens returned");
        vm.stopPrank();
    }
}
