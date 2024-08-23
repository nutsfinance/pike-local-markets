//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title Library for pToken errors.
 */
library PTokenError {
    error SetReserveFactorFreshCheck();

    error SetReserveFactorBoundsCheck();

    error BorrowRateBoundsCheck();

    error MintRiskEngineRejection(uint256 errorCode);
    error MintFreshnessCheck();

    error RedeemRiskEngineRejection(uint256 errorCode);
    error RedeemFreshnessCheck();
    error RedeemTransferOutNotPossible();

    error TransferNotAllowed();

    error DelegateNotAllowed();
}
