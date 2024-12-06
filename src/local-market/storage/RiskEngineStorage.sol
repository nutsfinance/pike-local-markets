//SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IPToken} from "@interfaces/IPToken.sol";
import {ExponentialNoError} from "@utils/ExponentialNoError.sol";

contract RiskEngineStorage {
    struct RiskEngineData {
        /**
         * @notice Multiplier used to calculate the maximum repayAmount when liquidating a borrow
         * @dev mapping pToken -> closeFactor
         */
        mapping(address => uint256) closeFactorMantissa;
        /**
         * @notice Max number of assets a single account can participate in (borrow or use as collateral)
         */
        uint256 maxAssets;
        /**
         * @notice Number of categories
         */
        uint8 totalCategories;
        /**
         * @notice Per-account mapping of "activated category"
         */
        mapping(address => uint8) accountCategory;
        /**
         * @notice Per-account mapping of "assets you are in collateral", capped by maxAssets
         */
        mapping(address => IPToken[]) accountCollateralAssets;
        /**
         * @notice Per-account mapping of "assets you are in borrow", capped by maxAssets
         */
        mapping(address => IPToken[]) accountBorrowAssets;
        /**
         * @notice Per-category mapping of "markets for collateral"
         */
        mapping(uint8 => mapping(IPToken => bool)) categoryCollateral;
        /**
         * @notice Per-category mapping of "markets for borrow"
         */
        mapping(uint8 => mapping(IPToken => bool)) categoryBorrow;
        /**
         * @notice Official mapping of pTokens -> Market metadata
         * @dev Used e.g. to determine if a market is supported
         */
        mapping(address => Market) markets;
        /// @notice oracle engine address
        address oracle;
        /// @notice A flag indicating whether transfers are paused by guardian.
        bool transferGuardianPaused;
        /// @notice A flag indicating whether the seize function is paused by guardian.
        bool seizeGuardianPaused;
        /// @notice A flag indicating whether the mint is paused for specific ptoken by guardian.
        mapping(address => bool) mintGuardianPaused;
        /// @notice A flag indicating whether the borrow is paused for specific ptoken by guardian.
        mapping(address => bool) borrowGuardianPaused;
        /// @notice Borrow caps enforced by borrowAllowed for each pToken address.
        ///  Defaults to zero which corresponds to unlimited borrowing.
        mapping(address => uint256) borrowCaps;
        /// @notice Supply caps enforced by mintAllowed for each pToken address.
        ///  Defaults to zero which corresponds to minting not allowed
        mapping(address => uint256) supplyCaps;
        /// @notice Whether the delegate is allowed to borrow or redeem on behalf of the user
        //mapping(address user => mapping (address delegate => bool approved)) public approvedDelegates;
        mapping(address => mapping(address => bool)) approvedDelegates;
        /// @notice A list of all markets in categories (0 is default category includes all markets)
        mapping(uint8 => IPToken[]) allMarkets;
    }

    /**
     * @dev Local vars for avoiding stack-depth limits in calculating account liquidity.
     *  Note that `pTokenBalance` is the number of pTokens the account owns in the market,
     *  whereas `borrowBalance` is the amount of underlying that the account has borrowed.
     */
    struct AccountLiquidityLocalVars {
        uint256 sumLiquidity;
        uint256 sumCollateral;
        uint256 sumBorrowPlusEffects;
        uint256 pTokenBalance;
        uint256 borrowBalance;
        uint256 exchangeRateMantissa;
        uint256 oraclePriceMantissa;
        ExponentialNoError.Exp threshold;
        ExponentialNoError.Exp exchangeRate;
        ExponentialNoError.Exp oraclePrice;
        ExponentialNoError.Exp tokensToDenom;
    }

    struct Market {
        // Whether or not this market is listed
        bool isListed;
        //  Multiplier representing the most one can borrow against their collateral in this market.
        //  For instance, 0.9 to allow borrowing 90% of collateral value.
        //  Must be between 0 and 1, and stored as a mantissa.
        uint256 collateralFactorMantissa;
        //  Multiplier representing the collateralization after which the borrow is eligible
        //  for liquidation. For instance, 0.8 liquidate when the borrow is 80% of collateral
        //  value. Must be between 0 and collateral factor, stored as a mantissa.
        uint256 liquidationThresholdMantissa;
        // Multiplier representing the discount on collateral that a liquidator receives
        uint256 liquidationIncentiveMantissa;
        // Per-market mapping of "accounts in this asset"
        mapping(address => bool) accountMembership;
    }

    struct EModeConfiguration {
        // Whether or not this emode is allowed
        bool allowed;
        //  Multiplier representing the most one can borrow against their collateral in this e-mode.
        uint256 collateralFactorMantissa;
        //  Multiplier representing the collateralization after which the borrow is eligible
        //  for liquidation in this e-mode.
        uint256 liquidationThresholdMantissa;
        // Multiplier representing the discount on collateral that a liquidator receives in this e-mode.
        uint256 liquidationIncentiveMantissa;
        // Per-emode mapping of "accounts in this asset"
        mapping(address => bool) accountMembership;
        IPToken[] collateralAssets;
        IPToken[] borrowAssets;
    }

    /// keccak256(abi.encode(uint256(keccak256("pike.LM.RiskEngine")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _SLOT_RISK_ENGINE_STORAGE =
        0x045c767dd6aa575c77a2f8d1bda11e214b14b47092bcc4f410a939f824586800;

    // closeFactorMantissa must be strictly greater than this value
    uint256 internal constant _CLOSE_FACTOR_MIN_MANTISSA = 0.05e18; // 0.05

    // closeFactorMantissa must not exceed this value
    uint256 internal constant _CLOSE_FACTOR_MAX_MANTISSA = 0.9e18; // 0.9

    // No collateralFactorMantissa may exceed this value
    uint256 internal constant _COLLATERAL_FACTOR_MAX_MANTISSA = 0.9e18; // 0.9

    uint256 internal constant _MANTISSA_ONE = 1e18;

    function _getRiskEngineStorage()
        internal
        pure
        returns (RiskEngineData storage data)
    {
        bytes32 s = _SLOT_RISK_ENGINE_STORAGE;
        assembly {
            data.slot := s
        }
    }
}
