// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title CustomRateFeedWrapper
/// @notice Wraps any contract exposing a custom view function (e.g., exchangeRate())
contract CustomRateFeedWrapper {
    /// @notice Address of the underlying rate provider contract
    address public immutable target;

    /// @notice Number of decimals in the returned rate
    uint8 public immutable decimals_;

    /// @notice Function selector for the rate function
    bytes public callData;

    error InvalidRate();
    error InvalidCall();
    error InvalidTarget();
    error InvalidCalldata();

    constructor(address _target, uint8 _decimals, bytes memory _callData) {
        require(_target != address(0), InvalidTarget());
        require(_callData.length != 0, InvalidCalldata());

        target = _target;
        callData = _callData;
        decimals_ = _decimals;
    }

    function decimals() external view returns (uint8) {
        return decimals_;
    }

    function latestRoundData()
        public
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        (bool success, bytes memory data) = target.staticcall(callData);
        require(success, InvalidCall());
        uint256 rate = abi.decode(data, (uint256));
        require(rate > 0, InvalidRate());

        return (
            0, // roundId
            int256(rate),
            block.timestamp,
            block.timestamp,
            0 // answeredInRound
        );
    }
}
