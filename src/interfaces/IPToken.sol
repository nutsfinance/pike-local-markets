// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";

interface IPToken is IERC20 {
    /**
     * @notice Sender supplies assets into the market and receives pTokens in exchange
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param mintAmount The amount of the underlying asset to supply
     * @return uint 0=success, otherwise a failure (see Errors for details)
     */
    function mint(uint256 mintAmount) external returns (uint256);

    /**
     * @notice Sender calls on-behalf of minter.
     * sender supplies assets into the market and minter receives pTokens in exchange
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param minter User whom the supply will be attributed to
     * @param mintAmount The amount of the underlying asset to supply
     * @return uint 0=success, otherwise a failure (see Errors for details)
     */
    function mintBehalf(address minter, uint256 mintAmount) external returns (uint256);

    /**
     * @notice Sender redeems pTokens in exchange for the underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param redeemTokens The number of pTokens to redeem into underlying
     * @return uint 0=success, otherwise a failure (see Errors for details)
     */
    function redeem(uint256 redeemTokens) external returns (uint256);

    /**
     * @notice Sender redeems assets on behalf of redeemer address. This function is only available
     *  for senders, explicitly marked as delegates of the supplier using `riskEngine.updateDelegate`
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param redeemer The user on behalf of whom to redeem
     * @param redeemTokens The number of vTokens to redeem into underlying
     * @return uint 0=success, otherwise a failure (see Errors for details)
     */
    function redeemBehalf(address redeemer, uint256 redeemTokens)
        external
        returns (uint256);

