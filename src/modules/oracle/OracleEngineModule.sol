//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IOracleEngine, IPToken} from "@interfaces/IOracleEngine.sol";
import {OracleEngineStorage} from "@storage/OracleEngineStorage.sol";
import {CommonError} from "@errors/CommonError.sol";
import {OwnableMixin} from "@utils/OwnableMixin.sol";

contract OracleEngineModule is IOracleEngine, OracleEngineStorage, OwnableMixin {
    function getUnderlyingPrice(IPToken pToken)
        external
        view
        override
        returns (uint256)
    {}

    function getPrice(address asset) external view override returns (uint256) {}
}
