// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IFactory {
    struct PToken {
        uint256 protocolId;
        string name;
        string symbol;
    }

    struct Governor {
        address governorAddress;
    }

    struct ProtocolInfo {
        uint256 protocolId;
        address protocolOwner;
        Governor governor;
    }

    /**
     * @dev This event is emitted when the governance is modified.
     * @param governance is the new value of the governance.
     */
    event GovernanceModified(address governance);

    /**
     * @dev This event is emitted when the governance is modified.
     * @param governance is the new value of the governance.
     */
    event GovernanceProposed(address governance);

    /// revert when caller is not governor address
    error InvalidGovernor();

    /**
     * @dev The function is called by protocol owner governance to deploy new protocol
     * @dev Deploys a new risk engine and oracle engine both with protocol owner s default owner
     * @dev set Governor access on risk engine in order to modify markets
     * @param initialState struct has required addresses to config that access control
     */
    function deployProtocol(Governor memory initialState) external;

    /**
     * @dev Deploys a new pToken for the deployed protocol by Governor access
     * and connects it to protocol risk engine
     * @dev Inititalize the pToken with given risk parameters
     * @dev Protocol owner will be the default owner of pToken
     * @param initialState struct with initial risk params of pToken
     */
    function deployPToken(PToken memory initialState) external;
}
