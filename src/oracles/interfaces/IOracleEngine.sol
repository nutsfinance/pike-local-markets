// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IPToken} from "@interfaces/IPToken.sol";

interface IOracleEngine {
    /**
     * @notice Get the price of a pToken's underlying asset
     * @param pToken The pToken address
     * @return price The price of the asset
     */
    function getUnderlyingPrice(IPToken pToken) external view returns (uint256);

    /**
     * @notice Get the price of a asset
     * @param asset The address of the asset
     * @return price The price of the asset
     */
    function getPrice(address asset) external view returns (uint256);
}
