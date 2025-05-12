// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title IProtocols
 * @notice Consolidated interface for external protocol dependencies used in periphery
 * @dev Includes interfaces for Uniswap V3, Aave V3, Balancer, Morpho Blue, and related protocols
 */

/* ========== Uniswap V3 Interfaces ========== */

interface IUniswapV3Factory {
    /**
     * @notice Returns the pool address for a given pair of tokens and fee tier
     * @param token0 First token in the pool (sorted by address)
     * @param token1 Second token in the pool (sorted by address)
     * @param fee The pool fee in hundredths of a bip (e.g., 3000 for 0.3%)
     * @return poolAddress The address of the pool
     */
    function getPool(address token0, address token1, uint24 fee)
        external
        view
        returns (address poolAddress);
}

// Pool state that never changes
interface IUniswapV3PoolImmutables {
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function fee() external view returns (uint24);
    function tickSpacing() external view returns (int24);
    function maxLiquidityPerTick() external view returns (uint128);
}

// Pool state that can change
interface IUniswapV3PoolState {
    function slot0()
        external
        view
        returns (
            uint160 sqrtPriceX96,
            int24 tick,
            uint16 observationIndex,
            uint16 observationCardinality,
            uint16 observationCardinalityNext,
            uint8 feeProtocol,
            bool unlocked
        );
    function feeGrowthGlobal0X128() external view returns (uint256);
    function feeGrowthGlobal1X128() external view returns (uint256);
    function protocolFees() external view returns (uint128 token0, uint128 token1);
    function liquidity() external view returns (uint128);
    function ticks(int24 tick)
        external
        view
        returns (
            uint128 liquidityGross,
            int128 liquidityNet,
            uint256 feeGrowthOutside0X128,
            uint256 feeGrowthOutside1X128,
            int56 tickCumulativeOutside,
            uint160 secondsPerLiquidityOutsideX128,
            uint32 secondsOutside,
            bool initialized
        );
    function tickBitmap(int16 wordPosition) external view returns (uint256);
    function positions(bytes32 key)
        external
        view
        returns (
            uint128 _liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );
    function observations(uint256 index)
        external
        view
        returns (
            uint32 blockTimestamp,
            int56 tickCumulative,
            uint160 secondsPerLiquidityCumulativeX128,
            bool initialized
        );
}

// Pool state that is not stored
interface IUniswapV3PoolDerivedState {
    function observe(uint32[] calldata secondsAgos)
        external
        view
        returns (
            int56[] memory tickCumulatives,
            uint160[] memory secondsPerLiquidityCumulativeX128s
        );
    function snapshotCumulativesInside(int24 tickLower, int24 tickUpper)
        external
        view
        returns (
            int56 tickCumulativeInside,
            uint160 secondsPerLiquidityInsideX128,
            uint32 secondsInside
        );
}

