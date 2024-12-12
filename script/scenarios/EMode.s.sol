pragma solidity 0.8.28;

import {IRBAC} from "@modules/common/RBACModule.sol";
import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";

import {Config, console} from "../Config.sol";

contract EMode is Config {
    string PATH;

    IPToken pUSDC;
    IPToken pWETH;
    IPToken pSTETH;

    IRiskEngine re;

    constructor() Config(1, true) {
        PATH = "/deployments/base-sepolia-demo/";
    }

    function run() public payable {
        setUp();
        vm.createSelectFork(vm.envString(rpcs[0]));
        forks[0] = vm.activeFork();

        re = IRiskEngine(getAddress("core"));
        pSTETH = IPToken(getAddress("pstETH"));
        pWETH = IPToken(getAddress("pWETH"));
        pUSDC = IPToken(getAddress("pUSDC"));

        // configure ptokens and risk params
        uint8 categoryId = 1;
        address[] memory ptokens = new address[](2);
        ptokens[0] = address(pWETH);
        ptokens[1] = address(pSTETH);
        IRiskEngine.BaseConfiguration memory config =
            IRiskEngine.BaseConfiguration(90e16, 93e16, 102e16);

        vm.startBroadcast(adminPrivateKey);
        configureEMode(categoryId, ptokens, config);
    }

    function configureEMode(
        uint8 categoryId,
        address[] memory ptokens,
        IRiskEngine.BaseConfiguration memory config
    ) internal {
        console.log("=== adding new e-mode with id %s ===", categoryId);
        bool[] memory collateralPermissions = new bool[](ptokens.length);
        bool[] memory borrowPermissions = new bool[](2);
        for (uint256 i = 0; i < ptokens.length; i++) {
            collateralPermissions[i] = true;
            borrowPermissions[i] = true;
            console.log(
                "Token %s: Collateral=%s Borrow=%s",
                IPToken(ptokens[i]).symbol(),
                collateralPermissions[i],
                borrowPermissions[i]
            );
        }

        console.log(
            "LTV: %s%, LLTV: %s%",
            config.collateralFactorMantissa / 1e16,
            config.liquidationThresholdMantissa / 1e16
        );

        re.supportEMode(
            categoryId, true, ptokens, collateralPermissions, borrowPermissions
        );
        re.configureEMode(categoryId, config);
    }

    function getAddress(string memory name) internal view returns (address) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, PATH, name, "/Proxy.json");
        bytes memory addr = vm.parseJson(vm.readFile(path), ".address");
        return abi.decode(addr, (address));
    }
}
