// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";
import {Config} from "script/Config.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {IPToken, IERC20} from "@interfaces/IPToken.sol";

contract TestProtocolFunctionality is Config, Test {
    address public alice;
    address public bob;

    IPToken pTokenA;
    IPToken pTokenB;

    function run() public {
        // Step 1: Set up fork
        uint256 chainId = vm.envUint("CHAIN_ID");

        vm.createSelectFork(vm.envString(rpcs[chainId]));
        console.log("=== Fork Setup ===");
        console.log("Fork created at block: %s", block.number);
        console.log("Timestamp: %s", block.timestamp);

        // Step 2: Define accounts
        alice = makeAddr("Alice");
        bob = makeAddr("Bob");
        console.log("Accounts initialized:");
        console.log("- Alice: %s", alice);
        console.log("- Bob: %s", bob);

        // Step 3: Load deployed contracts from JSON
        uint256 protocolId = vm.envUint("PROTOCOL_ID");
        string memory deploymentPath = getDeploymentPath(protocolId);
        string memory json = vm.readFile(deploymentPath);
        address riskEngineAddress = vm.parseJsonAddress(json, ".riskEngine");
        address pTokenAddressA = vm.parseJsonAddress(json, ".market-pweth");
        address pTokenAddressB = vm.parseJsonAddress(json, ".market-pweeth");

        IRiskEngine riskEngine = IRiskEngine(riskEngineAddress);
        pTokenA = IPToken(pTokenAddressA);
        pTokenB = IPToken(pTokenAddressB);

        address A = pTokenA.asset();
        address B = pTokenB.asset();
        console.log("=== Contracts Loaded ===");
        console.log("Risk Engine: %s", address(riskEngine));
        console.log("A PToken: %s (Asset: %s)", address(pTokenA), A);
        console.log("B PToken: %s (Asset: %s)", address(pTokenB), B);

        // Step 4: Prepare assets for accounts
        uint256 aliceDepositAmount = 1000 ether; // Alice deposits 1000 A
        uint256 bobDepositAmount = 500 ether; // Bob deposits 500 A
        uint256 bobCollateralAmount = 1000e18; // Bob deposits 1000 B as collateral
        uint256 bobBorrowAmount = 700 ether; // Bob borrows 700 A

        deal(A, alice, aliceDepositAmount);
        deal(A, bob, bobDepositAmount);
        deal(B, bob, bobCollateralAmount);
        console.log("=== Assets Prepared ===");
        console.log("Alice A balance: %s", IERC20(A).balanceOf(alice) / 1e18);
        console.log("Bob A balance: %s", IERC20(A).balanceOf(bob) / 1e18);
        console.log("Bob B balance: %s", IERC20(B).balanceOf(bob) / 1e18);

        // Step 5: Alice provides liquidity (A deposit)
        vm.startPrank(alice);
        IERC20(A).approve(address(pTokenA), aliceDepositAmount);
        pTokenA.deposit(aliceDepositAmount, alice);
        uint256 alicePTokenBalance = pTokenA.balanceOf(alice);
        vm.stopPrank();
        console.log("=== Alice's Actions ===");
        console.log("Alice deposited %s A", aliceDepositAmount / 1e18);
        console.log("Alice A PToken balance: %s", alicePTokenBalance / 1e8);

        // Step 6: Bob provides liquidity (A deposit) and collateral (B deposit)
        vm.startPrank(bob);
        IERC20(A).approve(address(pTokenA), bobDepositAmount);
        pTokenA.deposit(bobDepositAmount, bob);
        uint256 bobpTokenABalance = pTokenA.balanceOf(bob);
        IERC20(B).approve(address(pTokenB), bobCollateralAmount);
        pTokenB.deposit(bobCollateralAmount, bob);
        uint256 bobpTokenBBalance = pTokenB.balanceOf(bob);
        console.log("=== Bob's Actions ===");
        console.log("Bob deposited %s A", bobDepositAmount / 1e18);
        console.log("Bob A PToken balance: %s", bobpTokenABalance / 1e8);
        console.log("Bob deposited %s B as collateral", bobCollateralAmount / 1e18);
        console.log("Bob B PToken balance: %s", bobpTokenBBalance / 1e8);

        // Step 7: Bob borrows A
        pTokenA.borrow(bobBorrowAmount);
        uint256 bobBorrowBalance = pTokenA.borrowBalanceCurrent(bob);
        vm.stopPrank();
        console.log("Bob borrowed %s A", bobBorrowAmount / 1e18);
        console.log("Bob A borrow balance: %s", bobBorrowBalance / 1e18);

        // Step 8: Log initial APY
        uint256 initialSupplyRate = pTokenA.supplyRatePerSecond();
        uint256 initialBorrowRate = pTokenA.borrowRatePerSecond();
        console.log("=== Initial Rates ===");
        console.log("A Supply Rate (per second): %s", initialSupplyRate);
        console.log("A Borrow Rate (per second): %s", initialBorrowRate);

        // Step 9: Skip time (180 days)
        uint256 timeSkip = 180 days;
        vm.warp(block.timestamp + timeSkip);
        console.log("=== Time Skip ===");
        console.log("Skipped 180 days. New timestamp: %s", block.timestamp);
        pTokenA.accrueInterest();

        // Step 10: Log final APY and balances
        uint256 finalSupplyRate = pTokenA.supplyRatePerSecond();
        uint256 finalBorrowRate = pTokenA.borrowRatePerSecond();
        alicePTokenBalance = pTokenA.balanceOfUnderlying(alice);
        bobpTokenABalance = pTokenA.balanceOfUnderlying(bob);
        bobBorrowBalance = pTokenA.borrowBalanceCurrent(bob);
        console.log("=== Final Rates and Balances ===");
        console.log("Final A Supply Rate (per second): %s", finalSupplyRate);
        console.log("Final A Borrow Rate (per second): %s", finalBorrowRate);
        console.log(
            "Alice A PToken Balance of Underlying: %s", alicePTokenBalance / 1e18
        );
        console.log("Bob A PToken Balance of Underlying: %s", bobpTokenABalance / 1e18);
        console.log("Bob A Borrow Balance: %s", bobBorrowBalance / 1e18);

        // Step 11: verify interest accrual
        require(
            alicePTokenBalance > aliceDepositAmount, "Alice's balance did not increase"
        );
        require(
            bobpTokenABalance > bobDepositAmount, "Bob's A balance did not increase"
        );
        require(
            bobBorrowBalance > bobBorrowAmount, "Bob's borrow balance did not increase"
        );
        console.log("=== Verification ===");
        console.log("All interest accrual checks passed");
    }
}
