//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

contract ChainlinkOracleProviderStorage {
    struct OracleProviderData {
        mapping(address => AssetConfig) configs;
    }

    struct AssetConfig {
        address feed;
        uint256 maxStalePeriod;
    }

    /// keccak256(abi.encode(uint256(keccak256("pike.LM.ChainlinkOracleProvider")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _SLOT_ORACLE_PROVIDER_STORAGE =
        0x91fd4e14ee33623009d72c9afed0a1f850081d902688831c340fa2decd76fa00;

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
