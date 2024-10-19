//SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Initializable} from
    "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@modules/common/OwnableModule.sol";
import "@modules/common/UpgradeModule.sol";

// solhint-disable-next-line no-empty-blocks
contract InitialModuleBundle is OwnableModule, UpgradeModule, Initializable {
    constructor() {
        _disableInitializers();
    }

    function initialize(address initialOwner) public initializer {
        _getOwnableStorage().owner = initialOwner;
    }
}
