// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

contract TestStructs {
    struct ActionParameters {
        Action action;
        address pToken;
        address tokenAddress;
        uint256 amount;
        bool expectRevert;
        bytes4 error;
        address prankAddress;
        address onBehalfOf;
    }

    struct ActionStateData {
        PTokenData pTokenData;
        UserData userData;
    }

    struct PTokenData {
        uint256 totalCash;
        uint256 totalBorrow;
        uint256 totalReserve;
        uint256 totalSupply;
    }

    struct UserData {
        uint256 underlyingBalance;
        uint256 collateral;
        uint256 borrowed;
    }

    enum Action {
        SUPPLY,
        WITHDRAW,
        BORROW,
        REPAY,
        LIQUIDATE
    }
}
