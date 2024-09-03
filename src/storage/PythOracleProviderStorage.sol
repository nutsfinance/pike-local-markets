//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

contract PythOracleProviderStorage {
    struct OracleProviderData {
        mapping(bytes32 => AssetConfig) configs;
    }

    struct AssetConfig {
        bytes32 pythId;
        uint256 maxStalePeriod;
    }

    /// keccak256(abi.encode(uint256(keccak256("pike.LM.PythOracleProvider")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _SLOT_ORACLE_PROVIDER_STORAGE =
        0x1b7aa242845c3cae47efd8894c8daa44b3653b8b085b2a6726444dc711d32600;

    function _getOracleProviderStorage()
        internal
        pure
        returns (OracleProviderData storage data)
    {
        bytes32 s = _SLOT_ORACLE_PROVIDER_STORAGE;
        assembly {
            data.slot := s
        }
    }
}