    /**
     * @notice Sender redeems pTokens in exchange for a specified amount of underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param redeemAmount The amount of underlying to redeem
     * @return uint 0=success, otherwise a failure (see Errors for details)
     */
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);

    /**
     * @notice Sender redeems underlying assets on behalf of some other address. This function is only available
     *   for senders, explicitly marked as delegates of the supplier using `riskEngine.updateDelegate`
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param redeemer, on behalf of whom to redeem
     * @param redeemAmount The amount of underlying to receive from redeeming pTokens
     * @return uint 0=success, otherwise a failure (see Errors for details)
     */
    function redeemUnderlyingBehalf(address redeemer, uint256 redeemAmount)
        external
        returns (uint256);

    /**
     * @notice Sender borrows assets from the protocol to their own address
     * @param borrowAmount The amount of the underlying asset to borrow
     * @return uint 0=success, otherwise a failure (see Errors for details)
     */
    function borrow(uint256 borrowAmount) external returns (uint256);

    /**
     * @notice Sender borrows assets on behalf of some other address. This function is only available
     *   for senders, explicitly marked as delegates of the borrower using `riskEngine.updateDelegate`
     * @param borrower The borrower, on behalf of whom to borrow
     * @param borrowAmount The amount of the underlying asset to borrow
     * @return uint 0=success, otherwise a failure (see Errors for details)
     */
    function borrowBehalf(address borrower, uint256 borrowAmount)
        external
        returns (uint256);

    /**
     * @notice Sender repays their own borrow
     * @param repayAmount The amount to repay, or type(uint256).max for the full outstanding amount
     * @return uint 0=success, otherwise a failure (see Errors for details)
     */
    function repayBorrow(uint256 repayAmount) external returns (uint256);

    /**
     * @notice Sender repays a borrow belonging to borrower
     * @param borrower the account with the debt being payed off
     * @param repayAmount The amount to repay, or type(uint256).max for the full outstanding amount
     * @return uint 0=success, otherwise a failure (see Errors for details)
     */
    function repayBorrowBehalf(address borrower, uint256 repayAmount)
        external
        returns (uint256);

    /**
     * @notice The sender liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @param borrower The borrower of this pToken to be liquidated
     * @param repayAmount The amount of the underlying borrowed asset to repay
     * @param pTokenCollateral The market in which to seize collateral from the borrower
     * @return uint 0=success, otherwise a failure (see Errors for details)
     */
    function liquidateBorrow(
        address borrower,
        uint256 repayAmount,
        IPToken pTokenCollateral
    ) external returns (uint256);

    /**
     * @notice Applies accrued interest to total borrows and reserves
     * @dev This calculates interest accrued from the last checkpointed timestamp
     *   up to the current timestamp and writes new checkpoint to storage.
     */
    function accrueInterest() external returns (uint256);

    /**
     * @notice Transfers collateral tokens (this market) to the liquidator.
     * @dev Will fail unless called by another pToken during the process of liquidation.
     *  Its absolutely critical to use msg.sender as the borrowed pToken and not a parameter.
     * @param liquidator The account receiving seized collateral
     * @param borrower The account having collateral seized
     * @param seizeTokens The number of pTokens to seize
     * @return uint 0=success, otherwise a failure (see Errors for details)
     */
    function seize(address liquidator, address borrower, uint256 seizeTokens)
        external
        returns (uint256);

    /**
     * @notice The sender adds to reserves.
     * @param addAmount The amount fo underlying token to add as reserves
     * @return uint 0=success, otherwise a failure (see Errors for details)
     */
    function addReserves(uint256 addAmount) external returns (uint256);

    /// ***Admin Functions***

    /**
     * @notice Sets a new risk engine for the market
     * @dev Admin function to set a new risk engine
     * @return uint 0=success, otherwise a failure (see Errors for details)
     */
    function setRiskEngine(IRiskEngine newRiskEngine) external returns (uint256);

    /**
     * @notice accrues interest and sets a new reserve factor for the protocol
     * @dev Admin function to accrue interest and set a new reserve factor
     * @return uint 0=success, otherwise a failure (see Errors for details)
     */
    function setReserveFactor(uint256 newReserveFactorMantissa)
        external
        returns (uint256);

    /**
     * @notice Accrues interest and reduces reserves by transferring to reserve protocol contract
     * @param reduceAmount Amount of reduction to reserves
     * @return uint 0=success, otherwise a failure (see Errors for details)
     */
    function reduceReserves(uint256 reduceAmount) external returns (uint256);

    /**
     * @notice A public function to sweep accidental ERC-20 transfers to this contract.
     * Tokens are sent to admin (timelock)
     * @param token The address of the ERC-20 token to sweep
     */
    function sweepToken(IERC20 token) external;

    /// ***Getter Functions***

    /**
     * @notice Return the up-to-date exchange rate with pending accrued interest
     * @return Calculated exchange rate scaled by 1e18
     */
    function exchangeRateCurrent() external view returns (uint256);

    /**
     * @notice Get the underlying balance of the `owner`
     * @dev This does not accrues interest and use pending accrued interest for calculation
     * @param owner The address of the account to query
     * @return The amount of underlying owned by `owner`
     */
    function balanceOfUnderlying(address owner) external view returns (uint256);

    /**
     * @notice Get a snapshot of the account's balances, and the cached exchange rate
     * @dev This is used by risk engine to more efficiently perform liquidity checks.
     * @param account Address of the account to snapshot
     * @return (possible error, token balance, borrow balance, exchange rate mantissa)
     */
    function getAccountSnapshot(address account)
        external
        view
        returns (uint256, uint256, uint256, uint256);

    /**
     * @notice Returns the current total borrows plus pending accrued interest
     * @return The total borrows with interest
     */
    function totalBorrowsCurrent() external view returns (uint256);

    /**
     * @notice Calculate account's borrow balance using the pending updated borrowIndex
     * @param account The address whose balance should be calculated
     * @return The calculated balance
     */
    function borrowBalanceCurrent(address account) external view returns (uint256);

    /**
     * @notice Return the borrow balance of account based on stored data
     * @param account The address whose balance should be calculated
     * @return The calculated balance
     */
    function borrowBalanceStored(address account) external view returns (uint256);

    /**
     * @notice Calculates the exchange rate from the underlying to the pToken
     * @dev This function does not accrue interest before calculating the exchange rate
     * @return Calculated exchange rate scaled by 1e18
     */
    function exchangeRateStored() external view returns (uint256);

    /**
     * @notice Get cash balance of this pToken in the underlying asset
     * @return The quantity of underlying asset owned by this contract
     */
    function getCash() external view returns (uint256);

    /**
     * @notice Returns the last updated timestamp
     */
    function accrualTimestamp() external view returns (uint256);

    /**
     * @notice Returns the last updated total borrow without pending interest
     */
    function totalBorrows() external view returns (uint256);

    /**
     * @notice Returns the last stored borrow index
     */
    function borrowIndex() external view returns (uint256);

    /**
     * @notice Returns reserve factor mantissa
     */
    function reserveFactorMantissa() external view returns (uint256);

    /**
     * @notice Returns the risk engine contract
     */
    function riskEngine() external view returns (IRiskEngine);
}
