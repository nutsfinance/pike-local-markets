// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title ISPA
 * @notice Interface for SPA contract
 */
interface ISPA {
    function getTokens() external returns (address[] memory);
}
