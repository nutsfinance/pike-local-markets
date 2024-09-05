// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "forge-std/Test.sol";

import {TestUtilities} from "@helpers/TestUtilities.sol";
import {IPToken, IERC20} from "@interfaces/IPToken.sol";
import {IInterestRateModel} from "@interfaces/IInterestRateModel.sol";
import {IRiskEngine} from "@interfaces/IRiskEngine.sol";

contract TestHelpers is TestUtilities {
    function doAction(ActionParameters memory params) public {
        address user = params.prankAddress;
        bool onBehalfOf = params.onBehalfOf != params.prankAddress;

        vm.deal(user, 1 ether);

        Action action = Action(params.action);

        if (getDebug()) {
            console.log("-[User %s]--------------", user);
        }

        if (action == Action.SUPPLY || action == Action.REPAY) {
            deal(params.tokenAddress, user, params.amount);
            vm.prank(user);
            IERC20(params.tokenAddress).approve(params.pToken, params.amount);
        }

        ActionStateData memory beforeAction = getActionStateData(
            user, params.onBehalfOf, params.pToken, params.tokenAddress
        );

        vm.recordLogs();
        if (action == Action.SUPPLY) {
            if (getDebug()) {
                console.log(
                    "Depositing %s of %s",
                    params.amount,
                    IPToken(params.tokenAddress).name()
                );
            }

            if (onBehalfOf) {
                vm.prank(user);
                if (params.expectRevert) {
                    vm.expectRevert(params.error);
                }
                IPToken(params.pToken).mintOnBehalfOf(params.onBehalfOf, params.amount);
            } else {
                vm.prank(user);
                if (params.expectRevert) {
                    vm.expectRevert(params.error);
                }
                IPToken(params.pToken).mint(params.amount);
            }
        } else if (action == Action.REPAY) {
            if (getDebug()) {
                console.log(
                    "Repaying %s of %s",
                    params.amount,
                    IPToken(params.tokenAddress).name()
                );
            }

            if (onBehalfOf) {
                vm.prank(user);
                if (params.expectRevert) {
                    vm.expectRevert(params.error);
                }
                IPToken(params.pToken).repayBorrowOnBehalfOf(
                    params.onBehalfOf, params.amount
                );
            } else {
                vm.prank(user);
                if (params.expectRevert) {
                    vm.expectRevert(params.error);
                }
                IPToken(params.pToken).repayBorrow(params.amount);
            }
        } else if (action == Action.BORROW) {
            if (getDebug()) {
                console.log(
                    "Borrowing %s of %s",
                    params.amount,
                    IPToken(params.tokenAddress).name()
                );
            }

            if (onBehalfOf) {
                vm.prank(user);
                if (params.expectRevert) {
                    vm.expectRevert(params.error);
                }
                IPToken(params.pToken).borrowOnBehalfOf(params.onBehalfOf, params.amount);
            } else {
                vm.prank(user);
                if (params.expectRevert) {
                    vm.expectRevert(params.error);
                }
                IPToken(params.pToken).borrow(params.amount);
            }
        } else if (action == Action.WITHDRAW_UNDERLYING) {
            if (getDebug()) {
                console.log(
                    "Withdrawing %s of %s",
                    params.amount,
                    IPToken(params.tokenAddress).name()
                );
            }

            if (onBehalfOf) {
                vm.prank(user);
                if (params.expectRevert) {
                    vm.expectRevert(params.error);
                }
                IPToken(params.pToken).redeemUnderlyingOnBehalfOf(
                    params.onBehalfOf, params.amount
                );
            } else {
                vm.prank(user);
                if (params.expectRevert) {
                    vm.expectRevert(params.error);
                }
                IPToken(params.pToken).redeemUnderlying(params.amount);
            }
        } else if (action == Action.WITHDRAW) {
            if (getDebug()) {
                console.log(
                    "Withdrawing %s of %s", params.amount, IPToken(params.pToken).name()
                );
            }

            if (onBehalfOf) {
                vm.prank(user);
                if (params.expectRevert) {
                    vm.expectRevert(params.error);
                }
                IPToken(params.pToken).redeemOnBehalfOf(params.onBehalfOf, params.amount);
            } else {
                vm.prank(user);
                if (params.expectRevert) {
                    vm.expectRevert(params.error);
                }
                IPToken(params.pToken).redeem(params.amount);
            }
        }

        if (params.expectRevert) {
            if (getDebug()) {
                console.log("should revert");
                console.log("----------------------------------------");
                console.log("");
            }
            return;
        }

        ActionStateData memory afterAction = getActionStateData(
            user, params.onBehalfOf, params.pToken, params.tokenAddress
        );

        requireActionDataValid(
            action,
            params.pToken,
            params.amount,
            beforeAction,
            afterAction,
            params.expectRevert
        );

        if (getDebug()) {
            console.log("----------------------------------------");
            console.log("");
        }
    }

    function doDeposit(
        address prankAddress,
        address onBehalfOf,
        address pToken,
        uint256 amount
    ) public {
        doAction(
            ActionParameters({
                action: Action.SUPPLY,
                pToken: pToken,
                tokenAddress: IPToken(pToken).underlying(),
                amount: amount,
                expectRevert: false,
                error: bytes4(0),
                prankAddress: prankAddress,
                onBehalfOf: onBehalfOf
            })
        );
    }

    function doDepositAndEnter(
        address re,
        address prankAddress,
        address onBehalfOf,
        address pToken,
        uint256 amount
    ) public {
        doAction(
            ActionParameters({
                action: Action.SUPPLY,
                pToken: pToken,
                tokenAddress: IPToken(pToken).underlying(),
                amount: amount,
                expectRevert: false,
                error: bytes4(0),
                prankAddress: prankAddress,
                onBehalfOf: onBehalfOf
            })
        );
        enterMarket(re, prankAddress, pToken);
    }

    function doBorrow(
        address prankAddress,
        address onBehalfOf,
        address pToken,
        uint256 amount
    ) public {
        doAction(
            ActionParameters({
                action: Action.BORROW,
                pToken: pToken,
                tokenAddress: IPToken(pToken).underlying(),
                amount: amount,
                expectRevert: false,
                error: bytes4(0),
                prankAddress: prankAddress,
                onBehalfOf: onBehalfOf
            })
        );
    }

    function doRepay(
        address prankAddress,
        address onBehalfOf,
        address pToken,
        uint256 amount
    ) public {
        doAction(
            ActionParameters({
                action: Action.REPAY,
                pToken: pToken,
                tokenAddress: IPToken(pToken).underlying(),
                amount: amount,
                expectRevert: false,
                error: bytes4(0),
                prankAddress: prankAddress,
                onBehalfOf: onBehalfOf
            })
        );
    }

    function doWithdraw(
        address prankAddress,
        address onBehalfOf,
        address pToken,
        uint256 amount
    ) public {
        doAction(
            ActionParameters({
                action: Action.WITHDRAW,
                pToken: pToken,
                tokenAddress: IPToken(pToken).underlying(),
                amount: amount,
                expectRevert: false,
                error: bytes4(0),
                prankAddress: prankAddress,
                onBehalfOf: onBehalfOf
            })
        );
    }

    function doWithdrawUnderlying(
        address prankAddress,
        address onBehalfOf,
        address pToken,
        uint256 amount
    ) public {
        doAction(
            ActionParameters({
                action: Action.WITHDRAW_UNDERLYING,
                pToken: pToken,
                tokenAddress: IPToken(pToken).underlying(),
                amount: amount,
                expectRevert: false,
                error: bytes4(0),
                prankAddress: prankAddress,
                onBehalfOf: onBehalfOf
            })
        );
    }

    function enterMarket(address riskEngine, address prankAddress, address pToken)
        public
    {
        vm.prank(prankAddress);
        address[] memory markets = new address[](1);
        markets[0] = pToken;
        IRiskEngine(riskEngine).enterMarkets(markets);
    }
}
