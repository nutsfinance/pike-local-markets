// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IFactory {
    struct PTokenSetup {
        uint256 protocolId;
        address underlying;
        uint256 initialExchangeRateMantissa;
        uint256 reserveFactorMantissa;
        uint256 protocolSeizeShareMantissa;
        uint256 borrowRateMaxMantissa;
        string name;
        string symbol;
        uint8 decimals;
    }

    struct ProtocolInfo {
        uint256 protocolId;
        uint256 numOfMarkets;
        address protocolOwner;
        address initialGovernor;
        address riskEngine;
        address oracleEngine;
        address timelock;
    }

    /**
     * @dev Emitted when a new protocol is deployed.
     * @param protocolId Unique identifier for the deployed protocol.
     * @param riskEngine Address of the deployed Risk Engine contract for the protocol.
     * @param timelock Address of the deployed Timelock contract responsible to
     * deploy new pTokens and configure market parameters.
     * @param initialGovernor Address of the governor for the deployed timelock.
     */
    event ProtocolDeployed(
        uint256 indexed protocolId,
        address indexed riskEngine,
        address indexed timelock,
        address initialGovernor
    );

    /**
     * @dev Emitted when a new PToken is successfully deployed for a protocol.
     * @param protocolId Unique identifier of the protocol associated with the PToken.
     * @param index The index of the PToken within the protocol to track.
     * @param pToken Address of the deployed PToken proxy.
     * @param timelock Address of the Timelock contract assigned as pToken configurator.
     */
    event PTokenDeployed(
        uint256 indexed protocolId,
        uint256 indexed index,
        address indexed pToken,
        address timelock
    );

    /// revert when caller is not assigned timelock contract
    error InvalidTimelock();

    /**
     * @dev The function is called by protocol owner governance to deploy new protocol
     * @dev Deploys a new risk/oracle engine with protocol owner as default owner
     * @dev Deploys a new timelock and set governor as default admin and set
     * access on timelock to manage risk engine in order to modify markets
     * @param governor address of governor that is set as admin of timelock contract
     */
    function deployProtocol(address governor)
        external
        returns (address riskEngine, address oracleEngine, address governorTimelock);

    /**
     * @dev Deploys a new pToken for the deployed protocol
     * and connects it to protocol risk engine
     * @dev Inititalize the pToken with given risk parameters
     * @dev Protocol owner will be the default owner of pToken
     * @dev assigned timelock will be the core configurator of pToken
     * @param setupParams struct with initial risk params of pToken
     * @return pToken address of deployed proxy contract
     */
    function deployPToken(PTokenSetup memory setupParams)
        external
        returns (address pToken);
}
