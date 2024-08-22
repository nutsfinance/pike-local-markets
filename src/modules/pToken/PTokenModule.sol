//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {ExponentialNoError} from "@utils/ExponentialNoError.sol";
import {PTokenStorage} from "@storage/PTokenStorage.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {AddressError} from "@errors/AddressError.sol";
import {OwnableMixin} from "@utils/OwnableMixin.sol";
import {CommonError} from "@errors/CommonError.sol";
import {PTokenError} from "@errors/PTokenError.sol";
import {IPToken} from "@interfaces/IPToken.sol";

contract PToken is IPToken, PTokenStorage, OwnableMixin {
    using ExponentialNoError for ExponentialNoError.Exp;

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     */
    modifier nonReentrant() {
        if (!_getPTokenStorage()._notEntered) {
            revert CommonError.ReentrancyGuardReentrantCall();
        }
        _getPTokenStorage()._notEntered = false;
        _;
        _getPTokenStorage()._notEntered = true;
    }

    /**
     * @notice Initialize the local market
     * @param underlying_ The address of the underlying token
     * @param riskEngine_ The address of the RiskEngine
     * @param initialExchangeRateMantissa_ The initial exchange rate, scaled by 1e18
     * @param reserveFactorMantissa_ percentage of borrow interests that goes to protocol, scaled by 1e18
     * @param name_ ERC20 name of this token
     * @param symbol_ ERC20 symbol of this token
     * @param decimals_ ERC20 decimal precision of this token
     */
    function initialize(
        address underlying_,
        IRiskEngine riskEngine_,
        uint256 initialExchangeRateMantissa_,
        uint256 reserveFactorMantissa_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) external onlyOwner {
        if (
            _getPTokenStorage().accrualBlockTimestamp != 0
                || _getPTokenStorage().borrowIndex != 0
        ) {
            revert CommonError.AlreadyInitialized();
        }
        if (initialExchangeRateMantissa_ == 0) {
            revert CommonError.ZeroValue();
        }
        // Set initial exchange rate
        _getPTokenStorage().initialExchangeRateMantissa = initialExchangeRateMantissa_;

        // set risk engine
        _setRiskEngine(riskEngine_);

        _setReserveFactorFresh(reserveFactorMantissa_);

        // Initialize block timestamp and borrow index (block timestamp is set to current block timestamp)
        _getPTokenStorage().accrualBlockTimestamp = getBlockTimestamp();
        _getPTokenStorage().borrowIndex = _MANTISSA_ONE;

        _getPTokenStorage().name = name_;
        _getPTokenStorage().symbol = symbol_;
        _getPTokenStorage().decimals = decimals_;

        // The counter starts true to prevent changing it from zero to non-zero (i.e. smaller cost/refund)
        _getPTokenStorage()._notEntered = true;

        // Set underlying and sanity check it
        _getPTokenStorage().underlying = underlying_;
        IPToken(underlying_).totalSupply();
    }

    /**
     * @notice Sets a new risk engine for the market
     * @dev Admin function to set a new risk engine
     */
    function setRiskEngine(IRiskEngine newRiskEngine) external onlyOwner {
        _setRiskEngine(newRiskEngine);
    }

    /**
     * @notice Sets a new reserve factor for the protocol (*requires fresh interest accrual)
     * @dev Admin function to set a new reserve factor
     */
    function _setReserveFactorFresh(uint256 newReserveFactorMantissa) internal {
        // Verify market's block timestamp equals current block timestamp
        if (_getPTokenStorage().accrualBlockTimestamp != getBlockTimestamp()) {
            revert PTokenError.SetReserveFactorFreshCheck();
        }

        // Check newReserveFactor ≤ maxReserveFactor
        if (newReserveFactorMantissa > reserveFactorMaxMantissa) {
            revert PTokenError.SetReserveFactorBoundsCheck();
        }

        uint256 oldReserveFactorMantissa = _getPTokenStorage().reserveFactorMantissa;
        _getPTokenStorage().reserveFactorMantissa = newReserveFactorMantissa;

        emit NewReserveFactor(oldReserveFactorMantissa, newReserveFactorMantissa);
    }

    /**
     * @dev Function to simply retrieve block number
     *  This exists mainly for inheriting test contracts to stub this result.
     */
    function getBlockTimestamp() internal view returns (uint256) {
        return block.timestamp;
    }

    function _setRiskEngine(IRiskEngine newRiskEngine) internal {
        IRiskEngine oldRiskEngine = _getPTokenStorage().riskEngine;

        /// TODO: add erc165 checker

        // Set market's riskEngine to newRiskEngine
        _getPTokenStorage().riskEngine = newRiskEngine;

        // Emit NewRiskEngine(oldRiskEngine, newRiskEngine)
        emit NewRiskEngine(oldRiskEngine, newRiskEngine);
    }
}
