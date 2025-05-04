// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title ISPA
 * @notice Interface for SPA contract
 */
interface ISPA {
    function swap(uint256, uint256, uint256, uint256) external returns (uint256);

    function getTokens() external view returns (address[] memory);
}
