// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {console2} from "forge-std/console2.sol";
import {bytes64, iLayerMessage, iLayerCCMLibrary} from "@ilayer/libraries/iLayerCCMLibrary.sol";
import {iLayerRouter, IiLayerRouter} from "@ilayer/iLayerRouter.sol";
import {Validator} from "../src/Validator.sol";
import {OrderHub} from "../src/OrderHub.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {BaseScript} from "./BaseScript.sol";

contract CreateOrderScript is BaseScript {
    function run() external broadcastTx(userPrivateKey) {
        Validator.Order memory order = buildOrder();

        bytes[] memory permits = new bytes[](1);
        bytes memory signature = buildSignature(order);

        MockERC20 token = MockERC20(fromToken);
        token.approve(address(orderhub), inputAmount);
        token.mint(user, inputAmount);

        OrderHub.OrderRequest memory request =
            OrderHub.OrderRequest({order: order, deadline: block.timestamp + 1 days, nonce: 1});
        (bytes32 id, uint256 nonce) = OrderHub(orderhub).createOrder(request, permits, signature, 0);
        console2.log("order id", string(abi.encodePacked(id)));
        console2.log("order nonce", nonce);
    }
}
