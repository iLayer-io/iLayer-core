// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Validator} from "../src/Validator.sol";
import {Orderbook} from "../src/Orderbook.sol";
import {Settler} from "../src/Settler.sol";
import {BaseTest} from "./BaseTest.sol";

contract SettlerTest is BaseTest {
    constructor() BaseTest() {}

    function testFillOrder(uint256 inputAmount, uint256 outputAmount) public {
        vm.assume(inputAmount > 0);

        Validator.Order memory order = buildOrder(
            inputAmount, outputAmount, user0, user0_pk, address(inputToken), address(outputToken), 1 minutes, 5 minutes
        );

        inputToken.mint(user0, inputAmount);
        vm.prank(user0);
        inputToken.approve(address(orderbook), inputAmount);
        orderbook.createOrder(order, "");

        address filler = user1;

        vm.startPrank(filler);
        outputToken.mint(filler, outputAmount);
        outputToken.approve(address(settler), outputAmount);
        settler.fillOrder(order);
        vm.stopPrank();

        // Orderbook is empty
        assertEq(inputToken.balanceOf(address(orderbook)), 0);
        assertEq(outputToken.balanceOf(address(orderbook)), 0);
        // User has received the desired tokens
        assertEq(inputToken.balanceOf(user0), 0);
        assertEq(outputToken.balanceOf(user0), outputAmount);
        // Filler has received their payment
        assertEq(inputToken.balanceOf(filler), inputAmount);
        assertEq(outputToken.balanceOf(filler), 0);
        // Settler contract is empty
        assertEq(inputToken.balanceOf(address(settler)), 0);
        assertEq(outputToken.balanceOf(address(settler)), 0);
    }
}
