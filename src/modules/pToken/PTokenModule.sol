//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {
    SafeERC20, IERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {ExponentialNoError} from "@utils/ExponentialNoError.sol";
import {PTokenStorage} from "@storage/PTokenStorage.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";
import {AddressError} from "@errors/AddressError.sol";
import {OwnableMixin} from "@utils/OwnableMixin.sol";
import {CommonError} from "@errors/CommonError.sol";
import {PTokenError} from "@errors/PTokenError.sol";
import {IPToken} from "@interfaces/IPToken.sol";

abstract contract PToken is IPToken, PTokenStorage, OwnableMixin {
    using ExponentialNoError for ExponentialNoError.Exp;
    using ExponentialNoError for uint256;
    using SafeERC20 for IERC20;

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
        uint256 protocolSeizeShareMantissa_,
        uint256 borrowRateMaxMantissa_,
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
        if (initialExchangeRateMantissa_ == 0 || borrowRateMaxMantissa_ == 0) {
            revert CommonError.ZeroValue();
        }
        // Set initial exchange rate
        _getPTokenStorage().initialExchangeRateMantissa = initialExchangeRateMantissa_;

        _getPTokenStorage().protocolSeizeShareMantissa = protocolSeizeShareMantissa_;

        _getPTokenStorage().borrowRateMaxMantissa = borrowRateMaxMantissa_;

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
        IERC20(underlying_).totalSupply();
    }

    /**
     * @inheritdoc IPToken
     */
    function setRiskEngine(IRiskEngine newRiskEngine) external onlyOwner {
        _setRiskEngine(newRiskEngine);
    }

    /**
     * @inheritdoc IPToken
     */
    function setReserveFactor(uint256 newReserveFactorMantissa) external onlyOwner {
        accrueInterest();
        // _setReserveFactorFresh emits reserve-factor-specific logs on errors, so we don't need to.
        _setReserveFactorFresh(newReserveFactorMantissa);
    }

    /**
     * @inheritdoc IPToken
     */
    function addReserves(uint256 addAmount) external nonReentrant {
        accrueInterest();

        // _addReservesFresh emits reserve-addition-specific logs on errors, so we don't need to.
        _addReservesFresh(addAmount);
    }

    /**
     * @inheritdoc IPToken
     */
    function reduceReserves(uint256 reduceAmount) external onlyOwner nonReentrant {
        accrueInterest();
        // _reduceReservesFresh emits reserve-reduction-specific logs on errors, so we don't need to.
        _reduceReservesFresh(reduceAmount);
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
     * @inheritdoc IPToken
     */
    function mint(uint256 mintAmount) external nonReentrant {
        accrueInterest();
        mintFresh(msg.sender, msg.sender, mintAmount);
    }

    /**
     * @inheritdoc IPToken
     */
    function mintOnBehalfOf(address onBehalfOf, uint256 mintAmount)
        external
        nonReentrant
    {
        if (onBehalfOf == address(0)) {
            revert AddressError.ZeroAddress();
        }

        accrueInterest();
        mintFresh(msg.sender, onBehalfOf, mintAmount);
    }

    /**
     * @inheritdoc IPToken
     */
    function redeem(uint256 redeemTokens) external nonReentrant {
        accrueInterest();

        redeemFresh(msg.sender, msg.sender, redeemTokens, 0);
    }

    /**
     * @inheritdoc IPToken
     */
    function redeemOnBehalfOf(address onBehalfOf, uint256 redeemTokens)
        external
        nonReentrant
    {
        _isDelegateeOf(onBehalfOf);

        accrueInterest();

        redeemFresh(msg.sender, onBehalfOf, redeemTokens, 0);
    }

    /**
     * @inheritdoc IPToken
     */
    function redeemUnderlying(uint256 redeemAmount) external nonReentrant {
        accrueInterest();

        redeemFresh(msg.sender, msg.sender, 0, redeemAmount);
    }

    /**
     * @inheritdoc IPToken
     */
    function redeemUnderlyingOnBehalfOf(address onBehalfOf, uint256 redeemAmount)
        external
        nonReentrant
    {
        _isDelegateeOf(onBehalfOf);

        accrueInterest();

        redeemFresh(msg.sender, onBehalfOf, 0, redeemAmount);
    }

    /**
     * @inheritdoc IPToken
     */
    function borrow(uint256 borrowAmount) external nonReentrant {
        accrueInterest();

        borrowFresh(msg.sender, msg.sender, borrowAmount);
    }

    /**
     * @inheritdoc IPToken
     */
    function borrowOnBehalfOf(address onBehalfOf, uint256 borrowAmount)
        external
        nonReentrant
    {
        _isDelegateeOf(onBehalfOf);
        accrueInterest();

        borrowFresh(msg.sender, onBehalfOf, borrowAmount);
    }

    /**
     * @inheritdoc IPToken
     */
    function repayBorrow(uint256 repayAmount) external nonReentrant {
        accrueInterest();

        repayBorrowFresh(msg.sender, msg.sender, repayAmount);
    }

    /**
     * @inheritdoc IPToken
     */
    function repayBorrowOnBehalfOf(address onBehalfOf, uint256 repayAmount)
        external
        nonReentrant
    {
        accrueInterest();

        repayBorrowFresh(msg.sender, onBehalfOf, repayAmount);
    }

    /**
     * @inheritdoc IPToken
     */
    function liquidateBorrow(
        address borrower,
        uint256 repayAmount,
        IPToken pTokenCollateral
    ) external nonReentrant {
        accrueInterest();

        (bool success,) =
            address(pTokenCollateral).call(abi.encodeWithSignature("accrueInterest()"));
        if (!success) {
            // accrueInterest emits logs on errors, but we want to log the fact that an attempted liquidation failed
            revert PTokenError.LiquidateAccrueCollateralInterestFailed();
        }

        // liquidateBorrowFresh emits borrow-specific logs on errors, so we don't need to
        liquidateBorrowFresh(msg.sender, borrower, repayAmount, pTokenCollateral);
    }

    /**
     * @inheritdoc IPToken
     */
    function seize(address liquidator, address borrower, uint256 seizeTokens)
        external
        nonReentrant
    {
        seizeInternal(msg.sender, liquidator, borrower, seizeTokens);
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
     * @inheritdoc IPToken
     */
    function accrualBlockTimestamp() external view returns (uint256) {
        return _getPTokenStorage().accrualBlockTimestamp;
    }

    /**
     * @inheritdoc IPToken
     */
    function balanceOfUnderlying(address owner) external view returns (uint256) {
        ExponentialNoError.Exp memory exchangeRate =
            ExponentialNoError.Exp({mantissa: exchangeRateCurrent()});
        return exchangeRate.mul_ScalarTruncate(_getPTokenStorage().accountTokens[owner]);
    }

    /**
     * @inheritdoc IPToken
     */
    function getAccountSnapshot(address account)
        external
        view
        returns (uint256, uint256, uint256)
    {
        return (
            _getPTokenStorage().accountTokens[account],
            borrowBalanceStoredInternal(account),
            exchangeRateStoredInternal()
        );
    }

    /**
     * @inheritdoc IPToken
     */
    function exchangeRateStored() external view returns (uint256) {
        return exchangeRateStoredInternal();
    }

    /**
     * @inheritdoc IPToken
     */
    function borrowBalanceStored(address account) external view returns (uint256) {
        return borrowBalanceStoredInternal(account);
    }

    /**
     * @inheritdoc IPToken
     */
    function borrowRatePerSecond() external view returns (uint256) {
        return IInterestRateModel(address(this)).getBorrowRate(
            getCash(), _getPTokenStorage().totalBorrows, _getPTokenStorage().totalReserves
        );
    }

    /**
     * @inheritdoc IPToken
     */
    function supplyRatePerSecond() external view returns (uint256) {
        return IInterestRateModel(address(this)).getSupplyRate(
            getCash(),
            _getPTokenStorage().totalBorrows,
            _getPTokenStorage().totalReserves,
            _getPTokenStorage().reserveFactorMantissa
        );
    }

    /**
     * @inheritdoc IPToken
     */
    function totalBorrowsCurrent() external view returns (uint256) {
        PendingSnapshot memory snapshot = _pendingAccruedSnapshot();
        return snapshot.totalBorrow;
    }

    /**
     * @inheritdoc IPToken
     */
    function borrowBalanceCurrent(address account) external view returns (uint256) {
        PendingSnapshot memory snapshot = _pendingAccruedSnapshot();
        BorrowSnapshot memory borrowSnapshot = _getPTokenStorage().accountBorrows[account];

        if (borrowSnapshot.principal == 0) return 0;

        uint256 principalTimesIndex = borrowSnapshot.principal * snapshot.accBorrowIndex;
        return principalTimesIndex / borrowSnapshot.interestIndex;
    }

    /**
     * @inheritdoc IPToken
     */
    function accrueInterest() public {
        /* Remember the initial block timestamp */
        uint256 currentBlockTimestamp = _getBlockTimestamp();

        /* Short-circuit accumulating 0 interest */
        if (_getPTokenStorage().accrualBlockTimestamp == currentBlockTimestamp) {
            return;
        }

        /// Get accrued snapshot
        PendingSnapshot memory snapshot = _pendingAccruedSnapshot();

        if (snapshot.accBorrowIndex > _getPTokenStorage().borrowRateMaxMantissa) {
            revert PTokenError.BorrowRateBoundsCheck();
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /* We write the previously calculated values into storage */
        _getPTokenStorage().accrualBlockTimestamp = currentBlockTimestamp;
        _getPTokenStorage().borrowIndex = snapshot.accBorrowIndex;
        _getPTokenStorage().totalBorrows = snapshot.totalBorrow;
        _getPTokenStorage().totalReserves = snapshot.totalReserve;

        /* We emit an AccrueInterest event */
        emit AccrueInterest(
            getCash(),
            snapshot.totalReserve,
            snapshot.accBorrowIndex,
            snapshot.totalBorrow
        );
    }

    /**
     * @inheritdoc IPToken
     */
    function exchangeRateCurrent() public view returns (uint256) {
        uint256 _totalSupply = _getPTokenStorage().totalSupply;

        if (_totalSupply == 0) {
            return _getPTokenStorage().initialExchangeRateMantissa;
        }
        PendingSnapshot memory snapshot = _pendingAccruedSnapshot();
        uint256 totalCash = getCash();
        uint256 cashPlusBorrowsMinusReserves =
            totalCash + snapshot.totalBorrow - snapshot.totalReserve;
        return cashPlusBorrowsMinusReserves * ExponentialNoError.expScale / _totalSupply;
    }

    /**
     * @inheritdoc IPToken
     */
    function getCash() public view returns (uint256) {
        return IERC20(_getPTokenStorage().underlying).balanceOf(address(this));
    }

    /**
     * @notice User supplies assets into the market and receives pTokens in exchange
     * @dev Assumes interest has already been accrued up to the current timestamp
     * @param minter The address of the account which is supplying the assets
     * @param onBehalfOf The address whom the supply will be attributed to
     * @param mintAmount The amount of the underlying asset to supply
     */
    function mintFresh(address minter, address onBehalfOf, uint256 mintAmount) internal {
        /* Fail if mint not allowed */
        uint256 allowed = _getPTokenStorage().riskEngine.mintAllowed(
            address(this), onBehalfOf, mintAmount
        );
        if (allowed != 0) {
            revert PTokenError.MintRiskEngineRejection(allowed);
        }

        /* Verify market's block timestamp equals current block timestamp */
        if (_getPTokenStorage().accrualBlockTimestamp != _getBlockTimestamp()) {
            revert PTokenError.MintFreshnessCheck();
        }

        ExponentialNoError.Exp memory exchangeRate =
            ExponentialNoError.Exp({mantissa: exchangeRateStoredInternal()});

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
         *  We call `doTransferIn` for the minter and the mintAmount.
         *  `doTransferIn` reverts if anything goes wrong, since we can't be sure if
         *  side-effects occurred. The function returns the amount actually transferred,
         *  in case of a fee. On success, the pToken holds an additional `actualMintAmount`
         *  of cash.
         */
        uint256 actualMintAmount = doTransferIn(minter, mintAmount);

        /*
         * We get the current exchange rate and calculate the number of pTokens to be minted:
         *  mintTokens = actualMintAmount / exchangeRate
         */

        uint256 mintTokens = actualMintAmount.div_(exchangeRate);

        /*
         * We calculate the new total supply of pTokens and onBehalfOf token balance, checking for overflow:
         *  totalSupplyNew = totalSupply + mintTokens
         *  accountTokensNew = accountTokens[onBehalfOf] + mintTokens
         * And write them into storage
         */
        _getPTokenStorage().totalSupply = _getPTokenStorage().totalSupply + mintTokens;
        _getPTokenStorage().accountTokens[onBehalfOf] =
            _getPTokenStorage().accountTokens[onBehalfOf] + mintTokens;

        /* We emit a Mint event, and a Transfer event */
        emit Mint(onBehalfOf, actualMintAmount, mintTokens);
        emit Transfer(address(0), onBehalfOf, mintTokens);
    }

    /**
     * @notice User redeems pTokens in exchange for the underlying asset
     * @dev Assumes interest has already been accrued up to the current timestamp
     * @param redeemer The address of the account which is redeeming the tokens
     * @param onBehalfOf The address of user on behalf of whom to redeem
     * @param redeemTokensIn The number of pTokens to redeem into underlying
     * (only one of redeemTokensIn or redeemAmountIn may be non-zero)
     * @param redeemAmountIn The number of underlying tokens to receive from redeeming pTokens
     */
    function redeemFresh(
        address redeemer,
        address onBehalfOf,
        uint256 redeemTokensIn,
        uint256 redeemAmountIn
    ) internal {
        if (redeemTokensIn != 0 && redeemAmountIn != 0) {
            revert CommonError.ZeroValue();
        }

        /* exchangeRate = invoke Exchange Rate Stored() */
        ExponentialNoError.Exp memory exchangeRate =
            ExponentialNoError.Exp({mantissa: exchangeRateStoredInternal()});

        uint256 redeemTokens;
        uint256 redeemAmount;

        /* If redeemTokensIn > 0: */
        if (redeemTokensIn > 0) {
            /*
             * We calculate the exchange rate and the amount of underlying to be redeemed:
             *  redeemTokens = redeemTokensIn
             *  redeemAmount = redeemTokensIn x exchangeRateCurrent
             */
            redeemTokens = redeemTokensIn;
            redeemAmount = exchangeRate.mul_ScalarTruncate(redeemTokensIn);
        } else {
            /*
             * We get the current exchange rate and calculate the amount to be redeemed:
             *  redeemTokens = redeemAmountIn / exchangeRate
             *  redeemAmount = redeemAmountIn
             */
            redeemTokens = redeemAmountIn.div_(exchangeRate);
            redeemAmount = redeemAmountIn;
        }

        /* Fail if redeem not allowed */
        uint256 allowed = _getPTokenStorage().riskEngine.redeemAllowed(
            address(this), onBehalfOf, redeemTokens
        );
        if (allowed != 0) {
            revert PTokenError.RedeemRiskEngineRejection(allowed);
        }

        /* Verify market's block timestamp equals current block timestamp */
        if (_getPTokenStorage().accrualBlockTimestamp != _getBlockTimestamp()) {
            revert PTokenError.RedeemFreshnessCheck();
        }

        /* Fail gracefully if protocol has insufficient cash */
        if (getCash() < redeemAmount) {
            revert PTokenError.RedeemTransferOutNotPossible();
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
         * We write the previously calculated values into storage.
         *  Note: Avoid token reentrancy attacks by writing reduced supply before external transfer.
         */
        _getPTokenStorage().totalSupply = _getPTokenStorage().totalSupply - redeemTokens;
        _getPTokenStorage().accountTokens[onBehalfOf] =
            _getPTokenStorage().accountTokens[onBehalfOf] - redeemTokens;

        /*
         * We invoke doTransferOut for the redeemer and the redeemAmount.
         *  On success, the pToken has redeemAmount less of cash.
         *  doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
         */
        doTransferOut(redeemer, redeemAmount);

        /* We emit a Transfer event, and a Redeem event */
        emit Transfer(onBehalfOf, address(0), redeemTokens);
        emit Redeem(onBehalfOf, redeemAmount, redeemTokens);

        /* We call the defense hook */
        _getPTokenStorage().riskEngine.redeemVerify(
            address(this), onBehalfOf, redeemAmount, redeemTokens
        );
    }

    /**
     * @notice Users borrow assets from the protocol to their own address
     * @param borrower The address of the account which is borrowing the tokens
     * @param onBehalfOf The address on behalf of whom to borrow
     * @param borrowAmount The amount of the underlying asset to borrow
     */
    function borrowFresh(address borrower, address onBehalfOf, uint256 borrowAmount)
        internal
    {
        /* Fail if borrow not allowed */
        uint256 allowed = _getPTokenStorage().riskEngine.borrowAllowed(
            address(this), onBehalfOf, borrowAmount
        );
        if (allowed != 0) {
            revert PTokenError.BorrowRiskEngineRejection(allowed);
        }

        /* Verify market's block timestamp equals current block timestamp */
        if (_getPTokenStorage().accrualBlockTimestamp != _getBlockTimestamp()) {
            revert PTokenError.BorrowFreshnessCheck();
        }

        /* Fail gracefully if protocol has insufficient underlying cash */
        if (getCash() < borrowAmount) {
            revert PTokenError.BorrowCashNotAvailable();
        }

        /*
         * We calculate the new borrower and total borrow balances, failing on overflow:
         *  accountBorrowNew = accountBorrow + borrowAmount
         *  totalBorrowsNew = totalBorrows + borrowAmount
         */
        uint256 accountBorrowsPrev = borrowBalanceStoredInternal(onBehalfOf);
        uint256 accountBorrowsNew = accountBorrowsPrev + borrowAmount;
        uint256 totalBorrowsNew = _getPTokenStorage().totalBorrows + borrowAmount;

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
         * We write the previously calculated values into storage.
         *  Note: Avoid token reentrancy attacks by writing increased borrow before external transfer.
        `*/
        _getPTokenStorage().accountBorrows[onBehalfOf].principal = accountBorrowsNew;
        _getPTokenStorage().accountBorrows[onBehalfOf].interestIndex =
            _getPTokenStorage().borrowIndex;
        _getPTokenStorage().totalBorrows = totalBorrowsNew;

        /*
         * We invoke doTransferOut for the borrower and the borrowAmount.
         *  On success, the pToken borrowAmount less of cash.
         *  doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
         */
        doTransferOut(borrower, borrowAmount);

        /* We emit a Borrow event */
        emit Borrow(onBehalfOf, borrowAmount, accountBorrowsNew, totalBorrowsNew);
    }

    /**
     * @notice Borrows are repaid by another user (possibly the borrower).
     * @param payer the account paying off the borrow
     * @param onBehalfOf the account with the debt being payed off
     * @param repayAmount the amount of underlying tokens being returned,
     * or type(uint256).max for the full outstanding amount
     * @return the actual repayment amount.
     */
    function repayBorrowFresh(address payer, address onBehalfOf, uint256 repayAmount)
        internal
        returns (uint256)
    {
        /* Fail if repayBorrow not allowed */
        uint256 allowed = _getPTokenStorage().riskEngine.repayBorrowAllowed(
            address(this), payer, onBehalfOf, repayAmount
        );
        if (allowed != 0) {
            revert PTokenError.RepayBorrowRiskEngineRejection(allowed);
        }

        /* Verify market's block timestamp equals current block timestamp */
        if (_getPTokenStorage().accrualBlockTimestamp != _getBlockTimestamp()) {
            revert PTokenError.RepayBorrowFreshnessCheck();
        }

        /* We fetch the amount the borrower owes, with accumulated interest */
        uint256 accountBorrowsPrev = borrowBalanceStoredInternal(onBehalfOf);

        /* If repayAmount == type(uint256).max, repayAmount = accountBorrows */
        uint256 repayAmountFinal =
            repayAmount == type(uint256).max ? accountBorrowsPrev : repayAmount;

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
         * We call doTransferIn for the payer and the repayAmount
         *  On success, the pToken holds an additional repayAmount of cash.
         *  doTransferIn reverts if anything goes wrong, since we can't be sure if side effects occurred.
         *   it returns the amount actually transferred, in case of a fee.
         */
        uint256 actualRepayAmount = doTransferIn(payer, repayAmountFinal);

        /*
         * We calculate the new borrower and total borrow balances, failing on underflow:
         *  accountBorrowsNew = accountBorrows - actualRepayAmount
         *  totalBorrowsNew = totalBorrows - actualRepayAmount
         */
        uint256 accountBorrowsNew = accountBorrowsPrev - actualRepayAmount;
        uint256 totalBorrowsNew = _getPTokenStorage().totalBorrows - actualRepayAmount;

        /* We write the previously calculated values into storage */
        _getPTokenStorage().accountBorrows[onBehalfOf].principal = accountBorrowsNew;
        _getPTokenStorage().accountBorrows[onBehalfOf].interestIndex =
            _getPTokenStorage().borrowIndex;
        _getPTokenStorage().totalBorrows = totalBorrowsNew;

        /* We emit a RepayBorrow event */
        emit RepayBorrow(
            payer, onBehalfOf, actualRepayAmount, accountBorrowsNew, totalBorrowsNew
        );

        return actualRepayAmount;
    }

    /**
     * @notice The liquidator liquidates the borrowers collateral.
     *  The collateral seized is transferred to the liquidator.
     * @param borrower The borrower of this pToken to be liquidated
     * @param liquidator The address repaying the borrow and seizing collateral
     * @param pTokenCollateral The market in which to seize collateral from the borrower
     * @param repayAmount The amount of the underlying borrowed asset to repay
     */
    function liquidateBorrowFresh(
        address liquidator,
        address borrower,
        uint256 repayAmount,
        IPToken pTokenCollateral
    ) internal {
        /* Fail if liquidate not allowed */
        uint256 allowed = _getPTokenStorage().riskEngine.liquidateBorrowAllowed(
            address(this), address(pTokenCollateral), liquidator, borrower, repayAmount
        );
        if (allowed != 0) {
            revert PTokenError.LiquidateRiskEngineRejection(allowed);
        }

        /* Verify market's block timestamp equals current block timestamp */
        if (_getPTokenStorage().accrualBlockTimestamp != _getBlockTimestamp()) {
            revert PTokenError.LiquidateFreshnessCheck();
        }

        /* Verify pTokenCollateral market's block timestamp equals current block timestamp */
        if (pTokenCollateral.accrualBlockTimestamp() != _getBlockTimestamp()) {
            revert PTokenError.LiquidateCollateralFreshnessCheck();
        }

        /* Fail if borrower = liquidator */
        if (borrower == liquidator) {
            revert PTokenError.LiquidateLiquidatorIsBorrower();
        }

        /* Fail if repayAmount = 0 */
        if (repayAmount == 0) {
            revert PTokenError.LiquidateCloseAmountIsZero();
        }

        /* Fail if repayAmount = type(uint256).max */
        if (repayAmount == type(uint256).max) {
            revert PTokenError.LiquidateCloseAmountIsUintMax();
        }

        /* Fail if repayBorrow fails */
        uint256 actualRepayAmount = repayBorrowFresh(liquidator, borrower, repayAmount);

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /* We calculate the number of collateral tokens that will be seized */
        (uint256 amountSeizeError, uint256 seizeTokens) = _getPTokenStorage()
            .riskEngine
            .liquidateCalculateSeizeTokens(
            address(this), address(pTokenCollateral), actualRepayAmount
        );
        if (amountSeizeError != CommonError.NO_ERROR) {
            revert PTokenError.LiquidateCalculateAmountSeizeFailed(amountSeizeError);
        }

        /* Revert if borrower collateral token balance < seizeTokens */
        if (pTokenCollateral.balanceOf(borrower) < seizeTokens) {
            revert PTokenError.LiquidateSeizeTooMuch();
        }

        // If this is also the collateral, run seizeInternal to avoid re-entrancy, otherwise make an external call
        if (address(pTokenCollateral) == address(this)) {
            seizeInternal(address(this), liquidator, borrower, seizeTokens);
        } else {
            pTokenCollateral.seize(liquidator, borrower, seizeTokens);
        }

        /* We emit a LiquidateBorrow event */
        emit LiquidateBorrow(
            liquidator,
            borrower,
            actualRepayAmount,
            address(pTokenCollateral),
            seizeTokens
        );
    }

    /**
     * @notice Transfers collateral tokens (this market) to the liquidator.
     * @dev Called only during an in-kind liquidation, or by liquidateBorrow during the liquidation of another pToken.
     *  Its absolutely critical to use msg.sender as the seizer pToken and not a parameter.
     * @param seizerToken The contract seizing the collateral (i.e. borrowed pToken)
     * @param liquidator The account receiving seized collateral
     * @param borrower The account having collateral seized
     * @param seizeTokens The number of pTokens to seize
     */
    function seizeInternal(
        address seizerToken,
        address liquidator,
        address borrower,
        uint256 seizeTokens
    ) internal {
        /* Fail if seize not allowed */
        uint256 allowed = _getPTokenStorage().riskEngine.seizeAllowed(
            address(this), seizerToken, liquidator, borrower, seizeTokens
        );
        if (allowed != 0) {
            revert PTokenError.LiquidateSeizeRiskEngineRejection(allowed);
        }

        /* Fail if borrower = liquidator */
        if (borrower == liquidator) {
            revert PTokenError.LiquidateSeizeLiquidatorIsBorrower();
        }

        /*
         * We calculate the new borrower and liquidator token balances, failing on underflow/overflow:
         *  borrowerTokensNew = accountTokens[borrower] - seizeTokens
         *  liquidatorTokensNew = accountTokens[liquidator] + seizeTokens
         */
        uint256 protocolSeizeTokens = seizeTokens.mul_(
            ExponentialNoError.Exp({
                mantissa: _getPTokenStorage().protocolSeizeShareMantissa
            })
        );
        uint256 liquidatorSeizeTokens = seizeTokens - protocolSeizeTokens;
        ExponentialNoError.Exp memory exchangeRate =
            ExponentialNoError.Exp({mantissa: exchangeRateStoredInternal()});
        uint256 protocolSeizeAmount = exchangeRate.mul_ScalarTruncate(protocolSeizeTokens);
        uint256 totalReservesNew = _getPTokenStorage().totalReserves + protocolSeizeAmount;

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /* We write the calculated values into storage */
        _getPTokenStorage().totalReserves = totalReservesNew;
        _getPTokenStorage().totalSupply =
            _getPTokenStorage().totalSupply - protocolSeizeTokens;
        _getPTokenStorage().accountTokens[borrower] =
            _getPTokenStorage().accountTokens[borrower] - seizeTokens;
        _getPTokenStorage().accountTokens[liquidator] =
            _getPTokenStorage().accountTokens[liquidator] + liquidatorSeizeTokens;

        /* Emit a Transfer event */
        emit Transfer(borrower, liquidator, liquidatorSeizeTokens);
        emit Transfer(borrower, address(this), protocolSeizeTokens);
        emit ReservesAdded(address(this), protocolSeizeAmount, totalReservesNew);
    }

    /**
     * @dev Similar to ERC-20 transfer, but handles tokens that have transfer fees.
     *      This function returns the actual amount received,
     *      which may be less than `amount` if there is a fee attached to the transfer.
     * @param from Sender of the underlying tokens
     * @param amount Amount of underlying to transfer
     * @return Actual amount received
     */
    function doTransferIn(address from, uint256 amount)
        internal
        virtual
        returns (uint256)
    {
        // Read from storage once
        IERC20 token = IERC20(_getPTokenStorage().underlying);
        uint256 balanceBefore = token.balanceOf(address(this));
        token.safeTransferFrom(from, address(this), amount);
        uint256 balanceAfter = token.balanceOf(address(this));
        // Return the amount that was *actually* transferred
        return balanceAfter - balanceBefore;
    }

    /**
     * @dev Similar to ERC20 transfer, and reverts on failure.
     * @param to Receiver of the underlying tokens
     * @param amount Amount of underlying to transfer
     */
    function doTransferOut(address to, uint256 amount) internal virtual {
        IERC20(_getPTokenStorage().underlying).safeTransfer(to, amount);
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

    /**
     * @notice Add reserves by transferring from caller
     * @dev Requires fresh interest accrual
     * @param addAmount Amount of addition to reserves
     */
    function _addReservesFresh(uint256 addAmount) internal {
        // totalReserves + actualAddAmount
        uint256 totalReservesNew;
        uint256 actualAddAmount;

        // Verify market's block timestamp equals current block timestamp
        if (_getPTokenStorage().accrualBlockTimestamp != _getBlockTimestamp()) {
            revert PTokenError.AddReservesFactorFreshCheck();
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        /*
         * We call doTransferIn for the caller and the addAmount
         *  On success, the cToken holds an additional addAmount of cash.
         *  doTransferIn reverts if anything goes wrong, since we can't be sure if side effects occurred.
         *  it returns the amount actually transferred, in case of a fee.
         */

        actualAddAmount = doTransferIn(msg.sender, addAmount);

        totalReservesNew = _getPTokenStorage().totalReserves + actualAddAmount;

        // Store reserves[n+1] = reserves[n] + actualAddAmount
        _getPTokenStorage().totalReserves = totalReservesNew;

        /* Emit NewReserves(admin, actualAddAmount, reserves[n+1]) */
        emit ReservesAdded(msg.sender, actualAddAmount, totalReservesNew);
    }

    /**
     * @notice Reduces reserves by transferring to admin
     * @dev Requires fresh interest accrual
     * @param reduceAmount Amount of reduction to reserves
     */
    function _reduceReservesFresh(uint256 reduceAmount) internal {
        // totalReserves - reduceAmount
        uint256 totalReservesNew;

        // Verify market's block timestamp equals current block timestamp
        if (_getPTokenStorage().accrualBlockTimestamp != _getBlockTimestamp()) {
            revert PTokenError.ReduceReservesFreshCheck();
        }

        // Fail gracefully if protocol has insufficient underlying cash
        if (getCash() < reduceAmount) {
            revert PTokenError.ReduceReservesCashNotAvailable();
        }

        // Check reduceAmount ≤ reserves[n] (totalReserves)
        if (reduceAmount > _getPTokenStorage().totalReserves) {
            revert PTokenError.ReduceReservesCashValidation();
        }

        /////////////////////////
        // EFFECTS & INTERACTIONS
        // (No safe failures beyond this point)

        totalReservesNew = _getPTokenStorage().totalReserves - reduceAmount;

        // Store reserves[n+1] = reserves[n] - reduceAmount
        _getPTokenStorage().totalReserves = totalReservesNew;

        // doTransferOut reverts if anything goes wrong, since we can't be sure if side effects occurred.
        doTransferOut(msg.sender, reduceAmount);

        emit ReservesReduced(msg.sender, reduceAmount, totalReservesNew);
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
        /* Read the previous values out of storage */
        snapshot.totalBorrow = _getPTokenStorage().totalBorrows;
        snapshot.totalReserve = _getPTokenStorage().totalReserves;
        snapshot.accBorrowIndex = _getPTokenStorage().borrowIndex;

        uint256 accruedBlockTimestamp = _getPTokenStorage().accrualBlockTimestamp;

        if (_getBlockTimestamp() > accruedBlockTimestamp && snapshot.totalBorrow > 0) {
            /* Calculate the current borrow interest rate */
            uint256 borrowRate = IInterestRateModel(address(this)).getBorrowRate(
                getCash(), snapshot.totalBorrow, snapshot.totalReserve
            );

            /*
         * Calculate the interest accumulated into borrows and reserves and the new index:
         *  interestFactor = borrowRate * timeDelta
         *  interestAccumulated = interestFactor * totalBorrows
         *  totalBorrowsNew = interestAccumulated + totalBorrows
         *  totalReservesNew = interestAccumulated * reserveFactor + totalReserves
         *  borrowIndexNew = interestFactor * borrowIndex + borrowIndex
         */

            ExponentialNoError.Exp memory interestFactor = ExponentialNoError.Exp({
                mantissa: borrowRate
            }).mul_(_getBlockTimestamp() - accruedBlockTimestamp);
            uint256 interestAccumulated =
                interestFactor.mul_ScalarTruncate(snapshot.totalBorrow);

            snapshot.totalBorrow = snapshot.totalBorrow + interestAccumulated;
            snapshot.totalReserve = ExponentialNoError.Exp({
                mantissa: _getPTokenStorage().reserveFactorMantissa
            }).mul_ScalarTruncateAddUInt(interestAccumulated, snapshot.totalReserve);
            snapshot.accBorrowIndex = interestFactor.mul_ScalarTruncateAddUInt(
                snapshot.accBorrowIndex, snapshot.accBorrowIndex
            );
        }
    }

    /**
     * @notice Return the borrow balance of account based on stored data
     * @param account The address whose balance should be calculated
     * @return the calculated balance
     */
    function borrowBalanceStoredInternal(address account)
        internal
        view
        returns (uint256)
    {
        /* Get borrowBalance and borrowIndex */
        BorrowSnapshot memory borrowSnapshot = _getPTokenStorage().accountBorrows[account];

        /* If borrowBalance = 0 then borrowIndex is likely also 0.
         * Rather than failing the calculation with a division by 0, we immediately return 0 in this case.
         */
        if (borrowSnapshot.principal == 0) {
            return 0;
        }

        /* Calculate new borrow balance using the interest index:
         *  recentBorrowBalance = borrower.borrowBalance * market.borrowIndex / borrower.borrowIndex
         */
        uint256 principalTimesIndex =
            borrowSnapshot.principal * _getPTokenStorage().borrowIndex;
        return principalTimesIndex / borrowSnapshot.interestIndex;
    }

    /**
     * @notice Calculates the exchange rate from the underlying to the PToken
     * @dev This function does not accrue interest before calculating the exchange rate
     * @return calculated exchange rate scaled by 1e18
     */
    function exchangeRateStoredInternal() internal view returns (uint256) {
        uint256 _totalSupply = _getPTokenStorage().totalSupply;
        if (_totalSupply == 0) {
            /*
             * If there are no tokens minted:
             *  exchangeRate = initialExchangeRate
             */
            return _getPTokenStorage().initialExchangeRateMantissa;
        } else {
            /*
             * Otherwise:
             *  exchangeRate = (totalCash + totalBorrows - totalReserves) / totalSupply
             */
            uint256 totalCash = getCash();
            uint256 cashPlusBorrowsMinusReserves = totalCash
                + _getPTokenStorage().totalBorrows - _getPTokenStorage().totalReserves;
            return
                cashPlusBorrowsMinusReserves * ExponentialNoError.expScale / _totalSupply;
        }
    }

    /**
     * @dev Function to check if msg.sender is delegatee
     */
    function _isDelegateeOf(address onBehalfOf) internal view {
        if (!_getPTokenStorage().riskEngine.delegateAllowed(onBehalfOf, msg.sender)) {
            revert PTokenError.DelegateNotAllowed();
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
