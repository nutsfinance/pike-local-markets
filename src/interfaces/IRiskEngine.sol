// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IPToken} from "@interfaces/IPToken.sol";

interface IRiskEngine {
    /**
     * @notice Add assets to be included in account liquidity calculation
     * @param pTokens The list of addresses of the pToken markets to be enabled
     * @return Success indicator for whether each corresponding market was entered
     */
    function enterMarkets(address[] memory pTokens) external returns (uint256[] memory);

    /**
     * @notice Removes asset from sender's account liquidity calculation
     * @dev Sender must not have an outstanding borrow balance in the asset,
     *  or be providing necessary collateral for an outstanding borrow.
     * @param pTokenAddress The address of the asset to be removed
     * @return Whether or not the account successfully exited the market
     */
    function exitMarket(address pTokenAddress) external returns (uint256);

    /**
     * @notice Grants or revokes the borrowing or redeeming delegate rights to / from an account
     *  If allowed, the delegate will be able to borrow funds on behalf of the sender
     *  Upon a delegated borrow, the delegate will receive the funds, and the borrower
     *  will see the debt on their account
     *  Upon a delegated redeem, the delegate will receive the redeemed amount and the approver
     *  will see a deduction in his pToken balance
     * @param delegate The address to update the rights for
     * @param approved Whether to grant (true) or revoke (false) the borrowing or redeeming rights
     */
    function updateDelegate(address delegate, bool approved) external;

    /// *** Hooks ***

    /**
     * @notice Checks if the account should be allowed to mint tokens in the given market
     * @param pToken The market to verify the mint against
     * @param minter The account which would get the minted tokens
     * @param mintAmount The amount of underlying being supplied to the market in exchange for tokens
     * @return 0 if the mint is allowed, otherwise an error code (See Errors)
     */
    function mintAllowed(address pToken, address minter, uint256 mintAmount)
        external
        returns (uint256);

    /**
     * @notice Validates mint and reverts on rejection. May emit logs.
     * @param pToken Asset being minted
     * @param minter The address minting the tokens
     * @param actualMintAmount The amount of the underlying asset being minted
     * @param mintTokens The number of tokens being minted
     */
    function mintVerify(
        address pToken,
        address minter,
        uint256 actualMintAmount,
        uint256 mintTokens
    ) external;

    /**
     * @notice Checks if the account should be allowed to redeem tokens in the given market
     * @param pToken The market to verify the redeem against
     * @param redeemer The account which would redeem the tokens
     * @param redeemTokens The number of pTokens to exchange for the underlying asset in the market
     * @return 0 if the redeem is allowed, otherwise an error code (See Errors)
     */
    function redeemAllowed(address pToken, address redeemer, uint256 redeemTokens)
        external
        returns (uint256);

    /**
     * @notice Validates redeem and reverts on rejection. May emit logs.
     * @param pToken Asset being redeemed
     * @param redeemer The address redeeming the tokens
     * @param redeemAmount The amount of the underlying asset being redeemed
     * @param redeemTokens The number of tokens being redeemed
     */
    function redeemVerify(
        address pToken,
        address redeemer,
        uint256 redeemAmount,
        uint256 redeemTokens
    ) external;

    /**
     * @notice Checks if the account should be allowed to borrow the underlying asset of the given market
     * @param pToken The market to verify the borrow against
     * @param borrower The account which would borrow the asset
     * @param borrowAmount The amount of underlying the account would borrow
     * @return 0 if the borrow is allowed, otherwise an error code (See Errors)
     */
    function borrowAllowed(address pToken, address borrower, uint256 borrowAmount)
        external
        returns (uint256);

    /**
     * @notice Validates borrow and reverts on rejection. May emit logs.
     * @param pToken Asset whose underlying is being borrowed
     * @param borrower The address borrowing the underlying
     * @param borrowAmount The amount of the underlying asset requested to borrow
     */
    function borrowVerify(address pToken, address borrower, uint256 borrowAmount)
        external;

    /**
     * @notice Checks if the account should be allowed to repay a borrow in the given market
     * @param pToken The market to verify the repay against
     * @param payer The account which would repay the asset
     * @param borrower The account which would borrowed the asset
     * @param repayAmount The amount of the underlying asset the account would repay
     * @return 0 if the repay is allowed, otherwise an error code (See Errors)
     */
    function repayBorrowAllowed(
        address pToken,
        address payer,
        address borrower,
        uint256 repayAmount
    ) external returns (uint256);

    /**
     * @notice Validates repayBorrow and reverts on rejection. May emit logs.
     * @param pToken Asset being repaid
     * @param payer The address repaying the borrow
     * @param borrower The address of the borrower
     * @param actualRepayAmount The amount of underlying being repaid
     */
    function repayBorrowVerify(
        address pToken,
        address payer,
        address borrower,
        uint256 actualRepayAmount,
        uint256 borrowerIndex
    ) external;

