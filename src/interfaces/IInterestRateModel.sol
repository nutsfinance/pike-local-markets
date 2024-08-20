// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IInterestRateModel {
    /**
     * @notice Calculates the utilization rate of the market: `borrows / (cash + borrows - reserves)`
     */
    function getUtilization() external view returns (uint256);

    /**
     * @notice Returns the current per-second borrow interest rate for this pToken
     * @return The borrow interest rate per second, scaled by 1e18
     */
    function borrowRatePerSecond() external view returns (uint256);

    /**
     * @notice Returns the current per-second borrow interest rate for this pToken
     * @return The supply interest rate per second, scaled by 1e18
     */
    function supplyRatePerSecond() external view returns (uint256);
}
