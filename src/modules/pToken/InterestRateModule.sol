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
}
