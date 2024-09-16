// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "cannon-std/Cannon.sol";
import "forge-std/Test.sol";

import {IOwnable} from "@interfaces/IOwnable.sol";
import {IPToken} from "@interfaces/IPToken.sol";
import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";

import {TestDeploy} from "./TestDeploy.sol";

contract TestGetters is TestDeploy {
    using Cannon for Vm;

    function getPToken(string memory pToken) public view returns (IPToken) {
        if (local == true) {
            if (
                keccak256(abi.encodePacked(pToken))
                    == keccak256(abi.encodePacked("pUSDC"))
            ) {
                return IPToken(usdcMarket);
            } else if (
                keccak256(abi.encodePacked(pToken))
                    == keccak256(abi.encodePacked("pWETH"))
            ) {
                return IPToken(wethMarket);
            }
        } else {
            return IPToken(vm.getAddress(string.concat(pToken, ".Proxy")));
        }
    }

    function getIRM(string memory pToken) public view returns (IInterestRateModel) {
        if (local == true) {
            if (
                keccak256(abi.encodePacked(pToken))
                    == keccak256(abi.encodePacked("pUSDC"))
            ) {
                return IInterestRateModel(usdcMarket);
            } else if (
                keccak256(abi.encodePacked(pToken))
                    == keccak256(abi.encodePacked("pWETH"))
            ) {
                return IInterestRateModel(wethMarket);
            }
        } else {
            return IInterestRateModel(vm.getAddress(string.concat(pToken, ".Proxy")));
        }
    }

    function getRiskEngine() public view returns (IRiskEngine) {
        if (local == true) {
            return IRiskEngine(riskEngine);
        } else {
            return IRiskEngine(vm.getAddress("core.Proxy"));
        }
    }

    function getPTokenOwner(string memory pToken) public view returns (address) {
        if (local == true) {
            if (
                keccak256(abi.encodePacked(pToken))
                    == keccak256(abi.encodePacked("pUSDC"))
            ) {
                return IOwnable(usdcMarket).owner();
            } else if (
                keccak256(abi.encodePacked(pToken))
                    == keccak256(abi.encodePacked("pWETH"))
            ) {
                return IOwnable(wethMarket).owner();
            }
        } else {
            return IOwnable(vm.getAddress(string.concat(pToken, ".Proxy"))).owner();
        }
    }

    function getCoreOwner() public view returns (address) {
        if (local == true) {
            return IOwnable(riskEngine).owner();
        } else {
            return IOwnable(vm.getAddress("core.Proxy")).owner();
        }
    }

    function getDebug() public view returns (bool) {
        return _testState.debug;
    }
}
