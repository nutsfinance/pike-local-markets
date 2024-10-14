// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IPToken} from "@interfaces/IPToken.sol";

interface IRiskEngine {
    /// @notice Emitted when a new oracle engine is set
    event NewOracleEngine(address oldOracleEngine, address newOracleEngine);

    /// @notice Emitted when an admin supports a market
    event MarketListed(IPToken pToken);

    /// @notice Emitted when an account enters a market
    event MarketEntered(IPToken pToken, address account);

    /// @notice Emitted when an account exits a market
    event MarketExited(IPToken pToken, address account);

    /// @notice Emitted when close factor is changed by admin
    event NewCloseFactor(uint256 oldCloseFactorMantissa, uint256 newCloseFactorMantissa);

    /// @notice Emitted when a collateral factor is changed by admin
    event NewCollateralFactor(
        IPToken pToken,
        uint256 oldCollateralFactorMantissa,
        uint256 newCollateralFactorMantissa
    );

    /// @notice Emitted when a liquidation threshold is changed by admin
    event NewLiquidationThreshold(
        IPToken pToken,
        uint256 oldLiquidationThresholdMantissa,
        uint256 newLiquidationThresholdMantissa
    );

    /// @notice Emitted when liquidation incentive is changed by admin
    event NewLiquidationIncentive(
        uint256 oldLiquidationIncentiveMantissa, uint256 newLiquidationIncentiveMantissa
    );

    /// @notice Emitted when an action is paused globally
    event ActionPaused(string action, bool pauseState);

    /// @notice Emitted when an action is paused on a market
    event ActionPaused(IPToken pToken, string action, bool pauseState);

    /// @notice Emitted when borrow cap for a pToken is changed
    event NewBorrowCap(IPToken indexed pToken, uint256 newBorrowCap);

    /// @notice Emitted when supply cap for a pToken is changed
    event NewSupplyCap(IPToken indexed pToken, uint256 newSupplyCap);

    /// @notice Emitted when the borrowing or redeeming delegate rights are updated for an account
    event DelegateUpdated(
        address indexed approver, address indexed delegate, bool approved
    );

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
     */
    function exitMarket(address pTokenAddress) external;

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
     * @notice Checks if the account should be allowed to borrow the underlying asset of the given market
     * @param pToken The market to verify the borrow against
     * @param borrower The account which would borrow the asset
     * @param borrowAmount The amount of underlying the account would borrow
     * @return 0 if the borrow is allowed, otherwise an error code (See Errors)
     */
    function borrowAllowed(address pToken, address borrower, uint256 borrowAmount)
        external
        returns (uint256);

    /// *** Admin Functions ***

    /**
     * @notice Sets the oracle engine for a the risk engine
     * @dev Admin function to set oracle
     * @param newOracle The address of the new oracle
     */
    function setOracle(address newOracle) external;

    /**
     * @notice Sets the closeFactor for a market used when liquidating borrows
     * @dev Admin function to set closeFactor
     * @param newCloseFactorMantissa New close factor, scaled by 1e18
     */
    function setCloseFactor(uint256 newCloseFactorMantissa) external;

    /**
     * @notice Sets the collateralFactor and liquidation threshold for a market
     * @dev Admin function to set per-market collateralFactor
     * @param pToken The market to set the factor on
     * @param newCollateralFactorMantissa The new collateral factor, scaled by 1e18
     */
    function setCollateralFactor(
        IPToken pToken,
        uint256 newCollateralFactorMantissa,
        uint256 newLiquidationThresholdMantissa
    ) external;

    /**
     * @notice Sets liquidationIncentive for a market
     * @dev Admin function to set liquidationIncentive
     * @param newLiquidationIncentiveMantissa New liquidationIncentive scaled by 1e18
     */
    function setLiquidationIncentive(uint256 newLiquidationIncentiveMantissa) external;

    /**
     * @notice Add the market to the markets mapping and set it as listed
     * @dev Admin function to set isListed and add support for the market
     * @param pToken The address of the market (token) to list
     */
    function supportMarket(IPToken pToken) external;

