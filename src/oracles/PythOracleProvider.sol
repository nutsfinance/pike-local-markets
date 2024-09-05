//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IOracleProvider} from "@oracles/interfaces/IOracleProvider.sol";
import {CommonError} from "@errors/CommonError.sol";

contract PythOracleProviderModule is IOracleProvider {
    struct OracleProviderData {
        mapping(bytes32 => AssetConfig) configs;
    }

    struct AssetConfig {
        bytes32 pythId;
        uint256 maxStalePeriod;
    }

    function getPrice(address asset) external view override returns (uint256) {}
}
