// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IOracleProvider {
    /**
     * @notice Get the price of a asset
     */
    function getPrice(address asset) external view returns (uint256);
}
