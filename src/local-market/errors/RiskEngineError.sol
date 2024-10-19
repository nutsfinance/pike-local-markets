//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title Library for riskEngine errors.
 */
library RiskEngineError {
    enum Error {
        NO_ERROR,
        RISKENGINE_MISMATCH,
        INSUFFICIENT_SHORTFALL,
        INSUFFICIENT_LIQUIDITY,
        MARKET_NOT_LISTED,
        PRICE_ERROR,
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