// Permissionless pool actions
interface IUniswapV3PoolActions {
    function initialize(uint160 sqrtPriceX96) external;
    function mint(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount,
        bytes calldata data
    ) external returns (uint256 amount0, uint256 amount1);
    function collect(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1);
    function burn(int24 tickLower, int24 tickUpper, uint128 amount)
        external
        returns (uint256 amount0, uint256 amount1);
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
    function flash(
        address recipient,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external;
    function increaseObservationCardinalityNext(uint16 observationCardinalityNext)
        external;
}

// Permissioned pool actions
interface IUniswapV3PoolOwnerActions {
    function setFeeProtocol(uint8 feeProtocol0, uint8 feeProtocol1) external;
    function collectProtocol(
        address recipient,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external returns (uint128 amount0, uint128 amount1);
}

// Events emitted by a pool
interface IUniswapV3PoolEvents {
    event Initialize(uint160 sqrtPriceX96, int24 tick);
    event Mint(
        address sender,
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );
    event Collect(
        address indexed owner,
        address recipient,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount0,
        uint128 amount1
    );
    event Burn(
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );
    event Swap(
        address indexed sender,
        address indexed recipient,
        int256 amount0,
        int256 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick
    );
    event Flash(
        address indexed sender,
        address indexed recipient,
        uint256 amount0,
        uint256 amount1,
        uint256 paid0,
        uint256 paid1
    );
    event IncreaseObservationCardinalityNext(
        uint16 observationCardinalityNextOld, uint16 observationCardinalityNextNew
    );
    event SetFeeProtocol(
        uint8 feeProtocol0Old,
        uint8 feeProtocol1Old,
        uint8 feeProtocol0New,
        uint8 feeProtocol1New
    );
    event CollectProtocol(
        address indexed sender,
        address indexed recipient,
        uint128 amount0,
        uint128 amount1
    );
}

// Consolidated Uniswap V3 Pool interface
interface IUniswapV3Pool is
    IUniswapV3PoolImmutables,
    IUniswapV3PoolState,
    IUniswapV3PoolDerivedState,
    IUniswapV3PoolActions,
    IUniswapV3PoolOwnerActions,
    IUniswapV3PoolEvents
{}

/* ========== Aave V3 Interfaces ========== */

interface ILendingPoolV2 {
    /**
     * @notice Allows smart contracts to access pool liquidity within one transaction, as long as the amount plus fee is returned
     * @param receiverAddress Contract receiving the funds, implementing IFlashLoanReceiver
     * @param assets Addresses of assets being flash-borrowed
     * @param amounts Amounts being flash-borrowed
     * @param modes Debt types: 0 (revert if not returned), 1 (stable rate), 2 (variable rate)
     * @param onBehalfOf Address receiving debt if modes 1 or 2
     * @param params Extra information for the receiver
     * @param referralCode Code for integrator rewards (0 if none)
     */
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

/* ========== Balancer Interfaces ========== */

interface IFlashLoans {
    /**
     * @notice Executes a flash loan from Balancer Vault
     * @param recipient Address receiving the funds
     * @param tokens Tokens being flash-borrowed
     * @param amounts Amounts being flash-borrowed
     * @param userData Additional data for the callback
     */
    function flashLoan(
        address recipient,
        address[] memory tokens,
        uint256[] memory amounts,
        bytes memory userData
    ) external;
}

/* ========== Morpho Blue Interfaces ========== */

interface IMorphoBlue {
    /**
     * @notice Executes a flash loan with Morpho Blue
     * @dev Flash loans access the contract's entire balance
     * @param token Token to flash loan
     * @param assets Amount to flash loan
     * @param data Data passed to onMorphoFlashLoan callback
     */
    function flashLoan(address token, uint256 assets, bytes calldata data) external;
}

/* ========== Swap Router Interfaces ========== */

interface IV3SwapRouter {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    /**
     * @notice Swaps amountIn of tokenIn for at least amountOutMinimum of tokenOut
     * @param params Swap parameters
     * @return amountOut Amount of tokenOut received
     */
    function exactInputSingle(ExactInputSingleParams calldata params)
        external
        returns (uint256 amountOut);
}

/* ========== SelfPeggingAsset Interface ========== */
interface ISelfPeggingAsset {
    function swap(uint256, uint256, uint256, uint256) external returns (uint256);

    function getTokens() external view returns (address[] memory);
}

/* ========== Zap contract Interface ========== */
interface IZap {
    event ZapIn(
        address indexed spa,
        address indexed user,
        address indexed receiver,
        uint256 wlpAmount,
        uint256[] inputAmounts
    );
    event ZapOut(
        address indexed spa,
        address indexed user,
        address indexed receiver,
        uint256 wlpAmount,
        uint256[] outputAmounts,
        bool proportional
    );

    /**
     * @notice Add liquidity to SPA and automatically wrap LP tokens
     * @param spa Address of the SPA contract
     * @param wlp Address of the wrapped LP token contract
     * @param receiver Address to receive the wrapped LP tokens
     * @param minMintAmount Minimum amount of LP tokens to receive
     * @param amounts Array of token amounts to add
     * @return wlpAmount Amount of wrapped LP tokens minted
     */
    function zapIn(
        address spa,
        address wlp,
        address receiver,
        uint256 minMintAmount,
        uint256[] calldata amounts
    ) external returns (uint256 wlpAmount);

    /**
     * @notice Remove liquidity from SPA by unwrapping LP tokens first
     * @param spa Address of the SPA contract
     * @param wlp Address of the wrapped LP token contract
     * @param receiver Address to receive the tokens
     * @param wlpAmount Amount of wrapped LP tokens to redeem
     * @param minAmountsOut Minimum amounts of tokens to receive
     * @param proportional If true, withdraws proportionally; if false, uses minAmountsOut
     * @return amounts Array of token amounts received
     */
    function zapOut(
        address spa,
        address wlp,
        address receiver,
        uint256 wlpAmount,
        uint256[] calldata minAmountsOut,
        bool proportional
    ) external returns (uint256[] memory amounts);

    /**
     * @notice Unwrap wLP tokens and redeem a single asset
     * @param spa Address of the SPA contract
     * @param wlp Address of the wrapped LP token contract
     * @param receiver Address to receive the tokens
     * @param wlpAmount Amount of wrapped LP tokens to redeem
     * @param tokenIndex Index of the token to receive
     * @param minAmountOut Minimum amount of token to receive
     * @return amount Amount of token received
     */
    function zapOutSingle(
        address spa,
        address wlp,
        address receiver,
        uint256 wlpAmount,
        uint256 tokenIndex,
        uint256 minAmountOut
    ) external returns (uint256 amount);
}
