// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {console} from "forge-std/console.sol";

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
        uint256,
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
            MockToken(tokens[i]).mint(recipient, amounts[i]);
        }
        return amounts;
    }
}

// MockRiskEngine
contract MockRiskEngine {
    function delegateAllowed(address, address) external pure returns (bool) {
        return true;
    }
}

/**
 * @title MockUniswapV3Pool
 * @notice Mock of UniswapV3Pool with flashloan and swap functionality for testing
 */
contract MockUniswapV3Pool is Ownable {
    address public immutable token0;
    address public immutable token1;
    uint256 private constant Q96 = 2 ** 96;
    uint256 public constant FLASH_FEE = 500; // 0.05% fee (5 bps)
    uint256 public constant SWAP_FEE = 3000; // 0.3% fee (30 bps)

    // Mock slot0 data
    uint160 public sqrtPriceX96 = uint160(Q96 * 1); // Initial price of 1:1

    uint256 public token0Price = 1e18;
    uint256 public token1Price = 1e18;

    constructor(address _token0, address _token1) Ownable(msg.sender) {
        token0 = _token0;
        token1 = _token1;
    }

    function setPrices(uint256 _token0Price, uint256 _token1Price) external onlyOwner {
        require(_token0Price > 0 && _token1Price > 0, "Prices must be positive");
        token0Price = _token0Price;
        token1Price = _token1Price;
    }

    function transferTokensOwnership(address newOwner) external onlyOwner {
        MockTestToken(token0).transferOwnership(newOwner);
        MockTestToken(token1).transferOwnership(newOwner);
    }

    function sqrt(uint256 y) internal pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata,
        address,
        bytes calldata params,
        uint16
    ) external {
        require(assets.length == amounts.length, "Mismatched assets and amounts");

        uint256[] memory premiums = new uint256[](assets.length);
        uint256[] memory balancesBefore = new uint256[](assets.length);

        for (uint256 i = 0; i < assets.length; i++) {
            premiums[i] = (amounts[i] * FLASH_FEE) / 1_000_000;
            MockToken(assets[i]).mint(receiverAddress, amounts[i]);
        }

        require(
            IAaveFlashLoanReceiver(receiverAddress).executeOperation(
                assets, amounts, premiums, msg.sender, params
            ),
            "MockAavePool: executeOperation failed"
        );

        for (uint256 i = 0; i < assets.length; i++) {
            uint256 balanceAfter = IERC20(assets[i]).balanceOf(address(this));
            uint256 expected = amounts[i] + premiums[i];
            require(balanceAfter >= expected, "MockAavePool: not enough returned");
        }
    }

    function flash(
        address recipient,
        uint256 amount0,
        uint256 amount1,
        bytes calldata data
    ) external {
        uint256 fee0 = amount0 * FLASH_FEE / 1_000_000;
        uint256 fee1 = amount1 * FLASH_FEE / 1_000_000;

        uint256 balance0Before = IERC20(token0).balanceOf(address(this));
        uint256 balance1Before = IERC20(token1).balanceOf(address(this));

        // Mint tokens to recipient to simulate the flash loan
        if (amount0 > 0) {
            MockToken(token0).mint(recipient, amount0);
        }

        if (amount1 > 0) {
            MockToken(token1).mint(recipient, amount1);
        }

        // Call the callback expecting the repayment
        IUniswapV3FlashCallback(msg.sender).uniswapV3FlashCallback(
            uint256(fee0), uint256(fee1), data
        );

        // Verify repayment
        uint256 balance0After = IERC20(token0).balanceOf(address(this));
        uint256 balance1After = IERC20(token1).balanceOf(address(this));

        require(
            balance0After >= balance0Before + fee0,
            "MockUniswapV3Pool: not enough token0 returned"
        );
        require(
            balance1After >= balance1Before + fee1,
            "MockUniswapV3Pool: not enough token1 returned"
        );
    }

    function exactInputSingle(IV3SwapRouter.ExactInputSingleParams calldata params)
        external
        returns (uint256 amountOut)
    {
        bool isToken0ToToken1 = params.tokenIn == token0 && params.tokenOut == token1;
        bool isToken1ToToken0 = params.tokenIn == token1 && params.tokenOut == token0;

        require(
            isToken0ToToken1 || isToken1ToToken0, "MockUniswapV3Pool: invalid token pair"
        );

        // Calculate amount out based on price ratio
        uint256 tokenInPrice = isToken0ToToken1 ? token0Price : token1Price;
        uint256 tokenOutPrice = isToken0ToToken1 ? token1Price : token0Price;
        uint256 amountOutBeforeFee = (params.amountIn * tokenInPrice) / tokenOutPrice;
        uint256 fee = (amountOutBeforeFee * SWAP_FEE) / 1_000_000;
        amountOut = amountOutBeforeFee - fee;

        require(
            amountOut >= params.amountOutMinimum,
            "MockUniswapV3Pool: insufficient output amount"
        );

        // Transfer input token from sender to this contract
        require(
            IERC20(params.tokenIn).transferFrom(
                msg.sender, address(this), params.amountIn
            ),
            "MockUniswapV3Pool: transfer failed"
        );

        // Mint output token to recipient
        MockToken(params.tokenOut).mint(params.recipient, amountOut);

        int256 amount0;
        int256 amount1;

        if (isToken0ToToken1) {
            amount0 = int256(params.amountIn);
            amount1 = -int256(amountOut);
        } else {
            amount0 = -int256(amountOut);
            amount1 = int256(params.amountIn);
        }

        return amountOut;
    }

    function getPool(address, address, uint24) external view returns (address) {
        return address(this);
    }
}

interface IAaveFlashLoanReceiver {
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

interface IUniswapV3FlashCallback {
    function uniswapV3FlashCallback(uint256 fee0, uint256 fee1, bytes calldata data)
        external;
}
