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

        inputToken.mint(user0, inputAmount);
        vm.startPrank(user0);
        inputToken.approve(address(orderbook), inputAmount);
        orderbook.createOrder(order, 0);
        vm.stopPrank();

        iLayerMessage memory fillMessage = buildMessage(filler, address(settler), "");
        bytes memory messageData = abi.encode(order);
        bytes memory extraData = abi.encode(filler, 1e18, 0, 0);

        vm.startPrank(filler);
        outputToken.mint(filler, outputAmount);
        outputToken.approve(address(settler), outputAmount);
        router.deliverAndExecuteMessage(fillMessage, messageData, extraData, 0, msgProof);
        vm.stopPrank();

        iLayerMessage memory settleMessage = buildMessage(filler, address(orderbook), "");
        messageData = abi.encode(order, filler, filler);
        router.deliverAndExecuteMessage(settleMessage, messageData, "", 0, msgProof);

        validateOrderWasFilled(user0, filler, inputAmount, outputAmount);
    }

    /*
    function testFillOrderEmptyFiller() public {
        uint256 inputAmount = 1e18;
        uint256 outputAmount = 1e18;

        (Validator.Order memory order,) = buildOrder(
            address(0),
            inputAmount,
            outputAmount,
            user0,
            user0_pk,
            address(inputToken),
            address(outputToken),
            1 minutes,
            5 minutes
        );

        inputToken.mint(user0, inputAmount);
        vm.prank(user0);
        inputToken.approve(address(orderbook), inputAmount);
        orderbook.createOrder(order, 0);

        address filler = user1;

        vm.startPrank(filler);
        outputToken.mint(filler, outputAmount);
        outputToken.approve(address(settler), outputAmount);
        //settler.fillOrder(order);
        vm.stopPrank();

        validateOrderWasFilled(user0, filler, inputAmount, outputAmount);
    }*/
}
