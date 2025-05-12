// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {
    IMultiply,
    IPToken,
    IRiskEngine,
    IOracleEngine
} from "@periphery/interfaces/IMultiply.sol";
import {
    IERC20,
    SafeERC20,
    FLHelper,
    IFLHelper,
    IUniswapV3Pool
} from "@periphery/FLHelper.sol";
import {
    IV3SwapRouter, IZap, ISelfPeggingAsset
} from "@periphery/interfaces/IProtocols.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {CommonError} from "@errors/CommonError.sol";

/**
 * @title Multiply
 * @notice Implementation of leverage and deleverage operations for LP tokens
 * @dev Uses FLHelper, Uniswap V3/Tapio for swaps, and Tapio SPA contract for LP minting/redeeming
 */
contract Multiply is IMultiply, FLHelper, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Constants
    uint256 private constant PERCENTAGE_BASE = 10_000; // 100% = 10,000
    uint256 private constant BASE = 1e18; // 1e18 for precision

    // Immutable state variables
    IV3SwapRouter public immutable uniswapRouter;
    IZap public immutable zapContract;

    constructor(
        address _uniswapRouter,
        address _zapContract,
        address _initialOwner,
        address _uniV3Factory,
        address _aaveV3LendingPool,
        address _balancerVault,
        address _morphoBlue
    )
        FLHelper(_uniV3Factory, _aaveV3LendingPool, _balancerVault, _morphoBlue)
        Ownable(_initialOwner)
    {
        require(
            _uniswapRouter != address(0) && _zapContract != address(0),
            CommonError.ZeroAddress()
        );

        uniswapRouter = IV3SwapRouter(_uniswapRouter);
        zapContract = IZap(_zapContract);
    }

    /**
     * @inheritdoc IMultiply
     */
    function leverageLP(
        FlashLoanParams calldata flParams,
        LeverageLPParams calldata params
    ) external nonReentrant {
        _validateLeverageParams(params);

        InternalContext memory mainParams = InternalContext(msg.sender, true, false);

        IERC20 borrowToken = IERC20(IPToken(params.borrowPToken).asset());
        borrowToken.safeTransferFrom(msg.sender, address(this), params.collateralAmount);

        _executeFlashLoanLeverage(flParams, mainParams, params);
    }

    /**
     * @inheritdoc IMultiply
     */
    function leverageExisting(
        FlashLoanParams calldata flParams,
        LeverageLPParams calldata params
    ) external nonReentrant {
        _validateLeverageParams(params);
        InternalContext memory mainParams = InternalContext(msg.sender, true, true);

        _executeFlashLoanLeverage(flParams, mainParams, params);
    }

    /**
     * @inheritdoc IMultiply
     */
    function deleverageLP(
        FlashLoanParams calldata flParams,
        DeleverageLPParams calldata params
    ) external nonReentrant returns (uint256 excess) {
        _validateDeleverageParams(params);
        /// there should be allowance to redeem on behalf of
        InternalContext memory mainParams = InternalContext(msg.sender, false, false);
        _executeFlashLoanDeleverage(flParams, mainParams, params);

        // Return excess tokens to user
        IERC20 borrowToken = IERC20(IPToken(params.borrowPToken).asset());
        excess = borrowToken.balanceOf(address(this));
        if (excess > 0) {
            borrowToken.safeTransfer(msg.sender, excess);
        }
    }

    function executeOperation(
        address[] memory assets,
        uint256[] memory,
        uint256[] memory premiums,
        address initiator,
        bytes calldata data
    ) external override(FLHelper, IFLHelper) returns (bool) {
        verifyAaveCallback(msg.sender, initiator);
        require(assets.length == 1, CommonError.NoArrayParity());

        (InternalContext memory mainParams) = abi.decode(data, (InternalContext));

        address debtToken = assets[0];
        uint256 fee = premiums[0];
        uint256 amount = IERC20(debtToken).balanceOf(address(this));

        CallbackContext memory ctx = CallbackContext(
            mainParams.caller,
            debtToken,
            amount,
            fee,
            FlashLoanSource.AAVE_V3,
            mainParams.isExisting
        );

        bytes memory recipeData = data[96:];

        if (mainParams.isLeverage) {
            LeverageLPParams memory params = abi.decode(recipeData, (LeverageLPParams));

            _handleLeverageCallback(params, ctx);
        } else {
            DeleverageLPParams memory params =
                abi.decode(recipeData, (DeleverageLPParams));

            _handleDeleverageCallback(params, ctx);
        }

        return true;
    }

    function uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes calldata data)
        external
        override(FLHelper, IFLHelper)
    {
        (InternalContext memory mainParams, address pool) =
            abi.decode(data, (InternalContext, address));

        IUniswapV3Pool uniswapPool = IUniswapV3Pool(pool);

        require(msg.sender == address(uniswapPool), InvalidPool());

        address debtToken = fee0 > 0 ? uniswapPool.token0() : uniswapPool.token1();
        uint256 fee = fee0 > 0 ? fee0 : fee1;
        uint256 amount = IERC20(debtToken).balanceOf(address(this));

        CallbackContext memory ctx = CallbackContext(
            mainParams.caller,
            debtToken,
            amount,
            fee,
            FlashLoanSource.UNISWAP_V3,
            mainParams.isExisting
        );

        bytes memory recipeData = data[128:];

        if (mainParams.isLeverage) {
            LeverageLPParams memory params = abi.decode(recipeData, (LeverageLPParams));

            verifyUniswapV3Callback(
                msg.sender, uniswapPool.token0(), uniswapPool.token1(), params.feeTier
            );

            _handleLeverageCallback(params, ctx);
        } else {
            DeleverageLPParams memory params =
                abi.decode(recipeData, (DeleverageLPParams));

            verifyUniswapV3Callback(
                msg.sender, uniswapPool.token0(), uniswapPool.token1(), params.feeTier
            );

            _handleDeleverageCallback(params, ctx);
        }
    }

    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory data
    ) external override(FLHelper, IFLHelper) nonReentrant {}

    function onMorphoFlashLoan(uint256 assets, bytes calldata data)
        external
        override(FLHelper, IFLHelper)
        nonReentrant
    {}

    /**
     * @inheritdoc IMultiply
     */
    function calculateLeverageMaxBorrow(
        IRiskEngine riskEngine,
        address account,
        uint8 categoryId,
        IPToken supplyPToken
    ) external view returns (uint256 maxBorrowAmount) {
        (, uint256 liquidity, uint256 shortfall) =
            riskEngine.getAccountBorrowLiquidity(account);

        if (liquidity == 0 || shortfall > 0) return 0;
        if (address(supplyPToken) == address(0)) return liquidity;

        uint256 collateralFactor = riskEngine.collateralFactor(categoryId, supplyPToken);
        maxBorrowAmount = (liquidity * BASE) / (BASE - collateralFactor);
    }

    /**
     * @inheritdoc IMultiply
     */
    function calculateDeleverageRedeemableCollateral(
        IRiskEngine riskEngine,
        address account,
        IPToken borrowPToken,
        IPToken supplyPToken,
        uint8 categoryId,
        uint256 repayAmount
    ) external view returns (uint256 maxCollateralAmount) {
        IOracleEngine oracle = IOracleEngine(riskEngine.oracle());
        uint256 borrowPrice = oracle.getUnderlyingPrice(borrowPToken);
        uint256 supplyPrice = oracle.getUnderlyingPrice(supplyPToken);
        uint256 collateralFactor =
            riskEngine.collateralFactor(categoryId, IPToken(supplyPToken));
        uint256 collateralBalance = supplyPToken.balanceOfUnderlying(account);

        uint256 repayValue = (repayAmount * borrowPrice) / collateralFactor;
        uint256 collateralValue = (collateralBalance * supplyPrice) / BASE;
        if (collateralValue > repayValue) {
            maxCollateralAmount = (collateralValue - repayValue) * BASE / supplyPrice;
        }
    }

    // Internal Functions
    function _executeFlashLoanLeverage(
        FlashLoanParams memory flParams,
        InternalContext memory mainParams,
        LeverageLPParams memory params
    ) internal {
        bytes memory recipeData;
        if (flParams.source == FlashLoanSource.UNISWAP_V3) {
            recipeData = abi.encode(mainParams, flParams.tokens[2], params);
        } else {
            recipeData = abi.encode(mainParams, params);
        }
        executeFlashLoan(flParams, recipeData);
    }

    // Internal Functions
    function _executeFlashLoanDeleverage(
        FlashLoanParams memory flParams,
        InternalContext memory mainParams,
        DeleverageLPParams memory params
    ) internal {
        bytes memory recipeData;
        if (flParams.source == FlashLoanSource.UNISWAP_V3) {
            recipeData = abi.encode(mainParams, flParams.tokens[2], params);
        } else {
            recipeData = abi.encode(mainParams, params);
        }
        executeFlashLoan(flParams, recipeData);
    }

    function _handleLeverageCallback(
        LeverageLPParams memory params,
        CallbackContext memory ctx
    ) internal {
        address borrowToken = IPToken(params.borrowPToken).asset();
        require(ctx.debtToken == borrowToken, DebtTokenMismatch());

        if (!ctx.isExisting) {
            ctx.amount -= params.collateralAmount;
        }

        uint256 adjustedAmount = ctx.amount * params.safetyFactor / PERCENTAGE_BASE;
        uint256 totalBorrowedBalance =
            !ctx.isExisting ? params.collateralAmount + adjustedAmount : adjustedAmount;

        uint256[] memory amounts =
            _performLeverageSwaps(params, borrowToken, totalBorrowedBalance);
        uint256 lpAmount = _mintLPTokens(
            params.spa, IPToken(params.supplyPToken), amounts, params.minAmountOut[1]
        );

        uint256 suppliedCollateral =
            _supplyCollateral(IPToken(params.supplyPToken), lpAmount, ctx.caller);
        _repayBorrowFlashLoan(IPToken(params.borrowPToken), ctx);

        emit LeverageExecuted(
            ctx.caller,
            params.supplyPToken,
            params.borrowPToken,
            suppliedCollateral,
            ctx.isExisting ? params.collateralAmount : 0,
            adjustedAmount,
            ctx.fee,
            params.swapProtocol
        );
    }

    function _handleDeleverageCallback(
        DeleverageLPParams memory params,
        CallbackContext memory ctx
    ) internal {
        address borrowToken = IPToken(params.borrowPToken).asset();
        require(ctx.debtToken == borrowToken, DebtTokenMismatch());

        uint256 adjustedAmount = ctx.amount * params.safetyFactor / PERCENTAGE_BASE;

        _repayDebt(IPToken(params.borrowPToken), adjustedAmount, ctx.caller);
        uint256 redeemed = _redeemCollateral(
            IPToken(params.supplyPToken), params.collateralToRedeem, ctx.caller
        );
        (address[] memory tokens, uint256[] memory amounts) =
            _redeemLPTokens(params, redeemed);

        uint256 debtReceived = _swapToBorrowToken(params, tokens, amounts, borrowToken);
        require(debtReceived >= adjustedAmount, InsufficientToRepay());
        _repayFlashLoan(ctx.flSource, borrowToken, ctx.amount + ctx.fee);

        emit DeleverageExecuted(
            ctx.caller,
            params.borrowPToken,
            params.supplyPToken,
            adjustedAmount,
            params.collateralToRedeem,
            ctx.fee,
            params.swapProtocol
        );
    }

    function _performLeverageSwaps(
        LeverageLPParams memory params,
        address borrowToken,
        uint256 totalBorrowedBalance
    ) internal returns (uint256[] memory amounts) {
        address[] memory underlyingTokens = ISelfPeggingAsset(params.spa).getTokens();
        amounts = new uint256[](underlyingTokens.length);

        uint256 proportionToSwap =
            (totalBorrowedBalance * params.proportionToSwap) / PERCENTAGE_BASE;

        for (uint256 i = 0; i < underlyingTokens.length; i++) {
            if (underlyingTokens[i] == borrowToken) {
                amounts[i] = totalBorrowedBalance - proportionToSwap;
            } else {
                amounts[i] = params.swapProtocol == SwapProtocol.UNISWAP_V3
                    ? _swapTokensUniswapV3(
                        borrowToken,
                        underlyingTokens[i],
                        proportionToSwap,
                        params.minAmountOut[0],
                        params.feeTier
                    )
                    : _swapTokensTapio(
                        borrowToken,
                        underlyingTokens[i],
                        params.spa,
                        proportionToSwap,
                        params.minAmountOut[0]
                    );
            }
        }
    }

    function _mintLPTokens(
        address spa,
        IPToken supplyPToken,
        uint256[] memory amounts,
        uint256 minAmountOut
    ) internal returns (uint256 lpAmount) {
        address[] memory underlyingTokens = ISelfPeggingAsset(spa).getTokens();
        for (uint256 i = 0; i < underlyingTokens.length; i++) {
            IERC20(underlyingTokens[i]).forceApprove(address(zapContract), amounts[i]);
        }
        address supplyToken = supplyPToken.asset();
        lpAmount =
            zapContract.zapIn(spa, supplyToken, address(this), minAmountOut, amounts);
    }

    function _supplyCollateral(IPToken supplyPToken, uint256 lpAmount, address caller)
        internal
        returns (uint256)
    {
        address supplyToken = supplyPToken.asset();
        IERC20(supplyToken).forceApprove(address(supplyPToken), lpAmount);

        return supplyPToken.deposit(lpAmount, caller);
    }

    function _repayBorrowFlashLoan(IPToken borrowPToken, CallbackContext memory ctx)
        internal
    {
        uint256 totalRepay = ctx.amount + ctx.fee;
        borrowPToken.borrowOnBehalfOf(ctx.caller, totalRepay);
        _repayFlashLoan(ctx.flSource, ctx.debtToken, totalRepay);
    }

    function _repayDebt(IPToken borrowPToken, uint256 debtToRepay, address caller)
        internal
    {
        address borrowToken = borrowPToken.asset();
        IERC20(borrowToken).forceApprove(address(borrowPToken), debtToRepay);
        borrowPToken.repayBorrowOnBehalfOf(caller, debtToRepay);
    }

    function _redeemCollateral(
        IPToken supplyPToken,
        uint256 collateralToRedeem,
        address caller
    ) internal returns (uint256) {
        return supplyPToken.withdraw(collateralToRedeem, address(this), caller);
    }

    function _redeemLPTokens(DeleverageLPParams memory params, uint256 redeemed)
        internal
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        address supplyToken = IPToken(params.supplyPToken).asset();
        IERC20(supplyToken).forceApprove(address(zapContract), redeemed);

        if (params.redeemType == RedeemType.SINGLE) {
            tokens = new address[](1);
            amounts = new uint256[](1);
            tokens[0] =
                ISelfPeggingAsset(params.spa).getTokens()[params.tokenIndexForSingle];
            amounts[0] = zapContract.zapOutSingle(
                params.spa,
                supplyToken,
                address(this),
                redeemed,
                params.tokenIndexForSingle,
                params.minAmountOut[params.tokenIndexForSingle]
            );
        } else {
            uint256[] memory minAmountsOut = new uint256[](2);
            for (uint256 i = 0; i < 2; i++) {
                minAmountsOut[i] = params.minAmountOut[i];
            }
            tokens = ISelfPeggingAsset(params.spa).getTokens();
            amounts = zapContract.zapOut(
                params.spa,
                supplyToken,
                address(this),
                redeemed,
                minAmountsOut,
                params.redeemType == RedeemType.PROPORTIONAL
            );
        }
    }

    function _swapToBorrowToken(
        DeleverageLPParams memory params,
        address[] memory tokens,
        uint256[] memory amounts,
        address borrowToken
    ) internal returns (uint256 debtReceived) {
        debtReceived = 0;
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] != borrowToken && amounts[i] > 0) {
                amounts[i] = params.swapProtocol == SwapProtocol.UNISWAP_V3
                    ? _swapTokensUniswapV3(
                        tokens[i],
                        borrowToken,
                        amounts[i],
                        params.minAmountOut[i],
                        params.feeTier
                    )
                    : _swapTokensTapio(
                        tokens[i], borrowToken, params.spa, amounts[i], params.minAmountOut[i]
                    );
                debtReceived += amounts[i];
            } else if (tokens[i] == borrowToken) {
                debtReceived += amounts[i];
            }
        }
    }

    function _swapTokensUniswapV3(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint24 feeTier
    ) internal returns (uint256 amountOut) {
        if (amountIn == 0) return 0;
        IERC20(tokenIn).forceApprove(address(uniswapRouter), amountIn);

        IV3SwapRouter.ExactInputSingleParams memory swapParams = IV3SwapRouter
            .ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: feeTier,
            recipient: address(this),
            amountIn: amountIn,
            amountOutMinimum: minAmountOut,
            sqrtPriceLimitX96: 0
        });

        return uniswapRouter.exactInputSingle(swapParams);
    }

    function _swapTokensTapio(
        address tokenIn,
        address tokenOut,
        address spa,
        uint256 amountIn,
        uint256 minAmountOut
    ) internal returns (uint256 amountOut) {
        if (amountIn == 0) return 0;
        require(spa != address(0), CommonError.ZeroAddress());
        IERC20(tokenIn).forceApprove(address(spa), amountIn);

        ISelfPeggingAsset spaContract = ISelfPeggingAsset(spa);
        (uint256 tokenInIndex, uint256 tokenOutIndex) =
            _getTokenIndices(spaContract, tokenIn, tokenOut);
        return spaContract.swap(tokenInIndex, tokenOutIndex, amountIn, minAmountOut);
    }

    function _repayFlashLoan(
        FlashLoanSource flSource,
        address debtToken,
        uint256 amountToRepay
    ) internal {
        if (flSource == FlashLoanSource.UNISWAP_V3) {
            IERC20(debtToken).safeTransfer(msg.sender, amountToRepay);
        } else if (flSource == FlashLoanSource.AAVE_V3) {
            IERC20(debtToken).forceApprove(msg.sender, amountToRepay);
        } else if (flSource == FlashLoanSource.BALANCER) {
            IERC20(debtToken).safeTransfer(BALANCER_VAULT, amountToRepay);
        } else if (flSource == FlashLoanSource.MORPHO_BLUE) {
            IERC20(debtToken).forceApprove(MORPHO_BLUE_ADDR, amountToRepay);
        }
    }

    function _getTokenIndices(
        ISelfPeggingAsset spaContract,
        address tokenIn,
        address tokenOut
    ) internal view returns (uint256 tokenInIndex, uint256 tokenOutIndex) {
        address[] memory spaTokens = spaContract.getTokens();
        for (uint256 i = 0; i < spaTokens.length; i++) {
            if (spaTokens[i] == tokenIn) {
                tokenInIndex = i;
            }
            if (spaTokens[i] == tokenOut) {
                tokenOutIndex = i;
            }
        }
    }

    function _validateLeverageParams(LeverageLPParams memory params) internal pure {
        require(
            params.borrowPToken != address(0) && params.supplyPToken != address(0)
                && params.spa != address(0),
            CommonError.ZeroAddress()
        );
        require(params.safetyFactor <= PERCENTAGE_BASE, InvalidSafetyFactor());
        require(params.proportionToSwap <= PERCENTAGE_BASE, InvalidProportion());
    }

    function _validateDeleverageParams(DeleverageLPParams memory params) internal pure {
        require(
            params.borrowPToken != address(0) && params.supplyPToken != address(0)
                && params.spa != address(0),
            CommonError.ZeroAddress()
        );
        require(params.collateralToRedeem > 0, CommonError.ZeroValue());
    }
}
