# Audit Scope and Security Assumptions

## Contracts Overview

The following contracts are within the scope for audit. The project follows a modular design, leveraging upgradeable contracts with specific responsibilities.

### Core Contracts

#### Local Markets

**Errors** The following libraries define custom error messages used in local markets:

- `CommonError.sol`
- `IRMError.sol`
- `PTokenError.sol`
- `RiskEngineError.sol`

**Interfaces** These interfaces define the interactions with the system’s modules:

- `IDoubleJumpRateModel.sol`
- `IInterestRateModel.sol`
- `IOwnable.sol`
- `IPToken.sol`
- `IRiskEngine.sol`
- `IRBAC.sol`
- `IUpgrade.sol`

**Modules** handling core logic and business rules:

- `InitialModuleBundle.sol` **Description**: This is the initial module responsible for managing minimal access control and the system’s ability to upgrade (UUPS) implementations. Due to how Cannon handles deployments and upgrades, this module is first deployed independently and then used to call upgrades via the Cannon package. If the bytecode of implementation change, Cannon will handle the upgrade automatically to ensure the deployment reflects the latest version. This rerun of the upgrade process ensures consistent deployments with minimal overhead.
- `OwnableModule.sol`
- `RBACModule.sol`
- `UpgradeModule.sol`
- `DoubleJumpRateModel.sol` **Description**: Implements the DoubleJumpRate interest model with two kinks and three ranges of utilization (Encourage, Normal, Discourage).
- `PTokenModule.sol` **Description**: Represents the logic for the protocol’s pToken markets, which users interact with to supply, borrow, and redeem assets.
- `RiskEngineModule.sol` **Description**: Enforces risk management by controlling borrow and collateral parameters.

**Storage** These contracts store the state variables and manage storage layout for the modules:

- `DoubleJumpRateStorage.sol`
- `OwnableStorage.sol`
- `PTokenStorage.sol`
- `RBACStorage.sol`
- `RiskEngineStorage.sol`
- `UpgradeStorage.sol`

**Utilities** Utility contracts for mathematical operations and mixin:

- `ExponentialNoError.sol` **Description**: This contract is directly sourced from Compound v2 and handles safe mathematical operations such as exponentiation without errors. No changes have been made to the original Compound v2 implementation to ensure reliability.
- `RBACMixin.sol`
- `OwnableMixin.sol`
  **Description**: Mixins allow different modules to know specific storage layout and how to read it and it shares between those.

#### Oracle Contracts

**Oracles**

-`ChainlinkOracleProvider.sol`

- `PythOracleProvider.sol`

- `OracleEngine.sol`

- Interfaces:
  - `IOracleEngine.sol`
  - `IOracleProvider.sol`

**Deployment and Upgrade Mechanism**:
Unlike other parts of the system, the oracle providers do not follow the router proxy design. Instead, they utilize the standard UUPS proxy pattern for upgrades.

## System Architecture

The project is designed with two main router modules:

1. **PToken Router**: PTokenModule, InterestRateModel, InitialModuleBundle, RBACModule
2. **RiskEngine Router**: RiskEngineModule, InitialModuleBundle, RBACModule

These modules use the router pattern to manage upgrades and core business logic.

**Oracle Contracts**:
The oracle system is independent of the router proxy architecture and instead uses the regular UUPS proxy design to enable upgrades as needed.

## Security Assumptions

The following security assumptions have been considered in the design of the protocol:

1. **Inflation Attack Mitigation**: We assume that pToken markets will not have an empty liquidity state to prevent potential inflation attacks. However to mitigate this risk, the `redeemUnderlying` function includes a double-check mechanism on the exchangeRate to prevent high amounts of `redeemAmount` being processed in an empty market scenario.

2. **Access Control**: The system relies on the `RBACModule` and `OwnableModule` for managing access control, ensuring only authorized users can trigger upgrades or sensitive operations.

3. **Upgradability**: The system’s deployment mechanism, managed through Cannon, ensures that upgrades (config) only happen when necessary (i.e., when bytecode or arguments change). The initial module deployment guarantees a clean start for upgrades, preventing redeployment unless specific criteria are met.
