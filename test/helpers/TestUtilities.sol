// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {TestSetters} from "@helpers/TestSetters.sol";

contract TestUtilities is TestSetters {
    uint256 constant ONE_MANTISSA = 1e18;
    uint256 constant SECONDS_PER_YEAR = 31_536_000;
    uint256 constant liquidationPenalty = 5e16; //5%
    uint256 constant liquidationIncentive = 108e18; //10%

    function getActionStateData(
        address user,
        address onBehalfOf,
        address pTokenAddress,
        address tokenAddress
    ) public view returns (ActionStateData memory data) {
        uint256 collateral;
        IPToken pToken = IPToken(pTokenAddress);

        uint256 userPTokenBalance = pToken.balanceOf(onBehalfOf);

        uint256 userUnderlyingBalance = IERC20(tokenAddress).balanceOf(user);

        if (userPTokenBalance > 0) {
            collateral = (pToken.exchangeRateCurrent() * userPTokenBalance) / ONE_MANTISSA;
        }
        uint256 borrowed = pToken.borrowBalanceCurrent(onBehalfOf);
        UserData memory userData = UserData(userUnderlyingBalance, collateral, borrowed);
        PTokenData memory pTokenData = PTokenData({
            totalCash: pToken.getCash(),
            totalBorrow: pToken.totalBorrowsCurrent(),
            totalReserve: pToken.totalReservesCurrent(),
            totalSupply: pToken.totalSupply()
        });

        data = ActionStateData(pTokenData, userData);

        if (getDebug()) {
            console.log(
                "Balance of pToken %s is (deposited: %s, borrowed: %s)",
                pToken.name(),
                userData.collateral,
                userData.borrowed
            );
        }
    }

    function requireActionDataValid(
        Action action,
        address pTokenAddress,
        uint256 amount,
        ActionStateData memory beforeData,
        ActionStateData memory afterData,
        bool expectRevert
    ) public view {
        uint256 exchangeRateStored = IPToken(pTokenAddress).exchangeRateStored();

        if (action == Action.SUPPLY) {
            uint256 mintTokens = amount * ONE_MANTISSA / exchangeRateStored;
            require(
                beforeData.pTokenData.totalCash + amount == afterData.pTokenData.totalCash,
                "Did not transfer money to pToken"
            );
            require(
                beforeData.userData.collateral + mintTokens
                    == afterData.userData.collateral,
                "Did not deposit in pToken"
            );
            require(
                beforeData.pTokenData.totalSupply + mintTokens
                    == afterData.pTokenData.totalSupply,
                "Did not increase total supply"
            );
            require(
                beforeData.userData.underlyingBalance
                    == amount + afterData.userData.underlyingBalance,
                "Did not transfer money from user"
            );
        } else if (action == Action.REPAY) {} else if (action == Action.WITHDRAW) {} else
        if (action == Action.BORROW) {}
    }
}
