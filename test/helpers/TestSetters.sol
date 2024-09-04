// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import {TestStructs} from "@helpers/TestStructs.sol";
import {TestState} from "@helpers/TestState.sol";
import {TestGetters} from "@helpers/TestGetters.sol";

contract TestSetters is TestStructs, TestGetters {
    function setVm(Vm vm) public {
        _testState.vm = vm;
    }

    function setDebug(bool debug) public {
        _testState.debug = debug;
    }
}
