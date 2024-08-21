//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IRiskEngine} from "@interfaces/IRiskEngine.sol";

contract PTokenStorage {
    struct PTokenData {
        /**
         * @notice Underlying asset for this PToken
         */
        address underlying;
        /**
         * @dev Guard variable for re-entrancy checks
         */
        bool _notEntered;
        /**
         * @notice ERC20 token name for this token
         */
        string name;
        /**
         * @notice ERC20 token symbol for this token
         */
        string symbol;
        /**
         * @notice ERC20 token decimals for this token
         */
        uint8 decimals;
        /**
         * @notice Contract which oversees pToken operations
         */
        IRiskEngine riskEngine;
        /**
         *  @notice Initial exchange rate used when minting the first PTokens (used when totalSupply = 0)
         */
        uint256 initialExchangeRateMantissa;
        /**
         * @notice Fraction of interest currently set aside for reserves
         */
        uint256 reserveFactorMantissa;
        /**
         * @notice Block timestamp that interest was last accrued at
         */
        uint256 accrualBlockTimestamp;
        /**
         * @notice Accumulator of the total earned interest rate since the opening of the market
         */
        uint256 borrowIndex;
        /**
         * @notice Total amount of outstanding borrows of the underlying in this market
         */
        uint256 totalBorrows;
        /**
         * @notice Total amount of reserves of the underlying held in this market
         */
        uint256 totalReserves;
        /**
         * @notice Total number of tokens in circulation
         */
        uint256 totalSupply;
        /**
         * @notice Official record of token balances for each account
         */
        mapping(address => uint256) accountTokens;
        /**
         * @notice Approved token transfer amounts on behalf of others
         */
        mapping(address => mapping(address => uint256)) transferAllowances;
        /**
         * @notice Mapping of account addresses to outstanding borrow balances
         */
        mapping(address => BorrowSnapshot) accountBorrows;
    }

    /**
     * @notice Container for borrow balance information
     * @member principal Total balance (with accrued interest), after applying the most recent balance-changing action
     * @member interestIndex Global borrowIndex as of the most recent balance-changing action
     */
    struct BorrowSnapshot {
        uint256 principal;
        uint256 interestIndex;
    }

    /// keccak256(abi.encode(uint256(keccak256("pike.LM.PToken")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _SLOT_PTOKEN_STORAGE =
        0x0be5863c0c782626615eed72fc4c521bcfabebe439cbc2683e49afadb49a0d00;

    uint256 internal constant _MANTISSA_ONE = 1e18;

    // Maximum fraction of interest that can be set aside for reserves
    uint256 internal constant reserveFactorMaxMantissa = 1e18;

    function _getPTokenStorage() internal pure returns (PTokenData storage data) {
        bytes32 s = _SLOT_PTOKEN_STORAGE;
        assembly {
            data.slot := s
        }
    }
}
