// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IV3SwapRouter} from "swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@mocks/MockToken.sol";

// MockSPA
contract MockSPA {
    address[] public tokens;

    constructor(address[] memory _tokens) {
        tokens = _tokens;
    }

    function swap(uint256 i, uint256 j, uint256 amountIn, uint256)
        external
        returns (uint256)
    {
        MockToken(tokens[i]).transferFrom(msg.sender, address(this), amountIn);
        MockToken(tokens[j]).mint(msg.sender, amountIn);
    }

    function getTokens() external view returns (address[] memory) {
        return tokens;
    }
}

// MockZapContract
contract MockZapContract {
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function zapIn(
        address spa,
        address lpToken,
        address recipient,
        uint256 minAmountOut,
        uint256[] memory amounts
    ) external returns (uint256) {
        address[] memory tokens = MockSPA(spa).getTokens();
        require(tokens.length == 2 && amounts.length == 2, "Invalid input");
        uint256 lpAmount = min(amounts[0], amounts[1]);
        for (uint256 i = 0; i < 2; i++) {
            IERC20(tokens[i]).transferFrom(msg.sender, address(this), amounts[i]);
        }
        MockToken(lpToken).mint(recipient, lpAmount);
        return lpAmount;
    }

    function zapOut(
        address spa,
        address lpToken,
        address recipient,
        uint256 amount,
        uint256[] memory minAmountsOut,
        bool proportional
    ) external returns (uint256[] memory) {
        address[] memory tokens = MockSPA(spa).getTokens();
        require(tokens.length == 2, "Invalid SPA");
        MockToken(lpToken).transferFrom(msg.sender, address(this), amount);
        uint256[] memory amounts = new uint256[](2);
        for (uint256 i = 0; i < 2; i++) {
            amounts[i] = amount / 2;
            IERC20(tokens[i]).transfer(recipient, amounts[i]);
        }
        return amounts;
    }
}

// MockUniswapV3Pool
contract MockUniswapV3Pool {
    address public immutable token0;
    address public immutable token1;
    uint256 public constant FLASH_FEE = 0;
    uint256 public constant SWAP_FEE = 0;

    constructor(address _token0, address _token1) {
        token0 = _token0;
        token1 = _token1;
    }

    function flash(
        address recipient,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external {
        uint256 fee0 = amount0 * FLASH_FEE / 1_000_000;
        uint256 fee1 = amount1 * FLASH_FEE / 1_000_000;

        if (amount0 > 0) MockToken(token0).mint(recipient, amount0);
        if (amount1 > 0) MockToken(token1).mint(recipient, amount1);

        IUniswapV3FlashCallback(msg.sender).uniswapV3FlashCallback(fee0, fee1, data);

        uint256 balance0After = IERC20(token0).balanceOf(address(this));
        uint256 balance1After = IERC20(token1).balanceOf(address(this));
        require(balance0After >= fee0, "Insufficient token0 repayment");
        require(balance1After >= fee1, "Insufficient token1 repayment");
    }

    function exactInputSingle(IV3SwapRouter.ExactInputSingleParams calldata params)
        external
        returns (uint256)
    {
        bool isToken0ToToken1 = params.tokenIn == token0 && params.tokenOut == token1;
        bool isToken1ToToken0 = params.tokenIn == token1 && params.tokenOut == token0;
        require(isToken0ToToken1 || isToken1ToToken0, "Invalid token pair");

        uint256 amountOutBeforeFee = params.amountIn; // 1:1
        uint256 fee = (amountOutBeforeFee * SWAP_FEE) / 1_000_000;
        uint256 amountOut = amountOutBeforeFee - fee;

        require(amountOut >= params.amountOutMinimum, "Insufficient output");
        IERC20(params.tokenIn).transferFrom(msg.sender, address(this), params.amountIn);
        MockToken(params.tokenOut).mint(params.recipient, amountOut);
        return amountOut;
    }
}

// MockRiskEngine
contract MockRiskEngine {
    function delegateAllowed(address, address) external pure returns (bool) {
        return true;
    }
}

interface IUniswapV3FlashCallback {
    function uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes calldata data)
        external;
}
