pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {Multiply} from "@periphery/Multiply.sol";
import {Config, console} from "../Config.sol";

contract DeployMultiply is Config {
    function run() external {
        string memory chain = vm.envString("CHAIN");
        uint256 chainId = vm.envUint("CHAIN_ID");

        setUp();

        address uniswapRouter = vm.envAddress("UNISWAP_ROUTER");
        address zapContract = vm.envAddress("ZAP_CONTRACT");
        address initialOwner = vm.envAddress("INITIAL_OWNER");
        address uniV3Factory = vm.envAddress("UNI_V3_FACTORY");
        address aaveV3LendingPool = vm.envAddress("AAVE_V3_LENDING_POOL");
        address aaveV2LendingPool = vm.envAddress("AAVE_V2_LENDING_POOL");
        address balancerVault = vm.envAddress("BALANCER_VAULT");
        address morphoBlue = vm.envAddress("MORPHO_BLUE");

        vm.createSelectFork(vm.envString(rpcs[chainId]));
        vm.startBroadcast(adminPrivateKey);

        address multiply = address(
            new Multiply(
                uniswapRouter,
                zapContract,
                initialOwner,
                uniV3Factory,
                aaveV3LendingPool,
                aaveV2LendingPool,
                balancerVault,
                morphoBlue
            )
        );

        console.log("Deployed Multiply: ", multiply);

        vm.stopBroadcast();
    }
}
