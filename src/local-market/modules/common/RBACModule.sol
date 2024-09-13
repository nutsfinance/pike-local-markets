//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IRBAC} from "@interfaces/IRBAC.sol";
import {RBACMixin} from "@utils/RBACMixin.sol";
import {CommonError} from "@errors/CommonError.sol";
import {OwnableMixin} from "@utils/OwnableMixin.sol";

/**
 * @title Contract for facilitating role based access control.
 * See IRBAC.
 */
contract RBACModule is IRBAC, RBACMixin, OwnableMixin {
    /**
     * @inheritdoc IRBAC
     */
    function grantPermission(address target, bytes32 permission) external onlyOwner {
        if (_hasPermission(target, permission)) {
            revert AlreadyGranted();
        }
        _getRBACStorage().permissions[target][permission] = true;
        emit PermissionGranted(target, permission);
    }

    /**
     * @inheritdoc IRBAC
     */
    function revokePermission(address target, bytes32 permission) external onlyOwner {
        if (!_hasPermission(target, permission)) {
            revert AlreadyRevoked();
        }

        _getRBACStorage().permissions[target][permission] = false;
        emit PermissionRevoked(target, permission);
    }

    /**
     * @inheritdoc IRBAC
     */
    function hasPermission(address target, bytes32 permission)
        external
        view
        returns (bool)
    {
        return _hasPermission(target, permission);
    }

    function _hasPermission(address target, bytes32 permission)
        internal
        view
        returns (bool)
    {
        if (target == address(0)) {
            revert CommonError.ZeroAddress();
        }

        _isPermissionValid(permission);

        return _getRBACStorage().permissions[target][permission];
    }
}
