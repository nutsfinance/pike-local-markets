// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "cannon-std/Cannon.sol";
import "forge-std/Test.sol";

import {TestState} from "@helpers/TestState.sol";
import {IOwnable} from "@interfaces/IOwnable.sol";
import {IPToken} from "@interfaces/IPToken.sol";
import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";

contract TestGetters is Test, TestState {
    using Cannon for Vm;

    function getAdmin() public view returns (address) {
        return _testState.admin;
    }

    function getPToken(string memory pToken) public view returns (IPToken token) {
        if (getLocatState()) {
            return IPToken(_testState.pTokens[keccak256(abi.encodePacked(pToken))]);
        } else {
            return IPToken(vm.getAddress(string.concat(pToken, ".Proxy")));
        }
    }

    function getIRM(string memory pToken) public view returns (IInterestRateModel irm) {
        if (getLocatState()) {
            return IInterestRateModel(
                _testState.pTokens[keccak256(abi.encodePacked(pToken))]
            );
        } else {
            return IInterestRateModel(vm.getAddress(string.concat(pToken, ".Proxy")));
        }
    }

    function getRiskEngine() public view returns (IRiskEngine re) {
        if (getLocatState()) {
            return IRiskEngine(_testState.riskEngine);
        } else {
            return IRiskEngine(vm.getAddress("core.Proxy"));
        }
    }

    function getPTokenOwner(string memory pToken) public view returns (address owner) {
        if (getLocatState()) {
            return IOwnable(address(getPToken(pToken))).owner();
        } else {
            return IOwnable(vm.getAddress(string.concat(pToken, ".Proxy"))).owner();
        }
    }

    function getCoreOwner() public view returns (address owner) {
        if (getLocatState()) {
            return IOwnable(address(getRiskEngine())).owner();
        } else {
            return IOwnable(vm.getAddress("core.Proxy")).owner();
        }
    }

    function getDebug() public view returns (bool) {
        return _testState.debug;
    }

    function getLocatState() public view returns (bool) {
        return _testState.localState;
    }

    function getOracle() public view returns (address) {
        return _testState.oracle;
    }
}
