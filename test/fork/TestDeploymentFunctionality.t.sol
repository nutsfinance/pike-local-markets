// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";
import {Config} from "script/Config.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {
    IERC20Metadata
} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract TestProtocolFunctionality is Config, Test {
    address public alice;
    address public bob;

    mapping(address => string) names;

    uint256 tokenADecimals;
    uint256 tokenBDecimals;

    string tokenASymbol;
    string tokenBSymbol;

    string tokenAName = ".market-pusdc";
    string tokenBName = ".market-prlp";

    IPToken pTokenA;
    IPToken pTokenB;

    address public tokenA;
    address public tokenB;

    address oracleEngine;

    function run() public {
        setupForkAndContracts();
        setupAccounts();

        // Scenario 1: supply & borrow test
        supplyAndBorrow(alice, bob, 1000, 1000, 700);

        // Scenario 2: Interest accrual test
        interestAccrual(180 days);

        // Scenario 3: Repay & withdraw
        repayAndWithdraw(bob, 700, 500);
    }

    function mockOraclePrice(address ptoken, uint256 price) internal {
        bytes memory returnData = abi.encode(price);

        // If getUnderlyingPrice(IPToken) is also used, mock that too:
        bytes memory getUnderlyingPriceCall = abi.encodeWithSelector(
            bytes4(keccak256("getUnderlyingPrice(address)")), ptoken
        );
        vm.mockCall(oracleEngine, getUnderlyingPriceCall, returnData);

        console.log("Mocked oracle price for %s -> %s", ptoken, price);
    }

    function simulateLiquidation(
        address borrower,
        IPToken borrowedPToken,
        IPToken collateralPToken,
        uint256 repayAmount,
        uint256 newPrice
    ) internal {
        console.log("=== Simulate Liquidation ===");

        // Drop the price to make the position undercollateralized
        address collateralAsset = collateralPToken.asset();
        mockOraclePrice(collateralAsset, newPrice);

        // Trigger liquidation
        address liquidator = makeAddr("Liquidator");
        deal(borrowedPToken.asset(), liquidator, repayAmount * 1e18);

        vm.startPrank(liquidator);
        IERC20(borrowedPToken.asset()).approve(address(borrowedPToken), type(uint256).max);
        borrowedPToken.liquidateBorrow(borrower, repayAmount * 1e18, collateralPToken);
        vm.stopPrank();

        console.log("Liquidation executed for borrower: %s", borrower);
    }

    function supplyAndBorrow(
        address supplier,
        address borrower,
        uint256 supplyAmount,
        uint256 collateralAmount,
        uint256 borrowAmount
    ) internal {
        console.log("=== Supply and Borrow ===");

        // Supplier deposits
        supply(supplier, pTokenA, supplyAmount * tokenADecimals);
        console.log("Alice supplied %s tokens %s", tokenASymbol, supplyAmount);

        // Borrower deposits both supply and collateral
        supply(borrower, pTokenB, collateralAmount * tokenBDecimals);

        // Borrow
        borrow(borrower, pTokenA, borrowAmount * tokenADecimals);
        console.log("Bob borrowed %s tokens %s", tokenASymbol, borrowAmount);
    }

    function interestAccrual(uint256 duration) internal {
        console.log("=== Interest Accrual (%s days) ===", duration / 1 days);
        uint256 before = pTokenA.totalBorrows();
        vm.warp(block.timestamp + duration);
        pTokenA.accrueInterest();
        uint256 afterBorrows = pTokenA.totalBorrows();
        require(afterBorrows > before, "Interest did not accrue");
        console.log("Interest accrued successfully.");
    }

    function repayAndWithdraw(
        address borrower,
        uint256 repayAmount,
        uint256 withdrawAmount
    ) internal {
        console.log("=== Repay and Withdraw ===");
        repay(borrower, pTokenA, repayAmount * tokenADecimals);
        console.log("Bob repaid %s tokens %s", tokenASymbol, repayAmount);
        console.log(
            "Bob balance %s", pTokenB.balanceOfUnderlying(borrower) / tokenBDecimals
        );

        mockOraclePrice(address(pTokenB), 1e18);
        mockOraclePrice(address(pTokenA), 1e18);

        withdraw(borrower, pTokenB, withdrawAmount * tokenBDecimals);
        console.log("Bob withdrew %s tokens %s", tokenASymbol, withdrawAmount);
    }

    function setupForkAndContracts() internal {
        uint256 chainId = vm.envUint("CHAIN_ID");
        vm.createSelectFork(vm.envString(rpcs[chainId]));
        console.log("Fork created at block %s", block.number);
        console.log("Timestamp: %s", block.timestamp);

        uint256 protocolId = vm.envUint("PROTOCOL_ID");
        string memory deploymentPath = getDeploymentPath(protocolId);
        string memory json = vm.readFile(deploymentPath);

        address riskEngineAddress = vm.parseJsonAddress(json, ".riskEngine");
        address pTokenAAddress = vm.parseJsonAddress(json, tokenAName);
        address pTokenBAddress = vm.parseJsonAddress(json, tokenBName);

        IRiskEngine riskEngine = IRiskEngine(riskEngineAddress);
        pTokenA = IPToken(pTokenAAddress);
        pTokenB = IPToken(pTokenBAddress);

        tokenA = pTokenA.asset();
        tokenB = pTokenB.asset();
        tokenADecimals = 10 ** IERC20Metadata(tokenA).decimals();
        tokenBDecimals = 10 ** IERC20Metadata(tokenB).decimals();
        tokenASymbol = IERC20Metadata(tokenA).symbol();
        tokenBSymbol = IERC20Metadata(tokenB).symbol();

        oracleEngine = address(riskEngine.oracle());

        console.log("=== Contracts Loaded ===");
        console.log("Risk Engine: %s", address(riskEngine));
        console.log("%s PToken: %s (Asset: %s)", tokenASymbol, address(pTokenA), tokenA);
        console.log("%s PToken: %s (Asset: %s)", tokenBSymbol, address(pTokenB), tokenB);
    }

    function setupAccounts() internal {
        alice = makeAddr("Alice");
        bob = makeAddr("Bob");
        console.log("Accounts ready: Alice=%s, Bob=%s", alice, bob);
    }

    function supply(address user, IPToken pToken, uint256 amount) internal {
        address asset = pToken.asset();
        deal(asset, user, amount);
        vm.startPrank(user);
        IERC20(asset).approve(address(pToken), amount);
        pToken.deposit(amount, user);
        vm.stopPrank();
    }

    function borrow(address user, IPToken pToken, uint256 amount) internal {
        vm.startPrank(user);
        pToken.borrow(amount);
        vm.stopPrank();
    }

    function repay(address user, IPToken pToken, uint256 amount) internal {
        address asset = pToken.asset();
        deal(asset, user, amount);
        vm.startPrank(user);
        IERC20(asset).approve(address(pToken), amount);
        pToken.repayBorrow(amount);
        vm.stopPrank();
    }

    function withdraw(address user, IPToken pToken, uint256 amount) internal {
        vm.startPrank(user);
        pToken.withdraw(amount, user, user);
        vm.stopPrank();
    }
}
