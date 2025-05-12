// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IFLHelper {
    // Flash loan source enum
    enum FlashLoanSource {
        NONE,
        UNISWAP_V3,
        AAVE_V3,
        BALANCER,
        MORPHO_BLUE
    }

    // Parameter structure for flash loans
    struct FlashLoanParams {
        FlashLoanSource source;
        address[] tokens;
        uint256[] amounts;
    }

    // Event emitted when a flash loan is executed
    event FLExecuted(FlashLoanParams params, bytes recipeData);

    /**
     * @notice Callback for Aave V3 flash loans
     * @param assets The addresses of the assets being flash-borrowed
     * @param amounts The amounts of the assets being flash-borrowed
     * @param premiums The fees for the flash loan
     * @param initiator The address initiating the flash loan
     * @param params Additional data passed to the callback
     * @return True if the operation was successful
     */
    function executeOperation(
        address[] memory assets,
        uint256[] memory amounts,
        uint256[] memory premiums,
        address initiator,
        bytes memory params
    ) external returns (bool);

    /**
     * @notice Callback for Balancer flash loans
     * @param tokens The addresses of the tokens being flash-borrowed
     * @param amounts The amounts of the tokens being flash-borrowed
     * @param feeAmounts The fees for the flash loan
     * @param userData Additional data passed to the callback
     */
    function receiveFlashLoan(
        address[] memory tokens,
        uint256[] memory amounts,
        uint256[] memory feeAmounts,
        bytes memory userData
    ) external;

    /**
     * @notice Callback for Uniswap V3 flash loans
     * @param fee0 The fee for token0
     * @param fee1 The fee for token1
     * @param data Additional data passed to the callback
     */
    function uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes memory data)
        external;

    /**
     * @notice Callback for Morpho Blue flash loans
     * @param assets The amount of assets being flash-borrowed
     * @param data Additional data passed to the callback
     */
    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external;
}
