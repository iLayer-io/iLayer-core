// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Validator} from "../src/Validator.sol";
import {Orderbook} from "../src/Orderbook.sol";
import {BaseTest} from "./BaseTest.sol";

contract OrderbookTest is BaseTest {
    constructor() BaseTest() {}

    function testCreateOrderSimple(uint256 inputAmount) public {
        vm.assume(inputAmount > 0);

        Validator.Order memory order = buildOrder(
            address(this),
            inputAmount,
            1,
            user0,
            address(inputToken),
            address(outputToken),
            1 minutes,
            5 minutes,
            address(0),
            ""
        );

        inputToken.mint(user0, inputAmount);
        vm.prank(user0);
        inputToken.approve(address(orderbook), inputAmount);

        assertEq(inputToken.balanceOf(address(orderbook)), 0);
        vm.prank(user0);
        orderbook.createOrder(order, 0);
        assertEq(inputToken.balanceOf(address(orderbook)), inputAmount);
    }

    function testCreateOrderWithPermit() public {
        uint256 inputAmount = 1e18;

        Validator.Order memory order = buildOrder(
            address(this),
            inputAmount,
            1,
            user0,
            address(inputToken),
            address(outputToken),
            1 minutes,
            5 minutes,
            address(0),
            ""
        );

        bytes memory signature = buildSignature(order, user0_pk);
        assertTrue(orderbook.validateOrder(order, signature), "Invalid signature");

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
        bytes[] memory permits = new bytes[](1);
        permits[0] = permit;

        inputToken.mint(user0, inputAmount);
        orderbook.createOrder(order, permits, signature, 0);

        assertEq(inputToken.balanceOf(address(orderbook)), inputAmount);
    }

    function testOrderWithdrawal() public {
        uint256 inputAmount = 1e18;
        testCreateOrderSimple(inputAmount);

        Validator.Order memory order = buildOrder(
            address(this),
            inputAmount,
            1,
            user0,
            address(inputToken),
            address(outputToken),
            1 minutes,
            5 minutes,
            address(0),
            ""
        );

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

        Validator.Order memory order = buildOrder(
            address(this),
            inputAmount,
            1,
            user0,
            address(inputToken),
            address(outputToken),
            1 minutes,
            5 minutes,
            address(0),
            ""
        );
        bytes memory signature = buildSignature(order, user0_pk);

        // Tamper with the order to make the signature invalid
        order.deadline += 1;

        vm.prank(user0);
        inputToken.mint(user0, inputAmount);
        inputToken.approve(address(orderbook), inputAmount);

        vm.expectRevert(Orderbook.InvalidOrderSignature.selector);
        bytes[] memory permits = new bytes[](1);
        orderbook.createOrder(order, permits, signature, 0);
    }

    function testOrderDeadlineMismatch() public {
        uint256 inputAmount = 1e18;

        Validator.Order memory order = buildOrder(
            address(this),
            inputAmount,
            1,
            user0,
            address(inputToken),
            address(outputToken),
            6 minutes,
            5 minutes,
            address(0),
            ""
        );

        vm.startPrank(user0);
        inputToken.mint(user0, inputAmount);
        inputToken.approve(address(orderbook), inputAmount);

        vm.expectRevert(Orderbook.OrderDeadlinesMismatch.selector);
        orderbook.createOrder(order, 0);
        vm.stopPrank();
    }

    function testOrderExpired() public {
        uint256 inputAmount = 1e18;

        Validator.Order memory order = buildOrder(
            address(this),
            inputAmount,
            1,
            user0,
            address(inputToken),
            address(outputToken),
            1 minutes,
            5 minutes,
            address(0),
            ""
        );

        // Warp to a time after the deadline
        vm.warp(block.timestamp + 6 minutes);

        vm.startPrank(user0);
        inputToken.mint(user0, inputAmount);
        inputToken.approve(address(orderbook), inputAmount);

        vm.expectRevert(Orderbook.OrderExpired.selector);
        orderbook.createOrder(order, 0);
        vm.stopPrank();
    }

    function testDoubleWithdrawal() public {
        uint256 inputAmount = 1e18;
        testCreateOrderSimple(inputAmount);

        Validator.Order memory order = buildOrder(
            address(this),
            inputAmount,
            1,
            user0,
            address(inputToken),
            address(outputToken),
            1 minutes,
            5 minutes,
            address(0),
            ""
        );

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
