//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {IPToken} from "@interfaces/IPToken.sol";
import {IOracleEngine} from "@oracles/interfaces/IOracleEngine.sol";
import {RiskEngineStorage} from "@storage/RiskEngineStorage.sol";
import {ExponentialNoError} from "@utils/ExponentialNoError.sol";
import {RiskEngineError} from "@errors/RiskEngineError.sol";
import {CommonError} from "@errors/CommonError.sol";
import {OwnableMixin} from "@utils/OwnableMixin.sol";
import {RBACMixin} from "@utils/RBACMixin.sol";

/**
 * @title Pike Markets RiskEngine Contract
 * @author NUTS Finance (hello@pike.finance)
 */
contract RiskEngineModule is IRiskEngine, RiskEngineStorage, OwnableMixin, RBACMixin {
    using ExponentialNoError for ExponentialNoError.Exp;
    using ExponentialNoError for uint256;

    /**
     * @inheritdoc IRiskEngine
     */
    function setOracle(address newOracle) external {
        checkPermission(_CONFIGURATOR_PERMISSION, msg.sender);
        emit NewOracleEngine(_getRiskEngineStorage().oracle, newOracle);
        _getRiskEngineStorage().oracle = newOracle;
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function setCloseFactor(uint256 newCloseFactorMantissa) external {
        checkPermission(_CONFIGURATOR_PERMISSION, msg.sender);
        uint256 oldCloseFactorMantissa = _getRiskEngineStorage().closeFactorMantissa;
        _getRiskEngineStorage().closeFactorMantissa = newCloseFactorMantissa;
        emit NewCloseFactor(oldCloseFactorMantissa, newCloseFactorMantissa);
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function setCollateralFactor(
        IPToken pToken,
        uint256 newCollateralFactorMantissa,
        uint256 newLiquidationThresholdMantissa
    ) external {
        checkNestedPermission(_CONFIGURATOR_PERMISSION, address(pToken), msg.sender);
        // Verify market is listed
        Market storage market = _getRiskEngineStorage().markets[address(pToken)];
        if (!market.isListed) {
            revert RiskEngineError.MarketNotListed();
        }

        ExponentialNoError.Exp memory newCollateralFactorExp =
            ExponentialNoError.Exp({mantissa: newCollateralFactorMantissa});

        // Check collateral factor <= 0.9
        ExponentialNoError.Exp memory highLimit =
            ExponentialNoError.Exp({mantissa: _COLLATERAL_FACTOR_MAX_MANTISSA});
        if (highLimit.lessThanExp(newCollateralFactorExp)) {
            revert RiskEngineError.InvalidCollateralFactor();
        }

        // Ensure that liquidation threshold <= 1
        if (newLiquidationThresholdMantissa > _MANTISSA_ONE) {
            revert RiskEngineError.InvalidLiquidationThreshold();
        }

        // Ensure that liquidation threshold >= CF
        if (newLiquidationThresholdMantissa < newCollateralFactorMantissa) {
            revert RiskEngineError.InvalidLiquidationThreshold();
        }

        // Set market's collateral factor to new collateral factor, remember old value
        uint256 oldCollateralFactorMantissa = market.collateralFactorMantissa;
        market.collateralFactorMantissa = newCollateralFactorMantissa;

        // Set market's liquidation threshold to new liquidation threshold, remember old value
        uint256 oldLiquidationThresholdMantissa = market.liquidationThresholdMantissa;
        market.liquidationThresholdMantissa = newLiquidationThresholdMantissa;

        // Emit event with asset, old collateral factor, and new collateral factor
        emit NewCollateralFactor(
            pToken, oldCollateralFactorMantissa, newCollateralFactorMantissa
        );
        // Emit event with asset, old liquidation threshold, and new liquidation threshold
        emit NewLiquidationThreshold(
            pToken, oldLiquidationThresholdMantissa, newLiquidationThresholdMantissa
        );
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function setLiquidationIncentive(uint256 newLiquidationIncentiveMantissa) external {
        checkPermission(_CONFIGURATOR_PERMISSION, msg.sender);
        // Save current value for use in log
        uint256 oldLiquidationIncentiveMantissa =
            _getRiskEngineStorage().liquidationIncentiveMantissa;

        // Set liquidation incentive to new incentive
        _getRiskEngineStorage().liquidationIncentiveMantissa =
            newLiquidationIncentiveMantissa;

        // Emit event with old incentive, new incentive
        emit NewLiquidationIncentive(
            oldLiquidationIncentiveMantissa, newLiquidationIncentiveMantissa
        );
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function supportMarket(IPToken pToken) external {
        checkPermission(_CONFIGURATOR_PERMISSION, msg.sender);
        if (_getRiskEngineStorage().markets[address(pToken)].isListed) {
            revert RiskEngineError.AlreadyListed();
        }

        // Note that isComped is not in active use anymore
        Market storage newMarket = _getRiskEngineStorage().markets[address(pToken)];
        newMarket.isListed = true;
        newMarket.collateralFactorMantissa = 0;
        newMarket.liquidationThresholdMantissa = 0;

        _addMarketInternal(address(pToken));

        emit MarketListed(pToken);
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function setMarketBorrowCaps(
        IPToken[] calldata pTokens,
        uint256[] calldata newBorrowCaps
    ) external {
        uint256 numMarkets = pTokens.length;
        uint256 numBorrowCap = newBorrowCaps.length;

        if (numMarkets != numBorrowCap || numMarkets == 0) {
            revert CommonError.NoArrayParity();
        }

        for (uint256 i = 0; i < numMarkets; ++i) {
            checkNestedPermission(
                _BORROW_CAP_GUARDIAN_PERMISSION, address(pTokens[i]), msg.sender
            );
            _getRiskEngineStorage().borrowCaps[address(pTokens[i])] = newBorrowCaps[i];
            emit NewBorrowCap(pTokens[i], newBorrowCaps[i]);
        }
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function setMarketSupplyCaps(
        IPToken[] calldata pTokens,
        uint256[] calldata newSupplyCaps
    ) external {
        uint256 numMarkets = pTokens.length;
        uint256 newSupplyCap = newSupplyCaps.length;

        if (numMarkets != newSupplyCap || numMarkets == 0) {
            revert CommonError.NoArrayParity();
        }

        for (uint256 i; i < numMarkets; ++i) {
            checkNestedPermission(
                _SUPPLY_CAP_GUARDIAN_PERMISSION, address(pTokens[i]), msg.sender
            );
            _getRiskEngineStorage().supplyCaps[address(pTokens[i])] = newSupplyCaps[i];
            emit NewSupplyCap(pTokens[i], newSupplyCaps[i]);
        }
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function setMintPaused(IPToken pToken, bool state) external returns (bool) {
        checkPermission(_PAUSE_GUARDIAN_PERMISSION, msg.sender);
        if (!_getRiskEngineStorage().markets[address(pToken)].isListed) {
            revert RiskEngineError.MarketNotListed();
        }

        _getRiskEngineStorage().mintGuardianPaused[address(pToken)] = state;
        emit ActionPaused(pToken, "Mint", state);
        return state;
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function setBorrowPaused(IPToken pToken, bool state) external returns (bool) {
        checkPermission(_PAUSE_GUARDIAN_PERMISSION, msg.sender);
        if (!_getRiskEngineStorage().markets[address(pToken)].isListed) {
            revert RiskEngineError.MarketNotListed();
        }

        _getRiskEngineStorage().borrowGuardianPaused[address(pToken)] = state;
        emit ActionPaused(pToken, "Borrow", state);
        return state;
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function setTransferPaused(bool state) external returns (bool) {
        checkPermission(_PAUSE_GUARDIAN_PERMISSION, msg.sender);
        _getRiskEngineStorage().transferGuardianPaused = state;
        emit ActionPaused("Transfer", state);
        return state;
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function setSeizePaused(bool state) external returns (bool) {
        checkPermission(_PAUSE_GUARDIAN_PERMISSION, msg.sender);
        _getRiskEngineStorage().seizeGuardianPaused = state;
        emit ActionPaused("Seize", state);
        return state;
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function enterMarkets(address[] memory pTokens) external returns (uint256[] memory) {
        uint256 len = pTokens.length;

        uint256[] memory results = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            IPToken pToken = IPToken(pTokens[i]);

            results[i] = uint256(addToMarketInternal(pToken, msg.sender));
        }

        return results;
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function exitMarket(address pTokenAddress) external {
        IPToken pToken = IPToken(pTokenAddress);
        /* Get sender tokensHeld and amountOwed underlying from the pToken */
        (uint256 tokensHeld, uint256 amountOwed,) = pToken.getAccountSnapshot(msg.sender);

        /* Fail if the sender has a borrow balance */
        if (amountOwed != 0) {
            revert RiskEngineError.NonZeroBorrowBalance();
        }

        /* Fail if the sender is not permitted to redeem all of their tokens */
        uint256 allowed = redeemAllowedInternal(pTokenAddress, msg.sender, tokensHeld);
        if (allowed != 0) {
            revert RiskEngineError.ExitMarketRedeemRejection(allowed);
        }

        Market storage marketToExit = _getRiskEngineStorage().markets[pTokenAddress];

        /* Return true if the sender is not already ‘in’ the market */
        if (!marketToExit.accountMembership[msg.sender]) {
            return;
        }

        /* Set pToken account membership to false */
        delete marketToExit.accountMembership[msg.sender];

        /* Delete pToken from the account’s list of assets */
        // load into memory for faster iteration
        IPToken[] memory userAssetList = _getRiskEngineStorage().accountAssets[msg.sender];
        uint256 len = userAssetList.length;
        uint256 assetIndex = len;
        for (uint256 i = 0; i < len; i++) {
            if (userAssetList[i] == pToken) {
                assetIndex = i;
                break;
            }
        }

        // We *must* have found the asset in the list or our redundant data structure is broken
        assert(assetIndex < len);

        // copy last item in list to location of item to be removed, reduce length by 1
        IPToken[] storage storedList = _getRiskEngineStorage().accountAssets[msg.sender];
        storedList[assetIndex] = storedList[storedList.length - 1];
        storedList.pop();

        emit MarketExited(pToken, msg.sender);
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function updateDelegate(address delegate, bool approved) external {
        if (delegate == address(0)) {
            revert CommonError.ZeroAddress();
        }
        if (_getRiskEngineStorage().approvedDelegates[msg.sender][delegate] == approved) {
            revert RiskEngineError.DelegationStatusUnchanged();
        }

        _getRiskEngineStorage().approvedDelegates[msg.sender][delegate] = approved;
        emit DelegateUpdated(msg.sender, delegate, approved);
    }

    /// *** Hooks ***

    /**
     * @inheritdoc IRiskEngine
     */
    function borrowAllowed(address pToken, address borrower, uint256 borrowAmount)
        external
        returns (uint256)
    {
        // Pausing is a very serious situation - we revert to sound the alarms
        if (_getRiskEngineStorage().borrowGuardianPaused[pToken]) {
            revert RiskEngineError.BorrowPaused();
        }

        if (!_getRiskEngineStorage().markets[pToken].isListed) {
            return uint256(RiskEngineError.Error.MARKET_NOT_LISTED);
        }

        if (!_getRiskEngineStorage().markets[pToken].accountMembership[borrower]) {
            // only pTokens may call borrowAllowed if borrower not in market
            if (msg.sender != pToken) {
                revert RiskEngineError.SenderNotPToken();
            }

            // attempt to add borrower to the market
            // already checked if market is listed
            addToMarketInternal(IPToken(msg.sender), borrower);

            // it should be impossible to break the important invariant
            assert(_getRiskEngineStorage().markets[pToken].accountMembership[borrower]);
        }

        if (
            IOracleEngine(_getRiskEngineStorage().oracle).getUnderlyingPrice(
                IPToken(pToken)
            ) == 0
        ) {
            return uint256(RiskEngineError.Error.PRICE_ERROR);
        }

        uint256 cap = _getRiskEngineStorage().borrowCaps[pToken];
        // Borrow cap of type(uint256).max corresponds to unlimited borrowing
        if (cap != type(uint256).max) {
            uint256 totalBorrows = IPToken(pToken).totalBorrows();
            uint256 nextTotalBorrows = totalBorrows.add_(borrowAmount);
            if (nextTotalBorrows > cap) {
                return uint256(RiskEngineError.Error.BORROW_CAP_EXCEEDED);
            }
        }

        (RiskEngineError.Error err,, uint256 shortfall) =
        getHypotheticalAccountLiquidityInternal(
            borrower, IPToken(pToken), 0, borrowAmount, _getCollateralFactor
        );
        if (err != RiskEngineError.Error.NO_ERROR) {
            return uint256(err);
        }
        if (shortfall > 0) {
            return uint256(RiskEngineError.Error.INSUFFICIENT_LIQUIDITY);
        }

        return uint256(RiskEngineError.Error.NO_ERROR);
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function mintAllowed(address pToken, uint256 mintAmount)
        external
        view
        returns (uint256)
    {
        // Pausing is a very serious situation - we revert to sound the alarms
        if (_getRiskEngineStorage().mintGuardianPaused[pToken]) {
            revert RiskEngineError.MintPaused();
        }

        if (!_getRiskEngineStorage().markets[pToken].isListed) {
            return uint256(RiskEngineError.Error.MARKET_NOT_LISTED);
        }

        uint256 cap = _getRiskEngineStorage().supplyCaps[pToken];
        // Skipping the cap check for uncapped coins to save some gas
        if (cap != type(uint256).max) {
            uint256 pTokenSupply = IPToken(pToken).totalSupply();
            ExponentialNoError.Exp memory exchangeRate =
                ExponentialNoError.Exp({mantissa: IPToken(pToken).exchangeRateStored()});
            uint256 nextTotalSupply =
                exchangeRate.mul_ScalarTruncateAddUInt(pTokenSupply, mintAmount);
            if (nextTotalSupply > cap) {
                return uint256(RiskEngineError.Error.SUPPLY_CAP_EXCEEDED);
            }
        }

        return uint256(RiskEngineError.Error.NO_ERROR);
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function redeemAllowed(address pToken, address redeemer, uint256 redeemTokens)
        external
        view
        returns (uint256)
    {
        uint256 allowed = redeemAllowedInternal(pToken, redeemer, redeemTokens);
        if (allowed != uint256(RiskEngineError.Error.NO_ERROR)) {
            return allowed;
        }

        return uint256(RiskEngineError.Error.NO_ERROR);
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function repayBorrowAllowed(address pToken) external view returns (uint256) {
        if (!_getRiskEngineStorage().markets[pToken].isListed) {
            return uint256(RiskEngineError.Error.MARKET_NOT_LISTED);
        }

        return uint256(RiskEngineError.Error.NO_ERROR);
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function liquidateBorrowAllowed(
        address pTokenBorrowed,
        address pTokenCollateral,
        address borrower,
        uint256 repayAmount
    ) external view returns (uint256) {
        if (
            !_getRiskEngineStorage().markets[pTokenBorrowed].isListed
                || !_getRiskEngineStorage().markets[pTokenCollateral].isListed
        ) {
            return uint256(RiskEngineError.Error.MARKET_NOT_LISTED);
        }

        uint256 borrowBalance = IPToken(pTokenBorrowed).borrowBalanceStored(borrower);

        /* allow accounts to be liquidated if the market is deprecated */
        if (isDeprecated(IPToken(pTokenBorrowed))) {
            if (borrowBalance < repayAmount) {
                revert RiskEngineError.RepayMoreThanBorrowed();
            }
        } else {
            /* The borrower must have shortfall in order to be liquidatable */
            (RiskEngineError.Error err,, uint256 shortfall) =
                getAccountLiquidityInternal(borrower);
            if (err != RiskEngineError.Error.NO_ERROR) {
                return uint256(err);
            }

            if (shortfall == 0) {
                return uint256(RiskEngineError.Error.INSUFFICIENT_SHORTFALL);
            }

            /* The liquidator may not repay more than what is allowed by the closeFactor */
            uint256 maxClose = ExponentialNoError.Exp({
                mantissa: _getRiskEngineStorage().closeFactorMantissa
            }).mul_ScalarTruncate(borrowBalance);
            if (repayAmount > maxClose) {
                return uint256(RiskEngineError.Error.TOO_MUCH_REPAY);
            }
        }
        return uint256(RiskEngineError.Error.NO_ERROR);
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function seizeAllowed(address pTokenCollateral, address pTokenBorrowed)
        external
        view
        returns (uint256)
    {
        // Pausing is a very serious situation - we revert to sound the alarms
        if (_getRiskEngineStorage().seizeGuardianPaused) {
            revert RiskEngineError.SeizePaused();
        }

        if (
            !_getRiskEngineStorage().markets[pTokenCollateral].isListed
                || !_getRiskEngineStorage().markets[pTokenBorrowed].isListed
        ) {
            return uint256(RiskEngineError.Error.MARKET_NOT_LISTED);
        }

        if (
            IPToken(pTokenCollateral).riskEngine() != IPToken(pTokenBorrowed).riskEngine()
        ) {
            return uint256(RiskEngineError.Error.RISKENGINE_MISMATCH);
        }

        return uint256(RiskEngineError.Error.NO_ERROR);
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function transferAllowed(address pToken, address src, uint256 transferTokens)
        external
        view
        returns (uint256)
    {
        // Pausing is a very serious situation - we revert to sound the alarms
        if (_getRiskEngineStorage().transferGuardianPaused) {
            revert RiskEngineError.TransferPaused();
        }

        // Currently the only consideration is whether or not
        //  the src is allowed to redeem this many tokens
        uint256 allowed = redeemAllowedInternal(pToken, src, transferTokens);
        if (allowed != uint256(RiskEngineError.Error.NO_ERROR)) {
            return allowed;
        }

        return uint256(RiskEngineError.Error.NO_ERROR);
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function getAssetsIn(address account) external view returns (IPToken[] memory) {
        IPToken[] memory assetsIn = _getRiskEngineStorage().accountAssets[account];

        return assetsIn;
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function checkMembership(address account, IPToken pToken)
        external
        view
        returns (bool)
    {
        return _getRiskEngineStorage().markets[address(pToken)].accountMembership[account];
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function getAccountLiquidity(address account)
        external
        view
        returns (uint256, uint256, uint256)
    {
        (RiskEngineError.Error err, uint256 liquidity, uint256 shortfall) =
            getAccountLiquidityInternal(account);

        return (uint256(err), liquidity, shortfall);
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function getAccountBorrowLiquidity(address account)
        external
        view
        returns (uint256, uint256, uint256)
    {
        (RiskEngineError.Error err, uint256 liquidity, uint256 shortfall) =
        getHypotheticalAccountLiquidityInternal(
            account, IPToken(address(0)), 0, 0, _getCollateralFactor
        );

        return (uint256(err), liquidity, shortfall);
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function getHypotheticalAccountLiquidity(
        address account,
        address pTokenModify,
        uint256 redeemTokens,
        uint256 borrowAmount
    ) external view returns (uint256, uint256, uint256) {
        (RiskEngineError.Error err, uint256 liquidity, uint256 shortfall) =
        getHypotheticalAccountLiquidityInternal(
            account,
            IPToken(pTokenModify),
            redeemTokens,
            borrowAmount,
            _getCollateralFactor
        );
        return (uint256(err), liquidity, shortfall);
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function liquidateCalculateSeizeTokens(
        address pTokenBorrowed,
        address pTokenCollateral,
        uint256 actualRepayAmount
    ) external view returns (uint256, uint256) {
        /* Read oracle prices for borrowed and collateral markets */
        uint256 priceBorrowedMantissa = IOracleEngine(_getRiskEngineStorage().oracle)
            .getUnderlyingPrice(IPToken(pTokenBorrowed));
        uint256 priceCollateralMantissa = IOracleEngine(_getRiskEngineStorage().oracle)
            .getUnderlyingPrice(IPToken(pTokenCollateral));
        if (priceBorrowedMantissa == 0 || priceCollateralMantissa == 0) {
            return (uint256(RiskEngineError.Error.PRICE_ERROR), 0);
        }

        /*
         * Get the exchange rate and calculate the number of collateral tokens to seize:
         *  seizeAmount = actualRepayAmount * liquidationIncentive * priceBorrowed / priceCollateral
         *  seizeTokens = seizeAmount / exchangeRate
         *   = actualRepayAmount * (liquidationIncentive * priceBorrowed) / (priceCollateral * exchangeRate)
         */
        uint256 exchangeRateMantissa = IPToken(pTokenCollateral).exchangeRateStored(); // Note: reverts on error
        uint256 seizeTokens;
        ExponentialNoError.Exp memory numerator;
        ExponentialNoError.Exp memory denominator;
        ExponentialNoError.Exp memory ratio;

        numerator = ExponentialNoError.Exp({
            mantissa: _getRiskEngineStorage().liquidationIncentiveMantissa
        }).mul_(ExponentialNoError.Exp({mantissa: priceBorrowedMantissa}));
        denominator = ExponentialNoError.Exp({mantissa: priceCollateralMantissa}).mul_(
            ExponentialNoError.Exp({mantissa: exchangeRateMantissa})
        );
        ratio = numerator.div_(denominator);

        seizeTokens = ratio.mul_ScalarTruncate(actualRepayAmount);

        return (uint256(RiskEngineError.Error.NO_ERROR), seizeTokens);
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function getAllMarkets() external view returns (IPToken[] memory) {
        return _getRiskEngineStorage().allMarkets[0];
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function delegateAllowed(address user, address delegate)
        external
        view
        returns (bool)
    {
        return _getRiskEngineStorage().approvedDelegates[user][delegate];
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function oracle() external view returns (address) {
        return _getRiskEngineStorage().oracle;
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function collateralFactor(IPToken pToken) external view returns (uint256) {
        return _getCollateralFactor(pToken).mantissa;
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function liquidationThreshold(IPToken pToken) external view returns (uint256) {
        return _getLiquidationThreshold(pToken).mantissa;
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function liquidationIncentive() external view returns (uint256) {
        return _getRiskEngineStorage().liquidationIncentiveMantissa;
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function closeFactor() external view returns (uint256) {
        return _getRiskEngineStorage().closeFactorMantissa;
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function supplyCap(address pToken) external view returns (uint256) {
        return _getRiskEngineStorage().supplyCaps[pToken];
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function borrowCap(address pToken) external view returns (uint256) {
        return _getRiskEngineStorage().borrowCaps[pToken];
    }

    /**
     * @inheritdoc IRiskEngine
     */
    function isDeprecated(IPToken pToken) public view returns (bool) {
        return _getRiskEngineStorage().markets[address(pToken)].collateralFactorMantissa
            == 0 && _getRiskEngineStorage().borrowGuardianPaused[address(pToken)] == true
            && pToken.reserveFactorMantissa() == 1e18;
    }

    function _addMarketInternal(address pToken) internal {
        for (uint256 i = 0; i < _getRiskEngineStorage().allMarkets[0].length; i++) {
            if (_getRiskEngineStorage().allMarkets[0][i] == IPToken(pToken)) {
                revert RiskEngineError.AlreadyListed();
            }
        }
        _getRiskEngineStorage().allMarkets[0].push(IPToken(pToken));
    }

    /**
     * @notice Add the market to the borrower's "assets in" for liquidity calculations
     * @param pToken The market to enter
     * @param borrower The address of the account to modify
     * @return Success indicator for whether the market was entered
     */
    function addToMarketInternal(IPToken pToken, address borrower)
        internal
        returns (RiskEngineError.Error)
    {
        Market storage marketToJoin = _getRiskEngineStorage().markets[address(pToken)];

        if (!marketToJoin.isListed) {
            // market is not listed, cannot join
            return RiskEngineError.Error.MARKET_NOT_LISTED;
        }

        if (marketToJoin.accountMembership[borrower] == true) {
            // already joined
            return RiskEngineError.Error.NO_ERROR;
        }

        // survived the gauntlet, add to list
        // NOTE: we store these somewhat redundantly as a significant optimization
        //  this avoids having to iterate through the list for the most common use cases
        //  that is, only when we need to perform liquidity checks
        //  and not whenever we want to check if an account is in a particular market
        marketToJoin.accountMembership[borrower] = true;
        _getRiskEngineStorage().accountAssets[borrower].push(pToken);

        emit MarketEntered(pToken, borrower);

        return RiskEngineError.Error.NO_ERROR;
    }

    /**
     * @notice Determine the current account liquidity with respect to collateral requirements
     * @return (possible error code,
     *             account liquidity in excess of collateral requirements,
     *          account shortfall below collateral requirements)
     */
    function getAccountLiquidityInternal(address account)
        internal
        view
        returns (RiskEngineError.Error, uint256, uint256)
    {
        return getHypotheticalAccountLiquidityInternal(
            account, IPToken(address(0)), 0, 0, _getLiquidationThreshold
        );
    }

    function redeemAllowedInternal(address pToken, address redeemer, uint256 redeemTokens)
        internal
        view
        returns (uint256)
    {
        if (!_getRiskEngineStorage().markets[pToken].isListed) {
            return uint256(RiskEngineError.Error.MARKET_NOT_LISTED);
        }

        /* If the redeemer is not 'in' the market, then we can bypass the liquidity check */
        if (!_getRiskEngineStorage().markets[pToken].accountMembership[redeemer]) {
            return uint256(RiskEngineError.Error.NO_ERROR);
        }

        /* Otherwise, perform a hypothetical liquidity check to guard against shortfall */
        (RiskEngineError.Error err,, uint256 shortfall) =
        getHypotheticalAccountLiquidityInternal(
            redeemer, IPToken(pToken), redeemTokens, 0, _getCollateralFactor
        );
        if (err != RiskEngineError.Error.NO_ERROR) {
            return uint256(err);
        }
        if (shortfall > 0) {
            return uint256(RiskEngineError.Error.INSUFFICIENT_LIQUIDITY);
        }

        return uint256(RiskEngineError.Error.NO_ERROR);
    }

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
                IOracleEngine(_getRiskEngineStorage().oracle).getUnderlyingPrice(asset);
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
