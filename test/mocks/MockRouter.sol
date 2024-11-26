// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {EquitoApp} from "@equito-network/EquitoApp.sol";
import {bytes64, EquitoMessage, EquitoMessageLibrary} from "@equito-network/libraries/EquitoMessageLibrary.sol";
import {IEquitoRouter} from "../../src/interfaces/IEquitoRouter.sol";

contract MockRouter is IEquitoRouter {
    uint256 public fee;

    function setFee(uint256 _fee) external {
        fee = _fee;
    }

    function getFee(address) external view returns (uint256) {
        return fee;
    }

    function sendMessage(bytes64 calldata receiver, uint256, /*destinationChainSelector*/ bytes calldata data)
        external
        payable
        returns (bytes32)
    {
        assert(msg.value == fee);

        bytes32 hashedData = keccak256(data);
        address dest = EquitoMessageLibrary.bytes64ToAddress(receiver);

        EquitoMessage memory message = EquitoMessage({
            blockNumber: block.number,
            sourceChainSelector: block.chainid,
            destinationChainSelector: block.chainid,
            sender: EquitoMessageLibrary.addressToBytes64(msg.sender),
            receiver: receiver,
            hashedData: hashedData
        });
        EquitoApp(dest).receiveMessage(message, data);

        return hashedData;
    }
}
