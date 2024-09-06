//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {IOracleProvider} from "@oracles/interfaces/IOracleProvider.sol";
import {OwnableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@chainlink/contracts/shared/interfaces/AggregatorV3Interface.sol";

contract ChainlinkOracleProvider is IOracleProvider, OwnableUpgradeable {
    struct AssetConfig {
        address feed;
        uint256 maxStalePeriod;
    }

    mapping(address => AssetConfig) public configs;

    error InvalidAsset();

    error InvalidFeed();

    error InvalidStalePeriod();

    event AssetConfigSet(address asset, address feed, uint256 maxStalePeriod);

    /**
     * @notice Initialize the contract
     * @param owner Address of the owner
     */
    function initialize(address owner) public initializer {
        __Ownable_init(owner);
    }

    function setAssetConfig(
        address asset,
        address feed,
        uint256 maxStalePeriod
    ) external onlyOwner {
        if (asset == address(0)) {
            revert InvalidAsset();
        }

        if (feed == address(0)) {
            revert InvalidFeed();
        }

        if (maxStalePeriod == 0) {
            revert InvalidStalePeriod();
        }

        configs[asset] = AssetConfig(feed, maxStalePeriod);
        emit AssetConfigSet(asset, feed, maxStalePeriod);
    }

    function getPrice(address asset) external view override returns (uint256) {

    }
}
