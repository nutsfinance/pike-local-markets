// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";

contract Config is Script {
    bool testnet;

    uint256 deployerPrivateKey;
    uint256 adminPrivateKey;

    uint256[] public forks;

    address DEPLOYER;
    address ADMIN;

    string[] public rpcs;
    uint32[] public chainIds;

    constructor(uint256 _networkCount, bool _testnet) {
        forks = new uint256[](_networkCount);
        rpcs = new string[](_networkCount);
        chainIds = new uint32[](_networkCount);

        testnet = _testnet;

        if (testnet) {
            /// rpcs and chainIds for testnet should be added here
            /// based on network count

            rpcs[0] = "BASE_SEPOLIA_RPC";
            rpcs[1] = "ARB_SEPOLIA_RPC";
            rpcs[2] = "OP_SEPOLIA_RPC";
            rpcs[3] = "BERA_BARTIO_RPC";
            rpcs[4] = "MONAD_TESTNET_RPC";
            rpcs[5] = "HYPER_TESTNET";

            chainIds[0] = 84_532; // Base
            chainIds[1] = 421_614; // Arb
            chainIds[2] = 11_155_420; // Op
            chainIds[3] = 80_084; // BERA
            chainIds[4] = 10_143; // MONAD
            chainIds[5] = 998; // HYPERLIQUID
        } else {
            /// rpcs and chainIds for mainnet should be added here
            /// based on network count
        }
    }

    function setUp() internal {
        if (vm.envUint("HEX_PRIV_KEY") == 0) revert("No private keys found");
        deployerPrivateKey = vm.envUint("HEX_PRIV_KEY");
        adminPrivateKey = vm.envUint("MODERATOR_PRIV_KEY");
        DEPLOYER = vm.addr(deployerPrivateKey);
        ADMIN = vm.addr(adminPrivateKey);
    }
}
