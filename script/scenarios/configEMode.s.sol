pragma solidity 0.8.28;

import {IRBAC} from "@modules/common/RBACModule.sol";
import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IDoubleJumpRateModel} from "@interfaces/IDoubleJumpRateModel.sol";
import {IFactory} from "@factory/interfaces/IFactory.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {Timelock} from "@governance/Timelock.sol";

import {Config, console} from "../Config.sol";

contract EMode is Config {
    string PATH;

    IFactory factory;

    IPToken pUSDC;
    IPToken pWETH;
    IPToken pSTETH;

    IRiskEngine re;
    Timelock tm;

    constructor() Config(3, true) {
        PATH = "";
    }

    function run() public payable {
        setUp();
        vm.createSelectFork(vm.envString(rpcs[0]));
        forks[0] = vm.activeFork();

        factory = IFactory(0xF5b46BCB51963B8A7e0390a48C1D6E152A78174D);
        re = IRiskEngine(factory.getProtocolInfo(1).riskEngine);
        tm = Timelock(payable(factory.getProtocolInfo(1).timelock));
        pUSDC = IPToken(factory.getMarket(1, 0));
        pWETH = IPToken(factory.getMarket(1, 1));
        pSTETH = IPToken(factory.getMarket(1, 2));

        // configure ptokens and risk params
        uint8 categoryId = 2;
        address[] memory ptokens = new address[](2);
        ptokens[0] = address(pUSDC);
        ptokens[1] = address(pWETH);

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

        tm.emergencyExecute(
            address(re),
            0,
            abi.encodeWithSelector(
                re.supportEMode.selector,
                categoryId,
                true,
                ptokens,
                collateralPermissions,
                borrowPermissions
            )
        );

        tm.emergencyExecute(
            address(re),
            0,
            abi.encodeWithSelector(re.configureEMode.selector, categoryId, config)
        );
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
