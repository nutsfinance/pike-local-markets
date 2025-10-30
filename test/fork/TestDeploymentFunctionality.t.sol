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

    function run() public {
        setupForkAndContracts();
        setupAccounts();

        // Scenario 1: supply & borrow test
        supplyAndBorrow(alice, bob, 1000, 500, 1000, 700);

        // Scenario 2: Interest accrual test
        interestAccrual(180 days);

        // Scenario 3: Repay & withdraw
        repayAndWithdraw(bob, 700, 500);
    }

    function supplyAndBorrow(
        address supplier,
        address borrower,
        uint256 supplyAmount,
        uint256 borrowerSupply,
        uint256 collateralAmount,
        uint256 borrowAmount
    ) internal {
        console.log("=== Supply and Borrow ===");

        // Supplier deposits
        supply(supplier, pTokenA, supplyAmount * tokenADecimals);
        console.log("Alice supplied %s tokens %s", tokenASymbol, supplyAmount);

        // Borrower deposits both supply and collateral
        supply(borrower, pTokenA, borrowerSupply * tokenADecimals);
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
        // withdraw(borrower, pTokenA, withdrawAmount * tokenADecimals);
        // console.log("Bob withdrew %s tokens %s", tokenASymbol, withdrawAmount);
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
