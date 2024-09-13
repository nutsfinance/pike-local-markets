//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

abstract contract RBACStorage {
    struct RBACData {
        mapping(address => mapping(bytes32 => bool)) permissions;
    }

    /// keccak256(abi.encode(uint256(keccak256("pike.LM.RBAC")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant _SLOT_RBAC_STORAGE =
        0xd21fdb8e4b687c9e7355e21e2f4695df714198f0142124262187b209674d2600;

    bytes32 internal constant _CONFIGURATOR_PERMISSION = "CONFIGURATOR";
    bytes32 internal constant _PAUSE_GUARDIAN_PERMISSION = "PAUSE_GUARDIAN";
    bytes32 internal constant _BORROW_CAP_GUARDIAN_PERMISSION = "BORROW_CAP_GUARDIAN";
    bytes32 internal constant _SUPPLY_CAP_GUARDIAN_PERMISSION = "SUPPLY_CAP_GUARDIAN";

    error PermissionDenied(address, bytes32);
    error InvalidPermission();

    function _checkPermission(address target, bytes32 permission) internal view {
        _isPermissionValid(permission);
        if (!_getRBACStorage().permissions[target][permission]) {
            revert PermissionDenied(target, permission);
        }
    }

    function _isPermissionValid(bytes32 permission) internal pure {
        if (
            permission != _CONFIGURATOR_PERMISSION
                && permission != _PAUSE_GUARDIAN_PERMISSION
                && permission != _BORROW_CAP_GUARDIAN_PERMISSION
                && permission != _SUPPLY_CAP_GUARDIAN_PERMISSION
        ) {
            revert InvalidPermission();
        }
    }

    function _getRBACStorage() internal pure returns (RBACData storage $) {
        bytes32 s = _SLOT_RBAC_STORAGE;
        assembly {
            $.slot := s
        }
    }
}
