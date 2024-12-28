pragma solidity 0.8.28;

import {IRBAC} from "@modules/common/RBACModule.sol";
import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IDoubleJumpRateModel} from "@interfaces/IDoubleJumpRateModel.sol";
import {IFactory} from "@factory/interfaces/IFactory.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";

import {Config, console} from "../Config.sol";

contract EMode is Config {
    string PATH;

    IFactory factory;

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

        factory = IFactory(getAddress(".Factory", "Testnet"));
        re = IRiskEngine(factory.getProtocolInfo(1).riskEngine);
        pUSDC = IPToken(factory.getMarket(1, 0));
        pWETH = IPToken(factory.getMarket(1, 1));
        pSTETH = IPToken(factory.getMarket(1, 2));

        uint256 depositUSDCAmount = 1000e6;
        uint256 depositETHAmount = 1e18;
        uint256 borrowSTETHAmount = 5e17;
        // configure ptokens and risk params
        uint8 categoryId = 1;
        address[] memory ptokens = new address[](2);
        ptokens[0] = address(pWETH);
        ptokens[1] = address(pSTETH);

        bool[] memory collateralPermissions = new bool[](ptokens.length);
        collateralPermissions[0] = true;
        collateralPermissions[1] = false;
        bool[] memory borrowPermissions = new bool[](ptokens.length);
        borrowPermissions[0] = false;
        borrowPermissions[1] = true;

        IRiskEngine.BaseConfiguration memory config =
            IRiskEngine.BaseConfiguration(90e16, 93e16, 102e16);

        vm.startBroadcast(adminPrivateKey);
        configureEMode(
            categoryId, ptokens, collateralPermissions, borrowPermissions, config
        );

        console.log("deposit %s weth and enable collateral", depositETHAmount);
        pWETH.deposit(depositETHAmount, ADMIN);
        (, uint256 excessLiquidity,) = re.getAccountBorrowLiquidity(ADMIN);
        console.log("borrow liquidity before e-mode: %s", excessLiquidity);
        console.log(
            "LTV: %s%, LLTV: %s%",
            re.collateralFactor(0, pWETH) / 1e16,
            re.liquidationThreshold(0, pWETH) / 1e16
        );

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
        console.log("borrow %s steth", borrowSTETHAmount);
        pSTETH.borrow(borrowSTETHAmount);

        (, excessLiquidity,) = re.getAccountBorrowLiquidity(ADMIN);
        console.log(
            "borrow liquidity after borrowing supported asset: %s", excessLiquidity
        );
    }

    function configureEMode(
        uint8 categoryId,
        address[] memory ptokens,
        bool[] memory collateralPermissions,
        bool[] memory borrowPermissions,
        IRiskEngine.BaseConfiguration memory config
    ) internal {
        console.log("=== adding new e-mode with id %s ===", categoryId);
        for (uint256 i = 0; i < ptokens.length; i++) {
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

    function getAddress(string memory key, string memory name)
        internal
        view
        returns (address)
    {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, PATH, name, ".json");
        bytes memory addr = vm.parseJson(vm.readFile(path), key);
        return abi.decode(addr, (address));
    }
}
