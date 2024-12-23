// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {bytes64, iLayerMessage, iLayerCCMLibrary} from "@ilayer/libraries/iLayerCCMLibrary.sol";
import {iLayerRouter, IiLayerRouter} from "@ilayer/iLayerRouter.sol";
import {Validator} from "../src/Validator.sol";
import {Orderbook} from "../src/Orderbook.sol";

contract CreateOrderScript is Script {
    Orderbook public orderbook;

    function _createOrder(
        address user,
        address filler,
        address fromToken,
        uint256 inputAmount,
        address toToken,
        uint256 outputAmount,
        uint256 primaryDeadline,
        uint256 secondaryDeadline
    ) internal view returns (Validator.Order memory) {
        Validator.Token[] memory inputs = new Validator.Token[](1);
        inputs[0] = Validator.Token({
            tokenAddress: iLayerCCMLibrary.addressToBytes64(fromToken),
            tokenId: type(uint256).max,
            amount: inputAmount
        });

        Validator.Token[] memory outputs = new Validator.Token[](1);
        outputs[0] = Validator.Token({
            tokenAddress: iLayerCCMLibrary.addressToBytes64(toToken),
            tokenId: type(uint256).max,
            amount: outputAmount
        });

        return Validator.Order({
            user: iLayerCCMLibrary.addressToBytes64(user),
            filler: iLayerCCMLibrary.addressToBytes64(filler),
            inputs: inputs,
            outputs: outputs,
            sourceChainSelector: block.chainid,
            destinationChainSelector: block.chainid,
            sponsored: false,
            primaryFillerDeadline: block.timestamp + primaryDeadline,
            deadline: block.timestamp + secondaryDeadline,
            callRecipient: iLayerCCMLibrary.addressToBytes64(address(0)),
            callData: ""
        });
    }

    function _sign(Validator.Order memory order, uint256 user_pk) internal view returns (bytes memory) {
        bytes32 structHash = orderbook.hashOrder(order);
        bytes32 domainSeparator = orderbook.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user_pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function run(
        uint256 userPrivateKey,
        address user,
        address filler,
        address fromToken,
        uint256 inputAmount,
        address toToken,
        uint256 outputAmount,
        uint256 primaryDeadline,
        uint256 secondaryDeadline
    ) external {
        orderbook = Orderbook(vm.envAddress("ORDERBOOK_ADDRESS"));

        Validator.Order memory order = _createOrder(
            user, filler, fromToken, inputAmount, toToken, outputAmount, primaryDeadline, secondaryDeadline
        );

        bytes[] memory permits = new bytes[](1);
        bytes memory signature = _sign(order, userPrivateKey);

        vm.startBroadcast(userPrivateKey);

        Orderbook(orderbook).createOrder(order, permits, signature, 0);

        vm.stopBroadcast();
    }
}
