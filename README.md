![Endpoint Badge](https://img.shields.io/endpoint?url=https%3A%2F%2Fgist.githubusercontent.com%2Fzakrad%2F76be8eb437f8ba3a2f6b2ee5b7de9eb9%2Fraw%2FPike_local_market_line_coverage.json&style=flat-square) ![Static Badge](https://img.shields.io/badge/Built_with-Foundry-yellow?style=flat-square) ![Static Badge](https://img.shields.io/badge/License-MIT-blue?style=flat-square)

# Pike Local Market Protocol

Local Market is a decentralized lending and borrowing protocol built for EVMs, designed to provide a secure, scalable, and flexible environment for users to manage their digital assets. It allows users to supply assets to earn yield or borrow against collateralized assets through the pToken contracts.

## Overview

In Local Market, users can:

- **Supply** ERC-20 tokens to the protocol to receive pTokens (interest bearing tokens).
- **Borrow** assets by using pTokens as collateral.
- **Repay** loans or **redeem** their supplied assets at any time, with interest rates dynamically set based on market demand and utilization rate.
- **Liquidate** undercollateralized positions by repaying part of a borrower’s debt in exchange for a portion of their collateral with incentives.

The protocol is built using modular, upgradeable components following the [router proxy](https://github.com/Synthetixio/synthetix-router) pattern (static diamond proxy) and is based on a fork of [Compound v2](https://github.com/compound-finance/compound-protocol). This design ensuring the system can adapt and scale with evolving protocol requirements.

![Oracle System Diagram](https://i.imgur.com/jF3vkwv.jpeg)

## Contracts

Local Market uses several core contracts to facilitate lending and borrowing:

### pToken (pERC20)

The pToken module for managing supplied and borrowed assets. Each pToken (e.g., pUSDC, pWETH) represents a user’s stake in a lending market, and users interact with these contracts to supply and withdraw assets, or borrow and repay loans.

- **Mint**: Supply an asset to the protocol and receive pTokens in return.
- **Redeem**: Exchange pTokens back for the underlying asset.
- **Borrow**: Borrow assets against your supplied collateral.
- **Repay**: Repay borrowed assets to reclaim your collateral.

### InterestRateModel

This module dynamically adjusts interest rates for borrowers based on the utilization rate of each market.

### RiskEngine

Responsible for risk management, analogous to the Comptroller, validates permissible user actions and prevents those that fail to meet specific risk parameters. It safeguards the system against undercollateralization by ensuring that each borrower maintains a sufficient collateral balance across all pTokens,.

### OracleEngine

The OracleEngine aggregates real-time asset price data from various sources using OracleProviders. Accurate price feeds are essential for determining borrowing limits and triggering liquidations when necessary.

### OracleProvider

The OracleProvider is responsible for retrieving price data from specific external sources. Each provider implements its own logic for fetching and managing this data, which is then supplied to the OracleEngine to ensure accurate pricing across the platform.

### Installation

To run the Pike Local Market, clone the repository and install the necessary dependencies. Ensure you have [yarn](https://yarnpkg.com/lang/en/docs/install/) or [npm](https://docs.npmjs.com/cli/install) installed.

```bash
$ git clone https://github.com/nutsfinance/pike-local-markets.git
$ cd pike-local-markets
$ yarn install --lock-file # or `npm install`
```

### Build

```bash
yarn build
```

### Test

```bash
yarn test
```

## Code Coverage

```bash
yarn test:coverage
```

## Running Linters

```bash
yarn lint:check
```

## Deployment

For deployments we utilize [Cannon](https://usecannon.com/), a DevOps tool for protocols on EVMs. Cannon simplifies the deployment and upgrade processes, making it easier to manage our contracts.

- Build on base sepolia

```bash
yarn deploy:testnet # or dryrun before `yarn deploy:testnet:dryrun`
```

### Scope

```bash
Contracts
│   ├── local-market
│   │   ├── errors
│   │   │   ├── CommonError.sol
│   │   │   ├── IRMError.sol
│   │   │   ├── PTokenError.sol
│   │   │   └── RiskEngineError.sol
│   │   ├── interfaces
│   │   │   ├── IInterestRateModel.sol
│   │   │   ├── IDoubleJumpRateModel.sol
│   │   │   ├── IOwnable.sol
│   │   │   ├── IPToken.sol
│   │   │   ├── IRBAC.sol
│   │   │   ├── IRiskEngine.sol
│   │   │   └── IUpgrade.sol
│   │   ├── modules
│   │   │   ├── InitialModuleBundle.sol
│   │   │   ├── common
│   │   │   │   ├── OwnableModule.sol
│   │   │   │   ├── RBACModule.sol
│   │   │   │   └── UpgradeModule.sol
│   │   │   ├── interestRateModel
│   │   │   │   └── DoubleJumpRateModel.sol
│   │   │   ├── pToken
│   │   │   │   └── PTokenModule.sol
│   │   │   └── riskEngine
│   │   │       └── RiskEngineModule.sol
│   │   ├── storage
│   │   │   ├── DoubleJumpRateStorage.sol
│   │   │   ├── OwnableStorage.sol
│   │   │   ├── PTokenStorage.sol
│   │   │   ├── RBACStorage.sol
│   │   │   ├── RiskEngineStorage.sol
│   │   │   ├── UpgradeStorage.sol
│   │   └── utils
│   │       ├── ExponentialNoError.sol
│   │       ├── OwnableMixin.sol
│   │       └── RBACMixin.sol
└── └── oracles
        ├── ChainlinkOracleProvider.sol
        ├── OracleEngine.sol
        ├── PythOracleProvider.sol
        └── interfaces
            ├── IOracleEngine.sol
            └── IOracleProvider.sol
```
