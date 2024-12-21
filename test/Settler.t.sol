// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {bytes64, iLayerMessage, iLayerCCMLibrary} from "@ilayer/libraries/iLayerCCMLibrary.sol";
import {Validator} from "../src/Validator.sol";
import {Orderbook} from "../src/Orderbook.sol";
import {Settler} from "../src/Settler.sol";
import {BaseTest} from "./BaseTest.sol";

contract SettlerTest is BaseTest {
    constructor() BaseTest() {}

    function testFillOrder() public {
        uint256 inputAmount = 1e18;
        uint256 outputAmount = 2 * 1e18;
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

        // 2. Setup and create order
        inputToken.mint(user0, inputAmount);
        vm.startPrank(user0);
        inputToken.approve(address(orderbook), inputAmount);
        orderbook.createOrder(order, 0);
        vm.stopPrank();

        assertEq(inputToken.balanceOf(address(orderbook)), inputAmount, "Input token not transferred to orderbook");

        // 3. Fill order
        iLayerMessage memory fillMessage = buildMessage(filler, address(settler), "");
        bytes memory messageData = abi.encode(order);
        bytes memory extraData = abi.encode(filler, 1e18, 0, 0);

        vm.startPrank(filler);
        outputToken.mint(filler, outputAmount);
        outputToken.approve(address(settler), outputAmount);

        router.deliverAndExecuteMessage(fillMessage, messageData, extraData, 0, msgProof);
        vm.stopPrank();

        assertEq(outputToken.balanceOf(address(user0)), outputAmount, "Output token not transferred to the user");

        // 4. Settle order
        iLayerMessage memory settleMessage = buildMessage(filler, address(orderbook), "");
        messageData = abi.encode(order, filler, filler);
        router.deliverAndExecuteMessage(settleMessage, messageData, "", 0, msgProof);

        validateOrderWasFilled(user0, filler, inputAmount, outputAmount);
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

        // Setup order
        inputToken.mint(user0, inputAmount);
        vm.startPrank(user0);
        inputToken.approve(address(orderbook), inputAmount);
        orderbook.createOrder(order, 0);
        vm.stopPrank();

        // Try to fill with wrong filler
        iLayerMessage memory fillMessage = buildMessage(invalidFiller, address(settler), "");
        bytes memory messageData = abi.encode(order);
        bytes memory extraData = abi.encode(invalidFiller, 1e18, 0, 0);

        vm.startPrank(invalidFiller);
        outputToken.mint(invalidFiller, outputAmount);
        outputToken.approve(address(settler), outputAmount);

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

        // Setup order
        inputToken.mint(user0, inputAmount);
        vm.startPrank(user0);
        inputToken.approve(address(orderbook), inputAmount);
        orderbook.createOrder(order, 0);
        vm.stopPrank();

        // Move time past deadline
        vm.warp(block.timestamp + 6 minutes);

        iLayerMessage memory fillMessage = buildMessage(filler, address(settler), "");
        bytes memory messageData = abi.encode(order);
        bytes memory extraData = abi.encode(filler, 1e18, 0, 0);

        vm.startPrank(filler);
        outputToken.mint(filler, outputAmount);
        outputToken.approve(address(settler), outputAmount);

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

        // Setup order
        inputToken.mint(user0, inputAmount);
        vm.startPrank(user0);
        inputToken.approve(address(orderbook), inputAmount);
        orderbook.createOrder(order, 0);
        vm.stopPrank();

        uint256 insufficientAmount = outputAmount - 1e17; // Less than required
        iLayerMessage memory fillMessage = buildMessage(filler, address(settler), "");
        bytes memory messageData = abi.encode(order);
        bytes memory extraData = abi.encode(filler, insufficientAmount, 0, 0);

        vm.startPrank(filler);
        outputToken.mint(filler, insufficientAmount);
        outputToken.approve(address(settler), insufficientAmount);

        vm.expectRevert(); // Should revert because insufficient amount
        router.deliverAndExecuteMessage(fillMessage, messageData, extraData, 0, msgProof);
        vm.stopPrank();
    }
}
