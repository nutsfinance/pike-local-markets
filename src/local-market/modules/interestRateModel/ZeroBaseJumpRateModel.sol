//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {ZeroBaseJumpRateStorage} from "@storage/ZeroBaseJumpRateStorage.sol";
import {CommonError} from "@errors/CommonError.sol";
import {OwnableMixin} from "@utils/OwnableMixin.sol";

/**
 * @title Pike Markets ZeroBaseJumpRateModel Contract
 * @author NUTS Finance (hello@pike.finance)
 */
contract ZeroBaseJumpRateModel is
    IInterestRateModel,
    ZeroBaseJumpRateStorage,
    OwnableMixin
{
    /**
     * @notice Initialize an interest rate model
     * @param baseUtilizationRate the initial utilization rate that low slope starts from (scaled by BASE)
     * @param multiplierPerYear The rate of increase in interest rate wrt utilization (scaled by BASE)
     * @param jumpMultiplierPerYear The multiplierPerSecond after hitting a specified utilization point
     * @param kink The utilization point at which the jump multiplier is applied
     */
    function initialize(
        uint256 baseUtilizationRate,
        uint256 multiplierPerYear,
        uint256 jumpMultiplierPerYear,
        uint256 kink
    ) external onlyOwner {
        InterestRateData storage data = _getIRMStorage();
        if (data.kink != 0) {
            revert CommonError.AlreadyInitialized();
        }
        data.baseUtilizationRate = baseUtilizationRate;
        data.multiplierPerSecond = multiplierPerYear / SECONDS_PER_YEAR;
        data.jumpMultiplierPerSecond = jumpMultiplierPerYear / SECONDS_PER_YEAR;
        data.kink = kink;

        emit NewInterestParams(
            baseUtilizationRate, multiplierPerYear, jumpMultiplierPerYear, kink
        );
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
    function getBorrowRate(uint256 cash, uint256 borrows, uint256 reserves)
        public
        pure
        returns (uint256)
    {
        uint256 util = getUtilization(cash, borrows, reserves);
        InterestRateData memory data = _getIRMStorage();

        if (util <= data.baseUtilizationRate) {
            return 0;
        } else if (util <= data.kink) {
            return ((util - data.baseUtilizationRate) * data.multiplierPerSecond / BASE);
        } else {
            uint256 normalRate =
                ((data.kink - data.baseUtilizationRate) * data.multiplierPerSecond / BASE);
            uint256 excessUtil = util - data.kink;
            return (excessUtil * data.jumpMultiplierPerSecond / BASE) + normalRate;
        }
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
