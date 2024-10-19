//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

contract InterestRateStorage {
    struct InterestRateData {
        /**
         * @notice The multiplier of utilization rate that gives the slope of the interest rate
         */
        uint256 multiplierPerSecond;
        /**
         * @notice The base interest rate which is the y-intercept when utilization rate is 0
         */
        uint256 baseRatePerSecond;
        /**
         * @notice The multiplierPerSecond after hitting a specified utilization point
         */
        uint256 jumpMultiplierPerSecond;
        /**
         * @notice The utilization point at which the jump multiplier is applied
         */
        uint256 kink;
    }

    /// keccak256(abi.encode(uint256(keccak256("pike.LM.IRM")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant _SLOT_IRM_STORAGE =
        0x3851e8953f711665c6e7a2d0c4292cf1c4ce81f861601a91328edb40c914a000;

    uint256 internal constant BASE = 1e18;

    /**
     * @notice The approximate number of seconds per year that is assumed by the interest rate model
     */
    uint256 internal constant SECONDS_PER_YEAR = 31_536_000;

    function _getIRMStorage() internal pure returns (InterestRateData storage data) {
        bytes32 s = _SLOT_IRM_STORAGE;
        assembly {
            data.slot := s
        }
    }
}
