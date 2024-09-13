//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {RBACStorage} from "@storage/RBACStorage.sol";

contract RBACMixin is RBACStorage {
    /**
     * @dev Checks if target address has permission
     */
    function checkPermission(address target, bytes32 permission) internal view {
        _checkPermission(target, permission);
    }
}
