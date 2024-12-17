// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IiLayerFees} from "@ilayer/interfaces/IiLayerFees.sol";
import {iLayerMessage} from "@ilayer/libraries/iLayerCCMLibrary.sol";

contract MockiLayerFees is IiLayerFees {
    uint256 public fee;

    error InsufficientFee();

    function setFee(uint256 _fee) external {
        fee = _fee;
    }

    function getFee(address /* sender */ ) external view returns (uint256) {
        return fee;
    }

    function payFee(address sender) external payable {
        if (fee > msg.value) {
            revert InsufficientFee();
        }

        emit FeePaid(sender, msg.value);
    }
}