    /**
     * @notice Set the given borrow caps for the given pToken markets.
     * Borrowing that brings total borrows to or above borrow cap will revert.
     * @dev borrowCapGuardian function to set the borrow caps.
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
     * @dev supplyCapGuardian function to set the supply caps.
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
     * @notice Determine the current account liquidity with respect to liquidation threshold
     * @return (possible error code,
     *             account liquidity in excess of collateral requirements,
     *          account shortfall below collateral requirements)
     */
    function getAccountLiquidity(address account)
        external
        view
        returns (uint256, uint256, uint256);

    /**
     * @notice Determine the current account liquidity with respect to collateral factor
     * @return (possible error code,
     *             account liquidity in excess of borrow collateral requirements,
     *          account shortfall below borrow collateral requirements)
     */
    function getAccountBorrowLiquidity(address account)
        external
        view
        returns (uint256, uint256, uint256);

    /**
     * @notice Determine what the account liquidity would be if the given amounts were redeemed/borrowed
     *  with respect to collateral factor
     * @param pTokenModify The market to hypothetically redeem/borrow in
     * @param account The account to determine liquidity for
     * @param redeemTokens The number of tokens to hypothetically redeem
     * @param borrowAmount The amount of underlying to hypothetically borrow
     * @return (possible error code,
     *             hypothetical account liquidity in excess of borrow collateral requirements,
     *          hypothetical account shortfall below borrow collateral requirements)
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

    /**
     * @notice Checks if the account should be allowed to mint tokens in the given market
     * @param pToken The market to verify the mint against
     * @param mintAmount The amount of underlying being supplied to the market in exchange for tokens
     * @return 0 if the mint is allowed, otherwise an error code (See Errors)
     */
    function mintAllowed(address pToken, uint256 mintAmount)
        external
        view
        returns (uint256);

    /**
     * @notice Checks if the account should be allowed to redeem tokens in the given market
     * @param pToken The market to verify the redeem against
     * @param redeemer The account which would redeem the tokens
     * @param redeemTokens The number of pTokens to exchange for the underlying asset in the market
     * @return 0 if the redeem is allowed, otherwise an error code (See Errors)
     */
    function redeemAllowed(address pToken, address redeemer, uint256 redeemTokens)
        external
        view
        returns (uint256);

    /**
     * @notice Checks if the account should be allowed to repay a borrow in the given market
     * @param pToken The market to verify the repay against
     * @return 0 if the repay is allowed, otherwise an error code (See Errors)
     */
    function repayBorrowAllowed(address pToken) external view returns (uint256);

    /**
     * @notice Checks if the liquidation should be allowed to occur
     * @param pTokenBorrowed Asset which was borrowed by the borrower
     * @param pTokenCollateral Asset which was used as collateral and will be seized
     * @param borrower The address of the borrower
     * @param repayAmount The amount of underlying being repaid
     */
    function liquidateBorrowAllowed(
        address pTokenBorrowed,
        address pTokenCollateral,
        address borrower,
        uint256 repayAmount
    ) external view returns (uint256);

    /**
     * @notice Checks if the seizing of assets should be allowed to occur
     * @param pTokenCollateral Asset which was used as collateral and will be seized
     * @param pTokenBorrowed Asset which was borrowed by the borrower
     * @return 0 if the borrow is allowed, otherwise an error code (See Errors)
     */
    function seizeAllowed(address pTokenCollateral, address pTokenBorrowed)
        external
        view
        returns (uint256);

    /**
     * @notice Checks if the account should be allowed to transfer tokens in the given market
     * @param pToken The market to verify the transfer against
     * @param src The account which sources the tokens
     * @param transferTokens The number of pTokens to transfer
     * @return 0 if the transfer is allowed, otherwise an error code (See Errors)
     */
    function transferAllowed(address pToken, address src, uint256 transferTokens)
        external
        view
        returns (uint256);

    /**
     * @return the oracle engine address
     */
    function oracle() external view returns (address);
}
