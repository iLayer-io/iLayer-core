// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {bytes64, iLayerMessage, iLayerCCMLibrary} from "@ilayer/libraries/iLayerCCMLibrary.sol";
import {Validator} from "../src/Validator.sol";
import {OrderHub} from "../src/OrderHub.sol";
import {Executor} from "../src/Executor.sol";
import {BaseTest} from "./BaseTest.sol";

contract TargetContract {
    uint256 public bar = 0;

    function foo(uint256 val) external {
        bar = val;
    }
}

contract ExecutorTest is BaseTest {
    TargetContract public immutable target;

    constructor() BaseTest() {
        target = new TargetContract();
    }

    function testFillOrder(uint256 inputAmount, uint256 outputAmount) public {
        vm.assume(inputAmount > 0);
        address filler = user1;

        // 1. Build and verify order
        Validator.Order memory order = buildOrder(
            filler,
            inputAmount,
            outputAmount,
            user0,
            address(inputToken),
            address(outputToken),
            1 minutes,
            5 minutes,
            address(0),
            ""
        );
        bytes memory signature = buildSignature(order, user0_pk);

        // 2. Setup and create order
        inputToken.mint(user0, inputAmount);
        vm.startPrank(user0);
        inputToken.approve(address(orderhub), inputAmount);
        (, uint256 nonce) = orderhub.createOrder(order, permits, signature, 0);
        vm.stopPrank();

        assertEq(inputToken.balanceOf(address(orderhub)), inputAmount, "Input token not transferred to orderhub");

        // 3. Fill order
        iLayerMessage memory fillMessage = buildMessage(address(orderhub), address(executor), "");
        bytes memory messageData = abi.encode(order, nonce);
        bytes memory extraData = abi.encode(filler, 1e18, 0, 0);

        vm.startPrank(filler);
        outputToken.mint(filler, outputAmount);
        outputToken.approve(address(executor), outputAmount);

        router.deliverAndExecuteMessage(fillMessage, messageData, extraData, 0, msgProof);

        assertEq(outputToken.balanceOf(address(user0)), outputAmount, "Output token not transferred to the user");

        // 4. Settle order
        iLayerMessage memory settleMessage = buildMessage(address(executor), address(orderhub), "");
        messageData = abi.encode(order, nonce, filler, filler);
        router.deliverAndExecuteMessage(settleMessage, messageData, "", 0, msgProof);

        validateOrderWasFilled(user0, filler, inputAmount, outputAmount);
        vm.stopPrank();
    }

    function testFillOrderWithInvalidFiller() public {
        uint256 inputAmount = 1e18;
        uint256 outputAmount = 2 * 1e18;
        address filler = user1;
        address invalidFiller = user2; // Different from order's filler

        Validator.Order memory order = buildOrder(
            filler, // Original filler
            inputAmount,
            outputAmount,
            user0,
            address(inputToken),
            address(outputToken),
            1 minutes,
            5 minutes,
            address(0),
            ""
        );
        bytes memory signature = buildSignature(order, user0_pk);

        // Setup order
        inputToken.mint(user0, inputAmount);
        vm.startPrank(user0);
        inputToken.approve(address(orderhub), inputAmount);
        (, uint256 nonce) = orderhub.createOrder(order, permits, signature, 0);
        vm.stopPrank();

        // Try to fill with wrong filler
        iLayerMessage memory fillMessage = buildMessage(address(orderhub), address(executor), "");
        bytes memory messageData = abi.encode(order, nonce);
        bytes memory extraData = abi.encode(invalidFiller, 1e18, 0, 0);

        vm.startPrank(invalidFiller);
        outputToken.mint(invalidFiller, outputAmount);
        outputToken.approve(address(executor), outputAmount);

        vm.expectRevert(); // Should revert because wrong filler
        router.deliverAndExecuteMessage(fillMessage, messageData, extraData, 0, msgProof);
        vm.stopPrank();
    }

    function testFillOrderWithExpiredDeadline() public {
        uint256 inputAmount = 1e18;
        uint256 outputAmount = 2 * 1e18;
        address filler = user1;

        Validator.Order memory order = buildOrder(
            filler,
            inputAmount,
            outputAmount,
            user0,
            address(inputToken),
            address(outputToken),
            1 minutes,
            5 minutes,
            address(0),
            ""
        );
        bytes memory signature = buildSignature(order, user0_pk);

        // Setup order
        inputToken.mint(user0, inputAmount);
        vm.startPrank(user0);
        inputToken.approve(address(orderhub), inputAmount);
        (, uint256 nonce) = orderhub.createOrder(order, permits, signature, 0);
        vm.stopPrank();

        // Move time past deadline
        vm.warp(block.timestamp + 6 minutes);

        iLayerMessage memory fillMessage = buildMessage(address(orderhub), address(executor), "");
        bytes memory messageData = abi.encode(order, nonce);
        bytes memory extraData = abi.encode(filler, 1e18, 0, 0);

        vm.startPrank(filler);
        outputToken.mint(filler, outputAmount);
        outputToken.approve(address(executor), outputAmount);

        vm.expectRevert(); // Should revert because order expired
        router.deliverAndExecuteMessage(fillMessage, messageData, extraData, 0, msgProof);
        vm.stopPrank();
    }

    function testFillOrderWithInsufficientAmount() public {
        uint256 inputAmount = 1e18;
        uint256 outputAmount = 2 * 1e18;
        address filler = user1;

        Validator.Order memory order = buildOrder(
            filler,
            inputAmount,
            outputAmount,
            user0,
            address(inputToken),
            address(outputToken),
            1 minutes,
            5 minutes,
            address(0),
            ""
        );
        bytes memory signature = buildSignature(order, user0_pk);

        // Setup order
        inputToken.mint(user0, inputAmount);
        vm.startPrank(user0);
        inputToken.approve(address(orderhub), inputAmount);
        (, uint256 nonce) = orderhub.createOrder(order, permits, signature, 0);
        vm.stopPrank();

        uint256 insufficientAmount = outputAmount - 1e17; // Less than required
        iLayerMessage memory fillMessage = buildMessage(address(orderhub), address(executor), "");
        bytes memory messageData = abi.encode(order, nonce);
        bytes memory extraData = abi.encode(filler, insufficientAmount, 0, 0);

        vm.startPrank(filler);
        outputToken.mint(filler, insufficientAmount);
        outputToken.approve(address(executor), insufficientAmount);

        vm.expectRevert(); // Should revert because insufficient amount
        router.deliverAndExecuteMessage(fillMessage, messageData, extraData, 0, msgProof);
        vm.stopPrank();
    }

    function testFillOrderWithExternalContractCall() public {
        uint256 inputAmount = 1e18;
        uint256 outputAmount = 2 * 1e18;
        address filler = user1;

        Validator.Order memory order = buildOrder(
            filler,
            inputAmount,
            outputAmount,
            user0,
            address(inputToken),
            address(outputToken),
            1 minutes,
            5 minutes,
            address(target),
            abi.encodeWithSelector(TargetContract.foo.selector, 5)
        );
        bytes memory signature = buildSignature(order, user0_pk);

        inputToken.mint(user0, inputAmount);
        vm.startPrank(user0);
        inputToken.approve(address(orderhub), inputAmount);
        (, uint256 nonce) = orderhub.createOrder(order, permits, signature, 0);
        vm.stopPrank();

        assertEq(target.bar(), 0);

        iLayerMessage memory fillMessage = buildMessage(address(orderhub), address(executor), "");
        bytes memory messageData = abi.encode(order, nonce);
        bytes memory extraData = abi.encode(user2, 0, 0, 0);

        vm.startPrank(filler);
        outputToken.mint(filler, outputAmount);
        outputToken.approve(address(executor), outputAmount);

        // revert for out of gas
        vm.expectRevert();
        router.deliverAndExecuteMessage(fillMessage, messageData, extraData, 0, msgProof);

        extraData = abi.encode(user2, 1e8, 0, 0);
        router.deliverAndExecuteMessage(fillMessage, messageData, extraData, 0, msgProof);

        iLayerMessage memory settleMessage = buildMessage(address(executor), address(orderhub), "");
        messageData = abi.encode(order, nonce, filler, user2);
        router.deliverAndExecuteMessage(settleMessage, messageData, "", 0, msgProof);
        vm.stopPrank();

        assertEq(target.bar(), 5);
        assertEq(inputToken.balanceOf(filler), 0);
        assertEq(inputToken.balanceOf(user2), inputAmount);
    }
}
