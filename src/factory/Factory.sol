// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {OwnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from
    "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/**
 * @title Pike Markets Factory Contract
 * @author NUTS Finance (hello@pike.finance)
 */
contract Factory is UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    struct PToken {
        string name;
        string symbol;
    }

    struct Governor {
        address governorAddress;
    }

    struct ProtocolParams {
        uint256 protocolId;
        address protocolOwner;
        Governor governor;
    }

    mapping(uint256 => ProtocolParams) public protocolRegistry;

    uint256 public protocolCount;

    /**
     * @dev This is the account that has governance control over the protocol.
     */
    address public governance;

    /**
     * @dev Pending governance address,
     */
    address public pendingGovernance;
    /**
     * @dev Beacon for the RiskEngine implementation.
     */
    address public riskEngineBeacon;

    /**
     * @dev Beacon for the OracleEngine implementation.
     */
    address public oracleEngineBeacon;

    /**
     * @dev Beacon for the PToken implementation.
     */
    address public pTokenBeacon;

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

    modifier onlyGovernance() {
        require(msg.sender == governance, "not governance");
        _;
    }

    /**
     * @dev Initializes the Pike Market factory contract.
     */
    function initialize(
        address _governance,
        address _riskEngineBeacon,
        address _oracleEngineBeacon,
        address _pTokenBeacon
    ) public initializer {
        __ReentrancyGuard_init();
        governance = _governance;

        riskEngineBeacon = _riskEngineBeacon;
        oracleEngineBeacon = _oracleEngineBeacon;
        pTokenBeacon = _pTokenBeacon;
    }

    function deployProtocol(Governor memory initialState) external onlyGovernance {}

    function deployPToken(PToken memory initialState) external {}

    /**
     * @dev Propose the govenance address.
     * @param _governance Address of the new governance.
     */
    function proposeGovernance(address _governance) public {
        require(msg.sender == governance, "not governance");
        pendingGovernance = _governance;
        emit GovernanceProposed(_governance);
    }

    /**
     * @dev Accept the govenance address.
     */
    function acceptGovernance() public {
        require(msg.sender == pendingGovernance, "not pending governance");
        governance = pendingGovernance;
        pendingGovernance = address(0);
        emit GovernanceModified(governance);
    }

    /**
     * @notice Authorize upgrade
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyGovernance
    {}
}
