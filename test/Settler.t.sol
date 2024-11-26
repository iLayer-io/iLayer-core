// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Validator} from "../src/Validator.sol";
import {Orderbook} from "../src/Orderbook.sol";
import {Settler} from "../src/Settler.sol";
import {BaseTest} from "./BaseTest.sol";

contract SettlerTest is BaseTest {
    constructor() BaseTest() {}

    function testFillOrder() public {
        uint256 inputAmount = 100;

        Validator.Order memory order =
            buildOrder(inputAmount, 1, user0, user0_pk, address(inputToken), address(outputToken), 1 minutes, 5 minutes);

        inputToken.mint(user0, inputAmount);
        vm.prank(user0);
        inputToken.approve(address(orderbook), inputAmount);
        orderbook.createOrder(order, "");

        address filler = user1;

        vm.prank(filler);
        settler.fillOrder(order);

        assertEq(inputToken.balanceOf(address(settler)), 0);
        assertEq(inputToken.balanceOf(filler), inputAmount);
    }
}
