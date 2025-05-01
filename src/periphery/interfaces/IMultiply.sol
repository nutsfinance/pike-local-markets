// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IFLHelper} from "@periphery/interfaces/IFLHelper.sol";

/**
 * @title IMultiply
 * @notice Interface for leverage and deleverage operations with support for LP tokens
 * @dev Extends IFLHelper to use flash loans for leveraging positions
 */
interface IMultiply is IFLHelper {
    /**
     * @dev Parameters for leverage operations with LP tokens
     */
    struct LeverageLPParams {
        address borrowPToken; // Pike token for the borrowed asset
        address supplyPToken; // Pike token for the LP collateral
        address spa; // SPA contract address for LP operations
        uint256 collateralAmount; // Collateral amount to borrow against (it will be used as initial deposit if its called by leverageLP)
        uint256 safetyFactor; // Safety factor applied to the leverage to cover the fees
        SwapProtocol swapProtocol; // Protocol to use for swapping tokens
        uint256[] proportions; // Proportions of collateralAmount to use for mint and swap the rest to pair token, based on swap index
        uint256[] minAmountOut; // Min. output amount for swap, based on swap index
        uint24[] feeTiers; // Fee tiers for swap operations, based on swap index
    }

    /**
     * @dev Parameters for deleverage operations with LP tokens
     */
    struct DelevearageLPParams {
        address borrowPToken; // Pike token for the borrowed asset to be repaid
        address supplyPToken; // Pike token for the LP collateral to be redeemed
        address spa; // SPA contract address for LP operations
        uint256 debtToRepay; // Amount of debt to repay on borrowPToken
        uint256 collateralToRedeem; // Amount of LP collateral to redeem
        uint256 safetyFactor; // Safety factor applied to the deleverage to cover the fees
        SwapProtocol swapProtocol; // Protocol to use for swapping tokens
        RedeemType redeemType; // Method to redeem LP tokens
        uint256 tokenIndexForSingle; // Token index for single redemption (if applicable)
        uint256[] minAmountsOut; // Minimum amounts out for LP redemption, based on spa index
        uint24[] feeTiers; // Fee tiers for swap operations, based on spa index
    }

    /**
     * @dev Available swap protocols
     */
    enum SwapProtocol {
        NONE,
        UNISWAP_V3, // Uniswap V3
        TAPIO // Tapio

    }

    /**
     * @dev LP token redemption types (from Tapio SPA)
     */
    enum RedeemType {
        SINGLE, // Single asset redemption
        MULTI, // Multi-asset redemption
        PROPORTIONAL // Proportional redemption

    }

    /**
     * @dev Emitted when a leverage operation is executed
     */
    event LeverageExecuted(
        address indexed user,
        address supplyPToken,
        address borrowPToken,
        uint256 collateralAmount,
        uint256 borrowedAmount,
        uint256 swapFees,
        SwapProtocol swapProtocol
    );

    /**
     * @dev Emitted when a deleverage operation is executed
     */
    event DeleverageExecuted(
        address indexed user,
        address borrowPToken,
        address supplyPToken,
        uint256 debtRepaid,
        uint256 collateralRedeemed,
        uint256 swapFees,
        SwapProtocol swapProtocol
    );

    /**
     * @dev Emitted on flash loan callback execution
     */
    event FlashLoanCallback(
        address indexed user,
        FlashLoanSource source,
        address token,
        uint256 amount,
        uint256 fee
    );

    /**
     * @notice Opens a leveraged LP position using an initial deposit of the borrow token
     * @dev
     * - User supplies an initial `collateralAmount` in the borrow token's underlying asset
     * - Contract executes a flash loan of the same asset via `flParams`
     * - The total amount (initial + flashloan) is swapped into underlying tokens of the LP pair based on `proportions`
     * - Swapped tokens are used to mint LP tokens via the SPA contract (ZapIn)
     * - Minted LP tokens are supplied as collateral
     * - Contract borrows the flashloan amount to repay the flash loan
     * - Note: User must approve this contract on riskEngine to borrow on their behalf
     *
     * @param flParams Parameters for the flash loan
     * @param params Parameters for leveraging with LP tokens
     */
    function leverageLP(
        FlashLoanParams calldata flParams,
        LeverageLPParams calldata params
    ) external;

    /**
     * @notice Leverages an existing collateralized LP position without a new deposit
     * @dev
     * - Uses existing supplied LP token collateral, determined by `collateralAmount`
     * - No new deposit is made by the user
     * - Executes flash loan of the borrow token to simulate additional leverage
     * - Total amount is swapped and minted into LP tokens via the SPA contract (ZapIn)
     * - Newly minted LP tokens are added to collateral, and borrowed amount is used to repay flash loan
     * - Final position achieves increased leverage, limited by protocol caps
     *
     * @param flParams Parameters for the flash loan
     * @param params Parameters for leveraging using existing collateral
     */
    function leverageExisting(
        FlashLoanParams calldata flParams,
        LeverageLPParams calldata params
    ) external;

    /**
     * @notice Deleverages a position by repaying debt with flashloan
     * @dev
     * - Uses flash loan to repay specified debt amount
     * - Redeems corresponding LP collateral
     * - Uses SPA contract to redeem LP tokens (ZapOut)
     * - Swaps resulting tokens to borrowed asset
     * - Repays flash loan and returns excess (if any) to user
     *
     * @param params LP deleverage parameters
     * @return tokens The tokens returned to user (if excess)
     * @return amounts The amounts of each token returned
     */
    function deleverageLP(
        FlashLoanParams calldata flParams,
        DelevearageLPParams calldata params
    ) external returns (address[] memory tokens, uint256[] memory amounts);

    /**
     * @notice Calculates maxBorrowAmount for an account given supply token in usd
     * @dev Based on account's borrowing capacity and collateral factor of the token
     * @param account User account address
     * @param supplyPToken Pike token for the supply collateral
     * @return maxBorrowAmount Maximum amount that can be borrowed safely (in usd value)
     */
    function calculateMaxBorrowForLeverage(address account, address supplyPToken)
        external
        view
        returns (uint256 maxBorrowAmount);

    /**
     * @notice Calculates maximum collateral allowed to be redeemed for deleveraging specified debt
     * @dev Based on current price of collateral and debt tokens
     * @param borrowPToken Pike token for the debt
     * @param supplyPToken Pike token for the collateral
     * @param repayAmount Amount of debt to repay
     * @param initialCollateral Initial amount of deposit
     * @return maxCollateralAmount Maximum collateral amount that can be redeemed with given repay amount
     */
    function calculateMaxRedeemForDeleverage(
        address borrowPToken,
        address supplyPToken,
        uint256 repayAmount,
        uint256 initialCollateral
    ) external view returns (uint256 maxCollateralAmount);
}
