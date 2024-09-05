// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IPToken} from "@interfaces/IPToken.sol";

interface IOracleEngine {
    /**
     * @notice Get the underlying price of a pToken asset
     */
    function getUnderlyingPrice(IPToken pToken) external view returns (uint256);

    /**
     * @notice Get the price of a asset
     */
    function getPrice(address asset) external view returns (uint256);
}
