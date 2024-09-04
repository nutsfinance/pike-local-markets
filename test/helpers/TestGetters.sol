// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "cannon-std/Cannon.sol";
import "forge-std/Test.sol";

import {IOwnable} from "@interfaces/IOwnable.sol";
import {IPToken} from "@interfaces/IPToken.sol";
import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";

import {TestState} from "@helpers/TestState.sol";

contract TestGetters is Test, TestState {
    using Cannon for Vm;

    function getPToken(string memory pToken) public view returns (IPToken) {
        return IPToken(vm.getAddress(string.concat(pToken, ".Proxy")));
    }

    function getIRM(string memory pToken) public view returns (IInterestRateModel) {
        return IInterestRateModel(vm.getAddress(string.concat(pToken, ".Proxy")));
    }

    function getRiskEngine() public view returns (IRiskEngine) {
        return IRiskEngine(vm.getAddress("core.Proxy"));
    }

    function getPTokenOwner(string memory pToken) public view returns (address) {
        return IOwnable(vm.getAddress(string.concat(pToken, ".Proxy"))).owner();
    }

    function getCoreOwner() public view returns (address) {
        return IOwnable(vm.getAddress("core.Proxy")).owner();
    }

    function getDebug() public view returns (bool) {
        return _testState.debug;
    }
}
