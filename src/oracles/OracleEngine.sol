//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IPToken} from "@interfaces/IPToken.sol";
import {CommonError} from "@errors/CommonError.sol";
import {IOracleEngine} from "@oracles/interfaces/IOracleEngine.sol";

contract OracleEngine is IOracleEngine {
    struct OracleEngineData {
        mapping(address => AssetConfig) configs;
    }

    struct AssetConfig {
        address mainOracle;
        address fallbackOracle;
        uint256 lowerBoundRatio;
        uint256 upperBoundRatio;
    }

    function getUnderlyingPrice(IPToken pToken)
        external
        view
        override
        returns (uint256)
    {}

    function getPrice(address asset) external view override returns (uint256) {}
}
