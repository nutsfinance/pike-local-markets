//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

interface IRBAC {
    /**
     * @notice Emitted when an address has been granted permission
     * @param target The address that has been granted.
     * @param permission The permission.
     */
    event PermissionGranted(address target, bytes32 permission);

    /**
     * @notice Emitted when an address has been revoked permission
     * @param target The address that has been revoked.
     * @param permission The permission.
     */
    event PermissionRevoked(address target, bytes32 permission);

    /**
     * @notice Thrown when an address permission is already granted.
     */
    error AlreadyGranted();

    /**
     * @notice Thrown when an address permission is already revoked.
     */
    error AlreadyRevoked();

    /**
     * @notice grant permission for an address.
     * @param target The address that has to be granted.
     * @param permission The permission to be granted.
     */
    function grantPermission(address target, bytes32 permission) external;

    /**
     * @notice revoke permission for an address.
     * @param target The address that has to be revoked.
     * @param permission The permission to be revoked.
     */
    function revokePermission(address target, bytes32 permission) external;

    /**
     * @notice check for an address permission.
     * @param target The address to be checked.
     * @param permission The valid permission to be checked with target.
     */
    function hasPermission(address target, bytes32 permission)
        external
        view
        returns (bool);
}
