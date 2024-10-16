//SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {
    IInterestRateModel,
    IDoubleJumpRateModel
} from "@interfaces/IDoubleJumpRateModel.sol";
import {DoubleJumpRateStorage} from "@storage/DoubleJumpRateStorage.sol";
import {CommonError} from "@errors/CommonError.sol";
import {IRMError} from "@errors/IRMError.sol";
import {RBACMixin} from "@utils/RBACMixin.sol";

/**
 * @title Pike Markets DoubleJumpRateModel Contract
 * @author NUTS Finance (hello@pike.finance)
 */
contract DoubleJumpRateModel is IDoubleJumpRateModel, DoubleJumpRateStorage, RBACMixin {
    /**
     * @inheritdoc IDoubleJumpRateModel
     */
    function configureInterestRateModel(
        uint256 baseRatePerYear,
        uint256 multiplierPerYear,
        uint256 firstJumpMultiplierPerYear,
        uint256 secondJumpMultiplierPerYear,
        uint256 firstKink,
        uint256 secondKink
    ) external {
        checkPermission(_CONFIGURATOR_PERMISSION, msg.sender);
        InterestRateData storage data = _getIRMStorage();
        if (secondKink == 0) {
            revert CommonError.ZeroValue();
        }
        if (baseRatePerYear != 0 && firstKink != 0 && multiplierPerYear == 0) {
            revert IRMError.InvalidMultiplierForNonZeroBaseRate();
        }
        if (
            firstJumpMultiplierPerYear >= secondJumpMultiplierPerYear
                || firstKink >= secondKink
        ) {
            revert IRMError.InvalidKinkOrMultiplierOrder();
        }
        data.baseRatePerSecond = baseRatePerYear / SECONDS_PER_YEAR;
        data.multiplierPerSecond = multiplierPerYear / SECONDS_PER_YEAR;
        data.firstJumpMultiplierPerSecond = firstJumpMultiplierPerYear / SECONDS_PER_YEAR;
        data.secondJumpMultiplierPerSecond =
            secondJumpMultiplierPerYear / SECONDS_PER_YEAR;
        data.firstKink = firstKink;
        data.secondKink = secondKink;

        emit NewInterestParams(
            data.baseRatePerSecond,
            data.multiplierPerSecond,
            data.firstJumpMultiplierPerSecond,
            data.secondJumpMultiplierPerSecond,
            firstKink,
            secondKink
        );
    }

    /**
     * @inheritdoc IDoubleJumpRateModel
     */
    function kinks() external view returns (uint256, uint256) {
        return (_getIRMStorage().firstKink, _getIRMStorage().secondKink);
    }

    /**
     * @inheritdoc IDoubleJumpRateModel
     */
    function baseRatePerSecond() external view returns (uint256) {
        return _getIRMStorage().baseRatePerSecond;
    }

    /**
     * @inheritdoc IDoubleJumpRateModel
     */
    function multipliers() external pure returns (uint256, uint256, uint256) {
        InterestRateData memory data = _getIRMStorage();
        return (
            data.multiplierPerSecond,
            data.firstJumpMultiplierPerSecond,
            data.secondJumpMultiplierPerSecond
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
    ) public pure returns (uint256) {
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

        if (util <= data.firstKink) {
            return (util * data.multiplierPerSecond / BASE) + data.baseRatePerSecond;
        } else if (util <= data.secondKink) {
            uint256 normalRate = (data.firstKink * data.multiplierPerSecond / BASE)
                + data.baseRatePerSecond;
            uint256 excessUtil = util - data.firstKink;
            return (excessUtil * data.firstJumpMultiplierPerSecond / BASE) + normalRate;
        } else {
            uint256 normalRate = (data.firstKink * data.multiplierPerSecond / BASE)
                + data.baseRatePerSecond;
            normalRate += (data.secondKink - data.firstKink)
                * data.firstJumpMultiplierPerSecond / BASE;
            uint256 excessUtil = util - data.secondKink;
            return (excessUtil * data.secondJumpMultiplierPerSecond / BASE) + normalRate;
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
