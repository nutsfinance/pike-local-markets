// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IPToken} from "@interfaces/IPToken.sol";

interface IOracleManager {
    enum OracleType {
        Chainlink,
        Pyth,
        Custom
    }

    /// *** Admin Functions ***

    /**
     * @notice Admin function to add a new price feed for an asset
     */
    function addPriceFeed(
        IPToken pToken,
        OracleType oracle,
        address priceFeed,
        bytes calldata data
    ) external;

    /**
     * @notice Admin function to assign oracle guardian access
     * @param guardian The address of the new oracle guardian
     */
    function setOracleGuardian(address guardian) external;

    /// ***Getter Functions***

    /**
     * @notice Get the underlying price of a pToken asset
     */
    function getUnderlyingPrice(IPToken pToken) external view returns (uint256);

    /**
     * @notice Get the added price feed for an asset
     */
    function getPriceFeed(IPToken pToken) external view returns (address);
}
