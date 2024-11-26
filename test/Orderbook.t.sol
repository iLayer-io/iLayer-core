// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Validator} from "../src/Validator.sol";
import {Orderbook} from "../src/Orderbook.sol";
import {BaseTest} from "./BaseTest.sol";

contract OrderbookTest is BaseTest {
    constructor() BaseTest() {}

    function testCreateOrder(uint256 inputAmount) public {
        vm.assume(inputAmount > 0);

        Validator.Order memory order =
            buildOrder(inputAmount, 1, user0, user0_pk, address(inputToken), address(outputToken), 1 minutes, 5 minutes);

        assertTrue(orderbook.validateOrder(order), "Invalid signature");

        inputToken.mint(user0, inputAmount);
        vm.prank(user0);
        inputToken.approve(address(orderbook), inputAmount);

        assertEq(inputToken.balanceOf(address(orderbook)), 0);
        orderbook.createOrder(order, "");
        assertEq(inputToken.balanceOf(address(orderbook)), inputAmount);
    }

    function testCreateOrderWithPermit() public {
        uint256 inputAmount = 1e18;

        Validator.Order memory order =
            buildOrder(inputAmount, 1, user0, user0_pk, address(inputToken), address(outputToken), 1 minutes, 5 minutes);

        // Generate permit signature
        uint256 nonce = inputToken.nonces(user0);
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                inputToken.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(inputToken.PERMIT_TYPEHASH(), user0, address(orderbook), inputAmount, nonce, deadline)
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user0_pk, permitHash);

        bytes memory permit = abi.encode(inputAmount, deadline, v, r, s);

        inputToken.mint(user0, inputAmount);
        vm.prank(user0);
        orderbook.createOrder(order, permit);

        assertEq(inputToken.balanceOf(address(orderbook)), inputAmount);
    }

    function testOrderWithdrawal() public {
        uint256 inputAmount = 1e18;
        testCreateOrder(inputAmount);

        Validator.Order memory order =
            buildOrder(inputAmount, 1, user0, user0_pk, address(inputToken), address(outputToken), 1 minutes, 5 minutes);

        vm.warp(block.timestamp + 1 minutes);

        // should fail cause the order hasn't expired yet
        vm.startPrank(user0);
        vm.expectRevert(Orderbook.OrderCannotBeWithdrawn.selector);
        orderbook.withdrawOrder(order);
        vm.stopPrank();

        vm.warp(block.timestamp + 5 minutes);

        // should fail cause it's a different user
        vm.startPrank(user1);
        vm.expectRevert(Orderbook.Unauthorized.selector);
        orderbook.withdrawOrder(order);
        vm.stopPrank();

        assertEq(inputToken.balanceOf(address(orderbook)), inputAmount);

        // should succeed
        vm.prank(user0);
        orderbook.withdrawOrder(order);

        assertEq(inputToken.balanceOf(address(orderbook)), 0);
        assertEq(inputToken.balanceOf(user0), inputAmount);
    }

    function testInvalidOrderSignature() public {
        uint256 inputAmount = 1e18;

        Validator.Order memory order =
            buildOrder(inputAmount, 1, user0, user0_pk, address(inputToken), address(outputToken), 1 minutes, 5 minutes);

        // Tamper with the order to make the signature invalid
        order.deadline += 1;

        vm.prank(user0);
        inputToken.mint(user0, inputAmount);
        inputToken.approve(address(orderbook), inputAmount);

        vm.expectRevert(Orderbook.InvalidOrderSignature.selector);
        orderbook.createOrder(order, "");
    }

    function testOrderDeadlineMismatch() public {
        uint256 inputAmount = 1e18;

        Validator.Order memory order =
            buildOrder(inputAmount, 1, user0, user0_pk, address(inputToken), address(outputToken), 6 minutes, 5 minutes);

        vm.prank(user0);
        inputToken.mint(user0, inputAmount);
        inputToken.approve(address(orderbook), inputAmount);

        vm.expectRevert(Orderbook.OrderDeadlinesMismatch.selector);
        orderbook.createOrder(order, "");
    }

    function testOrderExpired() public {
        uint256 inputAmount = 1e18;

        Validator.Order memory order =
            buildOrder(inputAmount, 1, user0, user0_pk, address(inputToken), address(outputToken), 1 minutes, 5 minutes);

        // Warp to a time after the deadline
        vm.warp(block.timestamp + 6 minutes);

        vm.prank(user0);
        inputToken.mint(user0, inputAmount);
        inputToken.approve(address(orderbook), inputAmount);

        vm.expectRevert(Orderbook.OrderExpired.selector);
        orderbook.createOrder(order, "");
    }

    function testDoubleWithdrawal() public {
        uint256 inputAmount = 1e18;
        testCreateOrder(inputAmount);

        Validator.Order memory order =
            buildOrder(inputAmount, 1, user0, user0_pk, address(inputToken), address(outputToken), 1 minutes, 5 minutes);

        vm.warp(block.timestamp + 5 minutes);

        vm.prank(user0);
        orderbook.withdrawOrder(order);

        // Try to withdraw the same order again
        vm.startPrank(user0);
        vm.expectRevert(Orderbook.OrderCannotBeWithdrawn.selector);
        orderbook.withdrawOrder(order);
        vm.stopPrank();
    }
}
