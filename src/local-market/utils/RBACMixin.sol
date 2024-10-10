//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {RBACStorage} from "@storage/RBACStorage.sol";

contract RBACMixin is RBACStorage {
    /**
     * @dev Checks if target address has permission
     */
    function checkPermission(bytes32 permission, address target) internal view {
        _checkPermission(permission, target);
    }

    /**
     * @dev Checks if target address has permission in specified pToken
     */
    function checkNestedPermission(
        bytes32 permission,
        address nestedAddress,
        address target
    ) internal view {
        _checkNestedPermission(permission, nestedAddress, target);
    }
}
