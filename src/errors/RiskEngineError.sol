//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title Library for riskEngine errors.
 */
library RiskEngineError {
    enum Error {
        NO_ERROR,
        UNAUTHORIZED,
        RISKENGINE_MISMATCH,
        INSUFFICIENT_SHORTFALL,
        INSUFFICIENT_LIQUIDITY,
        INVALID_CLOSE_FACTOR,
        INVALID_COLLATERAL_FACTOR,
        INVALID_LIQUIDATION_INCENTIVE,
        MARKET_NOT_ENTERED, // no longer possible
        MARKET_NOT_LISTED,
        MARKET_ALREADY_LISTED,
        MATH_ERROR,
        NONZERO_BORROW_BALANCE,
        PRICE_ERROR,
        REJECTION,
        SNAPSHOT_ERROR,
        TOO_MANY_ASSETS,
        TOO_MUCH_REPAY,
        SUPPLY_CAP_EXCEEDED,
        BORROW_CAP_EXCEEDED
    }

    error NonZeroBorrowBalance();
    error ExitMarketRedeemRejection(uint256 errorCode);

    error MintPaused();
    error BorrowPaused();
    error SeizePaused();
    error TransferPaused();

    error InvalidRedeemTokens();
    error SenderNotPToken();
    error BorrowCapExceeded();
    error RepayMoreThanBorrowed();

    error MarketNotListed();
    error InvalidCollateralFactor();
    error InvalidPrice();
    error InvalidLiquidationThreshold();

    error AlreadyListed();

    error NotBorrowCapGaurdian();
    error NotSupplyCapGaurdian();
    error NotPauseGaurdian();

    error DelegationStatusUnchanged();
}