    /**
     * @notice Checks if the liquidation should be allowed to occur
     * @param pTokenBorrowed Asset which was borrowed by the borrower
     * @param pTokenCollateral Asset which was used as collateral and will be seized
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param repayAmount The amount of underlying being repaid
     */
    function liquidateBorrowAllowed(
        address pTokenBorrowed,
        address pTokenCollateral,
        address liquidator,
        address borrower,
        uint256 repayAmount
    ) external returns (uint256);

    /**
     * @notice Validates liquidateBorrow and reverts on rejection. May emit logs.
     * @param pTokenBorrowed Asset which was borrowed by the borrower
     * @param pTokenCollateral Asset which was used as collateral and will be seized
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param actualRepayAmount The amount of underlying being repaid
     */
    function liquidateBorrowVerify(
        address pTokenBorrowed,
        address pTokenCollateral,
        address liquidator,
        address borrower,
        uint256 actualRepayAmount,
        uint256 seizeTokens
    ) external;

    /**
     * @notice Checks if the seizing of assets should be allowed to occur
     * @param pTokenCollateral Asset which was used as collateral and will be seized
     * @param pTokenBorrowed Asset which was borrowed by the borrower
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param seizeTokens The number of collateral tokens to seize
     */
    function seizeAllowed(
        address pTokenCollateral,
        address pTokenBorrowed,
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external returns (uint256);

    /**
     * @notice Validates seize and reverts on rejection. May emit logs.
     * @param pTokenCollateral Asset which was used as collateral and will be seized
     * @param pTokenBorrowed Asset which was borrowed by the borrower
     * @param liquidator The address repaying the borrow and seizing the collateral
     * @param borrower The address of the borrower
     * @param seizeTokens The number of collateral tokens to seize
     */
    function seizeVerify(
        address pTokenCollateral,
        address pTokenBorrowed,
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) external;

    /**
     * @notice Checks if the account should be allowed to transfer tokens in the given market
     * @param pToken The market to verify the transfer against
     * @param src The account which sources the tokens
     * @param dst The account which receives the tokens
     * @param transferTokens The number of pTokens to transfer
     * @return 0 if the transfer is allowed, otherwise an error code (See Errors)
     */
    function transferAllowed(
        address pToken,
        address src,
        address dst,
        uint256 transferTokens
    ) external returns (uint256);

    /**
     * @notice Validates transfer and reverts on rejection. May emit logs.
     * @param pToken Asset being transferred
     * @param src The account which sources the tokens
     * @param dst The account which receives the tokens
     * @param transferTokens The number of pTokens to transfer
     */
    function transferVerify(
        address pToken,
        address src,
        address dst,
        uint256 transferTokens
    ) external;

    /// *** Admin Functions ***

    /**
     * @notice Sets the closeFactor for a market used when liquidating borrows
     * @dev Admin function to set closeFactor
     * @param newCloseFactorMantissa New close factor, scaled by 1e18
     * @return uint 0=success, otherwise a failure
     */
    function setCloseFactor(IPToken pToken, uint256 newCloseFactorMantissa)
        external
        returns (uint256);

    /**
     * @notice Sets the collateralFactor and liquidation threshold for a market
     * @dev Admin function to set per-market collateralFactor
     * @param pToken The market to set the factor on
     * @param newCollateralFactorMantissa The new collateral factor, scaled by 1e18
     * @return uint 0=success, otherwise a failure. (See Errors for details)
     */
    function setCollateralFactor(
        IPToken pToken,
        uint256 newCollateralFactorMantissa,
        uint256 newLiquidationThresholdMantissa
    ) external returns (uint256);

    /**
     * @notice Sets liquidationIncentive for a market
     * @dev Admin function to set liquidationIncentive
     * @param newLiquidationIncentiveMantissa New liquidationIncentive scaled by 1e18
     * @return uint 0=success, otherwise a failure. (See Errors for details)
     */
    function setLiquidationIncentive(uint256 newLiquidationIncentiveMantissa)
        external
        returns (uint256);

    /**
     * @notice Add the market to the markets mapping and set it as listed
     * @dev Admin function to set isListed and add support for the market
     * @param pToken The address of the market (token) to list
     * @return uint 0=success, otherwise a failure. (See enum Error for details)
     */
    function supportMarket(IPToken pToken) external returns (uint256);

    /**
     * @notice Set the given borrow caps for the given pToken markets.
     * Borrowing that brings total borrows to or above borrow cap will revert.
     * @dev Admin or borrowCapGuardian function to set the borrow caps.
     * A borrow cap of type(uint256).max corresponds to unlimited borrowing.
     * @param pTokens The addresses of the markets (tokens) to change the borrow caps for
     * @param newBorrowCaps The new borrow cap values in underlying to be set.
     * A value of type(uint256).max corresponds to unlimited borrowing.
     */
    function setMarketBorrowCaps(
        IPToken[] calldata pTokens,
        uint256[] calldata newBorrowCaps
    ) external;

    /**
     * @notice Set the given supply caps for the given pToken markets.
     * Supplying that brings total supply to or above supply cap will revert.
     * @dev Admin or supplyCapGuardian function to set the supply caps.
     * A supply cap of type(uint256).max corresponds to unlimited supplying.
     * @param pTokens The addresses of the markets (tokens) to change the supply caps for
     * @param newSupplyCaps The new supply cap values in underlying to be set.
     * A value of type(uint256).max corresponds to unlimited supplying.
     */
    function setMarketSupplyCaps(
        IPToken[] calldata pTokens,
        uint256[] calldata newSupplyCaps
    ) external;

    /**
     * @notice Admin function to change the Borrow Cap Guardian
     * @param newBorrowCapGuardian The address of the new Borrow Cap Guardian
     */
    function setBorrowCapGuardian(address newBorrowCapGuardian) external;

    /**
     * @notice Admin function to change the Supply Cap Guardian
     * @param newSupplyCapGuardian The address of the new Supply Cap Guardian
     */
    function setSupplyCapGuardian(address newSupplyCapGuardian) external;

    /**
     * @notice Admin function to change the Pause Guardian
     * @param newPauseGuardian The address of the new Pause Guardian
     * @return uint 0=success, otherwise a failure. (See enum Error for details)
     */
    function setPauseGuardian(address newPauseGuardian) external returns (uint256);

    /**
     * @notice Admin function to pause mint
     */
    function setMintPaused(IPToken pToken, bool state) external returns (bool);

    /**
     * @notice Admin function to pause borrow
     */
    function setBorrowPaused(IPToken pToken, bool state) external returns (bool);

    /**
     * @notice Admin function to pause transfer
     */
    function setTransferPaused(bool state) external returns (bool);

    /**
     * @notice Admin function to pause sieze
     */
    function setSeizePaused(bool state) external returns (bool);

    /// ***Getter Functions***

    /**
     * @notice Returns the assets an account has entered
     * @param account The address of the account to pull assets for
     * @return A dynamic list with the assets the account has entered
     */
    function getAssetsIn(address account) external view returns (IPToken[] memory);

    /**
     * @notice Returns whether the given account is entered in the given asset
     * @param account The address of the account to check
     * @param pToken The pToken to check
     * @return True if the account is in the asset, otherwise false.
     */
    function checkMembership(address account, IPToken pToken)
        external
        view
        returns (bool);

    /**
     * @notice Determine the current account liquidity with respect to collateral requirements
     * @return (possible error code,
     *             account liquidity in excess of collateral requirements,
     *          account shortfall below collateral requirements)
     */
    function getAccountLiquidity(address account)
        external
        view
        returns (uint256, uint256, uint256);

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     * @param pTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @return (possible error code,
     *             hypothetical account liquidity in excess of collateral requirements,
     *          hypothetical account shortfall below collateral requirements)
     */
    function getHypotheticalAccountLiquidity(
        address account,
        address pTokenModify,
        uint256 redeemTokens,
        uint256 borrowAmount
    ) external view returns (uint256, uint256, uint256);

    /**
     * @notice Calculate number of tokens of collateral asset to seize given an underlying amount
     * @dev Used in liquidation (called in pToken.liquidateBorrowFresh)
     * @param pTokenBorrowed The address of the borrowed pToken
     * @param pTokenCollateral The address of the collateral pToken
     * @param actualRepayAmount The amount of pTokenBorrowed underlying to convert into pTokenCollateral tokens
     * @return (errorCode, number of pTokenCollateral tokens to be seized in a liquidation)
     */
    function liquidateCalculateSeizeTokens(
        address pTokenBorrowed,
        address pTokenCollateral,
        uint256 actualRepayAmount
    ) external view returns (uint256, uint256);

    /**
     * @notice Checks if a delegate has been approved by a user for all markets.
     * @param user The address of the user who may have approved a delegatee.
     * @param delegate The address of the delegatee to check for approval.
     * @return True if the delegate is approved by the user, false otherwise.
     */
    function delegateAllowed(address user, address delegate)
        external
        view
        returns (bool);

    /**
     * @notice Return all of the markets
     * @dev The automatic getter may be used to access an individual market.
     * @return The list of market addresses
     */
    function getAllMarkets() external view returns (IPToken[] memory);

    /**
     * @notice Returns true if the given pToken market has been deprecated
     * @dev All borrows in a deprecated pToken market can be immediately liquidated
     * @param pToken The market to check if deprecated
     */
    function isDeprecated(IPToken pToken) external view returns (bool);
}
