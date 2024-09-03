//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

contract OracleEngineStorage {
    struct OracleEngineData {
        mapping(address => AssetConfig) configs;
    }

    struct AssetConfig {
        address mainOracle;
        address fallbackOracle;
        uint256 lowerBoundRatio;
        uint256 upperBoundRatio;
    }

    /// keccak256(abi.encode(uint256(keccak256("pike.LM.OracleEngine")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _SLOT_ORACLE_ENGINE_STORAGE =
        0x2a3f057af83b51dce21a33ee726ce4ef825c690399372270fb1f63428b527800;

    function _getOracleEngineStorage()
        internal
        pure
        returns (OracleEngineData storage data)
    {
        bytes32 s = _SLOT_ORACLE_ENGINE_STORAGE;
        assembly {
            data.slot := s
        }
    }
}
