// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {
    SafeERC20, IERC20
} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    IFlashLoans,
    ILendingPoolV2,
    IUniswapV3Factory,
    IMorphoBlue,
    IUniswapV3Pool
} from "@periphery/interfaces/IProtocols.sol";
import {IFLHelper} from "@periphery/interfaces/IFLHelper.sol";

/**
 * @title FlashLoanHelper
 * @notice Abstract contract providing flashloan functionality from multiple sources
 * @dev To be extended by specific use case contracts like LiquidationHelper
 */
abstract contract FLHelper is IFLHelper {
    using SafeERC20 for IERC20;

    // Protocol addresses
    address public immutable UNI_V3_FACTORY;
    address public immutable AAVE_V3_LENDING_POOL;
    address public immutable AAVE_V2_LENDING_POOL;
    address public immutable BALANCER_VAULT;
    address public immutable MORPHO_BLUE_ADDR;

    uint16 public constant AAVE_REFERRAL_CODE = 0;

    // Error declarations
    error UntrustedLender();
    error UntrustedInitiator();
    error InvalidFlashLoanSource();
    error WrongPaybackAmount();
    error InvalidArray();

    constructor(
        address _uniV3Factory,
        address _aaveV3LendingPool,
        address _aaveV2LendingPool,
        address _balancerVault,
        address _morphoBlue
    ) {
        UNI_V3_FACTORY = _uniV3Factory;
        AAVE_V3_LENDING_POOL = _aaveV3LendingPool;
        AAVE_V2_LENDING_POOL = _aaveV2LendingPool;
        BALANCER_VAULT = _balancerVault;
        MORPHO_BLUE_ADDR = _morphoBlue;
    }

    /**
     * @notice Callback for Aave V2/V3 flash loans
     * @dev Must be implemented by child contracts
     */
    function executeOperation(
        address[] memory assets,
        uint256[] memory amounts,
        uint256[] memory premiums,
        address initiator,
        bytes memory params
    ) external virtual returns (bool);

    /**
     * @notice Callback for Balancer flash loans
     * @dev Must be implemented by child contracts
     */
    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external virtual;

    /**
     * @notice Callback for Uniswap V3 flash loans
     * @dev Must be implemented by child contracts
     */
    function uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes memory data)
        external
        virtual;

    /**
     * @notice Callback for Morpho flash loans
     * @dev Must be implemented by child contracts
     */
    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external virtual;

    /**
     * @notice Execute a flash loan from the selected source
     * @param _params Flash loan parameters
     */
    function executeFlashLoan(FlashLoanParams memory _params, bytes memory _recipeData)
        internal
    {
        if (_params.source == FlashLoanSource.UNISWAP_V3) {
            _executeUniV3FlashLoan(_params, _recipeData);
        } else if (_params.source == FlashLoanSource.AAVE_V3) {
            _executeAaveV3FlashLoan(_params, _recipeData);
        } else if (_params.source == FlashLoanSource.AAVE_V2) {
            _executeAaveV2FlashLoan(_params, _recipeData);
        } else if (_params.source == FlashLoanSource.BALANCER) {
            _executeBalancerFlashLoan(_params, _recipeData);
        } else if (_params.source == FlashLoanSource.MORPHO_BLUE) {
            _executeMorphoFlashLoan(_params, _recipeData);
        } else {
            revert InvalidFlashLoanSource();
        }

        emit FLExecuted(_params, _recipeData);
    }

    /**
     * @notice Approves tokens for repayment
     * @param token Token to approve
     * @param spender Address to approve
     * @param amount Amount to approve
     */
    function approveToken(address token, address spender, uint256 amount) internal {
        IERC20(token).forceApprove(spender, amount);
    }

    /**
     * @notice Transfers tokens from this contract
     * @param token Token to transfer
     * @param to Recipient address
     * @param amount Amount to transfer
     */
    function transferToken(address token, address to, uint256 amount) internal {
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @notice Verifies that the caller is a valid Uniswap V3 pool
     * @param caller The address of the caller
     * @param token0 First token in the pool
     * @param token1 Second token in the pool
     * @param fee The pool fee
     */
    function verifyUniswapV3Callback(
        address caller,
        address token0,
        address token1,
        uint24 fee
    ) internal view {
        address pool = IUniswapV3Factory(UNI_V3_FACTORY).getPool(token0, token1, fee);
        if (caller != pool) revert UntrustedLender();
    }

    /**
     * @notice Gets the balance of a token for this contract
     * @param token Token to check
     * @return Balance of the token
     */
    function getBalance(address token) internal view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /**
     * @notice Utility function to verify the correct amount is paid back
     * @param token Token to check
     * @param balanceBefore Balance before the operation
     * @param amountToPayBack Amount that should be paid back
     */
    function verifyPayback(address token, uint256 balanceBefore, uint256 amountToPayBack)
        internal
        view
    {
        if (getBalance(token) < balanceBefore + amountToPayBack) {
            revert WrongPaybackAmount();
        }
    }

    /**
     * @notice Verifies that the caller is the Aave V3 and Aave V2 lending pool
     * @param caller The address of the caller
     */
    function verifyAaveCallback(address caller, address initiator) internal view {
        if (caller != AAVE_V3_LENDING_POOL || caller != AAVE_V2_LENDING_POOL) {
            revert UntrustedLender();
        }
        if (initiator != address(this)) revert UntrustedInitiator();
    }

    /**
     * @notice Verifies that the caller is the Balancer vault
     * @param caller The address of the caller
     */
    function verifyBalancerCallback(address caller) internal view {
        if (caller != BALANCER_VAULT) revert UntrustedLender();
    }

    /**
     * @notice Verifies that the caller is Morpho Blue
     * @param caller The address of the caller
     */
    function verifyMorphoBlueCallback(address caller) internal view {
        if (caller != MORPHO_BLUE_ADDR) revert UntrustedLender();
    }

    /**
     * @notice Execute a flash loan from Aave V2
     * @param _params Flash loan parameters
     */
    function _executeAaveV2FlashLoan(
        FlashLoanParams memory _params,
        bytes memory _recipeData
    ) private {
        // it should repay the loan in same transaction
        uint256[] memory modes = new uint256[](_params.tokens.length);

        ILendingPoolV2(AAVE_V2_LENDING_POOL).flashLoan(
            address(this),
            _params.tokens,
            _params.amounts,
            modes,
            address(this),
            _recipeData,
            AAVE_REFERRAL_CODE
        );
    }

    /**
     * @notice Execute a flash loan from Aave V3
     * @param _params Flash loan parameters
     */
    function _executeAaveV3FlashLoan(
        FlashLoanParams memory _params,
        bytes memory _recipeData
    ) private {
        // it should repay the loan in same transaction
        uint256[] memory modes = new uint256[](_params.tokens.length);

        ILendingPoolV2(AAVE_V3_LENDING_POOL).flashLoan(
            address(this),
            _params.tokens,
            _params.amounts,
            modes,
            address(this),
            _recipeData,
            AAVE_REFERRAL_CODE
        );
    }

    /**
     * @notice Execute a flash loan from Balancer
     * @param _params Flash loan parameters
     */
    function _executeBalancerFlashLoan(
        FlashLoanParams memory _params,
        bytes memory _recipeData
    ) private {
        IFlashLoans(BALANCER_VAULT).flashLoan(
            address(this), _params.tokens, _params.amounts, _recipeData
        );
    }

    /**
     * @notice Execute a flash loan from Balancer
     * @param _params Flash loan parameters
     */
    function _executeMorphoFlashLoan(
        FlashLoanParams memory _params,
        bytes memory _recipeData
    ) private {
        IMorphoBlue(MORPHO_BLUE_ADDR).flashLoan(
            _params.tokens[0],
            _params.amounts[0],
            abi.encode(_recipeData, _params.tokens[0])
        );
    }

    /**
     * @notice Execute a flash loan from Uniswap V3
     * @param _params Flash loan parameters
     */
    function _executeUniV3FlashLoan(
        FlashLoanParams memory _params,
        bytes memory _recipeData
    ) private {
        require(_params.tokens.length >= 3, InvalidArray());

        address poolAddress = _params.tokens[2]; // Third token is the pool address

        IUniswapV3Pool(poolAddress).flash(
            address(this), _params.amounts[0], _params.amounts[1], _recipeData
        );
    }
}
