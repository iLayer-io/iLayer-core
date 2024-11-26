// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {bytes64, EquitoMessage, EquitoMessageLibrary} from "@equito-network/libraries/EquitoMessageLibrary.sol";
import {Validator} from "./Validator.sol";
import {TransferUtils} from "./libraries/TransferUtils.sol";
import {IEquitoRouter} from "./interfaces/IEquitoRouter.sol";

contract Settler is Validator {
    using SafeERC20 for IERC20;

    IEquitoRouter public immutable router;
    mapping(bytes32 orderId => bool filled) public orders;
    mapping(uint256 chain => address orderbook) public orderbooks;

    event OrderFilled(bytes32 indexed orderId, address indexed filler);

    error UnavailablePeer();
    error InsufficientFeesPaid();
    error InvalidOrderSignature();
    error OrderAlreadyFilled();
    error RestrictedToPrimaryFiller();

    constructor(address _router) {
        router = IEquitoRouter(_router);
    }

    function fillOrder(Order memory order) external payable {
        if (!validateOrder(order)) revert InvalidOrderSignature();
        if (router.getFee(address(this)) < msg.value) revert InsufficientFeesPaid();

        if (orderbooks[order.sourceChainSelector] == address(0)) revert UnavailablePeer();

        bytes32 orderId = hashOrder(order);
        if (orders[orderId]) revert OrderAlreadyFilled();
        orders[orderId] = true;

        address user = EquitoMessageLibrary.bytes64ToAddress(order.user);
        address filler = EquitoMessageLibrary.bytes64ToAddress(order.filler);

        if (msg.sender != filler && block.timestamp > order.primaryFillerDeadline) {
            revert RestrictedToPrimaryFiller();
        }

        for (uint256 i = 0; i < order.outputs.length; i++) {
            Token memory output = order.outputs[i];

            address tokenAddress = EquitoMessageLibrary.bytes64ToAddress(output.tokenAddress);
            if (output.tokenId != type(uint256).max) {
                TransferUtils.transfer(filler, user, tokenAddress, output.tokenId, output.amount);
            } else {
                IERC20(tokenAddress).safeTransferFrom(filler, user, output.amount);
            }
        }

        bytes memory data = abi.encode(order, msg.sender);
        bytes64 memory dest = EquitoMessageLibrary.addressToBytes64(orderbooks[order.sourceChainSelector]);
        router.sendMessage{value: msg.value}(bytes64(dest.lower, dest.upper), order.sourceChainSelector, data);

        emit OrderFilled(orderId, msg.sender);
    }
}
