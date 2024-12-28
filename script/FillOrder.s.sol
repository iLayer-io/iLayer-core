// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {bytes64, iLayerMessage, iLayerCCMLibrary} from "@ilayer/libraries/iLayerCCMLibrary.sol";
import {iLayerRouter, IiLayerRouter} from "@ilayer/iLayerRouter.sol";
import {Validator} from "../src/Validator.sol";
import {Orderbook} from "../src/Orderbook.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {BaseScript} from "./BaseScript.sol";

contract FillOrderScript is BaseScript {
    function run() external {
        Validator.Order memory order = buildOrder();

        iLayerMessage memory fillMessage = buildMessage(filler, settler, "");
        bytes memory messageData = abi.encode(order);
        bytes memory extraData = abi.encode(filler, 1e18, 0, 0);

        vm.startPrank(filler);
        MockERC20 token = MockERC20(fromToken);
        token.mint(filler, outputAmount);
        token.approve(settler, outputAmount);

        router.deliverAndExecuteMessage(fillMessage, messageData, extraData, 0, msgProof);
        vm.stopPrank();

        iLayerMessage memory settleMessage = buildMessage(filler, address(orderbook), "");
        messageData = abi.encode(order, filler, filler);
        router.deliverAndExecuteMessage(settleMessage, messageData, "", 0, msgProof);
    }
}
