pragma solidity 0.8.28;

import {IRBAC} from "@modules/common/RBACModule.sol";
import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IDoubleJumpRateModel} from "@interfaces/IDoubleJumpRateModel.sol";
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

        uint256 depositUSDCAmount = 1000e6;
        uint256 depositETHAmount = 1e18;
        // configure ptokens and risk params
        uint8 categoryId = 1;
        address[] memory ptokens = new address[](2);
        ptokens[0] = address(pWETH);
        ptokens[1] = address(pSTETH);
        IRiskEngine.BaseConfiguration memory config =
            IRiskEngine.BaseConfiguration(90e16, 93e16, 102e16);

        vm.startBroadcast(adminPrivateKey);
        configureEMode(categoryId, ptokens, config);

        console.log("deposit %s weth and enable collateral", depositETHAmount);
        pWETH.deposit(depositETHAmount, ADMIN);
        (, uint256 excessLiquidity,) = re.getAccountBorrowLiquidity(ADMIN);
        console.log("borrow liquidity before e-mode: %s", excessLiquidity);
        console.log(
            "LTV: %s%, LLTV: %s%",
            re.collateralFactor(0, pWETH) / 1e16,
            re.liquidationThreshold(0, pWETH) / 1e16
        );

        re.getAccountBorrowLiquidity(ADMIN);

        console.log("=== switch to e-mode %s ===", categoryId);
        // switch to confugured e-mode
        re.switchEMode(categoryId);

        (, excessLiquidity,) = re.getAccountBorrowLiquidity(ADMIN);
        console.log("borrow liquidity after e-mode: %s", excessLiquidity);
        console.log(
            "LTV: %s%, LLTV: %s%",
            re.collateralFactor(1, pWETH) / 1e16,
            re.liquidationThreshold(1, pWETH) / 1e16
        );

        console.log("deposit %s usdc", depositUSDCAmount);
        pUSDC.deposit(depositUSDCAmount, ADMIN);

        (, excessLiquidity,) = re.getAccountBorrowLiquidity(ADMIN);
        console.log(
            "borrow liquidity after supplying unsupported asset: %s", excessLiquidity
        );

        // pSTETH.borrow(5e17);
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
