//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {InterestRateStorage} from "@storage/InterestRateStorage.sol";
import {OwnableMixin} from "@utils/OwnableMixin.sol";

contract InterestRateModule is IInterestRateModel, InterestRateStorage, OwnableMixin {
    /**
     * @notice Initialize an interest rate model
     * @param baseRatePerYear The approximate target base APR, as a mantissa (scaled by BASE)
     * @param multiplierPerYear The rate of increase in interest rate wrt utilization (scaled by BASE)
     * @param jumpMultiplierPerYear The multiplierPerBlock after hitting a specified utilization point
     * @param kink_ The utilization point at which the jump multiplier is applied
     */
    function initialize(
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 kink
    ) external onlyOwner {
        _getIRMStorage().baseRatePerSecond = baseRatePerYear / SECONDS_PER_YEAR;
        _getIRMStorage().multiplierPerSecond = multiplierPerYear / SECONDS_PER_YEAR;
        _getIRMStorage().jumpMultiplierPerSecond =
            jumpMultiplierPerYear / SECONDS_PER_YEAR;
        _getIRMStorage().kink = kink;

        emit NewInterestParams(
            baseRatePerYear, multiplierPerYear, jumpMultiplierPerYear, kink
        );
    }

    /**
     * @inheritdoc IInterestRateModel
     */
    function getBorrowRate(uint256 cash, uint256 borrows, uint256 reserves)
        public
        view
        returns (uint256)
    {
        uint256 util = getUtilization(cash, borrows, reserves);
        uint256 kink = _getIRMStorage().kink;

        if (util <= kink) {
            return (util * _getIRMStorage().multiplierPerSecond / BASE)
                + _getIRMStorage().baseRatePerSecond;
        } else {
            uint256 normalRate = (kink * _getIRMStorage().multiplierPerSecond / BASE)
                + _getIRMStorage().baseRatePerSecond;
            uint256 excessUtil = util - kink;
            return (excessUtil * _getIRMStorage().jumpMultiplierPerSecond / BASE)
                + normalRate;
        }
    }

    /**
     * @inheritdoc IInterestRateModel
     */
    function getSupplyRate(
        uint256 cash,
        uint256 borrows,
        uint256 reserves,
        uint256 reserveFactorMantissa
    ) public view returns (uint256) {
        uint256 oneMinusReserveFactor = BASE - reserveFactorMantissa;
        uint256 borrowRate = getBorrowRate(cash, borrows, reserves);
        uint256 rateToPool = borrowRate * oneMinusReserveFactor / BASE;
        return getUtilization(cash, borrows, reserves) * rateToPool / BASE;
    }

    /**
     * @inheritdoc IInterestRateModel
     */
    function getUtilization(uint256 cash, uint256 borrows, uint256 reserves)
        public
        pure
        returns (uint256)
    {
        // Utilization rate is 0 when there are no borrows
        if (borrows == 0) {
            return 0;
        }

        return borrows * BASE / (cash + borrows - reserves);
    }
}
