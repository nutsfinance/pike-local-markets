// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.28;

/// @dev This interface is used for factorizing IMorphoStaticTyping and IMorpho.
/// @dev Consider using the IMorpho interface instead of this one.
interface IMorphoBlue {
    /// @notice Executes a flash loan.
    /// @dev Flash loans have access to the whole balance of the contract (the liquidity and deposited collateral of all
    /// markets combined, plus donations).
    /// @dev Warning: Not ERC-3156 compliant but compatibility is easily reached:
    /// - `flashFee` is zero.
    /// - `maxFlashLoan` is the token's balance of this contract.
    /// - The receiver of `assets` is the caller.
    /// @param token The token to flash loan.
    /// @param assets The amount of assets to flash loan.
    /// @param data Arbitrary data to pass to the `onMorphoFlashLoan` callback.
    function flashLoan(address token, uint256 assets, bytes calldata data) external;
}
