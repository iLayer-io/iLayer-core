// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {bytes64, iLayerMessage, iLayerCCMLibrary} from "@ilayer/libraries/iLayerCCMLibrary.sol";
import {iLayerRouter, IiLayerRouter} from "@ilayer/iLayerRouter.sol";
import {Validator} from "../src/Validator.sol";
import {OrderHub} from "../src/OrderHub.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {BaseScript} from "./BaseScript.sol";

contract FillOrderScript is BaseScript {
    function run() external broadcastTx(fillerPrivateKey) {
        Validator.Order memory order = buildOrder();

        iLayerMessage memory fillMessage = buildMessage(filler, address(executor), "");
        bytes memory messageData = abi.encode(order);
        bytes memory extraData = abi.encode(filler, 1e18, 0, 0);

        MockERC20 token = MockERC20(toToken);
        token.mint(filler, outputAmount);
        token.approve(address(executor), outputAmount);

        router.deliverAndExecuteMessage(fillMessage, messageData, extraData, 0, msgProof);

        iLayerMessage memory settleMessage = buildMessage(filler, address(orderhub), "");
        messageData = abi.encode(order, filler, filler);
        router.deliverAndExecuteMessage(settleMessage, messageData, "", 0, msgProof);
    }
}
