//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {InterestRateStorage} from "@storage/InterestRateStorage.sol";
import {CommonError} from "@errors/CommonError.sol";
import {OwnableMixin} from "@utils/OwnableMixin.sol";

/**
 * @title Pike Markets InterestRateModule Contract
 * @author NUTS Finance (hello@pike.finance)
 */
contract InterestRateModule is IInterestRateModel, InterestRateStorage, OwnableMixin {
    event NewInterestParams(
        uint256 baseRatePerSecond,
        uint256 multiplierPerSecond,
        uint256 jumpMultiplierPerSecond,
        uint256 kink
    );

    /**
     * @notice Initialize an interest rate model
     * @param baseRatePerYear The approximate target base APR, as a mantissa (scaled by BASE)
     * @param multiplierPerYear The rate of increase in interest rate wrt utilization (scaled by BASE)
     * @param jumpMultiplierPerYear The multiplierPerSecond after hitting a specified utilization point
     * @param kink The utilization point at which the jump multiplier is applied
     */
    function initialize(
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 kink
    ) external onlyOwner {
        InterestRateData storage data = _getIRMStorage();
        if (data.kink != 0) {
            revert CommonError.AlreadyInitialized();
        }
        data.baseRatePerSecond = baseRatePerYear / SECONDS_PER_YEAR;
        data.multiplierPerSecond = multiplierPerYear / SECONDS_PER_YEAR;
        data.jumpMultiplierPerSecond = jumpMultiplierPerYear / SECONDS_PER_YEAR;
        data.kink = kink;

        emit NewInterestParams(
            data.baseRatePerSecond,
            data.multiplierPerSecond,
            data.jumpMultiplierPerSecond,
            kink
        );
    }

    /**
     * @inheritdoc IInterestRateModel
     */
    function getBorrowRate(uint256 cash, uint256 borrows, uint256 reserves)
        public
        pure
        returns (uint256)
    {
        uint256 util = getUtilization(cash, borrows, reserves);
        InterestRateData memory data = _getIRMStorage();

        if (util <= data.kink) {
            return (util * data.multiplierPerSecond / BASE) + data.baseRatePerSecond;
        } else {
            uint256 normalRate =
                (data.kink * data.multiplierPerSecond / BASE) + data.baseRatePerSecond;
            uint256 excessUtil = util - data.kink;
            return (excessUtil * data.jumpMultiplierPerSecond / BASE) + normalRate;
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
    ) public pure returns (uint256) {
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
