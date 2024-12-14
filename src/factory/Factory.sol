// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {OwnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from
    "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IFactory} from "@factory/interfaces/IFactory.sol";

/**
 * @title Pike Markets Factory Contract
 * @author NUTS Finance (hello@pike.finance)
 */
contract Factory is
    IFactory,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    struct FactoryStorage {
        uint256 protocolCount;
        /**
         * @dev This is the account that has governance control over the protocol.
         */
        address governance;
        /**
         * @dev Pending governance address,
         */
        address pendingGovernance;
        /**
         * @dev Beacon for the RiskEngine implementation.
         */
        address riskEngineBeacon;
        /**
         * @dev Beacon for the OracleEngine implementation.
         */
        address oracleEngineBeacon;
        /**
         * @dev Beacon for the PToken implementation.
         */
        address pTokenBeacon;
        /**
         * @dev mapping protocol id -> info
         */
        mapping(uint256 => ProtocolInfo) protocolRegistry;
    }

    /// keccak256(abi.encode(uint256(keccak256("pike.facotry")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _FACTORY_STORAGE =
        0xac42ae8baafcf09ffeb99e08f7111e43bf0a7cdbccbc7a91974415e2c3c2d700;

    modifier onlyGovernance() {
        require(msg.sender == _getFactoryStorage().governance, "not governance");
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
        FactoryStorage storage $ = _getFactoryStorage();
        $.governance = _governance;

        $.riskEngineBeacon = _riskEngineBeacon;
        $.oracleEngineBeacon = _oracleEngineBeacon;
        $.pTokenBeacon = _pTokenBeacon;
    }

    /**
     * @inheritdoc IFactory
     */
    function deployProtocol(Governor memory initialState) external onlyGovernance {}

    /**
     * @inheritdoc IFactory
     */
    function deployPToken(PToken memory initialState) external {
        if (
            msg.sender
                != _getFactoryStorage().protocolRegistry[initialState.protocolId]
                    .governor
                    .governorAddress
        ) {
            revert InvalidGovernor();
        }
    }

    /**
     * @dev Propose the govenance address.
     * @param _governance Address of the new governance.
     */
    function proposeGovernance(address _governance) public {
        require(msg.sender == _getFactoryStorage().governance, "not governance");
        _getFactoryStorage().pendingGovernance = _governance;
        emit GovernanceProposed(_governance);
    }

    /**
     * @dev Accept the govenance address.
     */
    function acceptGovernance() public {
        FactoryStorage storage $ = _getFactoryStorage();
        require(msg.sender == $.pendingGovernance, "not pending governance");
        $.governance = $.pendingGovernance;
        $.pendingGovernance = address(0);
        emit GovernanceModified($.governance);
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

    function _getFactoryStorage() internal pure returns (FactoryStorage storage data) {
        bytes32 s = _FACTORY_STORAGE;
        assembly {
            data.slot := s
        }
    }
}
