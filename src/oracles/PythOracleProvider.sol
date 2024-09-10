//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IOracleProvider} from "@oracles/interfaces/IOracleProvider.sol";
import {IPyth, PythStructs} from "@pythnetwork//IPyth.sol";
import {OwnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20Metadata} from
    "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract PythOracleProvider is IOracleProvider, OwnableUpgradeable {
    struct AssetConfig {
        /**
         * @notice Pyth feed for the asset
         */
        bytes32 feed;
        /**
         * @notice Maximum stale period for the price feed
         */
        uint256 maxStalePeriod;
    }

    /**
     * @notice Pyth oracle
     */
    IPyth public immutable pyth;

    /**
     * @notice Mapping of asset address to its configuration
     */
    mapping(address => AssetConfig) public configs;

    /**
     * @notice Event emitted when asset configuration is set
     */
    event AssetConfigSet(address asset, bytes32 feed, uint256 maxStalePeriod);

    /**
     * @notice Error emitted when asset is invalid
     */
    error InvalidAsset();

    /**
     * @notice Error emitted when max stale period is invalid
     */
    error InvalidMaxStalePeriod();

    /**
     * @notice Error emitted when price is invalid
     */
    error InvalidPrice();

    /**
     * @notice Contract constructor
     * @param _pyth Pyth oracle address
     */
    constructor(address _pyth) {
        pyth = IPyth(_pyth);
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
     * @notice Set the asset configuration
     * @param asset Address of the asset
     * @param feed Pyth feed for the asset
     * @param maxStalePeriod Maximum stale period for the price feed
     */
    function setAssetConfig(address asset, bytes32 feed, uint256 maxStalePeriod)
        external
        onlyOwner
    {
        if (asset == address(0)) {
            revert InvalidAsset();
        }

        if (maxStalePeriod == 0) {
            revert InvalidMaxStalePeriod();
        }

        configs[asset] = AssetConfig(feed, maxStalePeriod);
        emit AssetConfigSet(asset, feed, maxStalePeriod);
    }

    /**
     * @notice Get the price of the asset
     * @param asset Address of the asset
     * @return Price of the asset scaled to (36 - assetDecimals) decimals
     */
    function getPrice(address asset) external view override returns (uint256) {
        AssetConfig memory config = configs[asset];

        PythStructs.Price memory priceInfo =
            pyth.getPriceNoOlderThan(config.feed, config.maxStalePeriod);

        uint256 priceIn18Decimals = (uint256(uint64(priceInfo.price)) * (10 ** 18))
            / (10 ** uint8(uint32(-1 * priceInfo.expo)));

        IERC20Metadata token = IERC20Metadata(asset);
        uint256 decimals = token.decimals();

        return priceIn18Decimals * (10 ** (18 - decimals));
    }
}
