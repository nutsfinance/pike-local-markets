//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IOracleProvider} from "@oracles/interfaces/IOracleProvider.sol";
import {OwnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC20Metadata} from
    "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@chainlink/contracts/shared/interfaces/AggregatorV3Interface.sol";

contract ChainlinkOracleProvider is IOracleProvider, OwnableUpgradeable {
    struct AssetConfig {
        /**
         * @notice Chainlink feed for the asset
         */
        AggregatorV3Interface feed;
        /**
         * @notice Maximum stale period for the price feed
         */
        uint256 maxStalePeriod;
    }

    /**
     * @notice Grace period time after the sequencer is back up
     */
    uint256 private constant GRACE_PERIOD_TIME = 3600;

    /**
     * @notice Chainlink feed for the sequencer uptime
     */
    AggregatorV3Interface public immutable sequencerUptimeFeed;

    /**
     * @notice Mapping of asset address to its configuration
     */
    mapping(address => AssetConfig) public configs;

    /**
     * @notice Event emitted when asset configuration is set
     */
    event AssetConfigSet(
        address asset, AggregatorV3Interface feed, uint256 maxStalePeriod
    );

    /**
     * @notice Error emitted when asset is invalid
     */
    error InvalidAsset();

    /**
     * @notice Error emitted when feed is invalid
     */
    error InvalidFeed();

    /**
     * @notice Error emitted when stale period is invalid
     */
    error InvalidStalePeriod();

    /**
     * @notice Error emitted when price is stale
     */
    error StalePrice();

    /**
     * @notice Error emitted when sequencer is down
     */
    error SequencerDown();

    /**
     * @notice Error emitted when grace period is not over
     */
    error GracePeriodNotOver();

    /**
     * @notice Contract constructor
     *     @param _sequencerUptimeFeed L2 Sequencer uptime feed
     */
    constructor(AggregatorV3Interface _sequencerUptimeFeed) {
        sequencerUptimeFeed = _sequencerUptimeFeed;
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
     * @param feed Chainlink feed for the asset
     * @param maxStalePeriod Maximum stale period for the price feed
     */
    function setAssetConfig(
        address asset,
        AggregatorV3Interface feed,
        uint256 maxStalePeriod
    ) external onlyOwner {
        if (asset == address(0)) {
            revert InvalidAsset();
        }

        if (address(feed) == address(0)) {
            revert InvalidFeed();
        }

        if (maxStalePeriod == 0) {
            revert InvalidStalePeriod();
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
        _validateSequencerStatus();

        AssetConfig storage config = configs[asset];
        uint256 priceDecimals = config.feed.decimals();
        (, int256 price,, uint256 updatedAt,) = config.feed.latestRoundData();

        if (block.timestamp - updatedAt > config.maxStalePeriod) {
            revert StalePrice();
        }

        uint8 assetDecimals = IERC20Metadata(asset).decimals();
        return uint256(price) * (10 ** (36 - assetDecimals - priceDecimals));
    }

    /**
     * @notice Validate the sequencer status
     */
    function _validateSequencerStatus() internal view {
        if (address(sequencerUptimeFeed) == address(0)) {
            return;
        }

        (
            /*uint80 roundID*/
            ,
            int256 answer,
            uint256 startedAt,
            /*uint256 updatedAt*/
            ,
            /*uint80 answeredInRound*/
        ) = sequencerUptimeFeed.latestRoundData();

        // Answer == 0: Sequencer is up
        // Answer == 1: Sequencer is down
        bool isSequencerUp = answer == 0;
        if (!isSequencerUp) {
            revert SequencerDown();
        }

        // Make sure the grace period has passed after the
        // sequencer is back up.
        uint256 timeSinceUp = block.timestamp - startedAt;
        if (timeSinceUp <= GRACE_PERIOD_TIME) {
            revert GracePeriodNotOver();
        }
    }
}
