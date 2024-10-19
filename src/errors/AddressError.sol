//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title Library for address related errors.
 */
library AddressError {
    /**
     * @dev Thrown when an address representing a contract is expected, but no code is found at the address.
     */
    error NotAContract(address);

    /**
     * @dev Thrown when a zero address was passed as a function parameter (0x0000000000000000000000000000000000000000).
     */
    error ZeroAddress();
}
