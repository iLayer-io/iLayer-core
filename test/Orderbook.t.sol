// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Validator} from "../src/Validator.sol";
import {Orderbook} from "../src/Orderbook.sol";
import {BaseTest} from "./BaseTest.sol";

contract OrderbookTest is BaseTest {
    constructor() BaseTest() {}

    function testCreateOrder(uint256 inputAmount) public {
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
        bytes memory signature = buildSignature(order, user0_pk);

        inputToken.mint(user0, inputAmount);
        vm.prank(user0);
        inputToken.approve(address(orderbook), inputAmount);

        assertEq(inputToken.balanceOf(address(orderbook)), 0);
        vm.prank(user0);
        orderbook.createOrder(order, permits, signature, 0);
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
        testCreateOrder(inputAmount);

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
        orderbook.withdrawOrder(order, 1);
        vm.stopPrank();

        vm.warp(block.timestamp + 5 minutes);

        // should fail cause it's a different user
        vm.startPrank(user1);
        vm.expectRevert(Orderbook.Unauthorized.selector);
        orderbook.withdrawOrder(order, 1);
        vm.stopPrank();

        assertEq(inputToken.balanceOf(address(orderbook)), inputAmount);

        // should succeed
        vm.prank(user0);
        orderbook.withdrawOrder(order, 1);

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
        bytes memory signature = buildSignature(order, user0_pk);

        vm.startPrank(user0);
        inputToken.mint(user0, inputAmount);
        inputToken.approve(address(orderbook), inputAmount);

        vm.expectRevert(Orderbook.OrderDeadlinesMismatch.selector);
        orderbook.createOrder(order, permits, signature, 0);
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
        bytes memory signature = buildSignature(order, user0_pk);

        // Warp to a time after the deadline
        vm.warp(block.timestamp + 6 minutes);

        vm.startPrank(user0);
        inputToken.mint(user0, inputAmount);
        inputToken.approve(address(orderbook), inputAmount);

        vm.expectRevert(Orderbook.OrderExpired.selector);
        orderbook.createOrder(order, permits, signature, 0);
        vm.stopPrank();
    }

    function testDoubleWithdrawal() public {
        uint256 inputAmount = 1e18;
        testCreateOrder(inputAmount);

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
        orderbook.withdrawOrder(order, 1);

        // Try to withdraw the same order again
        vm.startPrank(user0);
        vm.expectRevert(Orderbook.OrderCannotBeWithdrawn.selector);
        orderbook.withdrawOrder(order, 1);
        vm.stopPrank();
    }

    function testCreateOrderWithZeroAmount() public {
        Validator.Order memory order = buildOrder(
            address(this),
            0, // set it to zero to simulate a null order
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

        vm.expectRevert(Orderbook.InvalidTokenAmount.selector);
        orderbook.createOrder(order, permits, signature, 0);
    }

    function testCreateOrderInsufficientAllowance() public {
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

        inputToken.mint(user0, inputAmount);
        vm.prank(user0);
        inputToken.approve(address(orderbook), inputAmount - 1); // Approve less than required

        vm.prank(user0);
        vm.expectRevert();
        orderbook.createOrder(order, permits, signature, 0);
    }

    function testCreateOrderInsufficientBalance() public {
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

        inputToken.mint(user0, inputAmount - 1); // Mint less than required
        vm.prank(user0);
        inputToken.approve(address(orderbook), inputAmount);

        vm.prank(user0);
        vm.expectRevert();
        orderbook.createOrder(order, permits, signature, 0);
    }

    function testWithdrawNonExistentOrder() public {
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

        vm.prank(user0);
        vm.expectRevert(Orderbook.OrderCannotBeWithdrawn.selector);
        orderbook.withdrawOrder(order, 1);
    }

    function testCreateMultipleOrdersSameUser(uint256 inputAmount1, uint256 inputAmount2) public {
        vm.assume(inputAmount1 < type(uint256).max - inputAmount2);
        vm.assume(inputAmount1 > 0);
        vm.assume(inputAmount2 > 0);

        Validator.Order memory order1 = buildOrder(
            address(this),
            inputAmount1,
            1,
            user0,
            address(inputToken),
            address(outputToken),
            1 minutes,
            5 minutes,
            address(0),
            ""
        );
        bytes memory signature1 = buildSignature(order1, user0_pk);

        Validator.Order memory order2 = buildOrder(
            address(this),
            inputAmount2,
            2,
            user0,
            address(inputToken),
            address(outputToken),
            2 minutes,
            6 minutes,
            address(0),
            ""
        );
        bytes memory signature2 = buildSignature(order2, user0_pk);

        inputToken.mint(user0, inputAmount1 + inputAmount2);
        vm.startPrank(user0);
        inputToken.approve(address(orderbook), inputAmount1 + inputAmount2);

        orderbook.createOrder(order1, permits, signature1, 0);
        orderbook.createOrder(order2, permits, signature2, 0);
        vm.stopPrank();

        assertEq(inputToken.balanceOf(address(orderbook)), inputAmount1 + inputAmount2);
    }

    function testCreateMultipleOrdersMultipleUsers(uint256 inputAmount1, uint256 inputAmount2) public {
        vm.assume(inputAmount1 < type(uint256).max - inputAmount2);
        vm.assume(inputAmount1 > 0);
        vm.assume(inputAmount2 > 0);

        Validator.Order memory order1 = buildOrder(
            address(this),
            inputAmount1,
            1,
            user1,
            address(inputToken),
            address(outputToken),
            1 minutes,
            5 minutes,
            address(0),
            ""
        );
        bytes memory signature1 = buildSignature(order1, user1_pk);

        Validator.Order memory order2 = buildOrder(
            address(this),
            inputAmount2,
            2,
            user2,
            address(inputToken),
            address(outputToken),
            2 minutes,
            6 minutes,
            address(0),
            ""
        );
        bytes memory signature2 = buildSignature(order2, user2_pk);

        vm.startPrank(user1);
        inputToken.mint(user1, inputAmount1);
        inputToken.approve(address(orderbook), inputAmount1);
        orderbook.createOrder(order1, permits, signature1, 0);
        vm.stopPrank();

        vm.startPrank(user2);
        inputToken.mint(user2, inputAmount2);
        inputToken.approve(address(orderbook), inputAmount2);
        orderbook.createOrder(order2, permits, signature2, 0);
        vm.stopPrank();

        assertEq(inputToken.balanceOf(address(orderbook)), inputAmount1 + inputAmount2);
    }

    function testCreateOrderWithInvalidTokens() public {
        uint256 inputAmount = 1e18;

        Validator.Order memory order = buildOrder(
            address(this),
            inputAmount,
            1,
            user0,
            address(0), // Invalid token address
            address(outputToken),
            1 minutes,
            5 minutes,
            address(0),
            ""
        );
        bytes memory signature = buildSignature(order, user0_pk);

        vm.expectRevert();
        orderbook.createOrder(order, permits, signature, 0);
    }

    function testCreateOrderSmartContract(uint256 inputAmount) public {
        vm.assume(inputAmount > 0);

        Validator.Order memory order = buildOrder(
            address(this),
            inputAmount,
            1,
            address(contractUser),
            address(inputToken),
            address(outputToken),
            1 minutes,
            5 minutes,
            address(0),
            ""
        );
        bytes memory signature = "";

        inputToken.mint(address(contractUser), inputAmount);

        assertEq(inputToken.balanceOf(address(orderbook)), 0);
        contractUser.approve(inputToken, address(orderbook), inputAmount);
        contractUser.createOrder(orderbook, order, permits, signature, 0);
        assertEq(inputToken.balanceOf(address(orderbook)), inputAmount);
    }

    function testWithdrawMultipleIdenticalOrders() public {
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

        inputToken.mint(user0, inputAmount * 2);
        vm.prank(user0);
        inputToken.approve(address(orderbook), inputAmount * 2);
        bytes memory signature = buildSignature(order, user0_pk);

        // Add the first order
        vm.prank(user0);
        (bytes32 orderId1,) = orderbook.createOrder(order, permits, signature, 0);
        assertEq(inputToken.balanceOf(address(orderbook)), inputAmount);
        assertEq(inputToken.balanceOf(user0), inputAmount);

        // Add the second order
        vm.prank(user0);
        (bytes32 orderId2, uint256 nonce) = orderbook.createOrder(order, permits, signature, 0);
        assertEq(inputToken.balanceOf(address(orderbook)), inputAmount * 2);
        assertEq(inputToken.balanceOf(user0), 0);

        // Order IDs are not the same
        assertNotEq(orderId1, orderId2);
        // Orders expire
        vm.warp(block.timestamp + 10 minutes);

        // Withdraw the first order
        vm.prank(user0);
        orderbook.withdrawOrder(order, nonce);
        assertEq(inputToken.balanceOf(address(orderbook)), inputAmount);
        assertEq(inputToken.balanceOf(user0), inputAmount);

        // Withdrawing again fails
        vm.prank(user0);
        vm.expectRevert();
        orderbook.withdrawOrder(order, nonce);
        assertEq(inputToken.balanceOf(address(orderbook)), inputAmount);
        assertEq(inputToken.balanceOf(user0), inputAmount);
    }
}
