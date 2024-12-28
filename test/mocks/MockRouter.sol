// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {iLayerCCMApp} from "@ilayer/iLayerCCMApp.sol";
import {IiLayerRouter} from "@ilayer/interfaces/IiLayerRouter.sol";
import {bytes64, iLayerMessage, iLayerCCMLibrary} from "@ilayer/libraries/iLayerCCMLibrary.sol";

contract MockRouter is IiLayerRouter {
    uint256 public fee;

    function setFee(uint256 _fee) external {
        fee = _fee;
    }

    function getFee(address) external view returns (uint256) {
        return fee;
    }

    function sendMessage(bytes64 calldata, uint256, uint16, bytes calldata) external payable returns (bytes32) {
        assert(msg.value == fee);

        return "";
    }

    function executeMessage(iLayerMessage calldata message, bytes calldata messageData, bytes calldata extraData)
        external
        payable
        override
    {
        _executeMessage(message, messageData, extraData);
    }

    function chainSelector() external view override returns (uint256) {}

    function defaultBlockConfirmations() external view override returns (uint16) {}

    function deliverMessages(iLayerMessage[] calldata messages, uint256 verifierIndex, bytes calldata proof)
        external
        override
    {}

    function deliverAndExecuteMessage(
        iLayerMessage calldata message,
        bytes calldata messageData,
        bytes calldata extraData,
        uint256,
        bytes calldata
    ) external payable override {
        _executeMessage(message, messageData, extraData);
    }

    function iLayerL1Address() external view override returns (bytes32, bytes32) {}

    function _executeMessage(iLayerMessage calldata message, bytes calldata messageData, bytes calldata extraData)
        internal
    {
        address dest = iLayerCCMLibrary.bytes64ToAddress(message.receiver);

        iLayerCCMApp(dest).receiveMessage(msg.sender, message, messageData, extraData);
    }
}
