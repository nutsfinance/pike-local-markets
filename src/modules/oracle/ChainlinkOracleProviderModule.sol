//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IOracleProvider} from "@interfaces/IOracleProvider.sol";
import {ChainlinkOracleProviderStorage} from "@storage/ChainlinkOracleProviderStorage.sol";
import {CommonError} from "@errors/CommonError.sol";
import {OwnableMixin} from "@utils/OwnableMixin.sol";

contract ChainlinkOracleProviderModule is
    IOracleProvider,
    ChainlinkOracleProviderStorage,
    OwnableMixin
{
    function getPrice(address asset) external view override returns (uint256) {}
}
