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

    IPToken wsPToken;
    IPToken stsPToken;

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
        string memory chain = vm.envString("CHAIN");
        uint256 protocolId = vm.envUint("PROTOCOL_ID");
        string memory deploymentPath = getDeploymentPath(protocolId);
        string memory json = vm.readFile(deploymentPath);
        address riskEngineAddress = vm.parseJsonAddress(json, ".riskEngine");
        address wsPTokenAddress = vm.parseJsonAddress(json, ".market-pws");
        address stsPTokenAddress = vm.parseJsonAddress(json, ".market-psts");

        IRiskEngine riskEngine = IRiskEngine(riskEngineAddress);
        wsPToken = IPToken(wsPTokenAddress);
        stsPToken = IPToken(stsPTokenAddress);

        address ws = wsPToken.asset();
        address sts = stsPToken.asset();
        console.log("=== Contracts Loaded ===");
        console.log("Risk Engine: %s", address(riskEngine));
        console.log("WS PToken: %s (Asset: %s)", address(wsPToken), ws);
        console.log("STS PToken: %s (Asset: %s)", address(stsPToken), sts);

        // Step 4: Prepare assets for accounts
        uint256 aliceDepositAmount = 1000 ether; // Alice deposits 1000 ws
        uint256 bobDepositAmount = 500 ether; // Bob deposits 500 ws
        uint256 bobCollateralAmount = 1000e18; // Bob deposits 1000 sts as collateral
        uint256 bobBorrowAmount = 700 ether; // Bob borrows 700 ws

        deal(ws, alice, aliceDepositAmount);
        deal(ws, bob, bobDepositAmount);
        deal(sts, bob, bobCollateralAmount);
        console.log("=== Assets Prepared ===");
        console.log("Alice WS balance: %s", IERC20(ws).balanceOf(alice) / 1e18);
        console.log("Bob WS balance: %s", IERC20(ws).balanceOf(bob) / 1e18);
        console.log("Bob STS balance: %s", IERC20(sts).balanceOf(bob) / 1e18);

        // Step 5: Alice provides liquidity (ws deposit)
        vm.startPrank(alice);
        IERC20(ws).approve(address(wsPToken), aliceDepositAmount);
        wsPToken.deposit(aliceDepositAmount, alice);
        uint256 alicePTokenBalance = wsPToken.balanceOf(alice);
        vm.stopPrank();
        console.log("=== Alice's Actions ===");
        console.log("Alice deposited %s WS", aliceDepositAmount / 1e18);
        console.log("Alice WS PToken balance: %s", alicePTokenBalance / 1e8);

        // Step 6: Bob provides liquidity (ws deposit) and collateral (sts deposit)
        vm.startPrank(bob);
        IERC20(ws).approve(address(wsPToken), bobDepositAmount);
        wsPToken.deposit(bobDepositAmount, bob);
        uint256 bobwsPTokenBalance = wsPToken.balanceOf(bob);
        IERC20(sts).approve(address(stsPToken), bobCollateralAmount);
        stsPToken.deposit(bobCollateralAmount, bob);
        uint256 bobstsPTokenBalance = stsPToken.balanceOf(bob);
        console.log("=== Bob's Actions ===");
        console.log("Bob deposited %s WS", bobDepositAmount / 1e18);
        console.log("Bob WS PToken balance: %s", bobwsPTokenBalance / 1e8);
        console.log("Bob deposited %s STS as collateral", bobCollateralAmount / 1e18);
        console.log("Bob STS PToken balance: %s", bobstsPTokenBalance / 1e8);

        // Step 7: Bob borrows ws
        wsPToken.borrow(bobBorrowAmount);
        uint256 bobBorrowBalance = wsPToken.borrowBalanceCurrent(bob);
        vm.stopPrank();
        console.log("Bob borrowed %s WS", bobBorrowAmount / 1e18);
        console.log("Bob WS borrow balance: %s", bobBorrowBalance / 1e18);

        // Step 8: Log initial APY
        uint256 initialSupplyRate = wsPToken.supplyRatePerSecond();
        uint256 initialBorrowRate = wsPToken.borrowRatePerSecond();
        console.log("=== Initial Rates ===");
        console.log("WS Supply Rate (per second): %s", initialSupplyRate);
        console.log("WS Borrow Rate (per second): %s", initialBorrowRate);

        // Step 9: Skip time (180 days)
        uint256 timeSkip = 180 days;
        vm.warp(block.timestamp + timeSkip);
        console.log("=== Time Skip ===");
        console.log("Skipped 180 days. New timestamp: %s", block.timestamp);
        wsPToken.accrueInterest();

        // Step 10: Log final APY and balances
        uint256 finalSupplyRate = wsPToken.supplyRatePerSecond();
        uint256 finalBorrowRate = wsPToken.borrowRatePerSecond();
        alicePTokenBalance = wsPToken.balanceOfUnderlying(alice);
        bobwsPTokenBalance = wsPToken.balanceOfUnderlying(bob);
        bobBorrowBalance = wsPToken.borrowBalanceCurrent(bob);
        console.log("=== Final Rates and Balances ===");
        console.log("Final WS Supply Rate (per second): %s", finalSupplyRate);
        console.log("Final WS Borrow Rate (per second): %s", finalBorrowRate);
        console.log(
            "Alice WS PToken Balance of Underlying: %s", alicePTokenBalance / 1e18
        );
        console.log("Bob WS PToken Balance of Underlying: %s", bobwsPTokenBalance / 1e18);
        console.log("Bob WS Borrow Balance: %s", bobBorrowBalance / 1e18);

        // Step 11: verify interest accrual
        require(
            alicePTokenBalance > aliceDepositAmount, "Alice's balance did not increase"
        );
        require(
            bobwsPTokenBalance > bobDepositAmount, "Bob's WS balance did not increase"
        );
        require(
            bobBorrowBalance > bobBorrowAmount, "Bob's borrow balance did not increase"
        );
        console.log("=== Verification ===");
        console.log("All interest accrual checks passed");
    }
}
