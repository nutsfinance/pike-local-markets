//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title Library for common errors.
 */
library CommonError {
    uint256 internal constant NO_ERROR = 0;

    /**
     * @dev Thrown when an operation is attempted on an already initialized contract.
     */
    error AlreadyInitialized();

    /**
     * @dev Thrown when a zero value is encountered.
     */
    error ZeroValue();
}
