// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";

contract TestState {
    struct State {
        Vm vm;
        bool debug;
    }

    State _testState;
}
