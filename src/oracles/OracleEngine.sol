//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IPToken} from "@interfaces/IPToken.sol";
import {IOracleEngine} from "@oracles/interfaces/IOracleEngine.sol";
import {IOracleProvider} from "@oracles/interfaces/IOracleProvider.sol";
import {OwnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from
    "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract OracleEngine is IOracleEngine, UUPSUpgradeable, OwnableUpgradeable {
    struct AssetConfig {
        /**
         * @notice Main oracle address for the asset
         */
        address mainOracle;
        /**
         * @notice Fallback oracle address for the asset
         */
        address fallbackOracle;
        /**
         * @notice Lower bound ratio for the main oracle price to be considered valid
         * @dev Scaled by 1e18 i.e., 1e18 = 1
         */
        uint256 lowerBoundRatio;
        /**
         * @notice Upper bound ratio for the main oracle price to be considered valid
         * @dev Scaled by 1e18 i.e., 1e18 = 1
         */
        uint256 upperBoundRatio;
    }

    /**
     * @notice Mapping of asset address to its configuration
     */
    mapping(address => AssetConfig) public configs;

    /**
     * @notice Event emitted when asset configuration is set
     */
    event AssetConfigSet(
        address indexed asset,
        address mainOracle,
        address fallbackOracle,
        uint256 lowerBoundRatio,
        uint256 upperBoundRatio
    );

    /**
     * @notice Error emitted when bounds are invalid
     */
    error InvalidBounds();

    /**
     * @notice Error emitted when main oracle is invalid
     */
    error InvalidMainOracle();

    /**
     * @notice Error emitted when asset is invalid
     */
    error InvalidAsset();

    /**
     * @notice Error emitted when bounds validation fails
     */
    error BoundValidationFailed();

    /**
     * @notice Error emitted when fallback oracle is invalid
     */
    error InvalidFallbackOraclePrice();

    /**
     * @notice Error emitted when main oracle price is invalid
     */
    error InvalidMainOraclePrice();

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @param owner Address of the owner
     */
    function initialize(address owner) public initializer {
        __Ownable_init(owner);
    }

    /**
     * @notice Set asset configuration
     * @param asset Address of the asset
     * @param mainOracle Address of the main oracle
     * @param fallbackOracle Address of the fallback oracle
     * @param lowerBoundRatio Lower bound ratio for the main oracle price to be considered valid
     * @param upperBoundRatio Upper bound ratio for the main oracle price to be considered valid
     */
    function setAssetConfig(
        address asset,
        address mainOracle,
        address fallbackOracle,
        uint256 lowerBoundRatio,
        uint256 upperBoundRatio
    ) external onlyOwner {
        if (
            (lowerBoundRatio != 0 && upperBoundRatio != 0)
                && lowerBoundRatio > upperBoundRatio
        ) {
            revert InvalidBounds();
        }

        if (mainOracle == address(0)) {
            revert InvalidMainOracle();
        }

        if (asset == address(0)) {
            revert InvalidAsset();
        }

        configs[asset] = AssetConfig({
            mainOracle: mainOracle,
            fallbackOracle: fallbackOracle,
            lowerBoundRatio: lowerBoundRatio,
            upperBoundRatio: upperBoundRatio
        });

        emit AssetConfigSet(
            asset, mainOracle, fallbackOracle, lowerBoundRatio, upperBoundRatio
        );
    }

    /**
     * @notice Get the price of the market
     * @param pToken Address of the market
     * @return price Price of the market scaled by (36 - assetDecimals)
     */
    function getUnderlyingPrice(IPToken pToken)
        external
        view
        override
        returns (uint256)
    {
        return getPrice(pToken.underlying());
    }

    /**
     * @notice Get the price of the asset
     * @param asset Address of the asset
     * @return price Price of the asset scaled by (36 - assetDecimals)
     */
    function getPrice(address asset) public view override returns (uint256 price) {
        AssetConfig storage config = configs[asset];

        try IOracleProvider(config.mainOracle).getPrice(asset) returns (
            uint256 mainOraclePrice
        ) {
            if (config.fallbackOracle == address(0)) {
                return mainOraclePrice;
            }

            try IOracleProvider(config.fallbackOracle).getPrice(asset) returns (
                uint256 fallbackOraclePrice
            ) {
                if (config.lowerBoundRatio != 0 && config.upperBoundRatio != 0) {
                    uint256 lowerBound =
                        fallbackOraclePrice * config.lowerBoundRatio / 1e18;
                    uint256 upperBound =
                        fallbackOraclePrice * config.upperBoundRatio / 1e18;

                    if (mainOraclePrice < lowerBound || mainOraclePrice > upperBound) {
                        revert BoundValidationFailed();
                    }
                }

                return mainOraclePrice;
            } catch {
                return mainOraclePrice;
            }
        } catch {
            if (config.fallbackOracle != address(0)) {
                try IOracleProvider(config.fallbackOracle).getPrice(asset) returns (
                    uint256 fallbackOraclePrice
                ) {
                    return fallbackOraclePrice;
                } catch {
                    revert InvalidFallbackOraclePrice();
                }
            } else {
                revert InvalidMainOraclePrice();
            }
        }
    }

    /**
     * @notice Authorize upgrade
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
