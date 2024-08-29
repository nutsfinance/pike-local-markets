//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {IPToken} from "@interfaces/IPToken.sol";
import {IOracleManager} from "@interfaces/IOracleManager.sol";
import {RiskEngineStorage} from "@storage/RiskEngineStorage.sol";
import {ExponentialNoError} from "@utils/ExponentialNoError.sol";
import {RiskEngineError} from "@errors/RiskEngineError.sol";
import {CommonError} from "@errors/CommonError.sol";
import {OwnableMixin} from "@utils/OwnableMixin.sol";

contract RiskEngineModule is IRiskEngine, RiskEngineStorage, OwnableMixin {
    using ExponentialNoError for ExponentialNoError.Exp;
    using ExponentialNoError for uint256;

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param pTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @dev Note that we calculate the exchangeRateStored for each collateral pToken using stored data,
     *  without calculating accumulated interest.
     * @return (possible error code,
     *             hypothetical account liquidity in excess of collateral requirements,
     *          hypothetical account shortfall below collateral requirements)
     */
    function getHypotheticalAccountLiquidityInternal(
        address account,
        IPToken pTokenModify,
        uint256 redeemTokens,
        uint256 borrowAmount,
        function (IPToken) internal view returns (ExponentialNoError.Exp memory) threshold
    ) internal view returns (RiskEngineError.Error, uint256, uint256) {
        AccountLiquidityLocalVars memory vars; // Holds all our calculation results

        // For each asset the account is in
        IPToken[] memory assets = _getRiskEngineStorage().accountAssets[account];
        for (uint256 i = 0; i < assets.length; i++) {
            IPToken asset = assets[i];

            // Read the balances and exchange rate from the pToken
            (vars.pTokenBalance, vars.borrowBalance, vars.exchangeRateMantissa) =
                asset.getAccountSnapshot(account);

            vars.threshold = threshold(asset);
            vars.exchangeRate =
                ExponentialNoError.Exp({mantissa: vars.exchangeRateMantissa});

            // Get the normalized price of the asset
            vars.oraclePriceMantissa =
                IOracleManager(address(this)).getUnderlyingPrice(asset);
            if (vars.oraclePriceMantissa == 0) {
                return (RiskEngineError.Error.PRICE_ERROR, 0, 0);
            }
            vars.oraclePrice =
                ExponentialNoError.Exp({mantissa: vars.oraclePriceMantissa});

            // Pre-compute a conversion factor from tokens -> ether (normalized price value)
            vars.tokensToDenom =
                vars.oraclePrice.mul_(vars.threshold.mul_(vars.exchangeRate));

            // sumCollateral += tokensToDenom * pTokenBalance
            vars.sumCollateral = vars.tokensToDenom.mul_ScalarTruncateAddUInt(
                vars.pTokenBalance, vars.sumCollateral
            );

            // sumBorrowPlusEffects += oraclePrice * borrowBalance
            vars.sumBorrowPlusEffects = vars.oraclePrice.mul_ScalarTruncateAddUInt(
                vars.borrowBalance, vars.sumBorrowPlusEffects
            );

            // Calculate effects of interacting with pTokenModify
            if (asset == pTokenModify) {
                // redeem effect
                // sumBorrowPlusEffects += tokensToDenom * redeemTokens
                vars.sumBorrowPlusEffects = vars.tokensToDenom.mul_ScalarTruncateAddUInt(
                    redeemTokens, vars.sumBorrowPlusEffects
                );

                // borrow effect
                // sumBorrowPlusEffects += oraclePrice * borrowAmount
                vars.sumBorrowPlusEffects = vars.oraclePrice.mul_ScalarTruncateAddUInt(
                    borrowAmount, vars.sumBorrowPlusEffects
                );
            }
        }

        // These are safe, as the underflow condition is checked first
        if (vars.sumCollateral > vars.sumBorrowPlusEffects) {
            return (
                RiskEngineError.Error.NO_ERROR,
                vars.sumCollateral - vars.sumBorrowPlusEffects,
                0
            );
        } else {
            return (
                RiskEngineError.Error.NO_ERROR,
                0,
                vars.sumBorrowPlusEffects - vars.sumCollateral
            );
        }
    }

    /**
     * @dev Return collateral factor for a market
     * @param asset Address for asset
     * @return Collateral factor as exponential
     */
    function _getCollateralFactor(IPToken asset)
        internal
        view
        returns (ExponentialNoError.Exp memory)
    {
        return ExponentialNoError.Exp({
            mantissa: _getRiskEngineStorage().markets[address(asset)].collateralFactorMantissa
        });
    }

    /**
     * @dev Retrieves liquidation threshold for a market as an exponential
     * @param asset Address for asset to liquidation threshold
     * @return Liquidation threshold as exponential
     */
    function _getLiquidationThreshold(IPToken asset)
        internal
        view
        returns (ExponentialNoError.Exp memory)
    {
        return ExponentialNoError.Exp({
            mantissa: _getRiskEngineStorage().markets[address(asset)]
                .liquidationThresholdMantissa
        });
    }
}
