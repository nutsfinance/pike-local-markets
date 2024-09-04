// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IOracleEngine} from "@interfaces/IOracleEngine.sol";
import {IPToken} from "@interfaces/IPToken.sol";

contract MockOracle {
    mapping(address => uint256) prices;

    /// usd price with 6 decimals
    function setPrice(address pToken, uint256 price, uint256 decimals) external {
        prices[address(pToken)] = price * (10 ** (30 - decimals));
    }

    function getUnderlyingPrice(IPToken pToken) external view returns (uint256 price) {
        return prices[address(pToken)];
    }
}
