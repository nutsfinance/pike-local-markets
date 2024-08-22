//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {ExponentialNoError} from "@utils/ExponentialNoError.sol";
import {PTokenStorage} from "@storage/PTokenStorage.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {AddressError} from "@errors/AddressError.sol";
import {OwnableMixin} from "@utils/OwnableMixin.sol";
import {CommonError} from "@errors/CommonError.sol";
import {PTokenError} from "@errors/PTokenError.sol";
import {IPToken} from "@interfaces/IPToken.sol";

contract PToken is IPToken, PTokenStorage, OwnableMixin {
    using ExponentialNoError for ExponentialNoError.Exp;

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     */
    modifier nonReentrant() {
        if (!_getPTokenStorage()._notEntered) {
            revert CommonError.ReentrancyGuardReentrantCall();
        }
        _getPTokenStorage()._notEntered = false;
        _;
        _getPTokenStorage()._notEntered = true;
    }

    /**
     * @notice Initialize the local market
     * @param underlying_ The address of the underlying token
     * @param riskEngine_ The address of the RiskEngine
     * @param initialExchangeRateMantissa_ The initial exchange rate, scaled by 1e18
     * @param reserveFactorMantissa_ percentage of borrow interests that goes to protocol, scaled by 1e18
     * @param name_ ERC20 name of this token
     * @param symbol_ ERC20 symbol of this token
     * @param decimals_ ERC20 decimal precision of this token
     */
    function initialize(
        address underlying_,
        IRiskEngine riskEngine_,
        uint256 initialExchangeRateMantissa_,
        uint256 reserveFactorMantissa_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) external onlyOwner {
        if (
            _getPTokenStorage().accrualBlockTimestamp != 0
                || _getPTokenStorage().borrowIndex != 0
        ) {
            revert CommonError.AlreadyInitialized();
        }
        if (initialExchangeRateMantissa_ == 0) {
            revert CommonError.ZeroValue();
        }
        // Set initial exchange rate
        _getPTokenStorage().initialExchangeRateMantissa = initialExchangeRateMantissa_;

        // set risk engine
        _setRiskEngine(riskEngine_);

        _setReserveFactorFresh(reserveFactorMantissa_);

        // Initialize block timestamp and borrow index (block timestamp is set to current block timestamp)
        _getPTokenStorage().accrualBlockTimestamp = _getBlockTimestamp();
        _getPTokenStorage().borrowIndex = _MANTISSA_ONE;

        _getPTokenStorage().name = name_;
        _getPTokenStorage().symbol = symbol_;
        _getPTokenStorage().decimals = decimals_;

        // The counter starts true to prevent changing it from zero to non-zero (i.e. smaller cost/refund)
        _getPTokenStorage()._notEntered = true;

        // Set underlying and sanity check it
        _getPTokenStorage().underlying = underlying_;
        IPToken(underlying_).totalSupply();
    }

    /**
     * @notice Sets a new risk engine for the market
     * @dev Admin function to set a new risk engine
     */
    function setRiskEngine(IRiskEngine newRiskEngine) external onlyOwner {
        _setRiskEngine(newRiskEngine);
    }

    /**
     * @notice Transfer `amount` tokens from `msg.sender` to `dst`
     * @param dst The address of the destination account
     * @param amount The number of tokens to transfer
     * @return success True if the transfer succeeded, reverts otherwise
     */
    function transfer(address dst, uint256 amount)
        external
        override
        nonReentrant
        returns (bool)
    {
        _transferTokens(msg.sender, msg.sender, dst, amount);
        return true;
    }

    /**
     * @notice Transfer `amount` tokens from `src` to `dst`
     * @param src The address of the source account
     * @param dst The address of the destination account
     * @param amount The number of tokens to transfer
     * @return success True if the transfer succeeded, reverts otherwise
     */
    function transferFrom(address src, address dst, uint256 amount)
        external
        override
        nonReentrant
        returns (bool)
    {
        _transferTokens(msg.sender, src, dst, amount);
        return true;
    }

    /**
     * @notice Approve `spender` to transfer up to `amount` from `src`
     * @dev This will overwrite the approval amount for `spender`
     *  and is subject to issues noted [here](https://eips.ethereum.org/EIPS/eip-20#approve)
     * @param spender The address of the account which may transfer tokens
     * @param amount The number of tokens that are approved (type(uint256).max for infinite)
     * @return success Whether or not the approval succeeded
     */
    function approve(address spender, uint256 amount) external override returns (bool) {
        if (spender == address(0)) {
            revert AddressError.ZeroAddress();
        }
        address src = msg.sender;
        _getPTokenStorage().transferAllowances[src][spender] = amount;
        emit Approval(src, spender, amount);
        return true;
    }

    /**
     * @notice Get the current allowance from `owner` for `spender`
     * @param owner The address of the account which owns the tokens to be spent
     * @param spender The address of the account which may transfer tokens
     * @return The number of tokens allowed to be spent (type(uint256).max for infinite)
     */
    function allowance(address owner, address spender)
        external
        view
        override
        returns (uint256)
    {
        return _getPTokenStorage().transferAllowances[owner][spender];
    }

    /**
     * @notice Get the token balance of the `owner`
     * @param owner The address of the account to query
     * @return The number of tokens owned by `owner`
     */
    function balanceOf(address owner) external view override returns (uint256) {
        return _getPTokenStorage().accountTokens[owner];
    }

    /**
     * @notice Transfer `tokens` tokens from `src` to `dst` by `spender`
     * @dev Called by both `transfer` and `transferFrom` internally
     * @param spender The address of the account performing the transfer
     * @param src The address of the source account
     * @param dst The address of the destination account
     * @param tokens The number of tokens to transfer
     */
    function _transferTokens(address spender, address src, address dst, uint256 tokens)
        internal
    {
        /* Fail if transfer not allowed */
        _getPTokenStorage().riskEngine.transferAllowed(address(this), src, dst, tokens);

        /* Do not allow self-transfers */
        if (src == dst) {
            revert PTokenError.TransferNotAllowed();
        }

        /* Get the allowance, infinite for the account owner */
        uint256 startingAllowance = 0;
        if (spender == src) {
            startingAllowance = type(uint256).max;
        } else {
            startingAllowance = _getPTokenStorage().transferAllowances[src][spender];
        }

        /* Do the calculations, checking for {under,over}flow */
        uint256 allowanceNew = startingAllowance - tokens;
        uint256 srcTokensNew = _getPTokenStorage().accountTokens[src] - tokens;
        uint256 dstTokensNew = _getPTokenStorage().accountTokens[dst] + tokens;

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        _getPTokenStorage().accountTokens[src] = srcTokensNew;
        _getPTokenStorage().accountTokens[dst] = dstTokensNew;

        /* Eat some of the allowance (if necessary) */
        if (startingAllowance != type(uint256).max) {
            _getPTokenStorage().transferAllowances[src][spender] = allowanceNew;
        }

        /* We emit a Transfer event */
        emit Transfer(src, dst, tokens);
    }

    /**
     * @notice Sets a new reserve factor for the protocol (*requires fresh interest accrual)
     * @dev Admin function to set a new reserve factor
     */
    function _setReserveFactorFresh(uint256 newReserveFactorMantissa) internal {
        // Verify market's block timestamp equals current block timestamp
        if (_getPTokenStorage().accrualBlockTimestamp != _getBlockTimestamp()) {
            revert PTokenError.SetReserveFactorFreshCheck();
        }

        // Check newReserveFactor ≤ maxReserveFactor
        if (newReserveFactorMantissa > _RESERVE_FACTOR_MAX_MANTISSA) {
            revert PTokenError.SetReserveFactorBoundsCheck();
        }

        uint256 oldReserveFactorMantissa = _getPTokenStorage().reserveFactorMantissa;
        _getPTokenStorage().reserveFactorMantissa = newReserveFactorMantissa;

        emit NewReserveFactor(oldReserveFactorMantissa, newReserveFactorMantissa);
    }

    function _setRiskEngine(IRiskEngine newRiskEngine) internal {
        IRiskEngine oldRiskEngine = _getPTokenStorage().riskEngine;

        /// TODO: add erc165 checker

        // Set market's riskEngine to newRiskEngine
        _getPTokenStorage().riskEngine = newRiskEngine;

        // Emit NewRiskEngine(oldRiskEngine, newRiskEngine)
        emit NewRiskEngine(oldRiskEngine, newRiskEngine);
    }

    function _pendingAccruedSnapshot()
        internal
        view
        returns (PendingSnapshot memory snapshot)
    {
        PendingSnapshot memory snapshot;
        snapshot.totalBorrow = _getPTokenStorage().totalBorrows;
        snapshot.totalReserve = _getPTokenStorage().totalReserves;
        snapshot.accBorrowIndex = _getPTokenStorage().borrowIndex;

        uint256 accrualBlockTimestamp = _getPTokenStorage().accrualBlockTimestamp;

        if (_getBlockTimestamp() > accrualBlockTimestamp && snapshot.totalBorrow > 0) {
            uint256 borrowRate = IInterestRateModel(address(this)).getBorrowRate(
                getCash(), snapshot.totalBorrow, snapshot.totalReserve
            );
            ExponentialNoError.Exp memory interestFactor = ExponentialNoError.Exp({
                mantissa: borrowRate
            }).mul_(_getBlockTimestamp() - accrualBlockTimestamp);
            uint256 pendingInterest =
                interestFactor.mul_ScalarTruncate(snapshot.totalBorrow);

            snapshot.totalBorrow = snapshot.totalBorrow + pendingInterest;
            snapshot.totalReserve = ExponentialNoError.Exp({
                mantissa: _getPTokenStorage().reserveFactorMantissa
            }).mul_ScalarTruncateAddUInt(pendingInterest, snapshot.totalReserve);
            snapshot.accBorrowIndex = interestFactor.mul_ScalarTruncateAddUInt(
                snapshot.accBorrowIndex, snapshot.accBorrowIndex
            );
        }
    }

    /**
     * @dev Function to simply retrieve block number
     *  This exists mainly for inheriting test contracts to stub this result.
     */
    function _getBlockTimestamp() internal view returns (uint256) {
        return block.timestamp;
    }
}
