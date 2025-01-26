// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Root} from "../src/Root.sol";
import {Validator} from "../src/Validator.sol";
import {OrderHub} from "../src/OrderHub.sol";
import {BaseTest} from "./BaseTest.sol";

contract OrderHubTest is BaseTest {
    constructor() BaseTest() {}

    function testHubSetup() external {
        assertEq(hub.owner(), address(this));

        /// TODO add l0 base config tests
    }

    function testCreateOrder(uint256 inputAmount, uint256 outputAmount) public returns (Root.Order memory) {
        Root.Order memory order = buildOrder(
            user0,
            address(this),
            address(inputToken),
            inputAmount,
            address(outputToken),
            outputAmount,
            1 minutes,
            5 minutes,
            address(0),
            ""
        );
        bytes memory signature = buildSignature(order, user0_pk);

        address hubAddr = address(hub);

        inputToken.mint(user0, inputAmount);
        vm.prank(user0);
        inputToken.approve(hubAddr, inputAmount);

        assertEq(inputToken.balanceOf(hubAddr), 0);
        vm.prank(user0);
        hub.createOrder(buildOrderRequest(order, 1), permits, signature);
        assertEq(inputToken.balanceOf(hubAddr), inputAmount);

        return order;
    }

    function testCreateOrderWithPermit() public {
        uint256 inputAmount = 1e18;

        Root.Order memory order = buildOrder(
            user0,
            address(this),
            address(inputToken),
            inputAmount,
            address(outputToken),
            1,
            1 minutes,
            5 minutes,
            address(0),
            ""
        );

        bytes memory signature = buildSignature(order, user0_pk);
        assertTrue(hub.validateOrder(order, signature), "Invalid signature");

        // Generate permit signature
        uint256 nonce = inputToken.nonces(user0);
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                inputToken.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(inputToken.PERMIT_TYPEHASH(), user0, address(hub), inputAmount, nonce, deadline))
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user0_pk, permitHash);

        bytes memory permit = abi.encode(inputAmount, deadline, v, r, s);
        bytes[] memory permits = new bytes[](1);
        permits[0] = permit;

        inputToken.mint(user0, inputAmount);
        hub.createOrder(buildOrderRequest(order, 1), permits, signature);

        assertEq(inputToken.balanceOf(address(hub)), inputAmount);
    }

    function testOrderWithdrawal() public {
        uint256 inputAmount = 1e18;
        Root.Order memory order = testCreateOrder(inputAmount, 1);

        vm.warp(block.timestamp + 1 minutes);

        // should fail cause the order hasn't expired yet
        vm.startPrank(user0);
        vm.expectRevert();
        hub.withdrawOrder(order, 1);
        vm.stopPrank();

        vm.warp(block.timestamp + 5 minutes);

        // should fail cause it's a different user
        vm.startPrank(user1);
        vm.expectRevert();
        hub.withdrawOrder(order, 1);
        vm.stopPrank();

        assertEq(inputToken.balanceOf(address(hub)), inputAmount);

        // should succeed
        vm.prank(user0);
        hub.withdrawOrder(order, 1);

        assertEq(inputToken.balanceOf(address(hub)), 0);
        assertEq(inputToken.balanceOf(user0), inputAmount);
    }

    function testDoubleWithdrawal() public {
        uint256 inputAmount = 1e18;
        Root.Order memory order = testCreateOrder(inputAmount, 1);

        vm.warp(block.timestamp + 5 minutes);

        vm.prank(user0);
        hub.withdrawOrder(order, 1);

        // Try to withdraw the same order again
        vm.startPrank(user0);
        vm.expectRevert();
        hub.withdrawOrder(order, 1);
        vm.stopPrank();
    }

    function testCreateOrderInsufficientAllowance() public {
        uint256 inputAmount = 1e18;

        Root.Order memory order = buildOrder(
            user0,
            address(this),
            address(inputToken),
            inputAmount,
            address(outputToken),
            1,
            1 minutes,
            5 minutes,
            address(0),
            ""
        );
        bytes memory signature = buildSignature(order, user0_pk);

        inputToken.mint(user0, inputAmount);
        vm.prank(user0);
        inputToken.approve(address(hub), inputAmount - 1); // Approve less than required

        vm.prank(user0);
        vm.expectRevert();
        hub.createOrder(buildOrderRequest(order, 1), permits, signature);
    }

    function testInvalidOrderSignature() public {
        uint256 inputAmount = 1e18;

        Root.Order memory order = buildOrder(
            user0,
            address(this),
            address(inputToken),
            inputAmount,
            address(outputToken),
            1,
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
        inputToken.approve(address(hub), inputAmount);

        vm.expectRevert();
        bytes[] memory permits = new bytes[](1);
        hub.createOrder(buildOrderRequest(order, 1), permits, signature);
    }

    function testOrderDeadlineMismatch() public {
        uint256 inputAmount = 1e18;

        Root.Order memory order = buildOrder(
            user0,
            address(this),
            address(inputToken),
            inputAmount,
            address(outputToken),
            1,
            6 minutes,
            5 minutes,
            address(0),
            ""
        );
        bytes memory signature = buildSignature(order, user0_pk);

        vm.startPrank(user0);
        inputToken.mint(user0, inputAmount);
        inputToken.approve(address(hub), inputAmount);

        vm.expectRevert();
        hub.createOrder(buildOrderRequest(order, 1), permits, signature);
        vm.stopPrank();
    }

    function testOrderExpired() public {
        uint256 inputAmount = 1e18;

        Root.Order memory order = buildOrder(
            user0,
            address(this),
            address(inputToken),
            inputAmount,
            address(outputToken),
            1,
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
        inputToken.approve(address(hub), inputAmount);

        vm.expectRevert();
        hub.createOrder(buildOrderRequest(order, 1), permits, signature);
        vm.stopPrank();
    }

    function testCreateOrderInsufficientBalance() public {
        uint256 inputAmount = 1e18;

        Root.Order memory order = buildOrder(
            user0,
            address(this),
            address(inputToken),
            inputAmount,
            address(outputToken),
            1,
            1 minutes,
            5 minutes,
            address(0),
            ""
        );
        bytes memory signature = buildSignature(order, user0_pk);

        inputToken.mint(user0, inputAmount - 1); // Mint less than required
        vm.prank(user0);
        inputToken.approve(address(hub), inputAmount);

        vm.prank(user0);
        vm.expectRevert();
        hub.createOrder(buildOrderRequest(order, 1), permits, signature);
    }

    function testWithdrawNonExistentOrder() public {
        uint256 inputAmount = 1e18;

        Root.Order memory order = buildOrder(
            user0,
            address(this),
            address(inputToken),
            inputAmount,
            address(outputToken),
            1,
            1 minutes,
            5 minutes,
            address(0),
            ""
        );

        vm.prank(user0);
        vm.expectRevert();
        hub.withdrawOrder(order, 1);
    }

    function testCreateMultipleOrdersSameUser(uint256 inputAmount1, uint256 inputAmount2) public {
        vm.assume(inputAmount1 < type(uint256).max - inputAmount2);
        vm.assume(inputAmount1 > 0);
        vm.assume(inputAmount2 > 0);

        Root.Order memory order1 = buildOrder(
            user0,
            address(this),
            address(inputToken),
            inputAmount1,
            address(outputToken),
            1,
            1 minutes,
            5 minutes,
            address(0),
            ""
        );
        bytes memory signature1 = buildSignature(order1, user0_pk);

        Root.Order memory order2 = buildOrder(
            user0,
            address(this),
            address(inputToken),
            inputAmount2,
            address(outputToken),
            2,
            1 minutes,
            5 minutes,
            address(0),
            ""
        );
        bytes memory signature2 = buildSignature(order2, user0_pk);

        inputToken.mint(user0, inputAmount1 + inputAmount2);
        vm.startPrank(user0);
        inputToken.approve(address(hub), inputAmount1 + inputAmount2);

        hub.createOrder(buildOrderRequest(order1, 1), permits, signature1);

        vm.expectRevert(); // request nonce reused
        hub.createOrder(buildOrderRequest(order2, 1), permits, signature2);

        hub.createOrder(buildOrderRequest(order2, 2), permits, signature2);
        vm.stopPrank();

        assertEq(inputToken.balanceOf(address(hub)), inputAmount1 + inputAmount2);
    }

    function testCreateMultipleOrdersMultipleUsers(uint256 inputAmount1, uint256 inputAmount2) public {
        vm.assume(inputAmount1 < type(uint256).max - inputAmount2);
        vm.assume(inputAmount1 > 0);
        vm.assume(inputAmount2 > 0);

        Root.Order memory order1 = buildOrder(
            user1,
            address(this),
            address(inputToken),
            inputAmount1,
            address(outputToken),
            1,
            1 minutes,
            5 minutes,
            address(0),
            ""
        );
        bytes memory signature1 = buildSignature(order1, user1_pk);

        Root.Order memory order2 = buildOrder(
            user2,
            address(this),
            address(inputToken),
            inputAmount2,
            address(outputToken),
            1,
            1 minutes,
            5 minutes,
            address(0),
            ""
        );
        bytes memory signature2 = buildSignature(order2, user2_pk);

        vm.startPrank(user1);
        inputToken.mint(user1, inputAmount1);
        inputToken.approve(address(hub), inputAmount1);
        hub.createOrder(buildOrderRequest(order1, 1), permits, signature1);
        vm.stopPrank();

        vm.startPrank(user2);
        inputToken.mint(user2, inputAmount2);
        inputToken.approve(address(hub), inputAmount2);
        hub.createOrder(buildOrderRequest(order2, 1), permits, signature2);
        vm.stopPrank();

        assertEq(inputToken.balanceOf(address(hub)), inputAmount1 + inputAmount2);
    }
}

/*
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
        orderhub.createOrder(buildOrderRequest(order, 1), permits, signature, 0);
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

        assertEq(inputToken.balanceOf(address(orderhub)), 0);
        contractUser.approve(inputToken, address(orderhub), inputAmount);
        contractUser.createOrder(orderhub, order, permits, signature, 0);
        assertEq(inputToken.balanceOf(address(orderhub)), inputAmount);
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
        inputToken.approve(address(orderhub), inputAmount * 2);
        bytes memory signature = buildSignature(order, user0_pk);

        // Add the first order
        vm.prank(user0);
        (bytes32 orderId1,) = orderhub.createOrder(buildOrderRequest(order, 1), permits, signature, 0);
        assertEq(inputToken.balanceOf(address(orderhub)), inputAmount);
        assertEq(inputToken.balanceOf(user0), inputAmount);

        // Add the second order
        vm.prank(user0);
        (bytes32 orderId2, uint256 nonce) = orderhub.createOrder(buildOrderRequest(order, 2), permits, signature, 0);
        assertEq(inputToken.balanceOf(address(orderhub)), inputAmount * 2);
        assertEq(inputToken.balanceOf(user0), 0);

        // Order IDs are not the same
        assertNotEq(orderId1, orderId2);
        // Orders expire
        vm.warp(block.timestamp + 10 minutes);

        // Withdraw the first order
        vm.prank(user0);
        orderhub.withdrawOrder(order, nonce);
        assertEq(inputToken.balanceOf(address(orderhub)), inputAmount);
        assertEq(inputToken.balanceOf(user0), inputAmount);

        // Withdrawing again fails
        vm.prank(user0);
        vm.expectRevert();
        orderhub.withdrawOrder(order, nonce);
        assertEq(inputToken.balanceOf(address(orderhub)), inputAmount);
        assertEq(inputToken.balanceOf(user0), inputAmount);
    }

    function testMaxDeadline() public {
        uint256 maxDeadline = 1 hours;
        orderhub.setMaxOrderDeadline(maxDeadline);

        uint256 inputAmount = 1e18;
        uint256 outputAmount = 2e18;
        Validator.Order memory order = buildOrder(
            user1,
            inputAmount,
            outputAmount,
            user0,
            address(inputToken),
            address(outputToken),
            1 minutes,
            1 weeks,
            address(0),
            ""
        );
        bytes memory signature = buildSignature(order, user0_pk);

        inputToken.mint(user0, inputAmount);
        vm.startPrank(user0);
        inputToken.approve(address(orderhub), inputAmount);
        vm.expectRevert();
        orderhub.createOrder(buildOrderRequest(order, 1), permits, signature, 0);
        vm.stopPrank();
    }

    function testTimeBuffer() public {
        uint256 timeBufferPeriod = 1 hours;
        orderhub.setTimeBuffer(timeBufferPeriod);

        uint256 inputAmount = 1e18;
        uint256 outputAmount = 2e18;

        Validator.Order memory order = buildOrder(
            user1, // filler
            inputAmount,
            outputAmount,
            user0, // user
            address(inputToken),
            address(outputToken),
            1 minutes, // primaryFillerDeadline
            5 minutes, // deadline
            address(0),
            ""
        );
        bytes memory signature = buildSignature(order, user0_pk);

        inputToken.mint(user0, inputAmount);
        vm.startPrank(user0);
        inputToken.approve(address(orderhub), inputAmount);
        (, uint256 nonce) = orderhub.createOrder(buildOrderRequest(order, 1), permits, signature, 0);

        // Try to withdraw before deadline - should fail
        vm.warp(block.timestamp + 4 minutes);
        vm.expectRevert();
        orderhub.withdrawOrder(order, nonce);

        // Try to withdraw after deadline but before time buffer expires - should fail
        vm.warp(block.timestamp + 2 minutes); // now at deadline + 1 minute
        vm.expectRevert();
        orderhub.withdrawOrder(order, nonce);

        // Try to withdraw after deadline + time buffer - should succeed
        vm.warp(block.timestamp + 1 hours); // well past deadline + buffer
        orderhub.withdrawOrder(order, nonce);
        vm.stopPrank();

        assertEq(inputToken.balanceOf(user0), inputAmount);
    }

    function testTimeBufferUpdate(uint256 timeBuffer) public {
        assertEq(orderhub.timeBuffer(), 0);
        orderhub.setTimeBuffer(timeBuffer);
        assertEq(orderhub.timeBuffer(), timeBuffer);

        vm.startPrank(user0);
        vm.expectRevert();
        orderhub.setTimeBuffer(2 hours);
        vm.stopPrank();
    }

    function testReplyAttack() public {
        uint256 inputAmount = 1 ether;
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

        inputToken.mint(user0, 10 * inputAmount);
        vm.prank(user0);
        inputToken.approve(address(orderhub), 10 * inputAmount);

        assertEq(inputToken.balanceOf(address(orderhub)), 0);

        // create 2 orders reusing the same signature
        orderhub.createOrder(buildOrderRequest(order, 1), permits, signature, 0);
        assertEq(inputToken.balanceOf(address(orderhub)), inputAmount);

        // replay attack is not possible
        vm.expectRevert();
        orderhub.createOrder(buildOrderRequest(order, 1), permits, signature, 0);
        assertEq(inputToken.balanceOf(address(orderhub)), inputAmount);
    }
}


    function testCreateERC721Order() public {
        Validator.Order memory order = buildERC721Order(
            address(this),
            1,
            1,
            user0,
            address(inputERC721Token),
            address(outputToken),
            1 minutes,
            5 minutes,
            address(0),
            ""
        );
        bytes memory signature = buildSignature(order, user0_pk);

        vm.prank(user0);
        inputERC721Token.mint(user0);

        vm.prank(user0);
        inputERC721Token.approve(address(orderhub), 1);

        assertEq(inputERC721Token.balanceOf(address(user0)), 1);
        assertEq(inputERC721Token.balanceOf(address(orderhub)), 0);

        vm.prank(user0);
        orderhub.createOrder(buildOrderRequest(order, 1), permits, signature, 0);

        assertEq(inputERC721Token.balanceOf(address(user0)), 0);
        assertEq(inputERC721Token.balanceOf(address(orderhub)), 1);
    }

    function testCreateERC1155Order() public {
        Validator.Order memory order = buildERC1155Order(
            address(this),
            1,
            1,
            user0,
            address(inputERC1155Token),
            address(outputToken),
            1 minutes,
            5 minutes,
            address(0),
            ""
        );
        bytes memory signature = buildSignature(order, user0_pk);

        vm.prank(user0);
        inputERC1155Token.mint(user0, 1, 1, "");

        vm.prank(user0);
        inputERC1155Token.setApprovalForAll(address(orderhub), true);

        assertEq(inputERC1155Token.balanceOf(address(user0), 1), 1);
        assertEq(inputERC1155Token.balanceOf(address(orderhub), 1), 0);

        vm.prank(user0);
        orderhub.createOrder(buildOrderRequest(order, 1), permits, signature, 0);

        assertEq(inputERC1155Token.balanceOf(address(user0), 1), 0);
        assertEq(inputERC1155Token.balanceOf(address(orderhub), 1), 1);
    }
*/
