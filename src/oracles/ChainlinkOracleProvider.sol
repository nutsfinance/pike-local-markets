//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IOracleProvider} from "@oracles/interfaces/IOracleProvider.sol";
import {CommonError} from "@errors/CommonError.sol";

contract ChainlinkOracleProvider is IOracleProvider {
    struct OracleProviderData {
        mapping(address => AssetConfig) configs;
    }

    struct AssetConfig {
        address feed;
        uint256 maxStalePeriod;
    }

    function getPrice(address asset) external view override returns (uint256) {}
}
